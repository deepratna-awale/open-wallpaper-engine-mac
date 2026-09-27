import simd

/// The `WEUniforms` bytes of one mesh's material (docs/models-plan.md §2.7): its constants
/// written once, its bound constants and the time-varying built-ins (lights included) every draw,
/// the built-ins that depend on where the model is drawn (`g_ModelMatrix`, `g_NormalModelMatrix`,
/// `g_ViewProjectionMatrix`, `g_EyePosition`, the texture sizes…) only when that changes, and the
/// bones slot (`g_Bones`, `BONECOUNT` × `mat4x3`) whenever the pose does.
///
/// A model's material takes nothing from its object: WE doesn't read `color`, `alpha` or
/// `brightness` on models (§2.6), so `g_Brightness`, `g_TintColor` and the like are the
/// material's own constants.
final class ModelMaterialUniforms {
    /// What the placement-dependent built-ins are computed from.
    struct PassKey: Equatable {
        var world: simd_float4x4
        var view: simd_float4x4
        var viewProjection: simd_float4x4
        var eye: SIMD3<Float>
        var screen: SIMD2<Float>
        var target: SIMD2<Float>
        /// Per bound slot: allocated width/height, content width/height.
        var textures: [SIMD4<Float>]
    }

    private(set) var bytes: [UInt8]
    let size: Int
    private let dynamic: [(member: UniformMember, constant: ShaderConstantResolver.DynamicConstant)]
    private let frameBuiltins: [UniformMember]
    private let passBuiltins: [UniformMember]
    private let bones: UniformMember?
    private let layout: UniformLayout?
    private var lastKey: PassKey?
    private var lastBones: [Float]?

    init(layout: UniformLayout?, constants: ShaderConstantResolver.ResolvedConstants) {
        size = layout?.size ?? 0
        self.layout = layout
        bytes = [UInt8](repeating: 0, count: size)
        let dynamicByName = Dictionary(constants.dynamic.map { ($0.uniform, $0) }, uniquingKeysWith: { a, _ in a })
        var dynamic: [(UniformMember, ShaderConstantResolver.DynamicConstant)] = []
        var builtins: [UniformMember] = []
        for member in (layout?.members.values).map(Array.init) ?? [] {
            if let constant = dynamicByName[member.name] {
                dynamic.append((member, constant))
            } else if let value = constants.staticValues[member.name] {
                UniformWriter.write(value.components, member: member, into: &bytes)
            } else if BuiltinUniforms.isBuiltin(member.name) {
                builtins.append(member)
            }
        }
        self.dynamic = dynamic
        let varies = { (member: UniformMember) in
            UniformProgram.timeVarying.contains(member.name) || member.name.hasPrefix("g_AudioSpectrum")
        }
        frameBuiltins = builtins.filter(varies)
        passBuiltins = builtins.filter { !varies($0) }
        bones = layout?.members["g_Bones"]
        // The bind pose until the first pose arrives: every bone the identity.
        if let bones { UniformWriter.write(Self.identityBones(count: bones.count), member: bones, into: &bytes) }
    }

    /// Writes this draw's values. `pass` builds the pass context; it runs only when needed.
    func update(key: PassKey, frame: BuiltinFrameContext, values: SceneValueContext, pass: () -> BuiltinPassContext) {
        for (member, constant) in dynamic {
            let value = ShaderConstantResolver.shape(SceneValueResolver.resolve(constant.source, in: values),
                                                     count: constant.count, isInt: constant.isInt)
            UniformWriter.write(value.components, member: member, into: &bytes)
        }
        let placementChanged = key != lastKey
        guard !frameBuiltins.isEmpty || placementChanged else { return }
        let context = pass()
        write(frameBuiltins, frame: frame, pass: context)
        if placementChanged {
            lastKey = key
            write(passBuiltins, frame: frame, pass: context)
        }
    }

    /// The bones slot: `g_Bones` as `mat4x3` components (per bone the four columns' x, y and z of
    /// `boneWorld · inverseBind`, `ScenePuppetPose.boneComponents`), padded with identities to the
    /// shader's `BONECOUNT`. Nothing to do for a material without skinning.
    func writeBones(_ components: [Float]) {
        guard let bones, components != lastBones else { return }
        lastBones = components
        let count = components.count / 12
        let padded = count >= bones.count ? Array(components.prefix(bones.count * 12))
            : components + Self.identityBones(count: bones.count - count)
        UniformWriter.write(padded, member: bones, into: &bytes)
    }

    var hasBones: Bool { bones != nil }

    /// Writes an engine value the material doesn't set and the built-ins don't cover (the shadow
    /// variant's `g_ViewportViewProjectionMatrices`); false when the layout has no such member.
    @discardableResult
    func write(_ components: [Float], member name: String) -> Bool {
        guard let member = layout?.members[name] else { return false }
        UniformWriter.write(components, member: member, into: &bytes)
        return true
    }

    private func write(_ members: [UniformMember], frame: BuiltinFrameContext, pass: BuiltinPassContext) {
        for member in members {
            guard let components = BuiltinUniforms.value(named: member.name, frame: frame, pass: pass,
                                                         arrayCount: member.count > 1 ? member.count : nil) else { continue }
            UniformWriter.write(components, member: member, into: &bytes)
        }
    }

    static func identityBones(count: Int) -> [Float] {
        Array([[Float]](repeating: [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0], count: max(count, 0)).joined())
    }
}
