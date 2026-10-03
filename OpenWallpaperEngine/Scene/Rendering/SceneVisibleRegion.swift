import Foundation
import simd

/// Switches for the fullscreen-layer optimisations, one per change so each can be measured alone
/// (`FullscreenEffectMeasureTests`). Read from the environment for comparisons:
/// `OWE_FX_CLAMP`, `OWE_FX_COPY_ALIAS` and `OWE_FX_HALF_ACCUM` (`0` off, `1` on).
struct SceneFullscreenEffectOptions: Equatable {
    /// Fullscreen layers' effects shade only the part of the scene a display shows
    /// (`SceneVisibleRegion`), plus a margin.
    var clampToVisible = true
    /// A `copy` between two of an effect's buffers hands the texture over instead of copying it
    /// (`EffectGraphRenderer.copyCanAlias`).
    var aliasCopies = true
    /// Temporal accumulations (motion blur's history) at half size; nil follows the
    /// Quality↔Efficiency slider (`QualityEfficiency.temporalAccumulationDivisor`).
    var halfResolutionAccumulation: Bool? = nil

    init(clampToVisible: Bool = true, aliasCopies: Bool = true, halfResolutionAccumulation: Bool? = nil) {
        self.clampToVisible = clampToVisible
        self.aliasCopies = aliasCopies
        self.halfResolutionAccumulation = halfResolutionAccumulation
    }

    /// Every change off: the render as it was before them (the measurement's reference).
    static let none = SceneFullscreenEffectOptions(clampToVisible: false, aliasCopies: false,
                                                   halfResolutionAccumulation: false)

    /// The defaults, overridden by `OWE_FX_*`.
    static func environment(_ values: [String: String] = ProcessInfo.processInfo.environment) -> Self {
        func flag(_ name: String) -> Bool? {
            switch values[name] {
            case "1": return true
            case "0": return false
            default: return nil
            }
        }
        var options = Self()
        if let clamp = flag("OWE_FX_CLAMP") { options.clampToVisible = clamp }
        if let alias = flag("OWE_FX_COPY_ALIAS") { options.aliasCopies = alias }
        options.halfResolutionAccumulation = flag("OWE_FX_HALF_ACCUM")
        return options
    }
}

/// What part of the scene target a display can show, and the part of a fullscreen layer's effect
/// buffers that can reach it.
///
/// A scene placed to fill a display of another shape is drawn larger than the display and cropped
/// (a 2560×1600 scene on a 3840×2160 display is drawn 3840×2400 and its top and bottom 120 rows
/// never show). A fullscreen layer's effects still shade every pixel of the target. Here they
/// shade only the rows and columns that can show (`chainRect`, a scissor in every pass), and the
/// layer draws its result only there (`targetRect`); everything else keeps the scene beneath it.
///
/// The margin: a pass may sample around the pixel it shades (a blur, bilinear filtering), so the
/// shaded part reaches `samplingMargin` target pixels beyond what shows, and the layer may move
/// (camera parallax and shake move every layer, `motionBound`), so it also reaches as far as the
/// layer can move, and stays put while it moves (a buffer carried into the next frame keeps its
/// pixels where they were).
enum SceneVisibleRegion {
    /// Target pixels shaded beyond what shows: the reach of passes that sample around a pixel.
    static let samplingMargin: Float = 64
    /// Buffer rects are snapped outward to this many pixels, so they stay put while the visible
    /// part moves a little (a live resize) and downsampled buffers keep whole texels.
    static let grid = 8
    /// A rect keeping more than this share of a buffer's pixels isn't worth a scissor.
    static let maximumKeptShare: Float = 0.98

    /// A rectangle in scene units, y up.
    struct Rect: Equatable {
        var min: SIMD2<Float>
        var max: SIMD2<Float>

        var size: SIMD2<Float> { max - min }

        func union(_ other: Rect) -> Rect { Rect(min: simd_min(min, other.min), max: simd_max(max, other.max)) }

        func expanded(by margin: SIMD2<Float>) -> Rect { Rect(min: min - margin, max: max + margin) }

        func contains(_ other: Rect) -> Bool {
            other.min.x >= min.x && other.min.y >= min.y && other.max.x <= max.x && other.max.y <= max.y
        }
    }

    /// One display showing the scene: its drawable in pixels and its backing scale.
    struct Display: Equatable {
        var drawableSize: SIMD2<Float>
        var pixelsPerPoint: Float
    }

