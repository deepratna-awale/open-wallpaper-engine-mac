import CoreGraphics
import ImageIO
import OWETheming
import XCTest
@testable import OpenWallpaperEngine

/// Settings › General › Theming is stored with the global settings, off by default, and its menu
/// bar strip reaches the desktop pictures only through `DesktopPictureTheming`.
final class ThemingSettingsTests: XCTestCase {
    func testThemingIsOffByDefaultAndRoundTrips() throws {
        XCTAssertFalse(GlobalSettings().theming.isEnabled)
        var settings = GlobalSettings()
        settings.theming.isEnabled = true
        settings.theming.accentColor = true
        settings.theming.restoresOnQuit = false
        let decoded = try JSONDecoder().decode(GlobalSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.theming, settings.theming)
    }

    func testSettingsSavedBeforeThemingKeepItsDefaults() throws {
        let stored = Data(#"{"autoStart": true}"#.utf8)
        let decoded = try JSONDecoder().decode(GlobalSettings.self, from: stored)
        XCTAssertTrue(decoded.autoStart)
        XCTAssertEqual(decoded.theming, ThemingSettings())
    }

    func testGeneralTabResetsTheming() {
        var settings = GlobalSettings()
        settings.theming.isEnabled = true
        XCTAssertTrue(SettingsTab.general.fields.contains { $0.isChanged(settings) })
        XCTAssertEqual(SettingsTab.general.resetting(settings).theming, ThemingSettings())
    }

    @MainActor
    func testNoProviderMeansNoStrips() {
        XCTAssertNil(DesktopPictureTheming.provider, "only the app's delegate registers one")
        XCTAssertNil(DesktopPictureTheming.strips())
    }

    func testDrawFillsTheStripOfTheWrittenPicture() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "owe-theming-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "desktop-1-a.jpg")
        let context = try XCTUnwrap(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let jpeg = try XCTUnwrap(DesktopSnapshotCache.jpegData(try XCTUnwrap(context.makeImage())))
        try jpeg.write(to: url)

        DesktopPictureTheming.draw(nil, into: url, display: 1)
        XCTAssertEqual(try Data(contentsOf: url), jpeg, "no strips leave the picture as written")

        let strips = DesktopPictureStrips(color: ThemeColor(red: 1, green: 1, blue: 1),
                                          displays: [1: MenuBarStripDisplay(size: CGSize(width: 32, height: 32), menuBarHeight: 8)])
        DesktopPictureTheming.draw(strips, into: url, display: 1)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, "public.jpeg")
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var pixels = [UInt8](repeating: 0, count: 64 * 64 * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let reader = CGContext(data: buffer.baseAddress, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 256,
                                   space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            reader?.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        XCTAssertGreaterThan(pixels[(4 * 64 + 10) * 4], 240, "the top quarter is the strip")
        XCTAssertLessThan(pixels[(40 * 64 + 10) * 4], 15, "the rest is untouched")
    }
}
