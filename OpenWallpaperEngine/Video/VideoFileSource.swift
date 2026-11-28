import AVFoundation
import UniformTypeIdentifiers

/// The file a video wallpaper plays, read as WE's "Video loading" setting says (`GSVideoReadMode`).
///
/// From disk, each player item opens the file. AVFoundation reads it past the buffer cache, so
/// every loop reads the whole file from its disk again: a 137 MB 4K loop of 27.6 s read 143 MB per
/// loop, about 5 MB/s for as long as it plays, keeping a hard disk spinning or a network volume
/// busy. In memory, the file is read once and the items read it from memory through a resource
/// loader (`VideoBytesLoader`): nothing is read from the disk after that, for the cost of the
/// file's size in memory (about 200 MB for that video, against 18 MB from disk).
///
/// A file whose video track keeps its parameter sets in band (`hev1`, `avc3`), which AVFoundation
/// refuses, plays repaired (`VideoSampleEntryRepair`) through the same loader: its own bytes, with
/// the repaired `moov` served in place of the original one. Nothing is written.
///
/// A scene's video texture (the MP4 a `.tex` holds) plays from the texture's bytes in place, through
/// the same loader: a slice of its mapped package, or of the file the scene read. Nothing is copied
/// or written to disk.
///
/// The source must outlive its items: an asset holds its resource loader's delegate weakly.
final class VideoFileSource: Sendable {
    let url: URL
    private let loader: VideoBytesLoader?

    /// Opens `url`. Reads the file's `moov` to check its sample entries, and in memory the whole
    /// file, so call it off the main thread. A file that can't be read plays from disk, which then
    /// reports the error itself.
    init(url: URL, mode: GSVideoReadMode) {
        self.url = url
        let repaired = Self.repairedMovie(of: url)
        var bytes: VideoBytes?
        if mode == .inMemory {
            do {
                let data = try Data(contentsOf: url)
                OWELog.info(.library, "Video \(url.lastPathComponent) loaded into memory (\(data.count) bytes)")
                bytes = repaired.map { VideoBytes(replacingMovieOf: .memory(data), with: $0) } ?? VideoBytes([.memory(data)])
            } catch {
                OWELog.error(.library, "Video \(url.lastPathComponent) could not be read into memory, playing it from disk: \(error)")
            }
        }
        if bytes == nil, let repaired {
            do {
                bytes = VideoBytes(replacingMovieOf: .file(try VideoFileReader(url: url)), with: repaired)
            } catch {
                OWELog.error(.library, "Can't open \(url.lastPathComponent) to play it repaired; playing the original: \(error)")
            }
        }
        loader = bytes.map { VideoBytesLoader(bytes: $0, contentType: Self.contentType(of: url)) }
    }

    /// Plays `bytes`, a video held by something else (a scene's video texture), named `name` in its
    /// asset's URL. The bytes are served where they are, never copied.
    init(bytes: Data, name: String) {
        let loader = VideoBytesLoader(bytes: VideoBytes([.memory(bytes)]), contentType: UTType.mpeg4Movie.identifier)
        self.loader = loader
        url = loader.assetURL(named: name)
    }

    /// Whether the items read from memory.
    var isInMemory: Bool { loader?.video.isInMemory ?? false }
    /// Whether the items play the file repaired (`VideoSampleEntryRepair`).
    var isRepaired: Bool { loader?.video.isRepaired ?? false }

    /// A new player item of the video.
    func makeItem() -> AVPlayerItem {
        AVPlayerItem(asset: makeAsset())
    }

    /// A new asset of the video, for an item whose asset is needed off the main actor
    /// (`AVPlayerItem.asset` is main-actor isolated): make the item with `AVPlayerItem(asset:)`.
    func makeAsset() -> AVURLAsset {
        guard let loader else { return AVURLAsset(url: url) }
        let asset = AVURLAsset(url: loader.assetURL(named: url.lastPathComponent))
        asset.resourceLoader.setDelegate(loader, queue: loader.queue)
        return asset
    }

