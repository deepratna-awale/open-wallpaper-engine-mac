import Foundation
import CryptoKit
import CoreGraphics
import Metal
import zlib

/// Everything that feeds a prepared scene. Two preparations with equal keys produce equal files,
/// so a file is only ever served for the inputs it was built from.
struct SceneCacheKey: Equatable, Sendable {
    struct SourceFile: Equatable, Sendable {
        var path: String
        var size: Int64
        var modified: Double
    }

    struct Display: Equatable, Sendable, Comparable {
        var pixelWidth: Int
        var pixelHeight: Int
        var scale: Double

        static func < (lhs: Display, rhs: Display) -> Bool {
            (lhs.pixelWidth, lhs.pixelHeight, lhs.scale) < (rhs.pixelWidth, rhs.pixelHeight, rhs.scale)
        }

        /// The connected displays, through CoreGraphics (safe off the main thread).
        static func connected() -> [Display] {
            var count: UInt32 = 0
            guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
            var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
            guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
            return ids.prefix(Int(count)).compactMap { id in
                guard let mode = CGDisplayCopyDisplayMode(id), mode.width > 0 else { return nil }
                return Display(pixelWidth: mode.pixelWidth, pixelHeight: mode.pixelHeight,
                               scale: Double(mode.pixelWidth) / Double(mode.width))
            }.sorted()
        }
    }

    /// The project's files (size and modification time), sorted by path.
    var sources: [SourceFile]
    /// The saved Inspector edits (`_owe_scene_object_*`).
    var edits: [String: String]
    /// Stored user property values that can change the content.
    var userProperties: [String: String]
    var displays: [Display]
    /// The settings that affect preparation (`SceneRenderSettings.contentKey`).
    var settings: String
    /// The OS build, the shader toolchain and the cache format (`currentEnvironment`), not the
    /// app's version: an update keeps prepared scenes unless what prepares them changed.
    var environment: String = SceneCacheKey.currentEnvironment
    var shaderRevision: Int = ShaderVariantTranslator.revision
    var gpu: String = SceneCacheKey.currentGPU

    /// Changes whenever what a preparation writes changes, so older files are rebuilt.
    static let contentRevision = 1

    /// As `EffectPipelineArchive.environmentKey` keys compiled pipelines: the OS build, the shader
    /// toolchain and translator revision, plus this cache's content revision.
    static let currentEnvironment: String = environment(os: ProcessInfo.processInfo.operatingSystemVersionString,
                                                        toolchain: InProcessShaderCompiler.libraryFingerprint)

    static func environment(os: String, toolchain: String) -> String {
        "\(EffectPipelineArchive.environmentKey(os: os, toolchain: toolchain))--c\(contentRevision)"
    }

    /// The GPU's name and the newest Apple and Mac families it supports.
    static let currentGPU: String = {
        guard let device = MTLCreateSystemDefaultDevice() else { return "none" }
        let apple: [MTLGPUFamily] = [.apple9, .apple8, .apple7, .apple6, .apple5]
        let family = apple.first(where: device.supportsFamily).map { "apple\($0.rawValue)" }
            ?? (device.supportsFamily(.mac2) ? "mac2" : "other")
        return "\(device.name)|\(family)"
    }()

    /// Size and modification time of `url`'s files: the file itself, or every regular file below
    /// a directory (hidden files and the cache itself excluded).
    static func sources(of directory: URL) -> [SourceFile] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let walker = fm.enumerator(at: directory, includingPropertiesForKeys: keys,
                                         options: [.skipsHiddenFiles]) else { return [] }
        let base = directory.standardizedFileURL.path
        var files: [SourceFile] = []
        for case let url as URL in walker {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            let path = url.standardizedFileURL.path
            let relative = path.hasPrefix(base) ? String(path.dropFirst(base.count)) : path
            files.append(SourceFile(path: relative, size: Int64(values.fileSize ?? -1),
                                    modified: values.contentModificationDate?.timeIntervalSince1970 ?? -1))
        }
        return files.sorted { $0.path < $1.path }
    }

    /// SHA-256 over a canonical encoding of every field.
    var digest: SHA256.Digest {
        var hasher = SHA256()
        func add(_ text: String) {
            var data = Data(text.utf8)
            var length = UInt32(data.count).littleEndian
            hasher.update(data: Data(bytes: &length, count: 4))
            hasher.update(data: data)
            data.removeAll()
        }
        add("sources"); add(String(sources.count))
        for file in sources { add(file.path); add(String(file.size)); add(String(file.modified.bitPattern)) }
        add("edits")
        for (key, value) in edits.sorted(by: { $0.key < $1.key }) { add(key); add(value) }
        add("properties")
        for (key, value) in userProperties.sorted(by: { $0.key < $1.key }) { add(key); add(value) }
        add("displays")
        for display in displays.sorted() {
            add("\(display.pixelWidth)x\(display.pixelHeight)@\(display.scale.bitPattern)")
        }
        add("settings"); add(settings)
        add("environment"); add(environment)
        add("revision"); add(String(shaderRevision))
        add("gpu"); add(gpu)
        return hasher.finalize()
    }

    /// The digest as the file name (hex).
    var name: String { digest.map { String(format: "%02x", $0) }.joined() }
}

