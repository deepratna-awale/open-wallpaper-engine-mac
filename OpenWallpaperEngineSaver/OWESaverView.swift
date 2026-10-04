import AVFoundation
import ScreenSaver

/// The bundled screen saver: plays the current wallpaper's loop video (or a video wallpaper's
/// own file, `AVPlayerLooper` making its loop seamless), which the app renders into
/// the saver host's container (`ScreenSaverManifest`), filling the screen, looping without a gap.
/// Each display plays the video listed for it; a stretched one shows its rect of the video.
/// Black when the app hasn't rendered one yet.
@objc(OWESaverView)
final class OWESaverView: ScreenSaverView {
    private let playerLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    /// The rect of the video this display shows; nil for the whole video.
    private var crop: ScreenSaverManifest.Crop?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true
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
        guard player == nil, let (url, rate) = videoURL() else { return }
        layoutPlayer()
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        looper = AVPlayerLooper(player: player, templateItem: item)
        playerLayer.player = player
        self.player = player
        if let rate, rate > 0 {
            player.defaultRate = rate
            player.rate = rate
        } else {
            player.play()
        }
    }

    override func stopAnimation() {
        super.stopAnimation()
        player?.pause()
        looper = nil
        player = nil
        playerLayer.player = nil
    }

    override var hasConfigureSheet: Bool { false }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutPlayer()
    }

    /// The whole view, or for a crop the whole video placed so the crop fills the view (an
    /// `AVPlayerLayer`'s `contentsRect` doesn't reach its video). The crop has the display's
    /// aspect, so the video is scaled to it exactly.
    private func layoutPlayer() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let crop {
            playerLayer.autoresizingMask = []
            playerLayer.videoGravity = .resize
            playerLayer.frame = crop.playerFrame(in: bounds)
        } else {
            playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            playerLayer.videoGravity = .resizeAspectFill
            playerLayer.frame = bounds
        }
        CATransaction.commit()
    }

    /// This view's display's identity, as the app names displays (`DisplayIdentity`).
    private var displayIdentity: String? {
        guard let number = window?.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }

    /// The manifest's video for this view's display and pixel size.
    private func videoURL() -> (URL, Float?)? {
        let folder = ScreenSaverManifest.sharedFolder(home: ScreenSaverManifest.userHome)
        guard let data = try? Data(contentsOf: folder.appending(path: ScreenSaverManifest.fileName)),
              let manifest = try? JSONDecoder().decode(ScreenSaverManifest.self, from: data),
              manifest.revision == ScreenSaverManifest.revision else { return nil } // No video yet: stay black.
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let pixels = (width: Int(bounds.width * scale), height: Int(bounds.height * scale))
        // A video wallpaper's entry may be a link to the library file; AVFoundation follows it.
        guard let video = manifest.video(forDisplay: displayIdentity, pixels: pixels) else { return nil }
        crop = video.crop
        return (folder.appending(path: video.file), video.rate)
    }
}
