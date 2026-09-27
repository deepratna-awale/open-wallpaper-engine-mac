import AppKit
import CoreText
import simd

/// Lays out a WE text object the way Wallpaper Engine does, in scene units:
/// - the glyph size (em) is `pointsize × 300/72` scene units: WE sets its FreeType face to
///   `pointsize` points at 300 dpi and lays the glyphs out one atlas pixel per scene unit;
/// - text wraps only when `limitwidth` is set (at `maxwidth`), and `limitrows` keeps the first
///   `maxrows` lines, ending in an ellipsis when `limituseellipsis` is set;
/// - nothing is ever shrunk to fit, and nothing is clipped;
/// - the lines sit around the object's origin by `horizontalalign` and `verticalalign` alone
///   (`baselineOrigins`); scene.json's `size` plays no part, and `padding` is room around the
///   glyphs (`wallpaper64.exe`'s layout 0x1401b0410 and its placement 0x140257690…0x1402577c4).
struct SceneTextLayout {
    struct Line: Equatable {
        let text: String
        /// WE's line width: the glyphs' ink joined with the pen's start, `min(0, xMin)` to
        /// `max(0, xMax)` (0x1401b215d).
        let width: CGFloat
        /// That span's left end from the pen's start (≤ 0).
        let minX: CGFloat
    }

    /// The text block (the quad), in unscaled scene units, centred on the object's origin: room
    /// for every line on both sides of the origin plus `padding`.
    let boxSize: SIMD2<Float>
    let lines: [Line]
    /// `size->metrics.height`, `ascender` and `descender` (0x1401b0bf0, 0x14025769a), whole pixels
    /// as FreeType rounds them: the height to nearest, the ascender up, the descender down.
    let lineHeight: CGFloat
    let ascent: CGFloat
    let descent: CGFloat
    let padding: SIMD2<Float>
    let horizontalAlignment: String?
    let verticalAlignment: String?

    /// WE's `FT_Set_Char_Size(face, 0, pointsize × 64, 300, 300)`: the em in scene units.
    static func pixelSize(pointSize: CGFloat) -> CGFloat { pointSize * 300 / 72 }

    init(text: String, font: NSFont, padding: SIMD2<Float>, horizontalAlignment: String?, verticalAlignment: String?,
         maxWidth: Float?, maxRows: Int?, useEllipsis: Bool) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        ascent = ceil(font.ascender)
        descent = floor(font.descender)
        lineHeight = (font.ascender - font.descender + font.leading).rounded()
        self.padding = padding
        self.horizontalAlignment = horizontalAlignment
        self.verticalAlignment = verticalAlignment

