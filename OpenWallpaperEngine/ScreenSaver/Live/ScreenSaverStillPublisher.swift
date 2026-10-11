import CoreGraphics
import Foundation

/// Keeps the savers' still pictures (`ScreenSaverStills`) the lock screen's: each time a display's
/// desktop picture is written (`DesktopPictureSync.onPictureWritten`), it is hard-linked into the
/// shared folder (copied when the folders are on different volumes) under the display's name,
/// replacing the earlier one in one rename, and listed in `stills.json`. Only the user's own copy
/// writes them (an isolated copy never installs the saver). Main thread.
@MainActor
final class ScreenSaverStillPublisher {
    let folder: URL
    private let fileManager = FileManager.default

    init(folder: URL) {
        self.folder = folder
    }

    static var current: ScreenSaverStillPublisher {
        ScreenSaverStillPublisher(folder: ScreenSaverVideoStore.current.directory)
    }

    /// `picture` is what display `display` (its identity) shows now.
    func publish(_ picture: URL, display: String) {
        let name = ScreenSaverStills.fileName(display: display, fileExtension: picture.pathExtension.lowercased())
        let target = folder.appending(path: name, directoryHint: .notDirectory)
        let staging = folder.appending(path: ".\(UUID().uuidString)-\(name)", directoryHint: .notDirectory)
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            do {
                try fileManager.linkItem(at: picture, to: staging)
            } catch {
                try fileManager.copyItem(at: picture, to: staging)
            }
            // rename(2) replaces the earlier still at once: a saver never finds it missing.
            guard rename(staging.path(percentEncoded: false), target.path(percentEncoded: false)) == 0 else {
                throw CocoaError(.fileWriteUnknown)
            }
            var stills = ScreenSaverStills.read(folder.appending(path: ScreenSaverStills.fileName)) ?? ScreenSaverStills()
            let previous = stills.stills[display]
            stills.stills[display] = name
            try JSONEncoder().encode(stills).write(to: folder.appending(path: ScreenSaverStills.fileName), options: .atomic)
            // Another format's earlier still (a .jpg after a .heic) is no longer listed.
            if let previous, previous != name {
                try? fileManager.removeItem(at: folder.appending(path: previous)) // Optional: a stale file.
            }
        } catch {
            try? fileManager.removeItem(at: staging) // Optional: the failed attempt's leftover.
            OWELog.error(.app, "Screen saver: can't keep the still of display \(display): \(error)")
        }
    }

    /// `picture` is what the display with id `display` shows now.
    func publish(_ picture: URL, display: CGDirectDisplayID) {
        publish(picture, display: DisplayIdentity.identity(of: display))
    }
}
