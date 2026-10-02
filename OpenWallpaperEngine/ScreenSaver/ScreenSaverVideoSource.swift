import AVFoundation
import Foundation
import os

/// A video wallpaper's screen saver: its own video file, played by the saver as it is, with no
/// render. The file goes in the saver's folder (`ScreenSaverVideoStore`) as a hard link to the
/// library file, else a symbolic link (the saver host may read any path), or, when the file keeps
/// its parameter sets in band (`hev1`, `avc3`), as its repaired copy (`VideoSampleEntryRepair`).
///
/// WebM (VP8/VP9) isn't eligible: AVFoundation can't play it, and the desktop plays it through
/// WebKit, which the saver doesn't have.
enum ScreenSaverVideoSource {
    /// Containers AVFoundation plays.
    static let containers: Set<String> = ["mp4", "m4v", "mov"]
    /// Video sample entries of H.264 and HEVC, in either form (the in-band ones after the repair).
    static let playableSampleEntries: Set<String> = ["avc1", "avc3", "hvc1", "hev1"]

    /// Whether `wallpaper` is a video wallpaper whose local file is in a container AVFoundation
    /// plays. Doesn't read the file; `isPlayable(sampleEntryTypes:)` checks the codec.
    static func isEligible(_ wallpaper: WEWallpaper) -> Bool {
        guard wallpaper.project != .invalid,
              wallpaper.project.type.caseInsensitiveCompare("video") == .orderedSame else { return false }
        let url = wallpaper.mediaURL
        return url.isFileURL && containers.contains(url.pathExtension.lowercased())
    }

    /// Whether a file with these sample entries has a video track AVFoundation decodes.
    static func isPlayable(sampleEntryTypes: [String]) -> Bool {
        sampleEntryTypes.contains { playableSampleEntries.contains($0) }
    }

    /// Whether the file needs the in-band → out-of-band repair before AVFoundation plays it.
    static func needsRepair(sampleEntryTypes: [String]) -> Bool {
        sampleEntryTypes.contains { VideoSampleEntryRepair.repairedTypes[$0] != nil }
    }

    private static let codecCache = OSAllocatedUnfairLock(initialState: [String: Bool]())

    /// Whether `source` has an H.264/HEVC track: reads `moov` only, once per file version (path,
    /// size, modification date). Never call it on the main thread.
    static func hasPlayableTrack(_ source: URL) -> Bool {
        let path = source.standardizedFileURL.path(percentEncoded: false)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return false }
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let key = "\(path)|\(size)|\(modified)"
        if let cached = codecCache.withLock({ $0[key] }) { return cached }
        let playable = (try? VideoSampleEntryRepair.sampleEntryTypes(source)).map { isPlayable(sampleEntryTypes: $0) } ?? false
        codecCache.withLock { $0[key] = playable }
        return playable
    }

    /// The store's name for `source` of the wallpaper keyed `key`: the wallpaper and its content,
    /// keeping the source's extension.
    static func fileName(key: ScreenSaverPlugin.StatusKey, source: URL) -> String {
        "\(key.wallpaperKey)_\(key.contentKey)-video-r\(ScreenSaverVideoStore.revision).\(source.pathExtension.lowercased())"
    }

    enum Outcome: Equatable {
        /// The video is at the destination: linked, or repaired when `repaired`.
        case ready(repaired: Bool)
        /// No H.264/HEVC track, or the file can't be read.
        case unsupported
        /// Linking or repairing failed (logged).
        case failed
    }

    /// Puts `source` at `destination` for the saver. `willRepair` is called before a repair.
    /// Reads the file: never call it on the main thread.
    static func prepare(_ source: URL, at destination: URL, willRepair: () -> Void = {}) -> Outcome {
        let types: [String]
        do { types = try VideoSampleEntryRepair.sampleEntryTypes(source) } catch {
            OWELog.error(.app, "Screen saver: can't read the video track of \(source.lastPathComponent): \(error)")
            return .unsupported
        }
        guard isPlayable(sampleEntryTypes: types) else { return .unsupported }
        let manager = FileManager.default
        let path = destination.path(percentEncoded: false)
        do {
            try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            // A stale or dangling entry (a link whose target moved) is replaced.
            if (try? manager.destinationOfSymbolicLink(atPath: path)) != nil || manager.fileExists(atPath: path) {
                try manager.removeItem(at: destination)
            }
        } catch {
            OWELog.error(.app, "Screen saver: can't prepare \(destination.lastPathComponent): \(error)")
            return .failed
        }
        if needsRepair(sampleEntryTypes: types) {
            willRepair()
            do {
                guard try VideoSampleEntryRepair.repair(source, to: destination) else { return link(source, at: destination) }
                return .ready(repaired: true)
            } catch {
                OWELog.error(.app, "Screen saver: can't repair \(source.lastPathComponent): \(error)")
                return .failed
            }
        }
        return link(source, at: destination)
    }

    /// A hard link (same volume), else a symbolic link: never a copy.
    private static func link(_ source: URL, at destination: URL) -> Outcome {
        do {
            try FileManager.default.linkItem(at: source, to: destination)
            return .ready(repaired: false)
        } catch {
            // Another volume: hard links can't cross it.
        }
        do {
            try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: source.standardizedFileURL)
            return .ready(repaired: false)
        } catch {
            OWELog.error(.app, "Screen saver: can't link \(source.lastPathComponent): \(error)")
            return .failed
        }
    }

    /// The video track's display size (its transform applied), or nil when it can't be read.
    static func displaySize(of url: URL) -> SIMD2<Int>? {
        let semaphore = DispatchSemaphore(value: 0)
        final class Box: @unchecked Sendable { var size: SIMD2<Int>? } // Written before the signal, read after the wait.
        let box = Box()
        Task.detached {
            defer { semaphore.signal() }
            let asset = AVURLAsset(url: url)
            guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                  let (natural, transform) = try? await track.load(.naturalSize, .preferredTransform) else { return }
            let rect = CGRect(origin: .zero, size: natural).applying(transform)
            box.size = SIMD2(Int(abs(rect.width).rounded()), Int(abs(rect.height).rounded()))
        }
        semaphore.wait()
        guard let size = box.size, size.x > 0, size.y > 0 else { return nil }
        return size
    }
}