    /// The picture and the soundtrack of a looping video, each an asset of that one track.
    /// `@unchecked Sendable`: both are immutable once made (an `AVComposition` copy, or an
    /// `AVURLAsset` nothing changes), and AVFoundation loads an asset's values thread-safely.
    struct LoopAssets: @unchecked Sendable {
        let picture: AVAsset
        /// Nil when the file has no sound.
        let soundtrack: AVAsset?

        /// A pass of the soundtrack, its pitch kept at other rates. Only for a file with sound.
        func makeSoundtrackItem() -> AVPlayerItem {
            let item = AVPlayerItem(asset: soundtrack ?? picture)
            item.audioTimePitchAlgorithm = .timeDomain
            return item
        }
    }

    /// The video split into its picture and its soundtrack, for `GaplessLoop`s.
    ///
    /// A queue player runs from one pass into the next without a break only for an item of a single
    /// track: with both, the sound's queue is started afresh at every pass, which held the picture
    /// for about 140 ms and silenced the sound for 75 ms (measured on a 4K60 loop). Both are as long
    /// as the picture, so the two loops keep in step pass after pass: a soundtrack that runs longer
    /// is cut there, a shorter one is padded with silence. When the tracks can't be read, both are
    /// the whole file, as before.
    func makeLoopAssets() async -> LoopAssets {
        let source = makeAsset()
        do {
            guard let video = try await source.loadTracks(withMediaType: .video).first else {
                return LoopAssets(picture: source, soundtrack: makeAsset())
            }
            let (videoRange, transform) = try await video.load(.timeRange, .preferredTransform)
            let length = videoRange.end
            let picture = AVMutableComposition()
            guard let pictureTrack = picture.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { throw CocoaError(.featureUnsupported) }
            try Self.insert(video, range: videoRange, into: pictureTrack, length: length)
            pictureTrack.preferredTransform = transform

            var soundtrack: AVComposition?
            if let audio = try await source.loadTracks(withMediaType: .audio).first {
                let audioRange = try await audio.load(.timeRange)
                let sound = AVMutableComposition()
                guard let soundTrack = sound.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                else { throw CocoaError(.featureUnsupported) }
                try Self.insert(audio, range: audioRange, into: soundTrack, length: length)
                soundtrack = sound.copy() as? AVComposition
            }
            guard let pictureCopy = picture.copy() as? AVComposition else { throw CocoaError(.featureUnsupported) }
            return LoopAssets(picture: pictureCopy, soundtrack: soundtrack)
        } catch {
            OWELog.error(.library, "Can't split \(url.lastPathComponent) into picture and sound; its loop point may pause: \(error)")
            return LoopAssets(picture: source, soundtrack: makeAsset())
        }
    }

    /// Puts `track`'s media of `range`, cut to `length`, into `target` at the same times, with
    /// silence (or no picture) before and after it up to `length`.
    private static func insert(_ track: AVAssetTrack, range: CMTimeRange, into target: AVMutableCompositionTrack,
                               length: CMTime) throws {
        let used = range.intersection(CMTimeRange(start: .zero, end: length))
        if used.start > .zero { target.insertEmptyTimeRange(CMTimeRange(start: .zero, end: used.start)) }
        if !used.isEmpty { try target.insertTimeRange(used, of: track, at: used.start) }
        let end = used.isEmpty ? .zero : used.end
        if end < length { target.insertEmptyTimeRange(CMTimeRange(start: end, end: length)) }
    }

    /// The file's type as AVFoundation wants it (a UTI); MPEG-4 when the extension says nothing.
    static func contentType(of url: URL) -> String {
        guard let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .audiovisualContent) else {
            return UTType.mpeg4Movie.identifier
        }
        return type.identifier
    }

    /// The repaired `moov` of `url` when its video track needs the repair; nil when it doesn't, or
    /// when the repair fails (logged: the original plays).
    private static func repairedMovie(of url: URL) -> VideoSampleEntryRepair.RepairedMovie? {
        guard VideoSampleEntryRepair.mayNeedRepair(url) else { return nil }
        do {
            guard let repaired = try VideoSampleEntryRepair.repairedMovie(url) else { return nil }
            OWELog.info(.library, "Playing \(url.lastPathComponent) with its in-band parameter sets moved to its sample entry")
            return repaired
        } catch {
            OWELog.error(.library, "Can't repair \(url.path(percentEncoded: false)) for AVFoundation; playing the original: \(error)")
            return nil
        }
    }
}

