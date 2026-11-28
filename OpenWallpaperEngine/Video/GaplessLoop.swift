import AVFoundation

/// Plays one video or soundtrack over and over without a pause at the loop point.
///
/// Seeking back to the start when the end is reported (`AVPlayerItemDidPlayToEndTime`) stops the
/// picture and the sound for about a third of a second at every loop: the end is only noticed on
/// the main queue, and the sound's queue is then flushed, primed and started again. AVFoundation
/// plays from one item into the next without a gap only on an `AVQueuePlayer` that advances into a
/// next item it already has queued, so this keeps two passes queued, the one playing and the next,
/// and queues another each time one ends. `AVPlayerLooper` does the same with copies of one item;
/// here the caller makes each pass, so every pass gets its own video output. The passes must be
/// items of a single track (`VideoFileSource.makeLoopAssets`) sharing one audio mix (`audioMix`):
/// otherwise the sound still starts afresh at every pass.
///
/// Main thread only: the end notifications are delivered on the main queue.
final class GaplessLoop {
    let player: AVQueuePlayer
    /// Makes the item of each pass; nil while nothing plays.
    private var makeItem: (() -> AVPlayerItem)?
    /// The end observer of each queued pass.
    private var observers: [ObjectIdentifier: NSObjectProtocol] = [:]

    /// The audio mix of every pass (a level tap's, `AudioLevelTap.attach(toItemsOf:apply:)`): one
    /// mix shared by all passes keeps them on one audio pipeline, so the sound runs on unbroken.
    var audioMix: AVAudioMix? {
        didSet { for item in player.items() { item.audioMix = audioMix } }
    }

    /// Called on the main queue each time a pass has played to its end.
    var passEnded: (() -> Void)?

    /// Whether the end runs into the next pass; when false, the last frame holds.
    var loops = true {
        didSet {
            guard loops != oldValue else { return }
            if loops {
                if player.items().count < 2 { enqueue() }
                player.actionAtItemEnd = .advance
            } else {
                player.actionAtItemEnd = .none
                for item in player.items().dropFirst() { remove(item) }
            }
        }
    }

    init(player: AVQueuePlayer) {
        self.player = player
        player.actionAtItemEnd = .advance
    }

    deinit {
        observers.values.forEach(NotificationCenter.default.removeObserver)
    }

    /// Plays passes of `makeItem`'s items from now on, in place of whatever was queued. The
    /// player's rate is left as it is.
    func play(_ makeItem: @escaping () -> AVPlayerItem) {
        clear()
        self.makeItem = makeItem
        player.actionAtItemEnd = loops ? .advance : .none
        enqueue()
        if loops { enqueue() }
    }

    /// Empties the queue: nothing plays until `play(_:)`.
    func clear() {
        makeItem = nil
        audioMix = nil
        observers.values.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        player.removeAllItems()
    }

    private func enqueue() {
        guard let makeItem else { return }
        let item = makeItem()
        if let audioMix { item.audioMix = audioMix }
        let key = ObjectIdentifier(item)
        // Weak and never reassigned: `nonisolated(unsafe)` only lets the `@Sendable` observer
        // block capture it. The block runs on the main queue.
        nonisolated(unsafe) weak let loop = self
        observers[key] = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { _ in loop?.ended(key) }
        player.insert(item, after: nil)
    }

    private func remove(_ item: AVPlayerItem) {
        if let token = observers.removeValue(forKey: ObjectIdentifier(item)) {
            NotificationCenter.default.removeObserver(token)
        }
        player.remove(item)
    }

    private func ended(_ key: ObjectIdentifier) {
        if loops, let token = observers.removeValue(forKey: key) {
            // The pass that ended has left the queue and the one behind it plays: queue the next.
            NotificationCenter.default.removeObserver(token)
            enqueue()
        }
        passEnded?()
    }
}
