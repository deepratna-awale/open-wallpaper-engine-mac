import Foundation

/// A model material's first pass as Advanced Texture Settings edits it: the shader, its combos,
/// textures by slot and constants, every other key kept as it was.
public struct MaterialPassDocument: Equatable, Sendable {
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