        var lines: [String] = []
        for paragraph in text.components(separatedBy: .newlines) {
            if let maxWidth, maxWidth > 0 {
                lines += Self.wrap(paragraph, attributes: attributes, width: CGFloat(maxWidth))
            } else {
                lines.append(paragraph)
            }
        }
        if let maxRows, maxRows > 0, lines.count > maxRows {
            lines = Array(lines.prefix(maxRows))
            if useEllipsis, let last = lines.popLast() {
                lines.append(Self.withEllipsis(last, attributes: attributes, width: maxWidth.map { CGFloat($0) }))
            }
        }
        let laidOut = lines.map { Self.line($0, attributes: attributes) }
        self.lines = laidOut
        let origins = Self.origins(laidOut, ascent: ascent, descent: descent, lineHeight: lineHeight,
                                   horizontal: horizontalAlignment, vertical: verticalAlignment)
        boxSize = Self.box(around: origins, lines: laidOut, ascent: ascent, descent: descent, lineHeight: lineHeight,
                           padding: padding)
    }

    /// Where each line's baseline starts, from the object's origin (y-up), as WE places them:
    /// - vertically (0x140257690…0x1402577c4): `center` puts the block from the first line's ascender to the
    ///   last line's baseline around the origin, `top` the first line's ascender on it, `bottom` the
    ///   last line's descender; lines follow each other by the line height;
    /// - horizontally (0x1401b2990, 0x140257690): lines are aligned within the widest, and the
    ///   block's span is centred on the origin, or starts (`left`) or ends (`right`) on it.
    func baselineOrigins() -> [CGPoint] {
        Self.origins(lines, ascent: ascent, descent: descent, lineHeight: lineHeight,
                     horizontal: horizontalAlignment, vertical: verticalAlignment)
    }

    private static func origins(_ lines: [Line], ascent: CGFloat, descent: CGFloat, lineHeight: CGFloat,
                                horizontal horizontalAlignment: String?, vertical verticalAlignment: String?) -> [CGPoint] {
        let count = CGFloat(lines.count)
        let first: CGFloat
        switch verticalAlignment?.lowercased() {
        case "top": first = -ascent
        case "bottom": first = -descent + (count - 1) * lineHeight
        default: first = -(ascent - (count - 1) * lineHeight) / 2
        }
        let blockMin = lines.map(\.minX).min() ?? 0
        let blockMax = lines.map { $0.minX + $0.width }.max() ?? 0
        let blockWidth = blockMax - blockMin
        let widest = lines.map(\.width).max() ?? 0
        let horizontal = horizontalAlignment?.lowercased()
        let shift: CGFloat = horizontal == "left" ? blockWidth / 2 : horizontal == "right" ? -blockWidth / 2 : 0
        return lines.enumerated().map { index, line in
            let offset: CGFloat
            switch horizontal {
            case "left": offset = 0
            case "right": offset = widest - line.width
            default: offset = (widest - line.width) / 2
            }
            return CGPoint(x: shift - blockWidth / 2 - line.minX + offset, y: first - CGFloat(index) * lineHeight)
        }
    }

    /// Draws the block into a new bitmap at `pixelsPerUnit` device pixels per scene unit, so
    /// the glyphs are rasterised at the size they are shown at instead of being upscaled.
    func rasterize(font: NSFont, color: NSColor, pixelsPerUnit: CGFloat) -> CGImage? {
        let width = max(1, Int(ceil(CGFloat(boxSize.x) * pixelsPerUnit)))
        let height = max(1, Int(ceil(CGFloat(boxSize.y) * pixelsPerUnit)))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setShouldAntialias(true)
        context.setShouldSmoothFonts(false)
        context.scaleBy(x: CGFloat(width) / CGFloat(max(boxSize.x, 0.0001)),
                        y: CGFloat(height) / CGFloat(max(boxSize.y, 0.0001)))
        // The box is centred on the origin.
        context.translateBy(x: CGFloat(boxSize.x) / 2, y: CGFloat(boxSize.y) / 2)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        for (line, origin) in zip(lines, baselineOrigins()) {
            let ctLine = CTLineCreateWithAttributedString(NSAttributedString(string: line.text, attributes: attributes))
            context.textPosition = origin
            CTLineDraw(ctLine, context)
        }
        return context.makeImage()
    }

    /// A line's text with WE's width: its glyphs' ink bounds joined with the pen's start.
    private static func line(_ text: String, attributes: [NSAttributedString.Key: Any]) -> Line {
        let ctLine = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let ink = CTLineGetBoundsWithOptions(ctLine, .useGlyphPathBounds)
        let minX = ink.isNull || ink.isEmpty ? 0 : min(0, ink.minX)
        let maxX = ink.isNull || ink.isEmpty ? 0 : max(0, ink.maxX)
        return Line(text: text, width: maxX - minX, minX: minX)
    }

    /// The box centred on the origin that holds every line (ascender to descender) with `padding`
    /// around it.
    private static func box(around origins: [CGPoint], lines: [Line], ascent: CGFloat, descent: CGFloat,
                            lineHeight: CGFloat, padding: SIMD2<Float>) -> SIMD2<Float> {
        var half = CGSize.zero
        for (origin, line) in zip(origins, lines) {
            half.width = max(half.width, abs(origin.x + line.minX), abs(origin.x + line.minX + line.width))
            // WE's line spans the ascender to the next line's ascender (0x9c/0x94); the descender
            // can reach below that.
            let bottom = min(origin.y + descent, origin.y + ascent - lineHeight)
            half.height = max(half.height, abs(origin.y + ascent), abs(bottom))
        }
        return SIMD2(Float(ceil(half.width)) * 2 + padding.x * 2, Float(ceil(half.height)) * 2 + padding.y * 2)
    }

    // MARK: - Line breaking

    private static func width(of text: String, attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    private static func wrap(_ paragraph: String, attributes: [NSAttributedString.Key: Any], width: CGFloat) -> [String] {
        guard !paragraph.isEmpty else { return [""] }
        let attributed = NSAttributedString(string: paragraph, attributes: attributes)
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        let utf16 = paragraph.utf16
        var lines: [String] = []
        var start = 0
        while start < utf16.count {
            let count = max(1, CTTypesetterSuggestLineBreak(typesetter, start, Double(width)))
            let from = utf16.index(utf16.startIndex, offsetBy: start)
            let to = utf16.index(from, offsetBy: count)
            let line = String(paragraph[from..<to])
            lines.append(line.trimmingCharacters(in: .whitespaces))
            start += count
        }
        return lines
    }

    private static func withEllipsis(_ line: String, attributes: [NSAttributedString.Key: Any], width: CGFloat?) -> String {
        let ellipsis = "\u{2026}"
        var trimmed = line
        while !trimmed.isEmpty,
              let width, Self.width(of: trimmed + ellipsis, attributes: attributes) > width {
            trimmed.removeLast()
        }
        return trimmed.trimmingCharacters(in: .whitespaces) + ellipsis
    }
}

/// How finely text is rasterised: device pixels per scene unit, in quarter-octave steps so an
/// animated scale doesn't re-rasterise every frame, and capped so a block stays a sane texture.
enum SceneTextRasterScale {
    static let maxTextureDimension: Float = 4096

    /// Where a text layer is rasterised: WE draws plain text's glyphs at the display's density
    /// (`onScreen`), but runs a text object's effects in buffers of its size, one pixel a scene
    /// unit (its `font` material has no texture: `wallpaper64.exe` 0x140209206…0x14020923c).
    static func layer(onScreen: Float, hasEffects: Bool) -> Float {
        hasEffects ? 1 : onScreen
    }

    static func quantized(_ pixelsPerUnit: Float) -> Float {
        guard pixelsPerUnit.isFinite, pixelsPerUnit > 0 else { return 1 }
        return exp2((log2(pixelsPerUnit) * 4).rounded(.up) / 4)
    }

    /// Text keeps the finest scale it has been rasterised at, so an animated scale re-rasterises
    /// only while it grows past what it has already reached, not at every step up and down.
    static func retained(_ pixelsPerUnit: Float, previous: Float?) -> Float {
        max(pixelsPerUnit, previous ?? 0)
    }

    static func clamped(_ pixelsPerUnit: Float, boxSize: SIMD2<Float>) -> Float {
        let largest = max(boxSize.x, boxSize.y, 1)
        return max(min(pixelsPerUnit, maxTextureDimension / largest), 1 / largest)
    }
}
