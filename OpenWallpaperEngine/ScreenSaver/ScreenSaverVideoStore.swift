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
    static let revision = 2
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

    /// Removes every video but `keep` (and partial renders), so only the current ones stay.
    func retain(_ keep: Set<String>) {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        } catch {
            // Optional: no folder yet means nothing to remove.
            return
        }
        for file in files where file.lastPathComponent != ScreenSaverManifest.fileName
            && !keep.contains(file.lastPathComponent) {
            do { try FileManager.default.removeItem(at: file) } catch {
                OWELog.error(.app, "Screen saver: can't remove \(file.lastPathComponent): \(error)")
            }
        }
    }

    /// Removes the folder: the plugin was turned off.
    func removeAll() {
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else { return }
        do { try FileManager.default.removeItem(at: directory) } catch {
            OWELog.error(.app, "Screen saver: can't remove the videos: \(error)")
        }
    }
}
