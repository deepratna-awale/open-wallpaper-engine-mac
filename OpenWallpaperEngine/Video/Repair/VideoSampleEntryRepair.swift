import Foundation

/// Losslessly rewrites an MP4 whose video sample entry keeps its parameter sets in band (`hev1`,
/// `avc3`) into the out-of-band form AVFoundation plays (`hvc1`, `avc1`). Wallpaper Engine plays
/// both forms; AVFoundation reports the in-band ones neither playable nor decodable.
///
/// Nothing is re-encoded. The parameter sets of the track's first sync sample go into its decoder
/// configuration record, and the sample entry is renamed; the samples keep their own copies, which
/// ISO/IEC 14496-15 allows for `hvc1` and `avc1` too. Only `moov` changes, so every other box is
/// read from the original where it is (`VideoBytes`: nothing is copied or written) and, when `moov`
/// changes size, each chunk offset pointing past it moves by the same amount.
enum VideoSampleEntryRepair {
    /// Sample entry types that may keep parameter sets in band, and what each becomes.
    static let repairedTypes = ["hev1": "hvc1", "avc3": "avc1"]
    /// A movie box larger than this is not a wallpaper's; reading it whole would cost too much.
    static let maximumMovieBoxSize: UInt64 = 256 << 20
    static let maximumSampleSize = 64 << 20
    private static let trackTablePath = ["mdia", "minf", "stbl"]

