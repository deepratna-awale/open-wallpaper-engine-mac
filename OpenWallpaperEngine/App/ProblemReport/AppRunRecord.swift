import Foundation

/// Marks that the app is running: written at launch and removed when it quits cleanly
/// (`applicationWillTerminate`, which a normal quit, SIGTERM, logout and an update relaunch all
/// reach). Found at the next launch, it means that run crashed, hung and was force-quit, or the
/// Mac lost power, and `ProblemReporter` offers a report.
///
/// Unlike the safe-restart sentinel it is kept whether or not a wallpaper is showing.
struct AppRunRecord: Codable, Equatable, Sendable {
    var processIdentifier: Int32
    var started: Date
    var version: String
}

struct AppRunRecordStore {
    let fileURL: URL

    init(directory: URL = AppStorageLocation.current.supportDirectory) {
        fileURL = directory.appending(path: "Running.json", directoryHint: .notDirectory)
    }

    func load() -> AppRunRecord? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return OWELog.attempt(.app, "Run record", {
            try JSONDecoder().decode(AppRunRecord.self, from: Data(contentsOf: fileURL))
        })
    }

    func save(_ record: AppRunRecord) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(record).write(to: fileURL, options: .atomic)
        } catch {
            OWELog.error(.app, "Can't write the run record at \(fileURL.path): \(error)")
        }
    }

    func clear() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            OWELog.error(.app, "Can't remove the run record at \(fileURL.path): \(error)")
        }
    }
}
