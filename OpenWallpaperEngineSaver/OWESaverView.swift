import AVFoundation
import ScreenSaver

/// The bundled screen saver: plays the current wallpaper's loop video, which the app renders into
/// the saver host's container (`ScreenSaverManifest`), filling the screen, looping without a gap.
/// Black when the app hasn't rendered one yet.
@objc(OWESaverView)
final class OWESaverView: ScreenSaverView {
    private let playerLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = bounds
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer?.addSublayer(playerLayer)
        animationTimeInterval = 1
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func startAnimation() {
        super.startAnimation()
        guard player == nil, let url = videoURL() else { return }
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        looper = AVPlayerLooper(player: player, templateItem: item)
        playerLayer.player = player
        self.player = player
        player.play()
    }

    override func stopAnimation() {
        super.stopAnimation()
        player?.pause()
        looper = nil
        player = nil
        playerLayer.player = nil
    }

    override var hasConfigureSheet: Bool { false }

    /// The manifest's video for this view's pixel size.
    private func videoURL() -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let folder = ScreenSaverManifest.folderInsideContainer(applicationSupport: support)
        guard let data = try? Data(contentsOf: folder.appending(path: ScreenSaverManifest.fileName)),
              let manifest = try? JSONDecoder().decode(ScreenSaverManifest.self, from: data),
              manifest.revision == ScreenSaverManifest.revision else { return nil } // No video yet: stay black.
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let pixels = (width: Int(bounds.width * scale), height: Int(bounds.height * scale))
        return manifest.video(forPixels: pixels).map { folder.appending(path: $0.file) }
    }
}
