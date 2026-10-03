import CryptoKit
import Foundation

/// The Wallpaper Editor's edits of one wallpaper: object fields and effect changes kept beside the
/// wallpaper, never written into its files (docs/editor-plan.md §3). The scene loader applies them
/// on top of scene.json (`applied(to:)`) wherever the wallpaper runs; Revert drops them; Save as
/// Local Wallpaper bakes them into a copy.
///
/// Objects are keyed by their scene.json `id` (their index when they have none), effects by their
/// index in the object's `effects`, as the Scene Inspector's edits are.
public struct SceneEditOverlay: Codable, Hashable, Sendable {
    public static let currentVersion = 1

    public struct EffectEdit: Codable, Hashable, Sendable {
        /// The effect's `visible`; nil keeps the authored one.
        public var visible: Bool?
        /// Values of its first pass's `constants`, by the material key.
        public var constants: [String: SceneJSONValue] = [:]

        public init(visible: Bool? = nil, constants: [String: SceneJSONValue] = [:]) {
            self.visible = visible
            self.constants = constants
        }

        public var isEmpty: Bool { visible == nil && constants.isEmpty }
    }

    public struct ObjectEdit: Codable, Hashable, Sendable {
        /// Object fields by scene.json name (`origin`, `scale`, `angles`, `alpha`, `color`,
        /// `colorBlendMode`, `visible`, …), each replacing the authored value.
        public var fields: [String: SceneJSONValue] = [:]
        /// Effect edits by the effect's index.
        public var effects: [String: EffectEdit] = [:]
        /// Editor state, not a scene edit: the layer can't be picked or moved on the canvas.
        public var locked: Bool?

        public init(fields: [String: SceneJSONValue] = [:], effects: [String: EffectEdit] = [:], locked: Bool? = nil) {
            self.fields = fields
            self.effects = effects
            self.locked = locked
        }

        public var hasSceneEdits: Bool { !fields.isEmpty || effects.values.contains { !$0.isEmpty } }
        var isEmpty: Bool { !hasSceneEdits && locked != true }
    }

    public var version = SceneEditOverlay.currentVersion
    public var objects: [String: ObjectEdit] = [:]
    /// Puppet Warp rigs made or edited in the editor, by the image layer's key
    /// (`SceneEditOverlay+Puppets`). They don't change the running scene; Save as Local
    /// Wallpaper writes them as `.mdl` files (`PuppetSceneBake`).
    public var puppets: [String: PuppetDocument]?

    public init(objects: [String: ObjectEdit] = [:]) {
        self.objects = objects
    }

    /// Nothing to save: no edits and no locked layers.
    public var isEmpty: Bool { objects.values.allSatisfy(\.isEmpty) && !hasPuppetEdits }

    /// Something changes the scene (locks don't).
    public var hasSceneEdits: Bool { objects.values.contains(where: \.hasSceneEdits) }

    // MARK: Reading

    public func field(_ name: String, of objectID: Int) -> SceneJSONValue? {
        objects[String(objectID)]?.fields[name]
    }

    public func effectVisible(_ effectIndex: Int, of objectID: Int) -> Bool? {
        objects[String(objectID)]?.effects[String(effectIndex)]?.visible
    }

    public func effectConstant(_ key: String, effect effectIndex: Int, of objectID: Int) -> SceneJSONValue? {
        objects[String(objectID)]?.effects[String(effectIndex)]?.constants[key]
    }

    public func isLocked(_ objectID: Int) -> Bool { objects[String(objectID)]?.locked == true }

    public func hasEdits(_ objectID: Int) -> Bool { objects[String(objectID)]?.hasSceneEdits == true }

    // MARK: Changing

    /// Sets field `name` of the object; nil drops the edit (the authored value again).
    public mutating func setField(_ name: String, to value: SceneJSONValue?, of objectID: Int) {
        update(objectID) { $0.fields[name] = value }
    }

    public mutating func setEffectVisible(_ visible: Bool?, effect effectIndex: Int, of objectID: Int) {
        updateEffect(effectIndex, of: objectID) { $0.visible = visible }
    }

    public mutating func setEffectConstant(_ key: String, to value: SceneJSONValue?, effect effectIndex: Int, of objectID: Int) {
        updateEffect(effectIndex, of: objectID) { $0.constants[key] = value }
    }

    public mutating func setLocked(_ locked: Bool, _ objectID: Int) {
        update(objectID) { $0.locked = locked ? true : nil }
    }

    private mutating func update(_ objectID: Int, _ change: (inout ObjectEdit) -> Void) {
        let key = String(objectID)
        var edit = objects[key] ?? ObjectEdit()
        change(&edit)
        objects[key] = edit.isEmpty ? nil : edit
    }

    private mutating func updateEffect(_ effectIndex: Int, of objectID: Int, _ change: (inout EffectEdit) -> Void) {
        update(objectID) { edit in
            let key = String(effectIndex)
            var effect = edit.effects[key] ?? EffectEdit()
            change(&effect)
            edit.effects[key] = effect.isEmpty ? nil : effect
        }
    }

    // MARK: Files

    /// Sorted, so the same edits always write the same bytes.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func decoded(from data: Data) throws -> SceneEditOverlay {
        let overlay = try JSONDecoder().decode(SceneEditOverlay.self, from: data)
        guard overlay.version <= currentVersion else { throw SceneEditOverlayError.newerVersion(overlay.version) }
        return overlay
    }

    /// Names the scene edits (not the locks) for the scene cache key: a parse is only reused for
    /// the edits it was made with.
    public var digest: String {
        var sceneEdits = self
        sceneEdits.puppets = nil
        for (key, edit) in sceneEdits.objects {
            sceneEdits.objects[key]?.locked = nil
            if !edit.hasSceneEdits { sceneEdits.objects[key] = nil }
        }
        guard let data = try? sceneEdits.encoded() else { return "" }
        return SHA256.hash(data: data).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}

public enum SceneEditOverlayError: Error, Equatable, LocalizedError {
    /// Written by a newer app, whose edits this one might apply wrong.
    case newerVersion(Int)
    /// scene.json isn't an object with an `objects` array.
    case notAScene

    public var errorDescription: String? {
        switch self {
        case .newerVersion(let version): return "The editor overlay is version \(version), newer than this app reads."
        case .notAScene: return "scene.json has no objects."
        }
    }
}