/// An open file read on demand, past the buffer cache as AVFoundation reads a file it opens itself.
final class VideoFileReader: Sendable {
    private let descriptor: Int32

    init(url: URL) throws {
        let path = url.path(percentEncoded: false)
        let descriptor = open(path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: path]) }
        _ = fcntl(descriptor, F_NOCACHE, 1)
        self.descriptor = descriptor
    }

    deinit { close(descriptor) }

    /// `count` bytes at `offset`.
    func read(at offset: UInt64, count: Int) throws -> Data {
        var data = Data(count: count)
        let read = data.withUnsafeMutableBytes { pread(descriptor, $0.baseAddress, count, off_t(offset)) }
        guard read == count else { throw CocoaError(.fileReadCorruptFile) }
        return data
    }
}

/// A video's bytes as pieces laid end to end: memory (a file read whole, a mapped package's slice,
/// a repaired `moov`) or ranges of an open file read on demand.
struct VideoBytes: Sendable {
    enum Piece: Sendable {
        case memory(Data)
        case file(VideoFileReader, offset: UInt64, count: Int)

        var count: Int {
            switch self {
            case .memory(let data): return data.count
            case .file(_, _, let count): return count
            }
        }
    }

    /// Where a repaired file's bytes come from: the original as a whole.
    enum Original {
        case memory(Data)
        case file(VideoFileReader)
    }

    let pieces: [Stored]
    let count: Int
    /// Every piece is in memory: a request is answered at once.
    let isInMemory: Bool
    let isRepaired: Bool

    init(_ pieces: [Piece], isRepaired: Bool = false) {
        var start = 0
        self.pieces = pieces.filter { $0.count > 0 }.map { piece in
            defer { start += piece.count }
            return Stored(piece, start: start)
        }
        count = start
        isInMemory = pieces.allSatisfy { if case .memory = $0 { return true } else { return false } }
        self.isRepaired = isRepaired
    }

    /// The original with its `moov` replaced by the repaired one.
    init(replacingMovieOf original: Original, with repaired: VideoSampleEntryRepair.RepairedMovie) {
        let movie = repaired.movie
        let tail = Int(repaired.fileSize - movie.upperBound)
        switch original {
        case .memory(let data):
            let base = data.startIndex
            self.init([.memory(data[base..<(base + Int(movie.lowerBound))]), .memory(repaired.moov),
                       .memory(data[(base + Int(movie.upperBound))...])], isRepaired: true)
        case .file(let reader):
            self.init([.file(reader, offset: 0, count: Int(movie.lowerBound)), .memory(repaired.moov),
                       .file(reader, offset: movie.upperBound, count: tail)], isRepaired: true)
        }
    }

    /// `range` of the bytes; from one memory piece, without copying.
    func bytes(_ range: Range<Int>) throws -> Data {
        guard !range.isEmpty else { return Data() }
        var result = Data()
        for piece in pieces where piece.start < range.upperBound && piece.start + piece.count > range.lowerBound {
            let lower = max(range.lowerBound, piece.start) - piece.start
            let upper = min(range.upperBound, piece.start + piece.count) - piece.start
            let part = try piece.bytes(lower..<upper)
            if result.isEmpty && upper - lower == range.count { return part }
            result.append(part)
        }
        return result
    }

    /// A piece and where it starts; memory keeps a stable pointer so responses share it.
    final class Stored: Sendable {
        let start: Int
        let count: Int
        private let piece: Piece
        /// Immutable after init, and only ever read through: points into the piece's data, which never changes.
        nonisolated(unsafe) private let base: UnsafeMutableRawPointer?

        init(_ piece: Piece, start: Int) {
            self.piece = piece
            self.start = start
            count = piece.count
            if case .memory(let data) = piece {
                base = data.withUnsafeBytes { $0.baseAddress.map(UnsafeMutableRawPointer.init(mutating:)) }
            } else {
                base = nil
            }
        }

