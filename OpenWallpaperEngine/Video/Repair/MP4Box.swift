import Foundation

/// One ISO base media file format box (ISO/IEC 14496-12 §4.2) held in memory, as far as the
/// sample entry repair needs to open it: the path `moov/trak/mdia/minf/stbl/stsd/<sample entry>`
/// is parsed into children, every other box is kept as its bytes. Serializing recomputes each
/// size, so a descendant that grows resizes its ancestors.
struct MP4Box {
    var type: String
    /// A parsed box's bytes between its header and its first child (a full box's version and
    /// flags plus `stsd`'s entry count, or a visual sample entry's fixed fields); a leaf's payload.
    var body: Data
    /// The children of a box this parser opens; nil for a leaf.
    var children: [MP4Box]?

    /// Fixed bytes before the children of a box the repair descends into; nil for a leaf.
    static func childOffset(of type: String) -> Int? {
        switch type {
        case "moov", "trak", "mdia", "minf", "stbl": return 0
        // Full box header, then entry_count (§8.5.2).
        case "stsd": return 8
        // SampleEntry (8) plus VisualSampleEntry's fields (70) before its boxes (§12.1.3).
        case "hev1", "hvc1", "avc3", "avc1": return 78
        default: return nil
        }
    }

    /// Parses consecutive boxes filling `data`.
    static func parseSequence(_ data: Data) throws -> [MP4Box] {
        var boxes: [MP4Box] = []
        var offset = 0
        while offset < data.count {
            let (box, size) = try parse(data, at: offset)
            boxes.append(box)
            offset += size
        }
        return boxes
    }

    /// Parses the box at `offset`; returns it with its size in bytes.
    static func parse(_ data: Data, at offset: Int) throws -> (MP4Box, Int) {
        let remaining = data.count - offset
        guard remaining >= 8 else { throw VideoRepairError.malformed("truncated box header at \(offset)") }
        let type = data.mp4FourCC(at: offset + 4)
        let size32 = data.mp4UInt32(at: offset)
        var header = 8
        var size: Int
        switch size32 {
        case 0:
            size = remaining
        case 1:
            guard remaining >= 16 else { throw VideoRepairError.malformed("truncated large box header of \(type)") }
            let size64 = data.mp4UInt64(at: offset + 8)
            guard size64 <= UInt64(Int.max) else { throw VideoRepairError.malformed("box \(type) too large") }
            size = Int(size64)
            header = 16
        default:
            size = Int(size32)
        }
        guard size >= header, size <= remaining else {
            throw VideoRepairError.malformed("box \(type) at \(offset) claims \(size) bytes, \(remaining) remain")
        }
        let payload = data.mp4Bytes((offset + header)..<(offset + size))
        guard let fixed = childOffset(of: type) else {
            return (MP4Box(type: type, body: payload, children: nil), size)
        }
        guard payload.count >= fixed else { throw VideoRepairError.malformed("box \(type) shorter than its fields") }
        let children = try parseSequence(payload.mp4Bytes(fixed..<payload.count))
        return (MP4Box(type: type, body: payload.mp4Bytes(0..<fixed), children: children), size)
    }

    /// The box as it is written to a file.
    var serialized: Data {
        var payload = body
        for child in children ?? [] { payload.append(child.serialized) }
        var data = Data()
        let compactSize = UInt64(payload.count) + 8
        if compactSize <= UInt64(UInt32.max) {
            data.appendMP4(UInt32(compactSize))
            data.appendMP4FourCC(type)
        } else {
            data.appendMP4(UInt32(1))
            data.appendMP4FourCC(type)
            data.appendMP4(UInt64(payload.count) + 16)
        }
        data.append(payload)
        return data
    }

    /// The first child of `type`.
    func child(_ type: String) -> MP4Box? {
        children?.first { $0.type == type }
    }

    /// The first box down `path` of child types.
    func descendant(_ path: [String]) -> MP4Box? {
        guard let first = path.first else { return self }
        return child(first)?.descendant(Array(path.dropFirst()))
    }

    /// Applies `update` to every box down `path` (each level may hold several matches).
    mutating func updateDescendants(_ path: [String], _ update: (inout MP4Box) throws -> Void) rethrows {
        guard let first = path.first else { return try update(&self) }
        guard children != nil else { return }
        for index in children!.indices where children![index].type == first {
            try children![index].updateDescendants(Array(path.dropFirst()), update)
        }
    }
}
