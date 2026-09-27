import AVFoundation

/// The `AVPlayer`s behind a video wallpaper, on both the AVKit and the Metal path.
///
/// A wallpaper is decoration, not something being watched. `AVPlayer` by default holds a
/// `PreventUserIdleDisplaySleep` assertion for as long as it plays, even muted, so a playing video
/// wallpaper kept the displays awake all night, and the "displays asleep → pause" playback rule
/// (`DisplayPlaybackMonitor`) could never fire. Wallpaper Engine doesn't keep the display awake
/// either; the user's energy settings apply.
enum WallpaperAVPlayer {
    static func make(item: AVPlayerItem? = nil) -> AVPlayer {
        let player = AVPlayer(playerItem: item)
        player.preventsDisplaySleepDuringVideoPlayback = false
        return player
    }
}
