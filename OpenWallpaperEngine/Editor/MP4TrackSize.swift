import Foundation

/// The picture size of an MP4's first video track (`moov/trak/tkhd`, 16.16 fixed point).
enum MP4TrackSize {
    static func pictureSize(of movie: Data) -> (width: Int, height: Int)? {
        let bytes = [UInt8](movie)
        func u32(_ at: Int) -> Int? {
            guard at >= 0, at + 4 <= bytes.count else { return nil }
            return Int(bytes[at]) << 24 | Int(bytes[at + 1]) << 16 | Int(bytes[at + 2]) << 8 | Int(bytes[at + 3])
        }
        /// The boxes in `range`: their type, and their contents' range.
        func boxes(_ range: Range<Int>) -> [(String, Range<Int>)] {
            var result: [(String, Range<Int>)] = []
            var cursor = range.lowerBound
            while cursor + 8 <= range.upperBound, let size = u32(cursor) {
                let type = String(decoding: bytes[cursor + 4..<cursor + 8], as: UTF8.self)
                var header = 8, length = size
                if size == 1, let high = u32(cursor + 8), let low = u32(cursor + 12) { length = high << 32 | low; header = 16 }
                if size == 0 { length = range.upperBound - cursor }
                guard length >= header, cursor + length <= range.upperBound else { break }
                result.append((type, cursor + header..<cursor + length))
                cursor += length
            }
            return result
        }
        guard let moov = boxes(0..<bytes.count).first(where: { $0.0 == "moov" }) else { return nil }
        for trak in boxes(moov.1) where trak.0 == "trak" {
            guard let tkhd = boxes(trak.1).first(where: { $0.0 == "tkhd" }) else { continue }
            let start = tkhd.1.lowerBound
            // Version 1 has 64-bit times: 12 more bytes before the size.
            let offset = bytes.indices.contains(start) && bytes[start] == 1 ? 88 : 76
            guard let width = u32(start + offset), let height = u32(start + offset + 4), width > 0, height > 0 else { continue }
            return (width >> 16, height >> 16)
        }
        return nil
    }
}
