import Foundation
import simd

/// The configuration beside an imported model's source (`models/<name>/<name>.json` next to
/// `<name>.fbx` or `.obj`), which WE's resource compiler reads with the source to write the
/// `.mdl` (`resourcecompiler64.exe -mdl`), and which WE's Model Editor edits
/// (docs/model-import.md).
///
/// The keys are WE's: `normals`, `tangentspace` and `seconduvchannel` (the default projects'
/// configurations; WE's importer writes the first two as true for every FBX and OBJ),
/// `additionalfiles`, `clips` (`start`, `end`, `frameoffset`, `matchloop`, `rootmotion`,
/// `motionflags`), `events`, `attachments` and per-bone `constraints` (the strings of
/// `resourcecompiler64.exe` and `wallpaperui.exe`). How the lists' records are laid out isn't in
/// any file this project has seen: the layout here is ours, documented as guessed, and keys
/// this type doesn't know are kept as they were.
public struct ModelImportConfig: Sendable, Equatable {
    /// A clip cut from an animation (Model Editor › Animation › Add Clip): an `MDLA` record with
    /// the clip record (flag 0x1) after it.
    public struct Clip: Sendable, Equatable, Identifiable {
        public var id: UInt64
        public var name: String
        /// The id of the animation it is cut from (one of the source's, `ModelCompiler.animationID`).
        public var animation: UInt64
        public var start: Int
        public var end: Int
        public var frameOffset: Int
        /// "Match loop" (flag 0x400), on by default in WE's editor.
        public var matchLoop: Bool
        /// The Motion root bone's name; empty for None.
        public var rootMotion: String
        /// Root motion axes as the editor's flags byte (bits 8…15 of the clip flags): 0x08, 0x10
        /// and 0x20 position x, y and z, 0x80 rotation about y (docs/models-plan.md §2.8).
        public var motionFlags: UInt8
        /// The clip's frame rate; nil keeps the source animation's.
        public var fps: Float?
        /// "loop", "mirror" or "single" (`MDLA`'s mode).
        public var mode: String

        public init(id: UInt64, name: String, animation: UInt64, start: Int, end: Int, frameOffset: Int = 0, matchLoop: Bool = true,
                    rootMotion: String = "", motionFlags: UInt8 = 0, fps: Float? = nil, mode: String = "loop") {
            self.id = id
            self.name = name
            self.animation = animation
            self.start = start
            self.end = end
            self.frameOffset = frameOffset
            self.matchLoop = matchLoop
            self.rootMotion = rootMotion
            self.motionFlags = motionFlags
            self.fps = fps
            self.mode = mode
        }

        public static let positionX: UInt8 = 0x08
        public static let positionY: UInt8 = 0x10
        public static let positionZ: UInt8 = 0x20
        public static let rotationY: UInt8 = 0x80
    }

    /// A named frame of an animation or clip (`MDLA`'s events, which a scene's
    /// `animationEvent` scripts receive).
    public struct Event: Sendable, Equatable, Identifiable {
        public var id: UInt64
        public var name: String
        public var frame: Float
        /// The animation or clip it belongs to.
        public var animation: UInt64

        public init(id: UInt64, name: String, frame: Float, animation: UInt64) {
            self.id = id
            self.name = name
            self.frame = frame
            self.animation = animation
        }
    }

    /// A named point on a bone (`MDAT0001`), which a scene object's `attachment` names.
    public struct Attachment: Sendable, Equatable, Identifiable {
        public var id: UInt64
        public var name: String
        public var bone: String
        public var origin: SIMD3<Float>
        /// Radians, as WE's scene vectors.
        public var angles: SIMD3<Float>

        public init(id: UInt64, name: String, bone: String, origin: SIMD3<Float> = .zero, angles: SIMD3<Float> = .zero) {
            self.id = id
            self.name = name
            self.bone = bone
            self.origin = origin
            self.angles = angles
        }

        /// The `MDAT` offset matrix: `T · R`, R = Rz·Ry·Rx.
        public var matrix: simd_float4x4 {
            PuppetMath.matrix(translation: origin, euler: angles, scale: SIMD3(repeating: 1))
        }
    }

    public var normals: Bool
    public var tangentSpace: Bool
    public var secondUVChannel: Bool
    /// More source files whose animations the model gets (Add FBX File), by name beside the source.
    public var additionalFiles: [String]
    public var clips: [Clip]
    public var events: [Event]
    public var attachments: [Attachment]
    /// Bone physics by bone name, compiled into the bones' properties JSON as Puppet Warp's are.
    public var constraints: [String: PuppetBonePhysics]
    /// Keys this type doesn't read, kept as they were.
    public var other: [String: SceneJSONValue]

    /// What WE's importer writes for a new FBX or OBJ: normals and tangents on.
    public init(normals: Bool = true, tangentSpace: Bool = true, secondUVChannel: Bool = false, additionalFiles: [String] = [],
                clips: [Clip] = [], events: [Event] = [], attachments: [Attachment] = [],
                constraints: [String: PuppetBonePhysics] = [:], other: [String: SceneJSONValue] = [:]) {
        self.normals = normals
        self.tangentSpace = tangentSpace
        self.secondUVChannel = secondUVChannel
        self.additionalFiles = additionalFiles
        self.clips = clips
        self.events = events
        self.attachments = attachments
        self.constraints = constraints
        self.other = other
    }

    /// A model without a configuration file: WE's compiler then writes neither normals nor
    /// tangents (the default projects' `techno/glow.mdl`, format 0x9).
    public static let missing = ModelImportConfig(normals: false, tangentSpace: false)

    /// The next id no clip, event or attachment uses, above every animation id.
    public func nextID(after animations: Int) -> UInt64 {
        let used = clips.map(\.id) + events.map(\.id) + attachments.map(\.id)
        return max(used.max() ?? 0, UInt64(animations), 1000) + 1
    }

