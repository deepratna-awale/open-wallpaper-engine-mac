import Foundation

/// What a model material's shader lets WE's Advanced Texture Settings change, read from its
/// annotations as WE's editor reads them: `// [COMBO] {…}` lines, and the `// {…}` after a
/// `uniform` (a sampler's label, combo and default; a constant's `material` key, label, range
/// and default). `generic4`, `foliage4`, `fur4` and `chroma4` are WE's model shaders
/// (docs/model-import.md).
public struct ModelShaderSchema: Equatable, Sendable {
    public struct Combo: Equatable, Sendable, Identifiable {
        public var name: String
        /// WE's label key (`ui_editor_properties_lighting`).
        public var label: String
        public var defaultValue: Int
        /// Choices by label key; empty for an on/off combo.
        public var options: [(label: String, value: Int)]
        /// Combos that must have these values for this one to apply.
        public var requirements: [String: Int]
        public var id: String { name }

        public static func == (lhs: Combo, rhs: Combo) -> Bool {
            lhs.name == rhs.name && lhs.label == rhs.label && lhs.defaultValue == rhs.defaultValue
                && lhs.options.map(\.label) == rhs.options.map(\.label) && lhs.options.map(\.value) == rhs.options.map(\.value)
                && lhs.requirements == rhs.requirements
        }
    }

    public struct Texture: Equatable, Sendable, Identifiable {
        /// The sampler's index (`g_Texture<slot>`), its place in the material's `textures`.
        public var slot: Int
        public var label: String
        public var defaultTexture: String?
        /// The combo its texture turns on (`NORMALMAP`, `PBRMASKS`).
        public var combo: String?
        /// The channels of a packed map (`PBRMASKS`: metallic, roughness, reflection, emissive), by label.
        public var components: [(label: String, combo: String)]
        public var requirements: [String: Int]
        public var id: Int { slot }

        public static func == (lhs: Texture, rhs: Texture) -> Bool {
            lhs.slot == rhs.slot && lhs.label == rhs.label && lhs.defaultTexture == rhs.defaultTexture && lhs.combo == rhs.combo
                && lhs.components.map(\.label) == rhs.components.map(\.label) && lhs.requirements == rhs.requirements
        }
    }

    public struct Constant: Equatable, Sendable, Identifiable {
        /// The key in the material's `constantshadervalues`.
        public var key: String
        public var label: String
        /// 1 to 4 numbers.
        public var defaultValue: [Double]
        public var minimum: Double
        public var maximum: Double
        public var isColor: Bool
        /// WE's group label key (`ui_editor_properties_material`); nil for the top.
        public var group: String?
        public var id: String { key }
    }

    public var combos: [Combo] = []
    public var textures: [Texture] = []
    public var constants: [Constant] = []

    public init(combos: [Combo] = [], textures: [Texture] = [], constants: [Constant] = []) {
        self.combos = combos
        self.textures = textures
        self.constants = constants
    }

    /// WE's model shaders, as Advanced Texture Settings offers them.
    public static let modelShaders = ["generic4", "foliage4", "fur4", "chroma4"]

    /// The schema of `shader` from its sources (`shaders/<shader>.frag` and `.vert`), read
    /// with `read`; nil when neither can be read.
    public static func load(_ shader: String, read: (String) -> Data?) -> ModelShaderSchema? {
        let sources = ["frag", "vert"].compactMap { read("shaders/\(shader).\($0)").map { String(decoding: $0, as: UTF8.self) } }
        guard !sources.isEmpty else { return nil }
        var schema = ModelShaderSchema()
        for source in sources { schema.merge(parse(source)) }
        return schema
    }

    mutating func merge(_ other: ModelShaderSchema) {
        for combo in other.combos where !combos.contains(where: { $0.name == combo.name }) { combos.append(combo) }
        for texture in other.textures where !textures.contains(where: { $0.slot == texture.slot }) { textures.append(texture) }
        for constant in other.constants where !constants.contains(where: { $0.key == constant.key }) { constants.append(constant) }
        textures.sort { $0.slot < $1.slot }
    }

