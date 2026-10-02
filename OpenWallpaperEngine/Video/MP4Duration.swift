import Foundation

/// An MP4's length from its movie header (`moov/mvhd`), without opening it in AVFoundation.
enum MP4Duration {
    static func seconds(of data: Data) -> Double? {
        let bytes = [UInt8](data)
        guard let moov = box("moov", in: bytes, from: 0, to: bytes.count),
              let mvhd = box("mvhd", in: bytes, from: moov.lowerBound + 8, to: moov.upperBound) else { return nil }
        let body = mvhd.lowerBound + 8
        guard body < mvhd.upperBound else { return nil }
        let version = bytes[body]
        let (scaleAt, durationAt, durationBytes) = version == 1 ? (body + 20, body + 24, 8) : (body + 12, body + 16, 4)
        guard durationAt + durationBytes <= mvhd.upperBound else { return nil }
        let timescale = integer(bytes, at: scaleAt, count: 4)
        let duration = integer(bytes, at: durationAt, count: durationBytes)
        guard timescale > 0 else { return nil }
        return Double(duration) / Double(timescale)
    }

    /// The range of the first box of `type` among the boxes in `start..<end`.
    private static func box(_ type: String, in bytes: [UInt8], from start: Int, to end: Int) -> Range<Int>? {
        let tag = Array(type.utf8)
        var offset = start
        while offset + 8 <= end {
            var size = Int(integer(bytes, at: offset, count: 4))
            var header = 8
            if size == 1, offset + 16 <= end { size = Int(clamping: integer(bytes, at: offset + 8, count: 8)); header = 16 }
            if size == 0 { size = end - offset }
            guard size >= header, offset + size <= end else { return nil }
            if Array(bytes[(offset + 4)..<(offset + 8)]) == tag { return offset..<(offset + size) }
            offset += size
        }
        return nil
    }

    private static func integer(_ bytes: [UInt8], at offset: Int, count: Int) -> UInt64 {
        (0..<count).reduce(UInt64(0)) { $0 << 8 | UInt64(bytes[offset + $1]) }
    }
}
