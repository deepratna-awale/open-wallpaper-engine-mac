import AppKit

/// Sets each display's system desktop picture to the scene wallpaper's full-resolution loading
/// snapshot (`SceneLoadingSnapshotStore`), so the lock screen, which shows the desktop picture,
/// shows the wallpaper. Nothing new is captured: a display with no snapshot yet keeps its picture
/// until the running scene writes one (`SceneLoadingSnapshotCapture`), which then shows on every
/// display still showing that wallpaper (`snapshotSaved`), as does a new one after the user's
/// properties change.
///
/// - **Files.** The snapshot is copied into OWE's desktop-picture folder (`DesktopSnapshotCache`)
///   as `lock-<display>-<a|b>.<heic|jpg>`, alternating like the menu bar tint's pictures (macOS
///   ignores setting the URL it already shows), so the snapshot store's LRU can't remove a picture
///   in use, and `DesktopSnapshotCache.isSnapshot` never saves it as the user's own.
/// - **The user's pictures.** The first time a display's picture is replaced, the picture it
///   showed is recorded per display (`originalsKey`); turning the setting off, or quitting, puts
///   them back.
/// - **Menu bar tint.** Scenes had no tint picture, so this is the scene's tint picture too. Video
///   and web wallpapers keep the tint picture (`DesktopSnapshotCache.setDesktopPicture`). Turning
///   the tint off while this is on leaves the lock-screen picture in place.
/// - **Isolation.** Like the tint, an isolated copy never sets, saves or restores the picture
///   (`DesktopSnapshotCache.mayChangeDesktopPicture`).
struct LockScreenPicture: @unchecked Sendable { // UserDefaults is thread-safe; the rest is immutable.
    static let prefix = "lock-"
    /// `[display id: picture URL]` of the pictures shown before OWE replaced them.
    static let originalsKey = "LockScreenOriginalPictures"

    let cache: DesktopSnapshotCache
    let defaults: UserDefaults

    static var current: LockScreenPicture { LockScreenPicture(cache: .current, defaults: .app) }

    // MARK: Names

    func url(display: CGDirectDisplayID, slot: Int, fileExtension: String) -> URL {
        cache.directory.appending(path: "\(Self.prefix)\(display)-\(slot == 0 ? "a" : "b").\(fileExtension)",
                                  directoryHint: .notDirectory)
    }

    /// Whether `url` is a lock-screen picture OWE set.
    func isLockPicture(_ url: URL) -> Bool {
        cache.isSnapshot(url) && url.lastPathComponent.hasPrefix(Self.prefix)
    }

    /// The slot to write next: the one `showing` isn't.
    func nextSlot(display: CGDirectDisplayID, showing: URL?) -> Int {
        guard let showing, isLockPicture(showing) else { return 0 }
        return showing.deletingPathExtension().lastPathComponent.hasSuffix("-a") ? 1 : 0
    }

    // MARK: The user's pictures

    func originals() -> [CGDirectDisplayID: URL] {
        let stored = defaults.dictionary(forKey: Self.originalsKey) as? [String: String] ?? [:]
        var result: [CGDirectDisplayID: URL] = [:]
        for (key, value) in stored {
            guard let id = CGDirectDisplayID(key), let url = URL(string: value) else { continue }
            result[id] = url
        }
        return result
    }

    /// Records what `display` shows as the user's picture, unless it is one of OWE's own or one is
    /// already recorded (the first replaced picture is the user's).
    func recordOriginal(_ showing: URL?, display: CGDirectDisplayID) {
        guard let showing, !cache.isSnapshot(showing) else { return }
        var stored = defaults.dictionary(forKey: Self.originalsKey) as? [String: String] ?? [:]
        guard stored[String(display)] == nil else { return }
        stored[String(display)] = showing.absoluteString
        defaults.set(stored, forKey: Self.originalsKey)
    }

    func forgetOriginals() { defaults.removeObject(forKey: Self.originalsKey) }

    /// The picture to put back on each display that shows a lock-screen picture now: its recorded
    /// original, else `fallback` (the main display's picture at launch, `OSWallpaper`).
    func restorePlan(showing: [CGDirectDisplayID: URL?], fallback: URL?) -> [CGDirectDisplayID: URL] {
        let originals = originals()
        var plan: [CGDirectDisplayID: URL] = [:]
        for (display, url) in showing {
            guard let url, isLockPicture(url), let original = originals[display] ?? fallback else { continue }
            plan[display] = original
        }
        return plan
    }

    // MARK: Writing

