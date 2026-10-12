import CryptoKit
import Foundation

/// Where the screen saver's loop videos live and what they are called.
///
/// **Path.** The videos go in `~/Library/Application Support/Open Wallpaper Engine/ScreenSaver`
/// (`ScreenSaverManifest.sharedFolder`). macOS stops the app writing into the screen saver host's
/// container, but the host (`legacyScreenSaver`) may read any path, so the saver reads them there.
/// An isolated copy (`AppStorageLocation`) writes under its own support folder instead, where no
/// saver looks, so a test or development run never changes what the user's saver plays.
///
/// **Names.** `<wallpaper key>-<property hash>-<width>x<height>-r<revision>.mov`: the wallpaper's
/// folder (`SceneLoadingSnapshotStore.wallpaperKey`) and content (`contentKey`), a hash of its
/// user properties, the display's pixel size and `revision`. A changed wallpaper, property,
/// display or renderer gives a new name, so a stale video is never played, and `retain` removes
/// every video the manifest no longer lists.
struct ScreenSaverVideoStore: Sendable {
    /// Bump whenever the rendered video changes (loop rules, encoding, what is drawn).
    static let revision = 3
    static let fileExtension = "mov"

    let directory: URL

    static var current: ScreenSaverVideoStore {
        ScreenSaverVideoStore(location: .current, home: ScreenSaverManifest.userHome)
    }

    init(directory: URL) { self.directory = directory }

    init(location: AppStorageLocation, home: URL) {
        directory = location.isIsolated
            ? location.supportDirectory.appending(path: "ScreenSaver", directoryHint: .isDirectory)
            : ScreenSaverManifest.sharedFolder(home: home)
    }

    // MARK: Keys

    /// A hash of a wallpaper's user properties, independent of their order.
    static func propertyHash(_ properties: [String: String]) -> String {
        let text = properties.keys.sorted().map { "\($0)=\(properties[$0] ?? "")" }.joined(separator: "\n")
        return SHA256.hash(data: Data(text.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    /// The video's file name for a wallpaper (`wallpaperKey` + `contentKey`), its property hash
    /// and a display's pixel size.
    static func fileName(wallpaperKey: String, contentKey: String, propertyHash: String, pixelSize: SIMD2<Int>) -> String {
        "\(wallpaperKey)_\(contentKey)-\(propertyHash)-\(pixelSize.x)x\(pixelSize.y)-r\(revision).\(fileExtension)"
    }

    func url(fileName: String) -> URL { directory.appending(path: fileName, directoryHint: .notDirectory) }

    var manifestURL: URL { directory.appending(path: ScreenSaverManifest.fileName, directoryHint: .notDirectory) }

    func exists(fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: url(fileName: fileName).path(percentEncoded: false))
    }

    // MARK: Writing

    func writeManifest(_ manifest: ScreenSaverManifest) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(manifest).write(to: manifestURL, options: .atomic)
    }

    /// Whether `name` is a file the saver reads besides the videos: the manifests (the videos',
    /// the live frames') and the stills (`ScreenSaverStills`, its pictures).
    static func isKept(_ name: String) -> Bool {
        name == ScreenSaverManifest.fileName || name == ScreenSaverLiveManifest.fileName || isStill(name)
    }

    /// Whether `name` is one of the stills (`stills.json`, a picture, or one being written:
    /// `ScreenSaverStillPublisher` stages it as `.<uuid>-still-…`).
    static func isStill(_ name: String) -> Bool {
        name == ScreenSaverStills.fileName || name.hasPrefix("still-") || name.hasPrefix(".") && name.contains("-still-")
    }

    /// Removes every video but `keep` (and partial renders), so only the current ones stay; the
    /// manifests and the stills stay.
    func retain(_ keep: Set<String>) {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        } catch {
            // Optional: no folder yet means nothing to remove.
            return
        }
        for file in files where !Self.isKept(file.lastPathComponent) && !keep.contains(file.lastPathComponent) {
            do { try FileManager.default.removeItem(at: file) } catch {
                OWELog.error(.app, "Screen saver: can't remove \(file.lastPathComponent): \(error)")
            }
        }
    }

    // MARK: Earlier versions' recordings

    /// Whether `name` is a video an earlier version recorded here: a scene's or a page's loop
    /// (`<wallpaper>_<content>-<property hash>-<width>x<height>-r<revision>.mov`) or a Screen Saver
    /// mode recording of one (the same with `-rec<time>`). A video wallpaper's own file
    /// (`…-video-r<revision>.<extension>`) and anything else isn't.
    static func isOldRecording(_ name: String) -> Bool {
        name.range(of: #"^[^/]+-[0-9a-f]{12}-[0-9]+x[0-9]+-r[0-9]+(-rec[0-9]+)?\.mov$"#, options: .regularExpression) != nil
            && !name.contains("-video-r")
    }

    /// Deletes the loop videos and recordings earlier versions made: only regular files directly
    /// in `folder` named as they were (`isOldRecording`), never one `keep` lists, never a link,
    /// a folder or anything outside it. Each deletion is logged. Returns the names deleted.
    @discardableResult
    static func removeOldRecordings(in folder: URL, keeping keep: Set<String> = []) -> [String] {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        } catch {
            // Optional: no folder means nothing to delete.
            return []
        }
        var removed: [String] = []
        for file in files where isOldRecording(file.lastPathComponent) && !keep.contains(file.lastPathComponent) {
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) // Optional: unreadable is skipped.
            guard values?.isRegularFile == true, values?.isSymbolicLink != true else { continue }
            do {
                try FileManager.default.removeItem(at: file)
                removed.append(file.lastPathComponent)
                OWELog.info(.app, "Screen saver: deleted the old recording \(file.lastPathComponent) from \(folder.lastPathComponent)")
            } catch {
                OWELog.error(.app, "Screen saver: can't delete the old recording \(file.lastPathComponent): \(error)")
            }
        }
        return removed
    }

    /// Deletes the recordings earlier versions left: in this folder (but `keep`), and in the
    /// recordings' staging folder in Caches, which goes once empty.
    func removeOldRecordings(cachesDirectory: URL, keeping keep: Set<String>) {
        Self.removeOldRecordings(in: directory, keeping: keep)
        let staging = cachesDirectory.appending(path: "ScreenSaverRecordings", directoryHint: .isDirectory)
        Self.removeOldRecordings(in: staging)
        if let left = try? FileManager.default.contentsOfDirectory(atPath: staging.path(percentEncoded: false)), left.isEmpty { // Optional: absent is fine.
            try? FileManager.default.removeItem(at: staging) // Optional: an empty folder of ours.
        }
    }

    /// The plugin was turned off: the videos and manifests go, the stills stay (`isStill`), so a
    /// saver shown before the next enable, or right after it, isn't left blank. The folder goes
    /// once nothing is left in it.
    func removeAll() {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        } catch {
            // Optional: no folder means nothing to remove.
            return
        }
        for file in files where !Self.isStill(file.lastPathComponent) {
            do { try FileManager.default.removeItem(at: file) } catch {
                OWELog.error(.app, "Screen saver: can't remove \(file.lastPathComponent): \(error)")
            }
        }
        if let left = try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)), left.isEmpty { // Optional: gone is fine.
            try? FileManager.default.removeItem(at: directory) // Optional: an empty folder of ours.
        }
    }
}
