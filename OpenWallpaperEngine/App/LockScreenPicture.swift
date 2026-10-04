import AppKit

/// The files and records behind each display's desktop picture (`DesktopPictureSync`): the
/// picture OWE sets, which the lock screen and the menu bar's tint show, and the user's own
/// pictures to put back.
///
/// - **Files.** A display's picture is OWE's own copy in its desktop-picture folder
///   (`DesktopSnapshotCache`) as `lock-<display>-<a|b>.<heic|jpg>`, never a file of a cache that
///   trims itself (the loading snapshots, the video frames), so a picture in use can't vanish.
///   The name alternates (macOS ignores setting the URL it already shows). Both slots stay while
///   the app runs and after it quits: desktop pictures are per Space, and a Space OWE can't reach
///   now may still show either. `DesktopSnapshotCache.isSnapshot` never saves one as the user's.
/// - **The user's pictures.** The first time a display's picture is replaced, the picture it
///   showed is recorded per display (`originalsKey`); turning the pictures off, or quitting, puts
///   them back when they still exist.
/// - **Isolation.** An isolated copy never sets, saves or restores the picture
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

    /// Forgets the recorded pictures of `displays`, all of them for nil.
    func forgetOriginals(of displays: [CGDirectDisplayID]? = nil) {
        guard let displays else { return defaults.removeObject(forKey: Self.originalsKey) }
        var stored = defaults.dictionary(forKey: Self.originalsKey) as? [String: String] ?? [:]
        for display in displays { stored[String(display)] = nil }
        defaults.set(stored, forKey: Self.originalsKey)
    }

    /// The picture to put back on each display that shows one of OWE's pictures now: its recorded
    /// original, else `fallback` (the main display's picture at launch, `OSWallpaper`), whichever
    /// still exists and isn't OWE's. A display with neither keeps OWE's picture, which stays on
    /// disk: never a missing file.
    func restorePlan(showing: [CGDirectDisplayID: URL?], fallback: URL?,
                     exists: (URL) -> Bool = LockScreenPicture.fileExists) -> [CGDirectDisplayID: URL] {
        let originals = originals()
        func usable(_ url: URL?) -> URL? {
            guard let url, !cache.isSnapshot(url), exists(url) else { return nil }
            return url
        }
        var plan: [CGDirectDisplayID: URL] = [:]
        for (display, url) in showing {
            guard let url, cache.isSnapshot(url), let original = usable(originals[display]) ?? usable(fallback) else { continue }
            plan[display] = original
        }
        return plan
    }

    /// The picture to save as the user's (`OSWallpaper`): the saved one while it still exists and
    /// isn't OWE's, else the one shown now if that is the user's; nil keeps nothing (an earlier
    /// run left OWE's picture showing).
    func userPicture(saved: URL?, showing: URL?, exists: (URL) -> Bool = LockScreenPicture.fileExists) -> URL? {
        for url in [saved, showing].compactMap({ $0 }) where !cache.isSnapshot(url) && exists(url) { return url }
        return nil
    }

    static func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    // MARK: Writing

    /// Copies `snapshot` into the display's next slot and returns its URL.
    func write(snapshot: URL, display: CGDirectDisplayID, showing: URL?) throws -> URL {
        let target = try clearedSlot(display: display, showing: showing, fileExtension: snapshot.pathExtension.lowercased())
        try FileManager.default.copyItem(at: snapshot, to: target)
        return target
    }

    /// Writes an encoded picture into the display's next slot and returns its URL.
    func write(_ data: Data, fileExtension: String, display: CGDirectDisplayID, showing: URL?) throws -> URL {
        let target = try clearedSlot(display: display, showing: showing, fileExtension: fileExtension)
        try data.write(to: target, options: .atomic)
        return target
    }

    /// The next slot's URL, with that slot's files in every format removed.
    private func clearedSlot(display: CGDirectDisplayID, showing: URL?, fileExtension: String) throws -> URL {
        try FileManager.default.createDirectory(at: cache.directory, withIntermediateDirectories: true)
        let slot = nextSlot(display: display, showing: showing)
        for other in SceneLoadingSnapshotStore.extensions {
            let file = url(display: display, slot: slot, fileExtension: other)
            guard Self.fileExists(file) else { continue }
            try FileManager.default.removeItem(at: file)
        }
        return url(display: display, slot: slot, fileExtension: fileExtension)
    }
}