    /// Copies `snapshot` into the display's next slot and returns its URL.
    func write(snapshot: URL, display: CGDirectDisplayID, showing: URL?) throws -> URL {
        try FileManager.default.createDirectory(at: cache.directory, withIntermediateDirectories: true)
        let target = url(display: display, slot: nextSlot(display: display, showing: showing),
                         fileExtension: snapshot.pathExtension.lowercased())
        if FileManager.default.fileExists(atPath: target.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.copyItem(at: snapshot, to: target)
        return target
    }

    /// Removes the display's lock pictures other than `kept` (all of them for nil).
    func removePictures(display: CGDirectDisplayID, except kept: URL?) {
        for slot in 0...1 {
            for fileExtension in SceneLoadingSnapshotStore.extensions {
                let file = url(display: display, slot: slot, fileExtension: fileExtension)
                guard file.standardizedFileURL != kept?.standardizedFileURL,
                      FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else { continue }
                do { try FileManager.default.removeItem(at: file) } catch {
                    OWELog.error(.app, "Lock screen picture: can't remove \(file.lastPathComponent): \(error)")
                }
            }
        }
    }

    // MARK: Applying

    private static let queue = DispatchQueue(label: "OWE.LockScreenPicture", qos: .utility)

    /// Shows `wallpaper`'s loading snapshot on every screen, when it is a scene with snapshots.
    /// File IO runs off the main thread.
    @MainActor
    static func apply(_ wallpaper: WEWallpaper, screens: [NSScreen] = NSScreen.screens) {
        guard DesktopSnapshotCache.mayChangeDesktopPicture,
              wallpaper.project.type.caseInsensitiveCompare("scene") == .orderedSame else { return }
        let picture = LockScreenPicture.current
        let store = SceneLoadingSnapshotStore.current
        let directory = wallpaper.wallpaperDirectory
        let targets = screens.compactMap { screen -> (CGDirectDisplayID, URL?, SIMD2<Int>)? in
            guard let id = DesktopSnapshotCache.displayID(screen) else { return nil }
            let size = SIMD2(Int(screen.frame.width * screen.backingScaleFactor),
                             Int(screen.frame.height * screen.backingScaleFactor))
            return (id, NSWorkspace.shared.desktopImageURL(for: screen), size)
        }
        let strips = DesktopPictureTheming.strips()
        queue.async {
            guard let contentKey = SceneLoadingSnapshotStore.contentKey(for: directory) else { return }
            var written: [(CGDirectDisplayID, URL?, URL)] = []
            for (id, showing, size) in targets {
                guard let snapshot = store.bestSnapshot(forWallpaperAt: directory, contentKey: contentKey,
                                                        pixelSize: size) else { continue }
                do {
                    let url = try picture.write(snapshot: snapshot, display: id, showing: showing)
                    DesktopPictureTheming.draw(strips, into: url, display: id)
                    written.append((id, showing, url))
                } catch {
                    OWELog.error(.app, "Lock screen picture: can't copy the snapshot: \(error)")
                }
            }
            DispatchQueue.main.async {
                for (id, showing, url) in written {
                    guard let screen = NSScreen.screens.first(where: { DesktopSnapshotCache.displayID($0) == id }) else { continue }
                    picture.recordOriginal(showing, display: id)
                    do {
                        try NSWorkspace.shared.setDesktopImageURL(url, for: screen)
                        queue.async { picture.removePictures(display: id, except: url) }
                    } catch {
                        OWELog.error(.app, "Lock screen picture: setting the desktop picture failed: \(error)")
                    }
                }
            }
        }
    }

    /// The screens whose picture should become the snapshot just saved for the wallpaper at
    /// `directory`: those still showing that wallpaper, when the setting is on and this copy may
    /// change the desktop picture.
    static func screensToRefresh<Screen>(savedFor directory: URL, screens: [Screen],
                                         shownDirectory: (Screen) -> URL?,
                                         isOn: Bool, mayChange: Bool) -> [Screen] {
        guard isOn, mayChange else { return [] }
        let saved = directory.standardizedFileURL.path
        return screens.filter { shownDirectory($0)?.standardizedFileURL.path == saved }
    }

    /// A running scene saved a loading snapshot of the wallpaper at `directory`
    /// (`SceneLoadingSnapshotCapture`): shows it on the displays still showing that wallpaper.
    /// Called off the main thread; the work is queued there.
    static func snapshotSaved(wallpaperDirectory directory: URL) {
        Task { @MainActor in
            let app = AppDelegate.shared
            let model = app.wallpaperViewModel
            let screens = screensToRefresh(
                savedFor: directory, screens: NSScreen.screens,
                shownDirectory: { model.wallpaper(for: WallpaperViewModel.screenId(for: $0)).wallpaperDirectory },
                isOn: app.globalSettingsViewModel.settings.lockScreenPicture,
                mayChange: DesktopSnapshotCache.mayChangeDesktopPicture)
            guard let first = screens.first else { return }
            apply(model.wallpaper(for: WallpaperViewModel.screenId(for: first)), screens: screens)
        }
    }

    /// Puts the user's pictures back on the screens showing a lock-screen picture, and forgets them.
    @MainActor
    static func restore(screens: [NSScreen] = NSScreen.screens, synchronously: Bool = false) {
        guard DesktopSnapshotCache.mayChangeDesktopPicture else { return }
        let picture = LockScreenPicture.current
        var showing: [CGDirectDisplayID: URL?] = [:]
        for screen in screens {
            guard let id = DesktopSnapshotCache.displayID(screen) else { continue }
            showing[id] = NSWorkspace.shared.desktopImageURL(for: screen)
        }
        let plan = picture.restorePlan(showing: showing, fallback: UserDefaults.app.url(forKey: "OSWallpaper"))
        for screen in screens {
            guard let id = DesktopSnapshotCache.displayID(screen), let original = plan[id] else { continue }
            do { try NSWorkspace.shared.setDesktopImageURL(original, for: screen) } catch {
                OWELog.error(.app, "Lock screen picture: restoring the user's picture failed: \(error)")
            }
        }
        picture.forgetOriginals()
        let ids = Array(showing.keys)
        let remove = { ids.forEach { picture.removePictures(display: $0, except: nil) } }
        // On quit the files go before the process does.
        if synchronously { remove() } else { queue.async(execute: remove) }
    }
}
