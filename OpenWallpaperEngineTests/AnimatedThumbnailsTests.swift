import AppKit
import XCTest
@testable import OpenWallpaperEngine

/// Animated library previews are built in and always on: no Plugins entry or preference, the
/// retired key is dropped, tiles play by default, and Low Power Mode plays only on hover.
@MainActor
final class AnimatedThumbnailsTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suite = "owe-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    private static let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "OpenWallpaperEngine")

    /// The Plugins page, its search entries and Restore Defaults no longer know the plugin.
    func testPluginsPageNoLongerListsIt() throws {
        let page = try String(contentsOf: Self.sources.appending(path: "Settings/PluginsPage.swift"), encoding: .utf8)
        XCTAssertFalse(page.contains("Animated Thumbnails"))
        XCTAssertFalse(page.contains(ThumbnailAnimation.retiredPreferenceKey))
        XCTAssertTrue(SettingsSearch.results(for: "Animated Thumbnails", locale: Locale(identifier: "en")).isEmpty)
        XCTAssertFalse(SettingsTabReset.allPreferenceKeys.contains(ThumbnailAnimation.retiredPreferenceKey))
        XCTAssertFalse(SettingsTransfer.preferenceKeys.contains(ThumbnailAnimation.retiredPreferenceKey))
        XCTAssertFalse(SettingsTabReset.hasChanges(.plugins, settings: GlobalSettings(), defaults: defaults))
    }

    /// A stored "off" is removed at launch, and a settings file that still carries it imports
    /// without it.
    func testRetiredKeyIsMigratedAndIgnored() throws {
        defaults.set(false, forKey: ThumbnailAnimation.retiredPreferenceKey)
        ThumbnailAnimation.removeRetiredPreference(from: defaults)
        XCTAssertNil(defaults.object(forKey: ThumbnailAnimation.retiredPreferenceKey))

        var old = SettingsTransfer.export(settings: GlobalSettings(), defaults: defaults, updates: nil, appVersion: "1")
        old.preferences = [ThumbnailAnimation.retiredPreferenceKey: false, "ReclaimOriginalPackages": true]
        let imported = try SettingsTransfer.decode(old.encoded())
        XCTAssertEqual(imported.preferences, ["ReclaimOriginalPackages": true])
        imported.applyPreferences(to: defaults)
        XCTAssertNil(defaults.object(forKey: ThumbnailAnimation.retiredPreferenceKey))
    }

    /// Tiles play by default, with nothing stored; not while the app is in the background.
    func testThumbnailsAnimateByDefault() {
        XCTAssertNil(defaults.object(forKey: ThumbnailAnimation.retiredPreferenceKey))
        XCTAssertTrue(ThumbnailAnimation.plays(isAppActive: true, isLowPowerMode: false, isHovered: false))
        XCTAssertFalse(ThumbnailAnimation.plays(isAppActive: false, isLowPowerMode: false, isHovered: true))
    }

    /// In Low Power Mode a tile plays only while hovered.
    func testLowPowerModePlaysOnHoverOnly() {
        XCTAssertFalse(ThumbnailAnimation.plays(isAppActive: true, isLowPowerMode: true, isHovered: false))
        XCTAssertTrue(ThumbnailAnimation.plays(isAppActive: true, isLowPowerMode: true, isHovered: true))
    }

    /// Low Power Mode is followed as it changes.
    func testLowPowerModeStateFollowsTheSystem() {
        var enabled = false
        let center = NotificationCenter()
        let state = LowPowerModeState(read: { enabled }, center: center)
        XCTAssertFalse(state.isEnabled)
        enabled = true
        center.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        XCTAssertTrue(state.isEnabled)
    }

    /// A preview in a window that isn't on screen stands still, however it's asked to play.
    func testPreviewPausesWhileItsWindowIsHidden() {
        XCTAssertFalse(ThumbnailAnimation.windowShows(nil))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let view = PreviewImageView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        window.contentView?.addSubview(view)
        view.wantsAnimation = true
        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(ThumbnailAnimation.windowShows(window))
        XCTAssertFalse(view.isAnimating)
        view.wantsAnimation = false
        XCTAssertFalse(view.isAnimating)
    }

    /// A wide preview fills a square tile centred, uncropped, so all its frames still play.
    func testFillFrameCoversTheTile() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let wide = PreviewImageView.imageFrame(for: CGSize(width: 320, height: 180), in: bounds, fills: true)
        XCTAssertEqual(wide.height, 100, accuracy: 0.001)
        XCTAssertEqual(wide.width, 3200.0 / 18, accuracy: 0.001)
        XCTAssertEqual(wide.midX, 50, accuracy: 0.001)
        XCTAssertEqual(wide.midY, 50, accuracy: 0.001)
        XCTAssertEqual(PreviewImageView.imageFrame(for: CGSize(width: 320, height: 180), in: bounds, fills: false), bounds)
        XCTAssertEqual(PreviewImageView.imageFrame(for: nil, in: bounds, fills: true), bounds)
    }
}
