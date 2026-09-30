import CryptoKit
import Foundation

/// The repaired copies of videos AVFoundation refuses (`VideoSampleEntryRepair`), kept in the
/// app's caches so the wallpaper's own folder, which may be a Steam or linked folder, is never
/// written: `<Caches>/Open Wallpaper Engine/RepairedVideos/r<revision>/<source key>/<size>-<mtime>.<ext>`.
/// A source that changes (size or modification time) gets a new copy, and the old one is removed.
struct RepairedVideoCache {
    /// Bump whenever `VideoSampleEntryRepair` writes different bytes.
    static let revision = 1
    /// Containers the repair reads; anything else (WebM) is played as it is.
    static let repairableExtensions: Set<String> = ["mp4", "m4v", "mov"]

    let directory: URL

    static var current: RepairedVideoCache {
        RepairedVideoCache(cachesDirectory: AppStorageLocation.current.cachesDirectory)
    }

    init(cachesDirectory: URL) {
        directory = cachesDirectory.appending(path: "Open Wallpaper Engine/RepairedVideos/r\(Self.revision)",
                                              directoryHint: .isDirectory)
    }

    /// Whether `source` is a local file the repair could apply to.
    static func mayNeedRepair(_ source: URL) -> Bool {
        source.isFileURL && repairableExtensions.contains(source.pathExtension.lowercased())
    }

    /// Where the repaired copy of `source` as it is now belongs, or nil when its attributes can't
    /// be read.
    func copyURL(for source: URL) -> URL? {
        let path = source.standardizedFileURL.path(percentEncoded: false)
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: path)
        } catch {
            OWELog.error(.library, "Can't read \(source.lastPathComponent) to check its video track: \(error.localizedDescription)")
            return nil
        }
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let key = SHA256.hash(data: Data(path.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        let name = "\(size)-\(Int64(modified * 1_000_000)).\(source.pathExtension.lowercased())"
        return directory.appending(path: key, directoryHint: .isDirectory).appending(path: name)
    }

    /// The file AVFoundation should open for `source`: its repaired copy, made now when missing,
    /// or `source` itself when it needs no repair or the repair fails (the failure is logged).
    /// `willRepair` is called before a copy is written. Reads the file: never call it on the main
    /// or render thread.
    func playableURL(for source: URL, willRepair: () -> Void = {}) -> URL {
        guard Self.mayNeedRepair(source), let copy = copyURL(for: source) else { return source }
        if FileManager.default.fileExists(atPath: copy.path(percentEncoded: false)) { return copy }
        do {
            guard try VideoSampleEntryRepair.needsRepair(source) else { return source }
            willRepair()
            let started = Date()
            guard try VideoSampleEntryRepair.repair(source, to: copy) else { return source }
            removeOlderCopies(besides: copy)
            OWELog.info(.library, "Repaired the in-band parameter sets of \(source.lastPathComponent) in \(String(format: "%.1f", Date().timeIntervalSince(started))) s")
            return copy
        } catch {
            OWELog.error(.library, "Can't repair \(source.path(percentEncoded: false)) for AVFoundation; playing the original: \(error)")
            return source
        }
    }

    /// Removes the copies made for earlier versions of the same source.
    private func removeOlderCopies(besides copy: URL) {
        let folder = copy.deletingLastPathComponent()
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        } catch {
            OWELog.error(.library, "Can't list \(folder.path(percentEncoded: false)): \(error.localizedDescription)")
            return
        }
        for entry in entries where entry.lastPathComponent != copy.lastPathComponent && !entry.lastPathComponent.hasSuffix(".partial") {
            do {
                try FileManager.default.removeItem(at: entry)
            } catch {
                OWELog.error(.library, "Can't remove the old repaired video \(entry.path(percentEncoded: false)): \(error.localizedDescription)")
            }
        }
    }
}
