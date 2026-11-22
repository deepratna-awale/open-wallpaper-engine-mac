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
/// 3. Hue and saturation: per pixel, in the composite that puts the layer on the drawable.
final class SceneUserAdjustmentLayer {
    static let blurFile = "effects/blur/effect.json"
    /// The effect graph's states for the layer's targets.
    static let blurStateID = "engine:user-blur"
    static let bloomStateID = "engine:user-bloom"

    private let builder: SceneEffectPlanBuilder
    private var blurPlan: SceneEffectPlan?
    private var blurFailed = false
    private var bloomChain: SceneBloomChain?
    private var bloomFailed = false
    private var holdsBlur = false
    private var holdsBloom = false
    /// Frames encoded so far: the effects' input changes every frame while its texture stays.
    private var frames: UInt64 = 0

    /// Plans nothing yet: each adjustment is planned the first time it is used. LDR: the layer
    /// works on the finished frame, after any HDR combine.
    init(builder: SceneEffectPlanBuilder) {
        var builder = builder
        builder.sceneEngineCombos.hdr = false
        self.builder = builder
    }

    /// Whether the layer draws anything for `extras` beyond the composite's hue and saturation.
    static func runs(_ extras: ScenePostProcess.AppExtras) -> Bool {
        extras.blur > 0 || extras.bloom > 0
    }

    /// The `scale` constant WE's Blur effect gets for the Blur slider.
    static func blurConstants(_ amount: Float) -> [SceneScriptConstantWrite] {
        [SceneScriptConstantWrite(material: nil, name: "scale", value: [amount, amount])]
    }

    /// Encodes the layer's blur and bloom on `frame` and returns the result; nil when neither runs
    /// or neither is ready (the frame shows as it is). Targets of an adjustment back at its default
    /// are released.
    func encode(on frame: MTLTexture, extras: ScenePostProcess.AppExtras, bloomThreshold: Float,
                effects: EffectGraphRenderer, builtins: BuiltinFrameContext, values: SceneValueContext,
                referenceSize: SIMD2<Float>, commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        frames &+= 1
        var output = frame
        if extras.blur > 0, let plan = blur() {
            holdsBlur = true
            var context = EffectGraphRenderer.Context(
                frame: builtins, values: values, assetTexture: { _, _ in nil },
                sceneSnapshot: frame, layerColor: SIMD3(repeating: 1), layerAlpha: 1)
            context.inputVersion = frames
            context.constantWrites = [plan.effectIndex: Self.blurConstants(extras.blur)]
            output = effects.apply([plan], to: output, layerID: Self.blurStateID, context: context,
                                   commandBuffer: commandBuffer) ?? output
        } else if holdsBlur {
            effects.releaseLayer(Self.blurStateID)
            holdsBlur = false
        }
        if extras.bloom > 0, let chain = bloom() {
            holdsBloom = true
            output = chain.encode(on: output, strength: extras.bloom, threshold: bloomThreshold, tint: SIMD3(repeating: 1),
                                  effects: effects, builtins: builtins, values: values, frameIndex: frames,
                                  referenceSize: referenceSize, stateID: Self.bloomStateID,
                                  commandBuffer: commandBuffer) ?? output
        } else if holdsBloom {
            effects.releaseLayer(Self.bloomStateID)
            holdsBloom = false
        }
        return output === frame ? nil : output
    }

    /// Releases every target a user adjustment layer holds (every adjustment back at its default),
    /// `layer`'s or an earlier content's.
    static func release(_ layer: SceneUserAdjustmentLayer?, from effects: EffectGraphRenderer) {
        effects.releaseLayer(blurStateID)
        effects.releaseLayer(bloomStateID)
        layer?.holdsBlur = false
        layer?.holdsBloom = false
    }

    private func blur() -> SceneEffectPlan? {
        if let blurPlan { return blurPlan }
        guard !blurFailed else { return nil }
        do {
            let effect = try JSONDecoder().decode(WEObjectEffect.self, from: Data(#"{"file": "\#(Self.blurFile)"}"#.utf8))
            let plan = try builder.build(effect)
            guard !plan.passes.isEmpty, !plan.passes.contains(where: { $0.variant == nil }) else {
                throw SceneEffectPlanError.missing("the Blur effect's shaders")
            }
            blurPlan = plan
            return plan
        } catch {
            blurFailed = true
            OWELog.error(.scene, "The Blur adjustment can't be planned; the wallpaper draws without it: \(error)")
            return nil
        }
    }

    private func bloom() -> SceneBloomChain? {
        if let bloomChain { return bloomChain }
        guard !bloomFailed else { return nil }
        do {
            let chain = try SceneBloomChain.build(with: builder)
            bloomChain = chain
            return chain
        } catch {
            bloomFailed = true
            OWELog.error(.scene, "The Bloom adjustment can't be planned; the wallpaper draws without it: \(error)")
            return nil
        }
    }
}
