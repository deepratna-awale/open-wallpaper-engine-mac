import CoreGraphics
import simd

/// Where a text raster's glyphs are (docs/models-plan.md §4.3 M5, the day text of 3455121165).
///
/// WE draws a text object as one quad per glyph, sampling its font's glyph atlas (`font.frag`'s
/// MSDF), so in a pass with depth (`basefont_depth.json`: test and write) only the glyphs' boxes
/// write depth. The app rasterises the whole text box into one texture and draws one quad, whose
/// empty rows would write depth over whatever lies behind them and is drawn later (the clock's box
/// hid the day text below it). Drawn through a camera, the quad is cut to the box of the texels
/// the glyphs cover: the colour is unchanged (the rest is transparent) and the depth footprint is
/// the glyphs' [I: the union of a line's glyph boxes, not each box].
enum SceneTextInk {
    /// The texture-space box (u right, v down, 0…1) of `image`'s texels with any alpha, grown by a
    /// texel so filtering keeps its edges; nil for an empty raster.
    static func bounds(of image: CGImage) -> SIMD4<Float>? {
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue),
              let data = context.data else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let alpha = data.bindMemory(to: UInt8.self, capacity: width * height)
        var low = SIMD2(width, height), high = SIMD2(-1, -1)
        for row in 0..<height {
            let line = alpha + row * width
            guard let first = (0..<width).first(where: { line[$0] != 0 }) else { continue }
            let last = (0..<width).last(where: { line[$0] != 0 }) ?? first
            // The context's first row is the image's top.
            low = simd_min(low, SIMD2(first, row))
            high = simd_max(high, SIMD2(last, row))
        }
        guard high.x >= 0 else { return nil }
        let size = SIMD2(Float(width), Float(height))
        let minimum = simd_max(SIMD2<Float>(Float(low.x - 1), Float(low.y - 1)) / size, .zero)
        let maximum = simd_min(SIMD2<Float>(Float(high.x + 2), Float(high.y + 2)) / size, SIMD2(repeating: 1))
        return SIMD4(minimum.x, minimum.y, maximum.x, maximum.y)
    }

    /// `placement`'s quad cut to `ink` (u0, v0, u1, v1 of the whole quad).
    static func crop(_ placement: SceneLayerPlacement, to ink: SIMD4<Float>) -> SceneLayerPlacement {
        var cropped = placement
        let size = placement.size
        cropped.size = SIMD2(size.x * (ink.z - ink.x), size.y * (ink.w - ink.y))
        cropped.offset += SIMD2(((ink.x + ink.z) / 2 - 0.5) * size.x, (0.5 - (ink.y + ink.w) / 2) * size.y)
        return cropped
    }
}
