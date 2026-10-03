import Foundation

/// Which effect buffers may be drawn below their authored size, and by how much (efficiency plan
/// WP3-C, item 4).
///
/// Blur, bloom, glow and god-ray effects spread light over many pixels, so their intermediate
/// buffers carry little detail: drawing them at ½ (or ¼ at the efficiency end of the
/// Quality↔Efficiency slider, `QualityEfficiency.blurResolutionDivisor`) costs a quarter (or a
/// sixteenth) of the pixels and looks the same once the pass that reads them samples them
/// bilinearly. Only the effect's own FBOs shrink: its last pass still draws at the layer's size,
/// and every reduced buffer reports its authored size to the built-ins (`g_Texture0Texel`), so a
/// kernel's reach in UV space, and so the blur's radius, is unchanged.
///
/// Recognised from the effect's file name or its buffers' pattern (`isBlurLike`), never per wallpaper. Left alone:
/// - buffers of fixed size (a tile) or that tile (`uvs: repeat`);
/// - effects that carry frames (motion blur's accumulation, simulations) or copy between buffers,
///   whose sizes must match;
/// - chains on text or line-art layers, where a softened intermediate would show at sharp edges.
///
/// A temporal accumulation (`isTemporalAccumulation`: motion blur's history and its copy) is the
/// one frame-carrying effect that may shrink, by its own divisor (`temporalDivisor`): its buffers
/// blend frames over time, so they hold the low-frequency trail, and every one of them shrinks by
/// the same factor, so its copies stay between equal sizes.
struct EffectResolutionPolicy: Equatable {
    /// 1 full size, 2 half, 4 quarter.
    var divisor: Int
    /// The layer is text or line art (`SceneLayerContentClass`): its chain stays at full size.
    var sharpContent: Bool
    /// The divisor of a temporal accumulation's buffers (1 keeps them; `QualityEfficiency.temporalAccumulationDivisor`).
    var temporalDivisor: Int

    init(divisor: Int = 1, sharpContent: Bool = false, temporalDivisor: Int = 1) {
        self.divisor = max(1, divisor)
        self.sharpContent = sharpContent
        self.temporalDivisor = max(1, temporalDivisor)
    }

    static let full = EffectResolutionPolicy()

    /// Authored and reduced scale together stay at or under this (a ¼ blur buffer halved again
    /// is ⅛; further only loses the blur's shape).
    static let maxTotalScale = 8
    /// A reduced buffer keeps at least this many pixels on its shorter side.
    static let minSide = 16

    /// Effect file names (without folders) of blur-like effects.
    private static let namePatterns = ["blur", "bloom", "glow", "godray", "shine", "lightshaft"]
    /// The effect spreads light (a blur, bloom, glow or god rays): its file or folder is named
    /// so, or its passes already draw into a downsampled buffer (an FBO with `scale` ≥ 2, WE's
    /// blur, god-ray, shine and local-contrast pattern: the author treats it as low-frequency).
    static func isBlurLike(_ effect: SceneEffectPlan) -> Bool {
        let name = (effect.file as NSString).lastPathComponent.lowercased()
        let folder = ((effect.file as NSString).deletingLastPathComponent as NSString).lastPathComponent.lowercased()
        if namePatterns.contains(where: { name.contains($0) || folder.contains($0) }) { return true }
        return effect.fbos.contains { $0.scale >= 2 && $0.width == nil }
    }

    /// The extra divisor of `fbo`'s size in `effect` (1 keeps the authored size).
    func divisor(for fbo: EffectFBO, in effect: SceneEffectPlan) -> Int {
        guard !sharpContent, Self.followsLayer(fbo) else { return 1 }
        if temporalDivisor > 1, Self.isTemporalAccumulation(effect) {
            // Every buffer by the same factor: a copy between two of them needs equal sizes.
            let shrinkable = effect.fbos.allSatisfy(Self.followsLayer) && Set(effect.fbos.map(\.scale)).count == 1
            guard shrinkable else { return 1 }
            var extra = temporalDivisor
            while extra > 1, max(fbo.scale, 1) * extra > Self.maxTotalScale { extra /= 2 }
            return extra
        }
        guard divisor > 1, Self.eligible(effect) else { return 1 }
        let authored = max(fbo.scale, 1)
        // A full-size buffer is the author asking for detail (`blurprecise`): at most halved.
        var extra = authored == 1 ? min(divisor, 2) : divisor
        while extra > 1, authored * extra > Self.maxTotalScale { extra /= 2 }
        return extra
    }

    /// `size` (the authored FBO size) divided by `extra`, keeping `minSide` on the shorter side.
    static func reduced(_ size: SIMD2<Int>, by extra: Int) -> SIMD2<Int> {
        guard extra > 1 else { return size }
        var factor = extra
        while factor > 1, min(size.x, size.y) / factor < minSide { factor /= 2 }
        guard factor > 1 else { return size }
        return SIMD2(max((size.x + factor - 1) / factor, 1), max((size.y + factor - 1) / factor, 1))
    }

    /// A buffer sized from the layer (`scale`), not fixed, fitted or tiled.
    private static func followsLayer(_ fbo: EffectFBO) -> Bool {
        if let width = fbo.width, let height = fbo.height, width > 0, height > 0 { return false }
        return fbo.uvs != "repeat" && fbo.fit == nil
    }

    /// A blur that carries frames through copies between its own buffers (motion blur: blend the
    /// image into the history, copy it back, show it). A simulation swaps its buffers and a copy
    /// from the effect's input keeps the input's size; neither is one.
    static func isTemporalAccumulation(_ effect: SceneEffectPlan) -> Bool {
        guard isBlurLike(effect), effect.carriesFrames else { return false }
        var copies = false
        for pass in effect.passes {
            switch pass.command {
            case .render:
                continue
            case .swap:
                return false
            case .copy(let source, _):
                if source == "previous" { return false }
                copies = true
            }
        }
        return copies
    }

    private static func eligible(_ effect: SceneEffectPlan) -> Bool {
        guard isBlurLike(effect), !effect.carriesFrames else { return false }
        return !effect.passes.contains { pass in
            if case .render = pass.command { return false }
            return true
        }
    }
}

extension EffectResolutionPolicy {
    /// The size `fbo` of `effect` is made at for a chain of `width`×`height`, and the size it
    /// stands for (reports to the built-ins) when that is smaller than the authored one.
    func fboSize(_ fbo: EffectFBO, in effect: SceneEffectPlan, width: Int, height: Int)
        -> (size: SIMD2<Int>, standsFor: SIMD2<Int>?) {
        let authored = EffectGraphRenderer.fboSize(fbo, width: width, height: height)
        let size = Self.reduced(authored, by: divisor(for: fbo, in: effect))
        return (size, size == authored ? nil : authored)
    }
}
