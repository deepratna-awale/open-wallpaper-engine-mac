import Foundation

/// Next and Previous Wallpaper (Playback menu and status menu). In a playlist they step through
/// it; otherwise Next picks a random wallpaper from the list the library shows and Previous goes
/// back through the display's history. Both act on the selected displays, like the playlist.
extension WallpaperViewModel {
    /// Whether Next and Previous step through the active playlist.
    var stepsThroughPlaylist: Bool {
        playlistEnabled && activePlaylist?.items.isEmpty == false
    }

    func canStepToNextWallpaper(shown: [WEWallpaper]) -> Bool {
        stepsThroughPlaylist || Self.randomPick(from: shown, excluding: currentWallpaper) != nil
    }

    var canStepToPreviousWallpaper: Bool {
        stepsThroughPlaylist || selectedScreenIds.contains { screenId in
            wallpaperHistory.previous(for: screenId, showing: wallpaper(for: screenId)) != nil
        }
    }

    /// `shown`: the Installed list as filtered, searched and sorted now.
    func stepToNextWallpaper(shown: [WEWallpaper],
                             random: (Range<Int>) -> Int = { Int.random(in: $0) }) {
        if stepsThroughPlaylist {
            nextPlaylistWallpaper()
        } else if let pick = Self.randomPick(from: shown, excluding: currentWallpaper, random: random) {
            // Through `nextCurrentWallpaper`, so safe restart and the web trust prompt still apply.
            nextCurrentWallpaper = pick
        }
    }

    func stepToPreviousWallpaper() {
        if stepsThroughPlaylist {
            previousPlaylistWallpaper()
            return
        }
        for screenId in selectedScreenIds {
            guard let previous = wallpaperHistory.back(for: screenId, showing: wallpaper(for: screenId)),
                  confirmApply?(previous) ?? true else { continue }
            wallpapers[screenId] = previous
            addToRecents(previous)
        }
    }

    /// A random wallpaper of `shown` other than `current`; nil when there is none.
    static func randomPick(from shown: [WEWallpaper], excluding current: WEWallpaper,
                           random: (Range<Int>) -> Int = { Int.random(in: $0) }) -> WEWallpaper? {
        let candidates = shown.filter {
            $0.project != .invalid && $0.wallpaperDirectory != current.wallpaperDirectory
        }
        guard !candidates.isEmpty else { return nil }
        return candidates[random(candidates.indices)]
    }
}