    /// The part of a scene of `sceneSize` the displays show at `placement` (scene units, the union
    /// over displays); nil when every display shows all of it, or there is no display to go by.
    static func window(sceneSize: SIMD2<Float>, displays: [Display], placement: WallpaperPlacement) -> Rect? {
        guard sceneSize.x > 0, sceneSize.y > 0, !displays.isEmpty, placement != .stretch else { return nil }
        let scene = Rect(min: .zero, max: sceneSize)
        var shown: Rect?
        for display in displays {
            let drawable = display.drawableSize
            guard drawable.x > 0, drawable.y > 0 else { return nil }
            let low = ScenePlacementScale.scenePoint(drawablePoint: .zero, placement: placement, sceneSize: sceneSize,
                                                     drawableSize: drawable, pixelsPerPoint: display.pixelsPerPoint)
            let high = ScenePlacementScale.scenePoint(drawablePoint: drawable, placement: placement, sceneSize: sceneSize,
                                                      drawableSize: drawable, pixelsPerPoint: display.pixelsPerPoint)
            guard low.x.isFinite, low.y.isFinite, high.x.isFinite, high.y.isFinite else { return nil }
            let rect = Rect(min: simd_max(simd_min(low, high), scene.min), max: simd_min(simd_max(low, high), scene.max))
            guard rect.max.x > rect.min.x, rect.max.y > rect.min.y else { continue }
            shown = shown.map { $0.union(rect) } ?? rect
        }
        guard let shown, !shown.contains(scene) else { return nil }
        return shown
    }

    /// The farthest camera shake moves the scene (scene units, each axis): `SceneCameraShake`'s
    /// vector `(cos t, sin 1.333t, sin t)` is at most √2 long (cos² t + sin² t is 1), and its
    /// roughness exponent keeps a length under 1 under 1 and raises √2 to at most √2^exponent;
    /// scaled as there.
    static func shakeBound(amplitude: Float, roughness: Float, orthographicHeight: Float?) -> Float {
        var scale = abs(amplitude) * 0.1
        if let orthographicHeight { scale *= abs(orthographicHeight) * 0.1 }
        let exponent = pow(roughness, 3)
        let length = Float(2).squareRoot()
        let shaped = exponent > 0.001 && exponent != 1 ? pow(length, exponent) : length
        let bound = max(shaped, length) * scale
        return bound.isFinite ? bound : .infinity
    }

    /// The farthest camera parallax moves a layer whose root object sits at `rootOrigin` with
    /// `rootDepth` (scene units, each axis): `SceneCameraParallax.offset` with the camera's
    /// position anywhere it can go, the scene centre ± half the scene times the mouse influence,
    /// moved by the shake (`shake`, its bound).
    static func parallaxBound(amount: Float, rootOrigin: SIMD2<Float>, rootDepth: SIMD2<Float>, sceneSize: SIMD2<Float>,
                              influence: Float, shake: Float) -> SIMD2<Float> {
        let reach = abs(rootOrigin - sceneSize / 2) + sceneSize * abs(influence) / 2 + SIMD2(repeating: abs(shake))
        let bound = abs(amount) * abs(rootDepth) * reach
        return SIMD2(bound.x.isFinite ? bound.x : .infinity, bound.y.isFinite ? bound.y : .infinity)
    }

    /// The rows and columns of a layer's effect buffers (`chainSize` pixels covering its `quad`,
    /// y down from the quad's top edge) that can show: `window` widened by `margin` (scene units),
    /// with the quad as it is when not moved by `offset` (parallax and shake this frame), so the
    /// rect stays put while the layer moves. Snapped outward to `grid`; nil when it would keep
    /// nearly all of them (`maximumKeptShare`) or the quad isn't axis-aligned and upright.
    static func chainRect(quad: SceneQuadGeometry, offset: SIMD2<Float>, window: Rect, margin: SIMD2<Float>,
                          chainSize: SIMD2<Int>) -> SceneSnapshotTracker.Rect? {
        guard chainSize.x > 0, chainSize.y > 0, quad.axisX.y == 0, quad.axisY.x == 0,
              quad.axisX.x > 0, quad.axisY.y > 0 else { return nil }
        let center = quad.center - offset
        let size = SIMD2(quad.axisX.x, quad.axisY.y)
        let low = center - size / 2
        let reach = window.expanded(by: margin)
        let chain = SIMD2<Float>(Float(chainSize.x), Float(chainSize.y))
        // Fractions of the quad, y down from its top.
        let left = (reach.min.x - low.x) / size.x, right = (reach.max.x - low.x) / size.x
        let top = (low.y + size.y - reach.max.y) / size.y, bottom = (low.y + size.y - reach.min.y) / size.y
        guard left.isFinite, right.isFinite, top.isFinite, bottom.isFinite else { return nil }
        return snapped(x0: left * chain.x, y0: top * chain.y, x1: right * chain.x, y1: bottom * chain.y, in: chainSize)
    }

    /// Target pixels the draw stays inside the shaded part by where that part ends inside the
    /// buffers: filtering at its edge would read the unshaded texels beyond it.
    static let drawInset: Float = 2

