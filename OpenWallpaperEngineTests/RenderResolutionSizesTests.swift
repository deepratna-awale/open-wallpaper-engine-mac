import XCTest
@testable import OpenWallpaperEngine

/// The sizes the Render Resolution picker shows beside Display and Retina.
final class RenderResolutionSizesTests: XCTestCase {
    private func screen(_ w: CGFloat, _ h: CGFloat, scale: CGFloat) -> RenderResolutionSizes.Screen {
        .init(points: CGSize(width: w, height: h), pixels: CGSize(width: w * scale, height: h * scale))
    }

    func testOneDisplay() {
        let sizes = RenderResolutionSizes(screens: [screen(1920, 1080, scale: 2)])
        XCTAssertEqual(sizes.displayList, "1920×1080")
        XCTAssertEqual(sizes.retinaList, "3840×2160")
    }

    func testTwoDistinctDisplaysListLargestFirst() {
        let sizes = RenderResolutionSizes(screens: [screen(1920, 1080, scale: 1), screen(2560, 1440, scale: 2)])
        XCTAssertEqual(sizes.displayList, "2560×1440, 1920×1080")
        XCTAssertEqual(sizes.retinaList, "5120×2880, 1920×1080")
    }

    func testDuplicateSizesCollapse() {
        let sizes = RenderResolutionSizes(screens: [screen(1920, 1080, scale: 2), screen(1920, 1080, scale: 2)])
        XCTAssertEqual(sizes.displayList, "1920×1080")
        XCTAssertEqual(sizes.retinaList, "3840×2160")
    }

    func testRetinaEqualsDisplayOnANonRetinaDisplay() {
        let standard = RenderResolutionSizes(screens: [screen(1920, 1080, scale: 1)])
        XCTAssertEqual(standard.retinaList, standard.displayList)
        XCTAssertEqual(standard.retinaList, "1920×1080")
        let retina = RenderResolutionSizes(screens: [screen(1512, 982, scale: 2)])
        XCTAssertEqual(retina.displayList, "1512×982")
        XCTAssertEqual(retina.retinaList, "3024×1964")
    }

    func testDisplayReadsPointsNotPixels() {
        let sizes = RenderResolutionSizes(screens: [.init(points: CGSize(width: 1710, height: 1112),
                                                          pixels: CGSize(width: 3420, height: 2224))])
        XCTAssertEqual(sizes.displayList, "1710×1112")
        XCTAssertTrue(sizes.displayLabel.contains("1710×1112"))
        XCTAssertFalse(sizes.displayLabel.contains("3420"))
        XCTAssertTrue(sizes.retinaLabel.contains("3420×2224"))
    }

    func testCurrentScreensUseFramePoints() throws {
        let main = try XCTUnwrap(NSScreen.screens.first)
        let s = RenderResolutionSizes.screen(main)
        XCTAssertEqual(s.points, main.frame.size)
        XCTAssertGreaterThanOrEqual(s.pixels.width, s.points.width)
    }
}