/// One prepared scene on disk: a versioned, little-endian container of 16-byte aligned sections,
/// read memory-mapped.
///
/// Layout: a 64-byte header (`magic`, format version, section count, the file's length, 8 reserved
/// bytes, the key's SHA-256), then one
/// 32-byte entry per section (id, flags, offset, length, CRC-32), then the sections.
struct SceneCacheFile: Equatable, @unchecked Sendable {
    enum Section: UInt32, CaseIterable, Sendable {
        /// The scene document with the saved edits applied (JSON).
        case scenePlan = 1
        /// Per-layer analysis seeds.
        case analysisSeeds = 2
        /// Prepared texture blobs.
        case textures = 3
        /// Shader variant names the scene uses.
        case shaderVariants = 4
        /// Pipeline descriptors used, for prewarming.
        case pipelines = 5
    }

    enum ReadError: Error, Equatable {
        case truncated, badMagic, foreignVersion(UInt32), keyMismatch, badSection, checksum(UInt32)
    }

    static let magic: [UInt8] = Array("OWESCENE".utf8)
    static let formatVersion: UInt32 = 1
    static let headerSize = 64
    static let entrySize = 32
    static let alignment = 16

    /// The key's SHA-256 (32 bytes).
    var key: [UInt8]
    var sections: [Section: Data]

    init(key: SHA256.Digest, sections: [Section: Data] = [:]) {
        self.init(key: Array(key), sections: sections)
    }

    init(key: [UInt8], sections: [Section: Data] = [:]) {
        self.key = key
        self.sections = sections
    }

    private static func aligned(_ value: Int) -> Int { (value + alignment - 1) / alignment * alignment }

    private static func crc(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { raw -> UInt32 in
            guard let base = raw.baseAddress, raw.count > 0 else { return 0 }
            var value: UInt = 0
            var offset = 0
            while offset < raw.count {
                let chunk = min(raw.count - offset, Int(UInt32.max))
                value = zlib.crc32(value, base.advanced(by: offset).assumingMemoryBound(to: Bytef.self), uInt(chunk))
                offset += chunk
            }
            return UInt32(truncatingIfNeeded: value)
        }
    }

    func encoded() -> Data {
        let ordered = sections.sorted { $0.key.rawValue < $1.key.rawValue }
        var out = Data()
        func put<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { out.append(contentsOf: $0) }
        }
        out.append(contentsOf: Self.magic)
        put(Self.formatVersion)
        put(UInt32(ordered.count))
        var offset = Self.aligned(Self.headerSize + ordered.count * Self.entrySize)
        var offsets: [Int] = []
        for (_, data) in ordered {
            offsets.append(offset)
            offset = Self.aligned(offset + data.count)
        }
        put(UInt64(offset))
        put(UInt64(0))
        out.append(contentsOf: key.count == 32 ? key : Array(SHA256.hash(data: Data(key))))
        for (index, (id, data)) in ordered.enumerated() {
            put(id.rawValue)
            put(UInt32(0))
            put(UInt64(offsets[index]))
            put(UInt64(data.count))
            put(Self.crc(data))
            put(UInt32(0))
        }
        for (index, (_, data)) in ordered.enumerated() {
            out.append(Data(count: offsets[index] - out.count))
            out.append(data)
        }
        out.append(Data(count: Self.aligned(out.count) - out.count))
        return out
    }

    /// Reads `data`, checking its version, its key and every section's bounds and checksum.
    /// Section data slices `data` (no copy when `data` is mapped).
    init(decoding data: Data, expectedKey: SHA256.Digest? = nil) throws {
        let bytes = data.count
        guard bytes >= Self.headerSize else { throw ReadError.truncated }
        let start = data.startIndex
        func read<T: FixedWidthInteger>(_ type: T.Type, at offset: Int) -> T {
            var value: T = 0
            withUnsafeMutableBytes(of: &value) { buffer in
                data.copyBytes(to: buffer, from: (start + offset)..<(start + offset + MemoryLayout<T>.size))
            }
            return T(littleEndian: value)
        }
        guard Array(data[start..<(start + 8)]) == Self.magic else { throw ReadError.badMagic }
        let version = read(UInt32.self, at: 8)
        guard version == Self.formatVersion else { throw ReadError.foreignVersion(version) }
        let count = Int(read(UInt32.self, at: 12))
        guard read(UInt64.self, at: 16) == UInt64(bytes) else { throw ReadError.truncated }
        let digest = Array(data[(start + 32)..<(start + 64)])
        if let expectedKey, Array(expectedKey) != digest { throw ReadError.keyMismatch }
        guard count <= Section.allCases.count * 4, Self.headerSize + count * Self.entrySize <= bytes else {
            throw ReadError.truncated
        }
        var sections: [Section: Data] = [:]
        for index in 0..<count {
            let entry = Self.headerSize + index * Self.entrySize
            let rawID = read(UInt32.self, at: entry)
            let offset = read(UInt64.self, at: entry + 8)
            let length = read(UInt64.self, at: entry + 16)
            let checksum = read(UInt32.self, at: entry + 24)
            guard offset % UInt64(Self.alignment) == 0, offset <= UInt64(bytes),
                  length <= UInt64(bytes) - offset else { throw ReadError.truncated }
            let slice = data[(start + Int(offset))..<(start + Int(offset) + Int(length))]
            guard Self.crc(slice) == checksum else { throw ReadError.checksum(rawID) }
            // A section this build doesn't know is skipped (it can't be misread).
            if let id = Section(rawValue: rawID) {
                guard sections[id] == nil else { throw ReadError.badSection }
                sections[id] = slice
            }
        }
        self.key = digest
        self.sections = sections
    }
}