        /// `range` of this piece; memory without copying (the bytes keep the piece alive).
        func bytes(_ range: Range<Int>) throws -> Data {
            switch piece {
            case .memory:
                guard let base else { return Data() }
                return Data(bytesNoCopy: base + range.lowerBound, count: range.count,
                            deallocator: .custom { _, _ in withExtendedLifetime(self) {} })
            case .file(let reader, let offset, _):
                return try reader.read(at: offset + UInt64(range.lowerBound), count: range.count)
            }
        }
    }
}

/// Serves a video's bytes (`VideoBytes`) to AVFoundation (`VideoFileSource`). Bytes in memory are
/// answered at once and in full, so no request is ever pending, and share the memory instead of
/// copying it. Bytes read from a file are answered a chunk at a time, so a request AVFoundation
/// cancels stops reading.
final class VideoBytesLoader: NSObject, AVAssetResourceLoaderDelegate, Sendable {
    static let scheme = "owe-memory-video"
    /// Responses are at most this long, so AVFoundation can start on a large request early.
    static let chunkLength = 1 << 20

    let queue = DispatchQueue(label: "com.owe.video.memory-loader", qos: .userInitiated)
    let video: VideoBytes
    private let contentType: String
    private let identifier = UUID()

    init(bytes: VideoBytes, contentType: String) {
        video = bytes
        self.contentType = contentType
    }

    convenience init(data: Data, contentType: String) {
        self.init(bytes: VideoBytes([.memory(data)]), contentType: contentType)
    }

    var byteCount: Int { video.count }

    /// The URL an asset reads this video through; its scheme sends every read to this loader.
    func assetURL(named name: String) -> URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = identifier.uuidString
        components.path = "/" + name
        // A scheme, a UUID host and a path always make a URL.
        return components.url!
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        if let information = loadingRequest.contentInformationRequest {
            information.contentType = contentType
            information.contentLength = Int64(byteCount)
            information.isByteRangeAccessSupported = true
            information.isEntireLengthAvailableOnDemand = true
        }
        guard let dataRequest = loadingRequest.dataRequest else {
            loadingRequest.finishLoading()
            return true
        }
        guard let range = Self.range(of: dataRequest, length: byteCount) else {
            loadingRequest.finishLoading(with: NSError(domain: NSURLErrorDomain, code: NSURLErrorDataLengthExceedsMaximum))
            return true
        }
        serve(Request(loadingRequest), from: range.lowerBound, to: range.upperBound)
        return true
    }

    /// A loading request, used only on `queue`, where AVFoundation calls the delegate.
    private struct Request: @unchecked Sendable {
        let loading: AVAssetResourceLoadingRequest
        init(_ loading: AVAssetResourceLoadingRequest) { self.loading = loading }
    }

    /// Responds from `offset` up to `end`: in memory all at once, from a file one chunk per turn of
    /// `queue`, stopping when AVFoundation cancels the request.
    private func serve(_ request: Request, from offset: Int, to end: Int) {
        var offset = offset
        while !request.loading.isCancelled {
            guard offset < end, let dataRequest = request.loading.dataRequest else {
                request.loading.finishLoading()
                return
            }
            let chunkEnd = min(end, offset + Self.chunkLength)
            do {
                dataRequest.respond(with: try video.bytes(offset..<chunkEnd))
            } catch {
                request.loading.finishLoading(with: error)
                return
            }
            offset = chunkEnd
            if !video.isInMemory, offset < end {
                let next = offset
                queue.async { [self] in serve(request, from: next, to: end) }
                return
            }
        }
    }

    /// The bytes a data request asks for, clamped to the file; nil when it starts past the end.
    static func range(of request: AVAssetResourceLoadingDataRequest, length: Int) -> Range<Int>? {
        range(offset: request.requestedOffset, length: request.requestedLength,
              toEnd: request.requestsAllDataToEndOfResource, fileLength: length)
    }

    static func range(offset: Int64, length: Int, toEnd: Bool, fileLength: Int) -> Range<Int>? {
        guard offset >= 0, offset <= Int64(fileLength) else { return nil }
        let start = Int(offset)
        let end = toEnd ? fileLength : min(fileLength, start + max(length, 0))
        return start..<end
    }

    /// `range` of the video, memory without copying (`VideoBytes.bytes`).
    func bytes(_ range: Range<Int>) throws -> Data {
        try video.bytes(range)
    }
}
