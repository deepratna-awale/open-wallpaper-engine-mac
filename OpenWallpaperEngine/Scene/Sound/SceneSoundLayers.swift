import AVFoundation

/// A wallpaper instance's sound layers (docs/scenescript-plan.md, sound layers): one
/// `SceneSoundPlayback` per scene.json `sound` object, played through one `SceneSoundMixer`, and
/// the wallpaper's gain. Owned by the renderer, main thread.
///
/// The wallpaper's gain is the app's volume, mute and pause (and whether this display is the one
/// that plays the wallpaper's sound). Like WE's wallpaper volume (0x140114d7c, 0x1401816d0) it
/// fades towards its target with WE's ease (`SceneClock.ease`: the gap shrinks by min(6·dt, 1) a
/// frame, and closes once under 0.01), stepped by each drawn frame's wall step (`advanceFade`),
/// as WE's main loop steps it. WE's loop keeps running while no wallpaper frame is drawn (it
/// sleeps 250 ms a turn while paused, 0x140111486), so while no frame comes a timer steps it
/// instead; at 0 the layers pause, above 0 they resume where they were.
///
/// A `spatialization` layer's mono files play from its object (`SceneSoundSpatialization`),
/// placed when they start and on every update, like WE's.
final class SceneSoundLayers {
    private struct Layer {
        var content: SceneSoundContent
        var voices: SceneSoundVoices
        var playback: SceneSoundPlayback
    }

    /// How long without a drawn frame before the timer steps the fade.
    static let frameGap: CFTimeInterval = 0.25

    private let label: String
    private let offline: AVAudioFormat?
    private let random: () -> Double
    private var mixer: SceneSoundMixer?
    private var layers: [Int: Layer] = [:]
    private var order: [Int] = []
    private(set) var gain: Float = 0
    private(set) var targetGain: Float = 0
    private var fadeTimer: Timer?
    private var lastFadeTime: CFTimeInterval = 0
    /// When a drawn frame last stepped the fade (`advanceFade`).
    private var lastFrameFade: CFTimeInterval = -.infinity
    /// The camera spatialized layers are placed against (the last frame's); nil before the first.
    var listener: SceneSoundSpatialization.Listener?
    /// A layer's object's world position this frame (its world matrix's translation).
    var locate: (Int) -> SIMD3<Float>? = { _ in nil }

    /// `offline` renders through a manual-rendering engine (tests).
    init(label: String, offline: AVAudioFormat? = nil, random: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        self.label = label
        self.offline = offline
        self.random = random
    }

    deinit {
        fadeTimer?.invalidate()
    }

    var isEmpty: Bool { layers.isEmpty }
    var ids: [Int] { order }

    /// The scene's sound layers. Layers that stay (same id and files) keep playing with the new
    /// settings, as a content rebuild for a user property doesn't restart WE's sounds; others
    /// stop, and new ones load (and play unless `startsilent`).
    func setContent(_ sounds: [SceneSoundContent]) {
        var kept: [Int: Layer] = [:]
        for content in sounds {
            guard var layer = layers.removeValue(forKey: content.id) else { continue }
            guard layer.content.files == content.files, layer.content.sound == content.sound else {
                layer.playback.stop()
                continue
            }
            if layer.content.volume != content.volume { layer.playback.setVolume(content.volume) }
            layer.content = content
            kept[content.id] = layer
        }
        for id in layers.keys { layers[id]?.playback.stop() }
        layers = kept
        order = sounds.map(\.id)
        for content in sounds where layers[content.id] == nil { add(content) }
        idleIfSilent()
    }

    /// Adds one layer (a script's `createLayer`, or new content) and loads it.
    func add(_ content: SceneSoundContent) {
        if layers[content.id] != nil { remove(content.id) }
        // OpenAL Soft places only mono sources; a stereo file of a spatialized sound plays as it is.
        let spatialFiles = content.sound.spatialization
            ? Set(content.files.indices.filter { content.files[$0].channels == 1 }) : []
        let voices = SceneSoundVoices(files: content.files, spatialFiles: spatialFiles,
                                      mixer: { [weak self] in self?.sharedMixer() }, label: "\(label) '\(content.name)'")
        let playback = SceneSoundPlayback(sound: content.sound, durations: content.files.map(\.duration),
                                          volume: content.volume, sceneGain: gain, output: voices, random: random)
        let layer = Layer(content: content, voices: voices, playback: playback)
        layers[content.id] = layer
        if !order.contains(content.id) { order.append(content.id) }
        place(layer)
        playback.load()
    }

