import XCTest
@testable import OpenWallpaperEngine

/// Settings export and import, and "Restore Defaults" per tab, in a defaults suite of their own.
@MainActor
final class SettingsTransferTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suite = "owe-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    private func changedSettings() -> GlobalSettings {
        var settings = GlobalSettings()
        settings.fps = 60
        settings.shadows = .ultra
        settings.otherApplicationFullscreen = .pauseAll
        settings.appearance = .dark
        settings.language = .ja
        settings.syncPropertiesAcrossDisplays = true
        settings.logLevel = .verbose
        return settings
    }

    /// What goes out comes back, and no secret goes out: the API key and the Steam account (here
    /// left in the defaults where old builds kept them) are never read.
    func testExportImportRoundTripWithoutSecrets() throws {
        defaults.set(true, forKey: "ReclaimOriginalPackages")
        defaults.set(true, forKey: "TestAnimates")
        defaults.set(false, forKey: "ReceiveBetaUpdates")
        defaults.set("SECRET-API-KEY-0123456789", forKey: "SteamWebAPIKey")
        defaults.set("secret-steam-account", forKey: "SteamLastUsername")
        let updates = SettingsTransfer.Updates(automaticallyChecksForUpdates: true, updatesAutomatically: false)

        let exported = SettingsTransfer.export(settings: changedSettings(), defaults: defaults,
                                               updates: updates, appVersion: "1.0.0 (Dev build)")
        let data = try exported.encoded()
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(text.contains("SECRET-API-KEY"))
        XCTAssertFalse(text.contains("secret-steam-account"))
        XCTAssertFalse(text.contains("SteamWebAPIKey"))
        XCTAssertFalse(text.contains("SteamLastUsername"))

        let imported = try SettingsTransfer.decode(data)
        XCTAssertEqual(imported, exported)
        XCTAssertEqual(imported.settings, changedSettings())
        XCTAssertEqual(imported.updates, updates)
        XCTAssertEqual(imported.preferences, ["ReclaimOriginalPackages": true, "TestAnimates": true, "ReceiveBetaUpdates": false])

        let other = try XCTUnwrap(UserDefaults(suiteName: suite + ".other"))
        defer { other.removePersistentDomain(forName: suite + ".other") }
        imported.applyPreferences(to: other)
        XCTAssertTrue(other.bool(forKey: "ReclaimOriginalPackages"))
        XCTAssertTrue(other.bool(forKey: "TestAnimates"))
        XCTAssertNil(other.object(forKey: "SteamWebAPIKey"))
    }

    /// Other JSON, a newer format and unknown preferences are refused or dropped.
    func testImportRefusesOtherFiles() throws {
        XCTAssertThrowsError(try SettingsTransfer.decode(Data("{\"fps\": 30}".utf8)))
        XCTAssertThrowsError(try SettingsTransfer.decode(Data("not json".utf8)))

        var newer = SettingsTransfer.export(settings: GlobalSettings(), defaults: defaults, updates: nil, appVersion: "9")
        newer.version = SettingsTransfer.currentVersion + 1
        XCTAssertThrowsError(try SettingsTransfer.decode(newer.encoded()))

        var extra = SettingsTransfer.export(settings: GlobalSettings(), defaults: defaults, updates: nil, appVersion: "1")
        extra.preferences = ["SteamWebAPIKey": true, "TestAnimates": true]
        XCTAssertEqual(try SettingsTransfer.decode(extra.encoded()).preferences, ["TestAnimates": true])
    }

    /// "Restore Defaults" resets only the shown tab's settings.
    func testResetPerTabKeepsTheOtherTabs() {
        let changed = changedSettings()

        let performance = SettingsTab.performance.resetting(changed)
        XCTAssertEqual(performance.fps, GlobalSettings().fps)
        XCTAssertEqual(performance.shadows, GlobalSettings().shadows)
        XCTAssertEqual(performance.otherApplicationFullscreen, GlobalSettings().otherApplicationFullscreen)
        XCTAssertEqual(performance.appearance, .dark)
        XCTAssertEqual(performance.language, .ja)
        XCTAssertTrue(performance.syncPropertiesAcrossDisplays)
        XCTAssertEqual(performance.logLevel, .verbose)

        let general = SettingsTab.general.resetting(changed)
        XCTAssertEqual(general.appearance, GlobalSettings().appearance)
        XCTAssertEqual(general.language, GlobalSettings().language)
        XCTAssertEqual(general.fps, 60)

        let optimizations = SettingsTab.optimizations.resetting(changed)
        XCTAssertFalse(optimizations.syncPropertiesAcrossDisplays)
        XCTAssertEqual(optimizations.logLevel, .verbose)

        XCTAssertEqual(SettingsTab.diagnostics.resetting(changed).logLevel, GlobalSettings().logLevel)
        XCTAssertEqual(SettingsTab.about.resetting(changed), changed)

        // Every tab reset in turn gives the defaults: each shown setting belongs to a tab.
        var all = changed
        for tab in SettingsTab.allCases { all = tab.resetting(all) }
        XCTAssertEqual(all, GlobalSettings())
    }

    /// Preferences kept outside `GlobalSettings` are reset with their tab, and the dots follow.
    func testResetPerTabClearsItsPreferences() {
        let viewModel = GlobalSettingsViewModel()
        let saved = viewModel.settings
        defer { viewModel.settings = saved; viewModel.flushPendingSave() }
        defaults.set(true, forKey: "TestAnimates")
        defaults.set(true, forKey: "ReclaimOriginalPackages")
        XCTAssertTrue(SettingsTabReset.hasChanges(.plugins, settings: GlobalSettings(), defaults: defaults))

        SettingsTabReset.reset(.plugins, viewModel: viewModel, defaults: defaults, updater: nil)
        XCTAssertNil(defaults.object(forKey: "TestAnimates"))
        XCTAssertTrue(defaults.bool(forKey: "ReclaimOriginalPackages"), "another tab's preference stays")
        XCTAssertFalse(SettingsTabReset.hasChanges(.plugins, settings: GlobalSettings(), defaults: defaults))

        var fast = GlobalSettings()
        fast.fps = 90
        XCTAssertTrue(SettingsField.anyChanged(on: .performance, fast))
        XCTAssertFalse(SettingsField.anyChanged(on: .general, fast))
    }
}

private enum SettingsField {
    static func anyChanged(on tab: SettingsTab, _ settings: GlobalSettings) -> Bool {
        tab.fields.contains { $0.isChanged(settings) }
    }
}
