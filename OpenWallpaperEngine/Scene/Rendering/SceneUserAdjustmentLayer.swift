import Foundation
import Metal

/// The User Adjustments of Details › User Scene Settings, which aren't WE's: one full-frame
/// composition layer over the finished wallpaper. Nothing of it exists while every adjustment is
/// at its default; the first frame one differs, the layer plans what that adjustment needs, and
/// the active adjustments are stacked on it in order:
///
/// 1. Blur: WE's Blur effect (`effects/blur`, the cheap blur, at its default kernel), its `scale`
///    set to the slider's value on both axes.
/// 2. Bloom: WE's LDR bloom (`SceneBloomChain`) at the slider's strength, whether or not the
///    scene has bloom of its own.
/// 3. WE's Tint, Local Contrast, Chromatic Aberration, VHS and Film Grain effects (`effects`), each
///    at its defaults but for the constant its slider sets.
/// 4. Hue, saturation, Color Pop and Dim: per pixel, in the composite that puts the layer on the
///    drawable.
final class SceneUserAdjustmentLayer: @unchecked Sendable {
    /// One of WE's effects on the layer: the slider's value goes to `constants`; 0 is off.
    struct Effect: Sendable {
        let name: String
        let amount: @Sendable (ScenePostProcess.AppExtras) -> Float
        let constants: @Sendable (ScenePostProcess.AppExtras) -> [SceneScriptConstantWrite]

        var file: String { "effects/\(name)/effect.json" }
        /// The effect graph's state for the effect's targets.
        var stateID: String { "engine:user-\(name)" }
    }

    static let blur = Effect(name: "blur", amount: { $0.blur }) { [SceneUserAdjustmentLayer.write("scale", [$0.blur, $0.blur])] }
    static let bloomStateID = "engine:user-bloom"
    /// The effects after the bloom, in the order they stack.
    static let effects: [Effect] = [
        Effect(name: "tint", amount: { $0.tint }) { [SceneUserAdjustmentLayer.write("alpha", [$0.tint]), SceneUserAdjustmentLayer.write("color", [$0.tintColor.x, $0.tintColor.y, $0.tintColor.z])] },
        Effect(name: "localcontrast", amount: { $0.localContrast }) { [SceneUserAdjustmentLayer.write("strength", [$0.localContrast])] },
        Effect(name: "chromaticaberration", amount: { $0.chromaticAberration }) { [SceneUserAdjustmentLayer.write("ui_editor_properties_strength", [$0.chromaticAberration])] },
        Effect(name: "vhs", amount: { $0.vhs }) { [SceneUserAdjustmentLayer.write("strength", [$0.vhs])] },
        Effect(name: "filmgrain", amount: { $0.filmGrain }) { [SceneUserAdjustmentLayer.write("strength", [$0.filmGrain])] }
    ]

    private let builder: SceneEffectPlanBuilder
    /// Where adjustments are planned, off the render thread (the content loader's queue); nil
    /// plans them where they are first used.
    private let planQueue: DispatchQueue?
    private let lock = NSLock()
    /// Each effect's plan once planned; nil for one that can't be. Behind `lock`.
    private var plans: [String: SceneEffectPlan?] = [:]
    private var bloomChain: SceneBloomChain??
    /// What `planQueue` is planning. Behind `lock`.
    private var planning: Set<String> = []
    /// The states whose targets the layer holds.
    private var held: Set<String> = []
    /// Frames encoded so far: the effects' input changes every frame while its texture stays.
    private var frames: UInt64 = 0

    /// Plans nothing yet: each adjustment is planned the first time it is used, on `planQueue`.
    /// LDR: the layer works on the finished frame, after any HDR combine.
    init(builder: SceneEffectPlanBuilder, planQueue: DispatchQueue? = nil) {
        var builder = builder
        builder.sceneEngineCombos.hdr = false
        self.builder = builder
        self.planQueue = planQueue
    }

    /// An adjustment in use is still being planned: the frame shows without it until it lands.
    var isPlanning: Bool { lock.withLock { !planning.isEmpty } }

    /// Whether the layer draws anything for `extras` beyond the composite's per-pixel adjustments.
    static func runs(_ extras: ScenePostProcess.AppExtras) -> Bool {
        extras.bloom > 0 || ([blur] + effects).contains { $0.amount(extras) > 0 }
    }

    private static func write(_ name: String, _ value: [Float]) -> SceneScriptConstantWrite {
        SceneScriptConstantWrite(material: nil, name: name, value: value)
    }

