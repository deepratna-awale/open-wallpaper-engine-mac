//
//  WebKitVideoWallpaperView.swift
//  Open Wallpaper Engine
//

import SwiftUI
import WebKit

/// A video wallpaper AVFoundation can't decode (`WebKitVideoPlayer.handles`) on one display: a
/// page per display, like a web wallpaper, paused by that display's playback rule and heard only
/// on the wallpaper's audible display, and moved by its music sync like the AVKit path.
struct WebKitVideoWallpaperView: NSViewRepresentable {
    @ObservedObject var wallpaperViewModel: WallpaperViewModel
    /// Redraws the view when a music-sync control changes.
    @ObservedObject var musicSyncStore = VideoMusicSyncStore.shared
    let screenId: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let wallpaper = wallpaperViewModel.wallpaper(for: screenId)
        // A page made before a transition's change (`prepare`) is already loading, so building the
        // view doesn't hold the main thread while the transition plays.
        let player = WebKitVideoPreparedPages.shared.take(wallpaper.mediaURL, on: screenId)
            ?? WebKitVideoPlayer(url: wallpaper.mediaURL, readAccess: wallpaper.wallpaperDirectory)
        context.coordinator.player = player
        player.state = state(for: wallpaper)
        player.musicSync = VideoMusicSyncEffect(wallpaper)
        // The WebKit initializer always makes a WKWebView.
        return player.webView ?? WKWebView()
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        let wallpaper = wallpaperViewModel.wallpaper(for: screenId)
        context.coordinator.player?.state = state(for: wallpaper)
        context.coordinator.player?.musicSync = VideoMusicSyncEffect(wallpaper)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.player?.stop()
        coordinator.player = nil
    }

    /// Makes the pages `wallpaper` will play in on `screenIds` now, before a transition changes to
    /// it: making a WKWebView and starting its web process holds the main thread for tens of
    /// milliseconds, which while a transition plays held up its frames. Only the displays that
    /// will show it through WebKit, each with a page of its own, get one.
    @MainActor
    static func prepare(_ wallpaper: WEWallpaper, on screenIds: Set<String>, wallpaperViewModel: WallpaperViewModel) {
        guard ["video", "remote-video"].contains(wallpaper.project.type.lowercased()),
              WebKitVideoPlayer.handles(wallpaper.mediaURL),
              WebEngineRouter.shared.engine(for: wallpaper) == .webKit else { return }
        for screenId in screenIds.sorted() where wallpaperViewModel.pageSource(of: screenId, engine: .webKit) == nil {
            WebKitVideoPreparedPages.shared.prepare(wallpaper.mediaURL, readAccess: wallpaper.wallpaperDirectory, on: screenId)
        }
    }

    private func state(for wallpaper: WEWallpaper) -> WebKitVideoPlayer.State {
        Self.state(for: wallpaper, wallpaperViewModel: wallpaperViewModel, screenId: screenId, engine: .webKit)
    }

    /// The player's state on `screenId`: the pause of the displays showing its page (its own and
    /// those mirroring it), the wallpaper's audible display and volume, placement and rate. Shared
    /// with the Chromium view.
    @MainActor
    static func state(for wallpaper: WEWallpaper, wallpaperViewModel: WallpaperViewModel,
                      screenId: String, engine: WebEngine) -> WebKitVideoPlayer.State {
        let key = WallpaperInstanceKey(wallpaper)
        let muted = !wallpaperViewModel.pagePlaysAudio(of: screenId, engine: engine) || wallpaperViewModel.playVolume == 0
            || !wallpaperViewModel.wallpaperPlayback(of: key).playsSound
        return WebKitVideoPlayer.State(placement: wallpaperViewModel.wallpaperPlacement,
                                       paused: !wallpaperViewModel.pageRendersFrames(of: screenId, engine: engine),
                                       muted: muted,
                                       volume: wallpaperViewModel.playVolume,
                                       // A page per display: its own playback rate (WE's option).
                                       rate: wallpaperViewModel.playRate
                                           * Float(wallpaperViewModel.displayOptions(on: screenId).playbackRate))
    }

    @MainActor
    final class Coordinator: WebPageSourceCoordinator {
        var player: WebKitVideoPlayer?
    }
}

/// WebKit video pages made ahead of the views that show them (`WebKitVideoWallpaperView.prepare`),
/// by display, until the display's view takes its page. One a view doesn't take in `lifetime` (the
/// change went elsewhere) is stopped.
@MainActor
final class WebKitVideoPreparedPages {
    static let shared = WebKitVideoPreparedPages()

    private struct Entry {
        let url: URL
        let player: WebKitVideoPlayer
        let expiry: Task<Void, Never>
    }
    private var entries: [String: Entry] = [:]
    let lifetime: Duration

    init(lifetime: Duration = .seconds(10)) {
        self.lifetime = lifetime
    }

    /// The displays with a page waiting.
    var screenIds: Set<String> { Set(entries.keys) }

    /// Starts a page for `url` on `screenId`, paused and silent until a view takes it; it replaces
    /// one waiting there.
    func prepare(_ url: URL, readAccess: URL, on screenId: String) {
        if let waiting = entries[screenId], waiting.url == url { return }
        discard(screenId)
        let player = WebKitVideoPlayer(url: url, readAccess: readAccess)
        player.state.paused = true
        let lifetime = lifetime
        let expiry = Task { @MainActor [weak self] in
            try? await Task.sleep(for: lifetime)
            guard !Task.isCancelled, let self, self.entries[screenId]?.player === player else { return }
            self.discard(screenId)
        }
        entries[screenId] = Entry(url: url, player: player, expiry: expiry)
    }

    /// The page waiting for `url` on `screenId`, which is then the caller's; nil when there is
    /// none, and one waiting there for another video is stopped.
    func take(_ url: URL, on screenId: String) -> WebKitVideoPlayer? {
        guard let entry = entries.removeValue(forKey: screenId) else { return nil }
        entry.expiry.cancel()
        guard entry.url == url else {
            entry.player.stop()
            return nil
        }
        return entry.player
    }

    private func discard(_ screenId: String) {
        guard let entry = entries.removeValue(forKey: screenId) else { return }
        entry.expiry.cancel()
        entry.player.stop()
    }
}
