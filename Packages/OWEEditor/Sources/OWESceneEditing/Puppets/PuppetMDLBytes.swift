import Foundation
import simd

/// The `.mdl` primitives (docs/models-plan.md §1.1): little-endian `u8/u16/u32/u64/f32`,
/// NUL-terminated UTF-8 strings, blobs as a `u32` byte length and the bytes.
struct PuppetMDLOutput {
    private(set) var bytes: [UInt8] = []

    var count: Int { bytes.count }

    mutating func u8(_ value: UInt8) { bytes.append(value) }
    mutating func u16(_ value: UInt16) { append(value) }
    mutating func u32(_ value: UInt32) { append(value) }
    mutating func i32(_ value: Int32) { append(UInt32(bitPattern: value)) }
    mutating func u64(_ value: UInt64) { append(value) }
    /// Negative zero is written as zero, so the same pose always writes the same bytes.
    mutating func f32(_ value: Float) { append((value + 0).bitPattern) }
    mutating func f32s(_ values: [Float]) { for value in values { f32(value) } }

    mutating func cstring(_ value: String) {
        bytes += Array(value.utf8).filter { $0 != 0 }
        bytes.append(0)
    }

    mutating func blob(_ data: [UInt8]) {
        u32(UInt32(data.count))
        bytes += data
    }

    mutating func raw(_ data: [UInt8]) { bytes += data }

    /// 16 floats in the file's order (a column-vector matrix's memory).
    mutating func matrix(_ m: simd_float4x4) {
        for column in [m.columns.0, m.columns.1, m.columns.2, m.columns.3] { f32s([column.x, column.y, column.z, column.w]) }
    }

    /// A section: `cstr tag`, `u32` absolute end offset, the body.
    mutating func section(_ tag: String, _ body: [UInt8]) {
        cstring(tag)
        u32(UInt32(bytes.count + 4 + body.count))
        bytes += body
    }

    private mutating func append<T: FixedWidthInteger>(_ value: T) {
        withUnsafeBytes(of: value.littleEndian) { bytes += $0 }
    }
}

/// Reads the primitives strictly: a read past the end throws (WE reads zeros).
struct PuppetMDLInput {
    let bytes: [UInt8]
    private(set) var offset = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    mutating func seek(to offset: Int) { self.offset = offset }

    func need(_ size: Int, _ what: @autoclosure () -> String) throws {
        guard size >= 0, size <= bytes.count - offset else { throw PuppetMDLError.truncated(what(), offset: offset) }
    }

    private mutating func little<T: FixedWidthInteger>(_ type: T.Type, _ what: String) throws -> T {
        let size = MemoryLayout<T>.size
        try need(size, what)
        var value: T = 0
        for index in 0..<size { value |= T(truncatingIfNeeded: bytes[offset + index]) << (8 * index) }
        offset += size
        return value
    }

    mutating func u8() throws -> UInt8 { try little(UInt8.self, "u8") }
    mutating func u16() throws -> UInt16 { try little(UInt16.self, "u16") }
    mutating func u32() throws -> UInt32 { try little(UInt32.self, "u32") }
    mutating func i32() throws -> Int32 { try little(Int32.self, "i32") }
    mutating func u64() throws -> UInt64 { try little(UInt64.self, "u64") }
    mutating func f32() throws -> Float { Float(bitPattern: try little(UInt32.self, "f32")) }

    mutating func f32s(_ count: Int) throws -> [Float] {
        try need(4 * count, "f32[\(count)]")
        return try (0..<count).map { _ in try f32() }
    }

    mutating func u32s(_ count: Int) throws -> [UInt32] {
        try need(4 * count, "u32[\(count)]")
        return try (0..<count).map { _ in try u32() }
    }

    mutating func matrix() throws -> simd_float4x4 { Self.matrix(try f32s(16)) }

    static func matrix(_ v: [Float]) -> simd_float4x4 {
        simd_float4x4(SIMD4(v[0], v[1], v[2], v[3]), SIMD4(v[4], v[5], v[6], v[7]),
                      SIMD4(v[8], v[9], v[10], v[11]), SIMD4(v[12], v[13], v[14], v[15]))
    }

    mutating func raw(_ count: Int, _ what: String) throws -> ArraySlice<UInt8> {
        try need(count, what)
        defer { offset += count }
        return bytes[offset..<(offset + count)]
    }

    mutating func blob(_ what: String) throws -> ArraySlice<UInt8> {
        let size = Int(try u32())
        return try raw(size, "\(what)[\(size)]")
    }

    mutating func cstring() throws -> String {
        guard let end = bytes[offset...].firstIndex(of: 0) else { throw PuppetMDLError.truncated("string", offset: offset) }
        defer { offset = end + 1 }
        return String(decoding: bytes[offset..<end], as: UTF8.self)
    }

    static func floats(_ bytes: ArraySlice<UInt8>) -> [Float] {
        bytes.withUnsafeBytes { raw in
            (0..<(raw.count / 4)).map { Float(bitPattern: raw.loadUnaligned(fromByteOffset: 4 * $0, as: UInt32.self).littleEndian) }
        }
    }
}

public enum PuppetMDLError: Error, Equatable, LocalizedError {
    case truncated(String, offset: Int)
    case malformed(String)
    case notAModel
    /// A rig the editor can't hold: no mesh, no skeleton, or a vertex format without positions.
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .truncated(let what, let offset): return "The model ends early (\(what) at \(offset))."
        case .malformed(let reason): return "The model is malformed: \(reason)."
        case .notAModel: return "The file isn't a Wallpaper Engine model."
        case .unsupported(let reason): return "The puppet can't be edited: \(reason)."
        }
    }
}

/// WE's 26 vertex attributes in interleaving order with their bits and sizes (docs/models-plan.md
/// §1.2; `MDLVertexAttribute`).
enum PuppetVertexLayout {
    static let order: [(mask: UInt32, size: Int)] = [
        (0x1, 12), (0x10000, 16), (0x2000000, 12), (0x2, 12), (0x4, 16), (0x800000, 16), (0x1000000, 16),
        (0x8, 8), (0x10, 12), (0x20, 16), (0x40, 8), (0x80, 12), (0x100, 16), (0x200, 8), (0x400, 12), (0x800, 16),
        (0x1000, 8), (0x2000, 12), (0x4000, 16), (0x20000, 8), (0x40000, 12), (0x80000, 16), (0x100000, 8),
        (0x200000, 12), (0x400000, 16), (0x8000, 16),
    ]
    static let knownBits: UInt32 = order.reduce(0) { $0 | $1.mask }

    static let position: UInt32 = 0x1
    static let positionVec4: UInt32 = 0x10000
    static let blendIndices: UInt32 = 0x800000
    static let blendWeights: UInt32 = 0x1000000
    static let texCoord: UInt32 = 0x8
    static let texCoordVec3: UInt32 = 0x10
    static let texCoordVec4: UInt32 = 0x20
    /// Position, blend indices, blend weights, texture coordinate: what WE's editor writes for a
    /// puppet (`0x1800009`, 52 bytes).
    static let puppet: UInt32 = position | blendIndices | blendWeights | texCoord

    static func stride(_ format: UInt32) -> Int {
        order.reduce(0) { format & $1.mask != 0 ? $0 + $1.size : $0 }
    }

    static func offset(of mask: UInt32, in format: UInt32) -> Int? {
        guard format & mask != 0 else { return nil }
        var offset = 0
        for entry in order {
            if entry.mask == mask { return offset }
            if format & entry.mask != 0 { offset += entry.size }
        }
        return nil
    }
}