    /// Encodes the layer's effects on `frame` and returns the result; nil when none runs or none
    /// is ready (the frame shows as it is). Targets of an adjustment back at its default are released.
    func encode(on frame: MTLTexture, extras: ScenePostProcess.AppExtras, bloomThreshold: Float,
                effects: EffectGraphRenderer, builtins: BuiltinFrameContext, values: SceneValueContext,
                assetTexture: @escaping (String, SceneMetalTextureSource) -> MTLTexture?,
                referenceSize: SIMD2<Float>, commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        frames &+= 1
        var output = frame
        func apply(_ effect: Effect) {
            guard effect.amount(extras) > 0, let plan = plan(effect) else {
                release(effect.stateID, from: effects)
                return
            }
            held.insert(effect.stateID)
            var context = EffectGraphRenderer.Context(
                frame: builtins, values: values, assetTexture: assetTexture,
                sceneSnapshot: frame, layerColor: SIMD3(repeating: 1), layerAlpha: 1)
            context.inputVersion = frames
            context.constantWrites = [plan.effectIndex: effect.constants(extras)]
            output = effects.apply([plan], to: output, layerID: effect.stateID, context: context,
                                   commandBuffer: commandBuffer) ?? output
        }
        apply(Self.blur)
        if extras.bloom > 0, let chain = bloom() {
            held.insert(Self.bloomStateID)
            output = chain.encode(on: output, strength: extras.bloom, threshold: bloomThreshold, tint: SIMD3(repeating: 1),
                                  effects: effects, builtins: builtins, values: values, frameIndex: frames,
                                  referenceSize: referenceSize, stateID: Self.bloomStateID,
                                  commandBuffer: commandBuffer) ?? output
        } else {
            release(Self.bloomStateID, from: effects)
        }
        Self.effects.forEach(apply)
        return output === frame ? nil : output
    }

    private func release(_ stateID: String, from effects: EffectGraphRenderer) {
        guard held.remove(stateID) != nil else { return }
        effects.releaseLayer(stateID)
    }

    /// Releases every target a user adjustment layer holds (every adjustment back at its default),
    /// `layer`'s or an earlier content's.
    static func release(_ layer: SceneUserAdjustmentLayer?, from effects: EffectGraphRenderer) {
        for stateID in [blur.stateID, bloomStateID] + Self.effects.map(\.stateID) {
            effects.releaseLayer(stateID)
        }
        layer?.held.removeAll()
    }

    private func plan(_ effect: Effect) -> SceneEffectPlan? {
        if let plan = lock.withLock({ plans[effect.name] }) { return plan }
        schedule(effect.name) { [self] in
            let plan = makePlan(effect)
            lock.withLock { plans[effect.name] = .some(plan) }
        }
        return lock.withLock { plans[effect.name] } ?? nil
    }

    private func bloom() -> SceneBloomChain? {
        if let chain = lock.withLock({ bloomChain }) { return chain }
        schedule("bloom") { [self] in
            var chain: SceneBloomChain?
            do {
                chain = try SceneBloomChain.build(with: builder)
            } catch {
                OWELog.error(.scene, "The Bloom adjustment can't be planned; the wallpaper draws without it: \(error)")
            }
            lock.withLock { bloomChain = .some(chain) }
        }
        return lock.withLock { bloomChain } ?? nil
    }

    /// Runs `work` on `planQueue` once for `name` (in place without a queue); `name` is planning until it ends.
    private func schedule(_ name: String, _ work: @escaping @Sendable () -> Void) {
        guard let planQueue else { return work() }
        guard lock.withLock({ planning.insert(name).inserted }) else { return }
        planQueue.async { [self] in
            work()
            _ = lock.withLock { planning.remove(name) }
        }
    }

    private func makePlan(_ effect: Effect) -> SceneEffectPlan? {
        do {
            let json = try JSONEncoder().encode(["file": effect.file])
            let plan = try builder.build(try JSONDecoder().decode(WEObjectEffect.self, from: json))
            guard !plan.passes.isEmpty, !plan.passes.contains(where: { $0.variant == nil }) else {
                throw SceneEffectPlanError.missing("the \(effect.name) effect's shaders")
            }
            return plan
        } catch {
            OWELog.error(.scene, "The \(effect.name) adjustment can't be planned; the wallpaper draws without it: \(error)")
            return nil
        }
    }
}