    /// The annotations of one shader source.
    public static func parse(_ source: String) -> ModelShaderSchema {
        var schema = ModelShaderSchema()
        for raw in source.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("// [COMBO]"), let json = object(String(line.dropFirst("// [COMBO]".count))),
               let name = json["combo"] as? String {
                var options: [(String, Int)] = []
                if let list = json["options"] as? [String: Any] {
                    options = list.compactMap { key, value in (value as? NSNumber).map { (key, $0.intValue) } }.sorted { $0.1 < $1.1 }
                }
                schema.combos.append(Combo(name: name, label: json["material"] as? String ?? name,
                                           defaultValue: (json["default"] as? NSNumber)?.intValue ?? 0, options: options,
                                           requirements: requirements(json["require"])))
                continue
            }
            guard line.hasPrefix("uniform "), let comment = line.range(of: "//"),
                  let json = object(String(line[comment.upperBound...])) else { continue }
            let declaration = line[..<comment.lowerBound].split(whereSeparator: { $0 == " " || $0 == ";" })
            guard declaration.count >= 3 else { continue }
            let type = String(declaration[1]), name = String(declaration[2])
            if type.hasPrefix("sampler2D") {
                guard json["hidden"] as? Bool != true, name.hasPrefix("g_Texture"), let slot = Int(name.dropFirst("g_Texture".count)) else { continue }
                let components = (json["components"] as? [[String: Any]] ?? []).compactMap { component -> (String, String)? in
                    guard let label = component["label"] as? String, let combo = component["combo"] as? String else { return nil }
                    return (label, combo)
                }
                schema.textures.append(Texture(slot: slot, label: json["label"] as? String ?? json["material"] as? String ?? name,
                                               defaultTexture: json["default"] as? String, combo: json["combo"] as? String,
                                               components: components, requirements: requirements(json["require"])))
            } else if let key = json["material"] as? String {
                let count = ["float": 1, "vec2": 2, "vec3": 3, "vec4": 4][type] ?? 0
                guard count > 0 else { continue }
                var value: [Double] = []
                if let number = json["default"] as? NSNumber { value = [number.doubleValue] }
                if let text = json["default"] as? String { value = text.split(separator: " ").compactMap { Double($0) } }
                if value.count != count { value = Array(repeating: value.first ?? 0, count: count) }
                let range = json["range"] as? [NSNumber]
                schema.constants.append(Constant(key: key, label: json["label"] as? String ?? key, defaultValue: value,
                                                 minimum: range?.first?.doubleValue ?? 0, maximum: range?.last?.doubleValue ?? 1,
                                                 isColor: (json["type"] as? String) == "color", group: json["group"] as? String))
            }
        }
        return schema
    }

    static func object(_ text: String) -> [String: Any]? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"),
              let data = String(text[start...end]).data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func requirements(_ value: Any?) -> [String: Int] {
        (value as? [String: Any] ?? [:]).compactMapValues { ($0 as? NSNumber)?.intValue }
    }

    /// Whether `combo`'s requirements hold for these combo values.
    public static func holds(_ requirements: [String: Int], values: (String) -> Int) -> Bool {
        requirements.allSatisfy { values($0.key) == $0.value }
    }
}

/// A model material's first pass as Advanced Texture Settings edits it: the shader, its combos,
/// textures by slot and constants, every other key kept as it was.
public struct ModelMaterialDocument: Equatable, Sendable {
    public var root: [String: SceneJSONValue]

    public init(root: [String: SceneJSONValue]) { self.root = root }

    public init?(json data: Data) {
        guard case .object(let root)? = SceneJSONValue(any: try? JSONSerialization.jsonObject(with: data)) else { return nil }
        self.root = root
    }

    var pass: [String: SceneJSONValue] {
        get {
            if case .array(let passes)? = root["passes"], case .object(let pass)? = passes.first { return pass }
            return [:]
        }
        set {
            var passes: [SceneJSONValue] = []
            if case .array(let existing)? = root["passes"] { passes = existing }
            if passes.isEmpty { passes = [.object(newValue)] } else { passes[0] = .object(newValue) }
            root["passes"] = .array(passes)
        }
    }

    public var shader: String {
        get { pass["shader"]?.stringValue ?? "generic4" }
        set { pass["shader"] = .string(newValue) }
    }

    public func combo(_ name: String, default fallback: Int) -> Int {
        if case .object(let combos)? = pass["combos"], let value = combos[name]?.doubleValue { return Int(value) }
        return fallback
    }

    public mutating func setCombo(_ name: String, _ value: Int?) {
        var combos: [String: SceneJSONValue] = [:]
        if case .object(let existing)? = pass["combos"] { combos = existing }
        combos[name] = value.map { .number(Double($0)) }
        pass["combos"] = combos.isEmpty ? nil : .object(combos)
    }

    public func texture(_ slot: Int) -> String? {
        if case .array(let textures)? = pass["textures"], slot < textures.count { return textures[slot].stringValue }
        return nil
    }

    /// Sets the texture of `slot`; earlier empty slots are `null`, as WE writes them.
    public mutating func setTexture(_ slot: Int, _ path: String?) {
        var textures: [SceneJSONValue] = []
        if case .array(let existing)? = pass["textures"] { textures = existing }
        while textures.count <= slot { textures.append(.null) }
        textures[slot] = path.map { .string($0) } ?? .null
        while let last = textures.last, last == .null { textures.removeLast() }
        pass["textures"] = .array(textures)
    }

    public func constant(_ key: String) -> [Double]? {
        guard case .object(let values)? = pass["constantshadervalues"], let value = values[key] else { return nil }
        let literal = SceneFieldBinding.literal(of: value) ?? value
        if let number = literal.doubleValue, case .number = literal { return [number] }
        let parts = SceneVector.components(literal)
        return parts.isEmpty ? nil : parts
    }

    /// Sets a constant: one number as a number, more as WE's "x y z" text.
    public mutating func setConstant(_ key: String, _ value: [Double]?) {
        var values: [String: SceneJSONValue] = [:]
        if case .object(let existing)? = pass["constantshadervalues"] { values = existing }
        if let value {
            values[key] = value.count == 1 ? .number(value[0]) : .string(value.map { String(format: "%.5f", $0) }.joined(separator: " "))
        } else {
            values[key] = nil
        }
        pass["constantshadervalues"] = values.isEmpty ? nil : .object(values)
    }

    public func jsonData() throws -> Data {
        try JSONSerialization.data(withJSONObject: SceneJSONValue.object(root).any, options: [.prettyPrinted, .sortedKeys])
    }
}