    /// Whether some video track of the file at `url` has an in-band sample entry. Reads the
    /// top-level box headers and `moov` only.
    static func needsRepair(_ url: URL) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() } // Closing a read-only handle has nothing to report.
        let fileSize = try handle.seekToEnd()
        let movie = try locateMovieBox(handle, fileSize: fileSize)
        let moov = try readMovieBox(handle, at: movie)
        return (moov.children ?? []).contains { trak in
            guard trak.type == "trak", let entries = trak.descendant(trackTablePath + ["stsd"])?.children else { return false }
            return entries.contains { repairedTypes[$0.type] != nil }
        }
    }

    /// The sample entry types (`avc1`, `hev1`, `mp4a`, …) of every track of the file at `url`.
    /// Reads the top-level box headers and `moov` only.
    static func sampleEntryTypes(_ url: URL) throws -> [String] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() } // Closing a read-only handle has nothing to report.
        let fileSize = try handle.seekToEnd()
        let moov = try readMovieBox(handle, at: try locateMovieBox(handle, fileSize: fileSize))
        return (moov.children ?? []).flatMap { trak -> [String] in
            guard trak.type == "trak", let entries = trak.descendant(trackTablePath + ["stsd"])?.children else { return [] }
            return entries.map(\.type)
        }
    }

    /// Containers the repair reads; anything else (WebM) is played as it is.
    static let repairableExtensions: Set<String> = ["mp4", "m4v", "mov"]

    /// Whether `source` is a local file the repair could apply to.
    static func mayNeedRepair(_ source: URL) -> Bool {
        source.isFileURL && repairableExtensions.contains(source.pathExtension.lowercased())
    }

    /// A file's repair: its `moov` (at `movie`) replaced by `moov`. Every other byte stays where
    /// it is in the original, the repaired `moov`'s chunk offsets already moved for its new size,
    /// so the repaired file is the original's bytes with `moov` swapped in (`VideoBytes`).
    struct RepairedMovie: Sendable {
        let fileSize: UInt64
        /// The original `moov`'s byte range.
        let movie: Range<UInt64>
        /// The repaired `moov`.
        let moov: Data

        /// The repaired file's size.
        var repairedSize: UInt64 { fileSize - UInt64(movie.count) + UInt64(moov.count) }
    }

    /// The repair of the file at `url`, or nil when no track needs it. Reads the top-level box
    /// headers, `moov` and each repaired track's first sync sample.
    static func repairedMovie(_ url: URL) throws -> RepairedMovie? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() } // Closing a read-only handle has nothing to report.
        let fileSize = try handle.seekToEnd()
        let movie = try locateMovieBox(handle, fileSize: fileSize)
        let original = try readMovieBox(handle, at: movie)
        guard var moov = try repairedMovieBox(original, readSample: { offset, size in
            guard offset + UInt64(size) <= fileSize else { throw VideoRepairError.malformed("sample past the end of the file") }
            return try read(handle, at: offset, count: size)
        }) else { return nil }

        let movieEnd = movie.offset + movie.size
        let delta = Int64(moov.serialized.count) - Int64(movie.size)
        if delta != 0 { try shiftChunkOffsets(in: &moov, from: movieEnd, by: delta) }
        return RepairedMovie(fileSize: fileSize, movie: movie.offset..<movieEnd, moov: moov.serialized)
    }

    // MARK: - Movie box

    /// The file's one top-level `moov`: its offset and size.
    private static func locateMovieBox(_ handle: FileHandle, fileSize: UInt64) throws -> (offset: UInt64, size: UInt64) {
        var offset: UInt64 = 0
        var movie: (offset: UInt64, size: UInt64)?
        while offset + 8 <= fileSize {
            let header = try read(handle, at: offset, count: Int(min(16, fileSize - offset)))
            let type = header.mp4FourCC(at: 4)
            var size = UInt64(header.mp4UInt32(at: 0))
            var headerSize: UInt64 = 8
            if size == 1 {
                guard header.count >= 16 else { throw VideoRepairError.malformed("truncated large box header of \(type)") }
                size = header.mp4UInt64(at: 8)
                headerSize = 16
            } else if size == 0 {
                size = fileSize - offset
            }
            guard size >= headerSize, size <= fileSize - offset else {
                throw VideoRepairError.malformed("top-level box \(type) at \(offset) claims \(size) bytes")
            }
            if type == "moov" {
                guard movie == nil else { throw VideoRepairError.malformed("more than one moov") }
                movie = (offset, size)
            }
            offset += size
        }
        guard let movie else { throw VideoRepairError.missingBox("moov") }
        return movie
    }

    private static func readMovieBox(_ handle: FileHandle, at movie: (offset: UInt64, size: UInt64)) throws -> MP4Box {
        guard movie.size <= maximumMovieBoxSize else { throw VideoRepairError.unsupported("moov of \(movie.size) bytes") }
        let data = try read(handle, at: movie.offset, count: Int(movie.size))
        return try MP4Box.parse(data, at: 0).0
    }

    /// `moov` with every in-band sample entry repaired, or nil when none is.
    static func repairedMovieBox(_ moov: MP4Box, readSample: (UInt64, Int) throws -> Data) throws -> MP4Box? {
        var moov = moov
        var changed = false
        try moov.updateDescendants(["trak"]) { trak in
            guard let stbl = trak.descendant(trackTablePath), let entries = stbl.child("stsd")?.children,
                  entries.contains(where: { repairedTypes[$0.type] != nil }) else { return }
            // One sample description per track is what video wallpapers have; several would need
            // each description's own first sync sample.
            guard entries.count == 1 else { throw VideoRepairError.unsupported("\(entries.count) sample descriptions in one track") }
            let table = try MP4SampleTable(stbl: stbl)
            let location = try table.location(ofSample: try table.firstSyncSample)
            guard location.size <= maximumSampleSize else { throw VideoRepairError.unsupported("first sync sample of \(location.size) bytes") }
            let sample = try readSample(location.offset, location.size)
            try trak.updateDescendants(trackTablePath + ["stsd"]) { stsd in
                stsd.children![0] = try repairedEntry(stsd.children![0], firstSyncSample: sample)
            }
            changed = true
        }
        return changed ? moov : nil
    }

    /// The sample entry renamed to its out-of-band type, its configuration record completed with
    /// the parameter sets of `firstSyncSample`.
    static func repairedEntry(_ entry: MP4Box, firstSyncSample: Data) throws -> MP4Box {
        guard let repairedType = repairedTypes[entry.type] else { return entry }
        let isHEVC = entry.type == "hev1"
        let configType = isHEVC ? "hvcC" : "avcC"
        guard let index = entry.children?.firstIndex(where: { $0.type == configType }) else {
            throw VideoRepairError.missingBox("\(entry.type)/\(configType)")
        }
        var entry = entry
        let record = entry.children![index].body
        let lengthSize = isHEVC ? try HEVCDecoderConfiguration.lengthSize(of: record)
                                : try AVCDecoderConfiguration.lengthSize(of: record)
        let units = try NALUnits.split(firstSyncSample, lengthSize: lengthSize)
        entry.children![index].body = isHEVC ? try HEVCDecoderConfiguration.rewrite(record, inBand: units)
                                             : try AVCDecoderConfiguration.rewrite(record, inBand: units)
        entry.type = repairedType
        return entry
    }

    /// Moves every chunk offset at or past `threshold` (the old end of `moov`) by `delta`.
    static func shiftChunkOffsets(in moov: inout MP4Box, from threshold: UInt64, by delta: Int64) throws {
        try moov.updateDescendants(["trak"] + trackTablePath) { stbl in
            guard stbl.children != nil else { return }
            for index in stbl.children!.indices {
                let isLarge: Bool
                switch stbl.children![index].type {
                case "stco": isLarge = false
                case "co64": isLarge = true
                default: continue
                }
                var body = stbl.children![index].body
                guard body.count >= 8 else { throw VideoRepairError.malformed("chunk offset box too short") }
                let count = Int(body.mp4UInt32(at: 4))
                let width = isLarge ? 8 : 4
                guard body.count >= 8 + count * width else { throw VideoRepairError.malformed("chunk offsets truncated") }
                for entry in 0..<count {
                    let position = 8 + entry * width
                    let value = isLarge ? body.mp4UInt64(at: position) : UInt64(body.mp4UInt32(at: position))
                    guard value >= threshold else { continue }
                    let (shifted, overflow) = Int64(clamping: value).addingReportingOverflow(delta)
                    guard !overflow, shifted >= 0, isLarge || shifted <= Int64(UInt32.max) else {
                        throw VideoRepairError.unsupported("chunk offset \(value) no longer fits after moving by \(delta)")
                    }
                    if isLarge { body.setMP4(UInt64(shifted), at: position) } else { body.setMP4(UInt32(shifted), at: position) }
                }
                stbl.children![index].body = body
            }
        }
    }

    // MARK: - Files

    private static func read(_ handle: FileHandle, at offset: UInt64, count: Int) throws -> Data {
        try handle.seek(toOffset: offset)
        let data = try handle.read(upToCount: count) ?? Data()
        guard data.count == count else { throw VideoRepairError.malformed("file ends early at \(offset)") }
        return data
    }
}
