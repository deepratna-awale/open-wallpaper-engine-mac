import ServiceManagement
import XCTest
@testable import OpenWallpaperEngine

/// Settings › General › Show in Dock and Show in Menu Bar.
final class AppPresenceSettingsTests: XCTestCase {
    func testDefaultsKeepTheMenuBarItemAndADockIconOnlyWithAWindow() throws {
        XCTAssertFalse(GlobalSettings().showInDock)
        XCTAssertTrue(GlobalSettings().showInMenuBar)
        let decoded = try JSONDecoder().decode(GlobalSettings.self, from: Data("{}".utf8))
        XCTAssertFalse(decoded.showInDock)
        XCTAssertTrue(decoded.showInMenuBar)
    }

    func testBothOffRoundTrips() throws {
        var settings = GlobalSettings()
        settings.showInDock = false
        settings.showInMenuBar = false
        let decoded = try JSONDecoder().decode(GlobalSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertFalse(decoded.showInDock)
        XCTAssertFalse(decoded.showInMenuBar)
    }

    func testRestoreDefaultsOnGeneralCoversThem() {
        var settings = GlobalSettings()
        settings.showInDock = true
        settings.showInMenuBar = false
        let changed = SettingsTab.general.fields.filter { $0.isChanged(settings) }
        XCTAssertEqual(changed.count, 2)
    }

    /// Settings › General › Launch at Login: the login item is changed only when it differs from
    /// the setting (the setting is published at every launch), and never by an isolated copy,
    /// which shares the real app's login item.
    func testTheLoginItemChangesOnlyWhenItDiffersAndNeverFromAnIsolatedCopy() {
        typealias Model = GlobalSettingsViewModel
        XCTAssertNil(Model.loginItemChange(wanted: false, status: .notRegistered, isIsolated: false))
        XCTAssertNil(Model.loginItemChange(wanted: false, status: .notFound, isIsolated: false))
        XCTAssertNil(Model.loginItemChange(wanted: true, status: .enabled, isIsolated: false))
        XCTAssertNil(Model.loginItemChange(wanted: true, status: .requiresApproval, isIsolated: false))
        XCTAssertEqual(Model.loginItemChange(wanted: true, status: .notRegistered, isIsolated: false), .register)
        XCTAssertEqual(Model.loginItemChange(wanted: true, status: .notFound, isIsolated: false), .register)
        XCTAssertEqual(Model.loginItemChange(wanted: false, status: .enabled, isIsolated: false), .unregister)
        XCTAssertEqual(Model.loginItemChange(wanted: false, status: .requiresApproval, isIsolated: false), .unregister)
        XCTAssertNil(Model.loginItemChange(wanted: false, status: .enabled, isIsolated: true))
        XCTAssertNil(Model.loginItemChange(wanted: true, status: .notRegistered, isIsolated: true))
    }
}
