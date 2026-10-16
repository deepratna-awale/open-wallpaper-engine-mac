import Foundation

/// The texture variants a `.tex` declares (WE 2.6, "Texture Properties › Variants"): textures of
/// the base's size and type a user property swaps in or blends over the base.
///
/// They aren't in scene.json. The editor keeps them in the texture's `.tex-json`
/// (`"variants": [{"options": [{"file", "blend": "replace" | "alphablend", "variantcondition"}]}]`)
/// and the resource compiler bakes them into the `.tex`, which WE's loader reads
/// (`wallpaper64.exe` 0x14015c8d0, the `TEXB` reader):
///
/// ```
/// "TEXB0004\0"  u32 image count, i32 FreeImage format, u32 option count
/// per option:   u32 group, u32 option id, u32 blend, NUL-terminated JSON condition
/// per image:    u32 mipmap count
///   per mipmap: u32 width, height, compression, uncompressed size, stored size, bytes
///               then, with options: u32 group count, per group u32 patch count,
///               per patch u32 group, u32 option id, u32 x, y, width, height,
///               i32 FreeImage format, u32 stored size, bytes
/// ```
///
/// A condition is `{"condition": "<bool property>"}` (on while the property is true) or
/// `{"condition": {"name": "<combo property>", "condition": "<value>"}}` (on while the property
/// has that value). In each group only the first option that is on applies; a group whose
/// options are all off shows the base (`TEXVariantResolver`).
struct TEXVariants: Equatable {
    /// How an option's patches go into the base mipmap (its `blend` word).
    struct Blend: OptionSet, Hashable {
        let rawValue: UInt32

        /// Drawn over the base by the patch's alpha ("Alpha-blended"); RGBA8888 textures only.
        static let alphaBlend = Blend(rawValue: 1)
        /// The patch's bytes are the whole mipmap, stored as the base's are (a replaced video or
        /// a replaced picture of the same encoding).
        static let wholeMipmap = Blend(rawValue: 2)
    }

    enum Condition: Hashable {
        /// On while the bool property is true.
        case flag(property: String)
        /// On while the combo property has `value`.
        case equals(property: String, value: String)

        var property: String {
            switch self {
            case .flag(let property), .equals(let property, _): return property
            }
        }

        /// `{"condition": "<name>"}` or `{"condition": {"name", "condition"}}`; nil for anything
        /// else, which WE's loader never turns on.
        init?(json text: String) {
            let object: Any
            do {
                object = try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
            } catch {
                OWELog.error(.texture, "A texture variant's condition isn't JSON (\(text)): \(error)")
                return nil
            }
            guard let fields = object as? [String: Any] else { return nil }
            if let name = fields["condition"] as? String {
                self = .flag(property: name)
            } else if let binding = fields["condition"] as? [String: Any], let name = binding["name"] as? String,
                      let value = binding["condition"] {
                self = .equals(property: name, value: value as? String ?? "\(value)")
            } else {
                return nil
            }
        }
    }

    struct Option: Equatable {
        let group: UInt32
        let id: UInt32
        let blend: Blend
        /// Nil when the record has none WE reads: the option is never on.
        let condition: Condition?
    }

    let options: [Option]

    /// The options each group shows when `isOn` says which conditions hold: the first option of
    /// a group that is on, by option id with its blend.
    func enabled(_ isOn: (Condition) -> Bool) -> [UInt32: Blend] {
        var groups: Set<UInt32> = []
        var chosen: [UInt32: Blend] = [:]
        for option in options {
            guard let condition = option.condition, isOn(condition), !groups.contains(option.group) else { continue }
            groups.insert(option.group)
            chosen[option.id] = option.blend
        }
        return chosen
    }

    /// The variants `data` declares; nil when it is not a `TEXB0004` `.tex` with any.
    init?(texData data: Data) {
        guard var reader = TEXVariantReader(data), let header = reader.header(), header.optionCount > 0,
              let options = reader.options(count: header.optionCount) else { return nil }
        self.options = options
    }

    init(options: [Option]) {
        self.options = options
    }

    /// Whether `data` is a `.tex` that declares variants, read from its header alone.
    static func declares(in data: Data) -> Bool {
        // The header is in the first hundred bytes; the file isn't copied to read it.
        guard var reader = TEXVariantReader(data.prefix(128)), let header = reader.header() else { return false }
        return header.optionCount > 0
    }
}

/// Reads a `.tex` up to and through its variant declarations (`TEXVariants` has the layout).
struct TEXVariantReader {
    struct Header {
        let format: UInt32
        let flags: UInt32
        /// From `TEXB000n`.
        let version: Int
        let imageCount: Int
        let freeImageFormat: Int32
        let optionCount: Int
        /// Where `TEXB000n` starts.
        let containerOffset: Int
    }

    /// The `TEXI` flag of a volume texture, whose header and mipmaps carry a depth word.
    static let volumeFlag: UInt32 = 0x40

    let bytes: [UInt8]
    var cursor = 0

    init?(_ data: Data) {
        guard data.count >= 18 else { return nil }
        bytes = [UInt8](data)
    }

    mutating func word() -> UInt32? {
        guard cursor + 4 <= bytes.count else { return nil }
        defer { cursor += 4 }
        return UInt32(bytes[cursor]) | UInt32(bytes[cursor + 1]) << 8 | UInt32(bytes[cursor + 2]) << 16
            | UInt32(bytes[cursor + 3]) << 24
    }

    mutating func string() -> String? {
        guard cursor < bytes.count, let end = bytes[cursor...].firstIndex(of: 0) else { return nil }
        defer { cursor = end + 1 }
        return String(decoding: bytes[cursor..<end], as: UTF8.self)
    }

    /// `count` bytes from the cursor, which moves past them.
    mutating func range(_ count: Int) -> Range<Int>? {
        guard count >= 0, count <= bytes.count - cursor else { return nil }
        defer { cursor += count }
        return cursor..<(cursor + count)
    }

    /// The header through the container's words; the cursor is then at the first option.
    mutating func header() -> Header? {
        cursor = 0
        guard string() == "TEXV0005", string() == "TEXI0001", let format = word(), let flags = word() else { return nil }
        // Texture and image sizes, a volume's depth (flag 0x40, `TEXVolume`), the colour word.
        cursor += (flags & TEXVariantReader.volumeFlag != 0 ? 6 : 5) * 4
        let containerOffset = cursor
        guard let container = string(), container.hasPrefix("TEXB"), let version = Int(container.dropFirst(4)),
              (1...4).contains(version), let imageCount = word() else { return nil }
        var freeImageFormat: Int32 = -1
        if version >= 3 {
            guard let value = word() else { return nil }
            freeImageFormat = Int32(bitPattern: value)
        }
        var optionCount = 0
        if version >= 4 {
            guard let value = word() else { return nil }
            optionCount = Int(value)
        }
        return Header(format: format, flags: flags, version: version, imageCount: Int(imageCount),
                      freeImageFormat: freeImageFormat, optionCount: optionCount, containerOffset: containerOffset)
    }

    /// The option records after the header.
    mutating func options(count: Int) -> [TEXVariants.Option]? {
        // Each record is at least three words and a NUL.
        guard count <= (bytes.count - cursor) / 13 else { return nil }
        var options: [TEXVariants.Option] = []
        for _ in 0..<count {
            guard let group = word(), let id = word(), let blend = word(), let condition = string() else { return nil }
            options.append(TEXVariants.Option(group: group, id: id, blend: TEXVariants.Blend(rawValue: blend),
                                              condition: TEXVariants.Condition(json: condition)))
        }
        return options
    }
}