    /// Stops and forgets one layer (`destroyLayer`).
    func remove(_ id: Int) {
        layers.removeValue(forKey: id)?.playback.stop()
        order.removeAll { $0 == id }
        idleIfSilent()
    }

    /// Stops everything (content released).
    func stopAll() {
        for layer in layers.values { layer.playback.stop() }
        layers.removeAll()
        order.removeAll()
        fadeTimer?.invalidate()
        fadeTimer = nil
        mixer?.idle()
    }

    // MARK: - Scripts

    func perform(_ playback: SceneScriptObjectCommand.Playback, on id: Int) {
        guard let layer = layers[id] else { return }
        switch playback {
        case .play: layer.playback.play()
        case .pause: layer.playback.pause()
        case .stop: layer.playback.stop()
        }
        idleIfSilent()
    }

    /// `volume` as a script left it.
    func setVolume(_ volume: Float, of id: Int) {
        guard let layer = layers[id], layer.playback.volume != volume else { return }
        layer.playback.setVolume(volume)
        idleIfSilent()
    }

    func isPlaying(_ id: Int) -> Bool? { layers[id]?.playback.isPlaying }

    func playback(of id: Int) -> SceneSoundPlayback? { layers[id]?.playback }

    // MARK: - Frame

    /// WE's per-frame update, `seconds` of real time since the last draw.
    func update(deltaTime seconds: Double) {
        guard !layers.isEmpty else { return }
        for id in order {
            guard let layer = layers[id] else { continue }
            layer.playback.update(deltaTime: seconds)
            place(layer)
        }
        idleIfSilent()
    }

    /// Places a spatialized layer's files at its object (0x1401f5029): WE sets one position for
    /// every file of the sound.
    private func place(_ layer: Layer) {
        guard !layer.voices.spatialFiles.isEmpty else { return }
        let world = locate(layer.content.id) ?? .zero
        let position = SceneSoundSpatialization.position(world: world, listener: listener)
        let gains = SceneSoundSpatialization.gains(position: position, minDistance: layer.content.minDistance,
                                                   attenuation: layer.content.attenuation)
        for file in layer.voices.spatialFiles { layer.voices.setSpatialGains(gains, file: file) }
    }

    // MARK: - Wallpaper gain

    /// The gain the wallpaper fades to. The first target (before any sound played) is taken at once.
    func setTargetGain(_ target: Float) {
        let target = max(target, 0)
        targetGain = target
        if layers.isEmpty && fadeTimer == nil {
            gain = target
            return
        }
        guard gain != target, fadeTimer == nil else { return }
        lastFadeTime = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = CACurrentMediaTime()
            let seconds = now - self.lastFadeTime
            self.lastFadeTime = now
            // Frames step the fade while they come.
            guard now - self.lastFrameFade > Self.frameGap else { return }
            self.stepFade(min(max(seconds, SceneClock.minimumFrameDelta), SceneClock.maximumFrameDelta))
        }
        fadeTimer = timer
        // On the owner's run loop (the renderer's render thread), so the fade and the frames step
        // the same state on one thread. Common modes: default-mode timers stall while menus track.
        RunLoop.current.add(timer, forMode: .common)
    }

    /// A drawn frame's step of the fade: `frameSeconds` is its wall step, clamped as the scene
    /// clock clamps it (`SceneClock.frame`).
    func advanceFade(frameSeconds: Double) {
        lastFrameFade = CACurrentMediaTime()
        guard gain != targetGain else { return }
        stepFade(frameSeconds)
    }

    /// One step of WE's fade, `seconds` long.
    func stepFade(_ seconds: Double) {
        let next = SceneClock.ease(gain, toward: targetGain, seconds: max(seconds, 0))
        if next != gain {
            gain = next
            for id in order { layers[id]?.playback.setSceneGain(next) }
        }
        if gain == targetGain {
            fadeTimer?.invalidate()
            fadeTimer = nil
        }
        idleIfSilent()
    }

    /// The one mixer of this wallpaper instance, made when the first voice plays.
    private func sharedMixer() -> SceneSoundMixer {
        if let mixer { return mixer }
        let made = SceneSoundMixer(label: label, offline: offline)
        mixer = made
        return made
    }

    /// Pauses the engine while no voice plays.
    private func idleIfSilent() {
        guard let mixer else { return }
        let anyPlaying = layers.values.contains { $0.playback.hasSoundingVoice }
        if !anyPlaying { mixer.idle() }
    }

    /// The mixer (tests render it offline).
    var soundMixer: SceneSoundMixer? { mixer }
}