    // MARK: JSON

    static let knownKeys: Set<String> = ["normals", "tangentspace", "seconduvchannel", "additionalfiles", "clips", "events",
                                         "attachments", "constraints"]

    public init(json data: Data) throws {
        guard case .object(let root)? = SceneJSONValue(any: try JSONSerialization.jsonObject(with: data)) else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        self.init(object: root)
    }

    public init(object root: [String: SceneJSONValue]) {
        self.init(normals: root["normals"]?.boolValue ?? false, tangentSpace: root["tangentspace"]?.boolValue ?? false,
                  secondUVChannel: root["seconduvchannel"]?.boolValue ?? false)
        additionalFiles = root["additionalfiles"]?.arrayValue?.compactMap(\.stringValue) ?? []
        clips = (root["clips"]?.arrayValue ?? []).compactMap { value in
            guard case .object(let o) = value else { return nil }
            return Clip(id: o["id"]?.idValue ?? 0, name: o["name"]?.stringValue ?? "", animation: o["animation"]?.idValue ?? 0,
                        start: o["start"]?.intValue ?? 0, end: o["end"]?.intValue ?? 0, frameOffset: o["frameoffset"]?.intValue ?? 0,
                        matchLoop: o["matchloop"]?.boolValue ?? true, rootMotion: o["rootmotion"]?.stringValue ?? "",
                        motionFlags: UInt8(clamping: o["motionflags"]?.intValue ?? 0), fps: o["fps"]?.numberValue.map(Float.init),
                        mode: o["mode"]?.stringValue ?? "loop")
        }
        events = (root["events"]?.arrayValue ?? []).compactMap { value in
            guard case .object(let o) = value else { return nil }
            return Event(id: o["id"]?.idValue ?? 0, name: o["name"]?.stringValue ?? "", frame: Float(o["frame"]?.numberValue ?? 0),
                         animation: o["animation"]?.idValue ?? 0)
        }
        attachments = (root["attachments"]?.arrayValue ?? []).compactMap { value in
            guard case .object(let o) = value else { return nil }
            return Attachment(id: o["id"]?.idValue ?? 0, name: o["name"]?.stringValue ?? "", bone: o["bone"]?.stringValue ?? "",
                              origin: Self.vector(o["origin"]) ?? .zero, angles: Self.vector(o["angles"]) ?? .zero)
        }
        if case .object(let bones)? = root["constraints"] {
            for (bone, value) in bones {
                if case .object(let properties) = value, let physics = PuppetBonePhysics(properties: properties) {
                    constraints[bone] = physics
                }
            }
        }
        other = root.filter { !Self.knownKeys.contains($0.key) }
    }

    public var object: [String: SceneJSONValue] {
        var root = other
        root["normals"] = .bool(normals)
        root["tangentspace"] = .bool(tangentSpace)
        if secondUVChannel { root["seconduvchannel"] = .bool(true) }
        if !additionalFiles.isEmpty { root["additionalfiles"] = .array(additionalFiles.map { .string($0) }) }
        if !clips.isEmpty {
            root["clips"] = .array(clips.map { clip in
                var o: [String: SceneJSONValue] = [
                    "id": .number(Double(clip.id)), "name": .string(clip.name), "animation": .number(Double(clip.animation)),
                    "start": .number(Double(clip.start)), "end": .number(Double(clip.end)),
                    "frameoffset": .number(Double(clip.frameOffset)), "matchloop": .bool(clip.matchLoop),
                    "rootmotion": .string(clip.rootMotion), "motionflags": .number(Double(clip.motionFlags)), "mode": .string(clip.mode),
                ]
                if let fps = clip.fps { o["fps"] = .number(Double(fps)) }
                return .object(o)
            })
        }
        if !events.isEmpty {
            root["events"] = .array(events.map {
                .object(["id": .number(Double($0.id)), "name": .string($0.name), "frame": .number(Double($0.frame)),
                         "animation": .number(Double($0.animation))])
            })
        }
        if !attachments.isEmpty {
            root["attachments"] = .array(attachments.map {
                .object(["id": .number(Double($0.id)), "name": .string($0.name), "bone": .string($0.bone),
                         "origin": .string(Self.vectorString($0.origin)), "angles": .string(Self.vectorString($0.angles))])
            })
        }
        if !constraints.isEmpty {
            root["constraints"] = .object(constraints.mapValues { .object($0.properties(childDistance: nil)) })
        }
        return root
    }

    /// The configuration as WE's files write JSON (tab-indented by WE; sorted keys here so the
    /// same edits always write the same bytes).
    public func jsonData() throws -> Data {
        try JSONSerialization.data(withJSONObject: SceneJSONValue.object(object).any, options: [.prettyPrinted, .sortedKeys])
    }

    static func vector(_ value: SceneJSONValue?) -> SIMD3<Float>? {
        guard case .string(let text)? = value else { return nil }
        let parts = text.split(whereSeparator: \.isWhitespace).compactMap { Float($0) }
        return parts.count == 3 ? SIMD3(parts[0], parts[1], parts[2]) : nil
    }

    static func vectorString(_ v: SIMD3<Float>) -> String {
        String(format: "%.5f %.5f %.5f", Double(v.x), Double(v.y), Double(v.z))
    }
}

extension SceneJSONValue {
    var numberValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    var intValue: Int? { numberValue.map { Int($0.rounded()) } }

    var idValue: UInt64? { numberValue.flatMap { $0 >= 0 ? UInt64($0.rounded()) : nil } }

    var arrayValue: [SceneJSONValue]? {
        if case .array(let values) = self { return values }
        return nil
    }
}