    /// Where the buffers' `rect` lands in the scene target (`targetSize` pixels over `sceneSize`
    /// units, y down) through the layer's `quad` as drawn this frame: the scissor of its draw,
    /// `drawInset` inside the rect's edges that lie within the buffers (rounded inward there).
    static func targetRect(_ rect: SceneSnapshotTracker.Rect, chainSize: SIMD2<Int>, quad: SceneQuadGeometry,
                           sceneSize: SIMD2<Float>, targetSize: SIMD2<Int>) -> SceneSnapshotTracker.Rect? {
        guard chainSize.x > 0, chainSize.y > 0, sceneSize.x > 0, sceneSize.y > 0 else { return nil }
        let size = SIMD2(quad.axisX.x, quad.axisY.y)
        let top = quad.center.y + size.y / 2
        let left = quad.center.x - size.x / 2
        let perUnit = SIMD2<Float>(Float(targetSize.x), Float(targetSize.y)) / sceneSize
        let chain = SIMD2<Float>(Float(chainSize.x), Float(chainSize.y))
        let x0 = (left + Float(rect.x) / chain.x * size.x) * perUnit.x
        let x1 = (left + Float(rect.maxX) / chain.x * size.x) * perUnit.x
        let y0 = (sceneSize.y - (top - Float(rect.y) / chain.y * size.y)) * perUnit.y
        let y1 = (sceneSize.y - (top - Float(rect.maxY) / chain.y * size.y)) * perUnit.y
        // An edge at the buffers' own edge is the quad's: drawn whole, as without a rect.
        func low(_ value: Float, interior: Bool) -> Float { interior ? (value + drawInset).rounded(.up) : value.rounded(.down) }
        func high(_ value: Float, interior: Bool) -> Float { interior ? (value - drawInset).rounded(.down) : value.rounded(.up) }
        let pixels = SIMD4(low(x0, interior: rect.x > 0), low(y0, interior: rect.y > 0),
                           high(x1, interior: rect.maxX < chainSize.x), high(y1, interior: rect.maxY < chainSize.y))
        guard pixels.x.isFinite, pixels.y.isFinite, pixels.z.isFinite, pixels.w.isFinite else { return nil }
        let clampedLow = simd_clamp(SIMD2(pixels.x, pixels.y), .zero, SIMD2(Float(targetSize.x), Float(targetSize.y)))
        let clampedHigh = simd_clamp(SIMD2(pixels.z, pixels.w), .zero, SIMD2(Float(targetSize.x), Float(targetSize.y)))
        let width = Int(clampedHigh.x) - Int(clampedLow.x), height = Int(clampedHigh.y) - Int(clampedLow.y)
        guard width > 0, height > 0 else { return nil }
        return SceneSnapshotTracker.Rect(x: Int(clampedLow.x), y: Int(clampedLow.y), width: width, height: height)
    }

    /// `rect` of a `base`-sized buffer on another buffer of `size` (a downsampled FBO), rounded
    /// outward and clamped to it.
    static func scaled(_ rect: SceneSnapshotTracker.Rect, from base: SIMD2<Int>, to size: SIMD2<Int>) -> SceneSnapshotTracker.Rect {
        guard base != size, base.x > 0, base.y > 0 else { return rect }
        let ratio = SIMD2<Float>(Float(size.x) / Float(base.x), Float(size.y) / Float(base.y))
        let x0 = Int((Float(rect.x) * ratio.x).rounded(.down)), y0 = Int((Float(rect.y) * ratio.y).rounded(.down))
        let x1 = Int((Float(rect.maxX) * ratio.x).rounded(.up)), y1 = Int((Float(rect.maxY) * ratio.y).rounded(.up))
        let left = min(max(x0, 0), size.x), top = min(max(y0, 0), size.y)
        let right = min(max(x1, left), size.x), bottom = min(max(y1, top), size.y)
        return SceneSnapshotTracker.Rect(x: left, y: top, width: right - left, height: bottom - top)
    }

    /// Pixel bounds snapped outward to `grid` and clamped to `size`; nil when empty or keeping
    /// nearly all of it.
    private static func snapped(x0: Float, y0: Float, x1: Float, y1: Float, in size: SIMD2<Int>) -> SceneSnapshotTracker.Rect? {
        let grid = Float(Self.grid)
        let bounds = SIMD2<Float>(Float(size.x), Float(size.y))
        let low = simd_clamp(SIMD2((x0 / grid).rounded(.down), (y0 / grid).rounded(.down)) * grid, .zero, bounds)
        let high = simd_clamp(SIMD2((x1 / grid).rounded(.up), (y1 / grid).rounded(.up)) * grid, .zero, bounds)
        let width = Int(high.x) - Int(low.x), height = Int(high.y) - Int(low.y)
        guard width > 0, height > 0 else { return nil }
        guard Float(width * height) <= maximumKeptShare * bounds.x * bounds.y else { return nil }
        return SceneSnapshotTracker.Rect(x: Int(low.x), y: Int(low.y), width: width, height: height)
    }
}
