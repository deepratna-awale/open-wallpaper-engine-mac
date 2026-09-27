import XCTest
@testable import OpenWallpaperEngine

/// D1, D2, D4, D6: WE text layout — 300/72 sizing, lines placed around the origin by
/// `horizontalalign`/`verticalalign` as `wallpaper64.exe` places them, wrapping only under
/// `limitwidth`, row limits with ellipsis, and no shrink-to-fit or clipping.
final class SceneTextLayoutTests: XCTestCase {
    private func font(pointSize: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: SceneTextLayout.pixelSize(pointSize: pointSize))
    }

    private func fixtureObject(_ id: Int) throws -> WESceneObject {
        let objects = try JSONDecoder().decode([WESceneObject].self,
                                               from: Fixtures.data("Scenes/text-transforms/objects.json"))
        return try XCTUnwrap(objects.first { $0.id == id })
    }

    private func layout(_ text: String, pointSize: CGFloat = 32, font: NSFont? = nil,
                        padding: SIMD2<Float> = SIMD2(32, 32), horizontal: String? = "center",
                        vertical: String? = "center", maxWidth: Float? = nil, maxRows: Int? = nil,
                        ellipsis: Bool = false) -> SceneTextLayout {
        SceneTextLayout(text: text, font: font ?? self.font(pointSize: pointSize), padding: padding,
                        horizontalAlignment: horizontal, verticalAlignment: vertical,
                        maxWidth: maxWidth, maxRows: maxRows, useEllipsis: ellipsis)
    }

    /// WE sets its FreeType face at 300 dpi (`FT_Set_Char_Size(…, pointsize × 64, 300, 300)`) and
    /// lays glyphs out one atlas pixel per scene unit. R1: 3270035750's "Nami" and "Robin"
    /// (Deutschlands, `pointsize` 25, scale 1) best match WE's capture at an em of 104 units.
    func testPixelSizeIsPointSizeAt300DPI() {
        XCTAssertEqual(SceneTextLayout.pixelSize(pointSize: 32), 133.3333, accuracy: 0.001)
        XCTAssertEqual(SceneTextLayout.pixelSize(pointSize: 25), 104.1667, accuracy: 0.001)
        XCTAssertEqual(SceneTextLayout.pixelSize(pointSize: 72), 300)
    }

    /// WE 2.8's capture of "WE Text 123" (NotoSans-Regular, `pointsize` 64, centred, origin y 540,
    /// effect gallery EXTRAS.md item 8) has its baseline at y 681…683, 143 below the origin: the
    /// block from the ascender (286, rounded up) to the baseline is centred, not the whole line
    /// (363); its ink is centred on the origin.
    func testCentredLineSitsAsInWEsCapture() throws {
        let url = ShaderVariantTests.weAssets.appending(path: "fonts/NotoSans-Regular.ttf")
        let descriptors = try XCTUnwrap(CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])
        let noto = CTFontCreateWithFontDescriptor(try XCTUnwrap(descriptors.first),
                                                  SceneTextLayout.pixelSize(pointSize: 64), nil) as NSFont
        let text = layout("WE Text 123", font: noto)
        XCTAssertEqual(text.ascent, 286)
        XCTAssertEqual(text.lineHeight, 363)
        let origin = try XCTUnwrap(text.baselineOrigins().first)
        XCTAssertEqual(origin.y, -143)
        XCTAssertEqual(origin.x + text.lines[0].minX, -text.lines[0].width / 2, accuracy: 0.001, "ink centred")
    }

    /// `verticalalign`: `top` hangs the first line's ascender on the origin, `bottom` stands the
    /// last line's descender on it, `center` centres the first ascender to the last baseline.
    func testVerticalAlignmentsPlaceTheLinesAsWEDoes() {
        func baselines(_ vertical: String) -> (SceneTextLayout, [CGFloat]) {
            let text = layout("One\nTwo\nThree", vertical: vertical)
            return (text, text.baselineOrigins().map(\.y))
        }
        let (top, topLines) = baselines("top")
        XCTAssertEqual(topLines[0], -top.ascent)
        XCTAssertEqual(topLines[1], topLines[0] - top.lineHeight)
        let (bottom, bottomLines) = baselines("bottom")
        XCTAssertEqual(bottomLines[2] + bottom.descent, 0, accuracy: 0.001)
        let (centre, centreLines) = baselines("center")
        XCTAssertEqual(centreLines[0] + centre.ascent, -centreLines[2], accuracy: 0.001)
    }

    /// `horizontalalign`: lines align within the widest, whose ink starts (`left`), ends (`right`)
    /// or is centred on the origin.
    func testHorizontalAlignmentsPlaceTheInkAsWEDoes() {
        let left = layout("Hi\nthere", horizontal: "left")
        for (line, origin) in zip(left.lines, left.baselineOrigins()) {
            XCTAssertEqual(origin.x + line.minX, 0, accuracy: 0.001, line.text)
        }
        let right = layout("there", horizontal: "right")
        let end = try! XCTUnwrap(right.baselineOrigins().first).x + right.lines[0].minX + right.lines[0].width
        XCTAssertEqual(end, 0, accuracy: 0.001)
        let centre = layout("Hi\nthere")
        let spans = zip(centre.lines, centre.baselineOrigins()).map { ($1.x + $0.minX, $1.x + $0.minX + $0.width) }
        XCTAssertEqual(spans[1].0, -spans[1].1, accuracy: 0.001, "the widest line is centred")
        XCTAssertEqual(spans[0].0 + spans[0].1, 0, accuracy: 0.001, "a shorter line is centred within it")
    }

    /// The block is centred on the origin and holds every line with `padding` around it.
    func testBoxHoldsTheLinesWithPadding() {
        for (h, v) in [("left", "top"), ("right", "bottom"), ("center", "center")] {
            let text = layout("Hello\nworld", padding: SIMD2(10, 20), horizontal: h, vertical: v)
            let half = CGSize(width: CGFloat(text.boxSize.x) / 2, height: CGFloat(text.boxSize.y) / 2)
            for (line, origin) in zip(text.lines, text.baselineOrigins()) {
                XCTAssertGreaterThanOrEqual(origin.x + line.minX, -half.width + 10, "\(h) \(v)")
                XCTAssertLessThanOrEqual(origin.x + line.minX + line.width, half.width - 10, "\(h) \(v)")
                XCTAssertLessThanOrEqual(origin.y + text.ascent, half.height - 20, "\(h) \(v)")
                XCTAssertGreaterThanOrEqual(origin.y + text.descent, -half.height + 20, "\(h) \(v)")
            }
        }
    }

    func testNoWrapWithoutLimitWidth() {
        let text = "a fairly long line of text that would wrap if allowed"
        let result = layout(text, padding: SIMD2(4, 4))
        XCTAssertEqual(result.lines.map(\.text), [text])
        XCTAssertGreaterThan(result.lines[0].width, 100, "no shrink-to-fit: the line keeps its natural width")
        XCTAssertGreaterThanOrEqual(result.boxSize.x, Float(result.lines[0].width) + 8)
    }

    /// 3546971487 'Song Title': limitwidth 471, limitrows 2.
    func testWrapsAtMaxWidthAndLimitsRows() throws {
        let object = try fixtureObject(50)
        let maxWidth = Float(try XCTUnwrap(object.maxwidth))
        let text = String(repeating: "Song title words ", count: 12)
        let wrapped = layout(text, pointSize: 20, maxWidth: maxWidth)
        XCTAssertGreaterThan(wrapped.lines.count, 2)
        XCTAssertTrue(wrapped.lines.allSatisfy { $0.width <= CGFloat(maxWidth) + 0.5 })

        let limited = layout(text, pointSize: 20, maxWidth: maxWidth, maxRows: object.maxrows)
        XCTAssertEqual(limited.lines.count, 2)
        XCTAssertFalse(limited.lines.last!.text.hasSuffix("\u{2026}"))

        let ellipsis = layout(text, pointSize: 20, maxWidth: maxWidth, maxRows: 1, ellipsis: true)
        XCTAssertEqual(ellipsis.lines.count, 1)
        XCTAssertTrue(ellipsis.lines[0].text.hasSuffix("\u{2026}"))
        XCTAssertLessThanOrEqual(ellipsis.lines[0].width, CGFloat(maxWidth) + 0.5)
    }

    func testExplicitNewlinesMakeRows() {
        XCTAssertEqual(layout("OUR JOURNEY IS\nTO THE STARS").lines.map(\.text), ["OUR JOURNEY IS", "TO THE STARS"])
    }

    /// 3245833232's clock (scale 0.28 in a 4K scene on a 1080p display) blurs in WE's buffer of
    /// its size; blurred at its on-screen 0.14 px a unit, the blur spread over the whole date.
    func testTextWithEffectsRasterisesAtItsOwnSize() {
        XCTAssertEqual(SceneTextRasterScale.layer(onScreen: 0.14, hasEffects: true), 1)
        XCTAssertEqual(SceneTextRasterScale.layer(onScreen: 0.14, hasEffects: false), 0.14)
        XCTAssertEqual(SceneTextRasterScale.layer(onScreen: 2, hasEffects: true), 1)
    }

    func testRasterisesAtRequestedPixelScale() throws {
        let result = layout("12:34")
        let image = try XCTUnwrap(result.rasterize(font: font(pointSize: 32), color: .white, pixelsPerUnit: 2))
        XCTAssertEqual(image.width, Int(ceil(result.boxSize.x * 2)))
        XCTAssertEqual(image.height, Int(ceil(result.boxSize.y * 2)))
        XCTAssertEqual(SceneTextRasterScale.quantized(1.3), exp2(Float(0.5)), accuracy: 0.0001)
        XCTAssertEqual(SceneTextRasterScale.clamped(100, boxSize: SIMD2(1000, 10)), 4.096, accuracy: 0.0001)
    }
}