/// The scene cache folder: `<root>/<wallpaper>/<key>.owescene`, capped in bytes, least recently
/// used first out. Reads and writes are heavy work and belong on the preparation pool.
final class SceneCacheStore: @unchecked Sendable {
    static let fileExtension = "owescene"
    static let defaultCapacity: Int64 = 4 << 30

    let root: URL
    let capacity: Int64
    private let lock = NSLock()

    init(root: URL, capacity: Int64 = SceneCacheStore.defaultCapacity) {
        self.root = root
        self.capacity = max(0, capacity)
    }

    /// `<Wallpaper Storage>/.owe-cache`.
    static var defaultRoot: URL { WallpaperStorage.directory.appending(path: ".owe-cache", directoryHint: .isDirectory) }

    func url(wallpaper: String, key: SceneCacheKey) -> URL {
        root.appending(path: Self.folderName(wallpaper), directoryHint: .isDirectory)
            .appending(path: "\(key.name).\(Self.fileExtension)")
    }

    private static func folderName(_ wallpaper: String) -> String {
        let safe = wallpaper.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }
        return safe.isEmpty ? "_" : String(safe)
    }

    /// The file for `key`, or nil. A file that fails to read (truncated, corrupt, another format
    /// version, another key) is deleted. A hit marks the file as just used.
    func read(wallpaper: String, key: SceneCacheKey) -> SceneCacheFile? {
        ThreadGuards.assertBackground("scene cache read")
        let url = url(wallpaper: wallpaper, key: key)
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        do {
            let data = try Data(contentsOf: url, options: .alwaysMapped)
            let file = try SceneCacheFile(decoding: data, expectedKey: key.digest)
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: path)
            return file
        } catch {
            OWELog.info(.scene, "Scene cache: dropping unreadable \(url.lastPathComponent): \(error)")
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    /// Writes atomically (a temporary file renamed into place), then trims the folder to capacity.
    @discardableResult
    func write(_ file: SceneCacheFile, wallpaper: String, key: SceneCacheKey) throws -> URL {
        ThreadGuards.assertBackground("scene cache write")
        let url = url(wallpaper: wallpaper, key: key)
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let temporary = folder.appending(path: ".\(UUID().uuidString).tmp")
        do {
            try file.encoded().write(to: temporary)
            if rename(temporary.path(percentEncoded: false), url.path(percentEncoded: false)) != 0 {
                throw CocoaError(.fileWriteUnknown)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        trim()
        return url
    }

    /// Deletes least recently used files until the folder fits `capacity`.
    func trim() {
        lock.lock(); defer { lock.unlock() }
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return }
        var files: [(url: URL, size: Int64, used: Date)] = []
        for case let url as URL in walker where url.pathExtension == Self.fileExtension {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            files.append((url, Int64(values.fileSize ?? 0), values.contentModificationDate ?? .distantPast))
        }
        var total = files.reduce(Int64(0)) { $0 + $1.size }
        for file in files.sorted(by: { $0.used < $1.used }) where total > capacity {
            try? FileManager.default.removeItem(at: file.url)
            total -= file.size
        }
    }
}
