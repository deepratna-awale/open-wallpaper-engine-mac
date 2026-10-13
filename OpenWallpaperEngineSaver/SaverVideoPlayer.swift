import AVFoundation
import AppKit

/// The screen saver's loop video in a view: the current wallpaper's loop (or a video wallpaper's
/// own file), listed for the view's display in the app's manifest (`ScreenSaverManifest`), filling
/// the view and looping without a gap (`AVPlayerLooper`); a stretched display shows its rect of
/// the video. Nothing (black) when the app hasn't rendered one yet.
final class SaverVideoPlayer {
    let layer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    /// Logs a video the saver can't open (a file it may not read, a codec it can't decode).
    private var looperStatus: NSKeyValueObservation?
    /// The rect of the video this display shows; nil for the whole video.
    private var crop: ScreenSaverManifest.Crop?

    init() {
        layer.videoGravity = .resizeAspectFill
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
    }

    var isLoaded: Bool { player != nil }

    /// Loads and plays the manifest's video for `display` in `bounds` of `scale` pixels per point;
    /// false when there is none.
    @discardableResult
    func start(display: String?, bounds: CGRect, scale: CGFloat) -> Bool {
        if let player {
            player.play()
            return true
        }
        guard let (url, rate) = videoURL(display: display, bounds: bounds, scale: scale) else { return false }
        layout(in: bounds)
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        let looper = AVPlayerLooper(player: player, templateItem: item)
        let file = url.lastPathComponent
        looperStatus = looper.observe(\.status, options: [.initial, .new]) { looper, _ in
            guard looper.status == .failed else { return }
            SaverLog.lifecycle.error("video \(file, privacy: .public) can't play: \(String(describing: looper.error), privacy: .public)")
        }
        self.looper = looper
        layer.player = player
        self.player = player
        if let rate, rate > 0 {
            player.defaultRate = rate
            player.rate = rate
        } else {
            player.play()
        }
        return true
    }

    /// Pauses it, keeping the frame it shows.
    func pause() { player?.pause() }

    /// Unloads it.
    func stop() {
        player?.pause()
        looperStatus = nil
        looper = nil
        player = nil
        layer.player = nil
    }

    /// The whole view, or for a crop the whole video placed so the crop fills the view (an
    /// `AVPlayerLayer`'s `contentsRect` doesn't reach its video). The crop has the display's
    /// aspect, so the video is scaled to it exactly.
    func layout(in bounds: CGRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let crop {
            layer.autoresizingMask = []
            layer.videoGravity = .resize
            layer.frame = crop.playerFrame(in: bounds)
        } else {
            layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            layer.videoGravity = .resizeAspectFill
            layer.frame = bounds
        }
        CATransaction.commit()
    }

    /// The manifest's video for the display and the view's pixel size.
    private func videoURL(display: String?, bounds: CGRect, scale: CGFloat) -> (URL, Float?)? {
        let folder = ScreenSaverManifest.sharedFolder(home: ScreenSaverManifest.userHome)
        guard let data = try? Data(contentsOf: folder.appending(path: ScreenSaverManifest.fileName)),
              let manifest = try? JSONDecoder().decode(ScreenSaverManifest.self, from: data),
              manifest.revision == ScreenSaverManifest.revision else { return nil } // No video yet: stay black.
        let pixels = (width: Int(bounds.width * scale), height: Int(bounds.height * scale))
        // A video wallpaper's entry is a hard link or a copy of the library file: the saver can't
        // follow a symbolic link out of this folder.
        guard let video = manifest.video(forDisplay: display, pixels: pixels) else { return nil }
        crop = video.crop
        return (folder.appending(path: video.file), video.rate)
    }
}
