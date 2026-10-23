import Foundation

/// The screen saver's shared folder, where the app writes what the savers read: the live frames'
/// manifest (`ScreenSaverLiveManifest`) and the stills (`ScreenSaverStills`).
///
/// **Path.** `~/Library/Application Support/Open Wallpaper Engine/ScreenSaver`
/// (`ScreenSaverManifest.sharedFolder`). macOS stops the app writing into the screen saver host's
/// container, but the host (`legacyScreenSaver`) may read any path, so the saver reads them there.
/// An isolated copy (`AppStorageLocation`) writes under its own support folder instead, where no
/// saver looks, so a test or development run never changes what the user's saver shows.
struct ScreenSaverVideoStore: Sendable {
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

    func url(fileName: String) -> URL { directory.appending(path: fileName, directoryHint: .notDirectory) }

    /// Whether `name` is one of the stills (`stills.json`, a picture, or one being written:
    /// `ScreenSaverStillPublisher` stages it as `.<uuid>-still-…`).
    static func isStill(_ name: String) -> Bool {
        name == ScreenSaverStills.fileName || name.hasPrefix("still-") || name.hasPrefix(".") && name.contains("-still-")
    }

    /// The plugin was turned off: the manifests go, the stills stay (`isStill`), so a
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
