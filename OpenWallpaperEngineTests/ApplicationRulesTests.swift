import XCTest
@testable import OpenWallpaperEngine

/// Settings › Performance › Application Rules (`ApplicationRule`): evaluated with the other
/// playback rules (`PlaybackRules`), found on the desktop (`DesktopWindowLayout`), stored in the
/// settings, exported and imported.
@MainActor
final class ApplicationRulesTests: XCTestCase {
    private let displays = ["1", "2"]
    private let editor = "com.example.editor"
    private let game = "com.example.game"

    private func rule(_ bundle: String, _ condition: ApplicationRule.Condition, _ action: GSPlayback,
                      enabled: Bool = true) -> ApplicationRule {
        ApplicationRule(bundleIdentifier: bundle, name: bundle, condition: condition, action: action, isEnabled: enabled)
    }

    private func playback(_ rules: PlaybackRules, _ conditions: [String: DisplayConditions] = [:],
                          running: Set<String> = []) -> [String: DisplayPlayback] {
        rules.playback(displays: displays, conditions: conditions,
                       system: SystemPlaybackConditions(runningApplications: running))
    }

    // MARK: Conditions and actions

    func testRunningActsOnEveryDisplay() {
        let rules = PlaybackRules(applicationRules: [rule(editor, .running, .pause)])
        XCTAssertEqual(playback(rules, running: [editor]), ["1": .pause, "2": .pause])
        XCTAssertEqual(playback(rules, running: [game]), ["1": .run, "2": .run])
    }

    func testFocusedActsOnTheWindowsDisplay() {
        let rules = PlaybackRules(applicationRules: [rule(editor, .focused, .mute)])
        XCTAssertEqual(playback(rules, ["2": DisplayConditions(focused: true, focusedApplication: editor)]),
                       ["1": .run, "2": .mute])
        XCTAssertEqual(playback(rules, ["2": DisplayConditions(focused: true, focusedApplication: game)]),
                       ["1": .run, "2": .run])
    }

    func testFullscreenActsOnTheFilledDisplay() {
        let rules = PlaybackRules(applicationRules: [rule(game, .fullscreen, .stop)])
        XCTAssertEqual(playback(rules, ["1": DisplayConditions(fullscreen: true, fillingApplications: [game])]),
                       ["1": .stop, "2": .run])
    }

    func testEachAction() {
        for (action, expected) in [(GSPlayback.mute, DisplayPlayback.mute), (.pause, .pause), (.stop, .stop)] {
            let rules = PlaybackRules(applicationRules: [rule(game, .fullscreen, action)])
            XCTAssertEqual(playback(rules, ["1": DisplayConditions(fillingApplications: [game])]),
                           ["1": expected, "2": .run], "\(action)")
        }
        // Pause All from one display's window pauses both.
        let all = PlaybackRules(applicationRules: [rule(game, .focused, .pauseAll)])
        XCTAssertEqual(playback(all, ["1": DisplayConditions(focusedApplication: game)]), ["1": .pause, "2": .pause])
    }

    func testDisabledAndKeepRunningRulesDoNothing() {
        let rules = PlaybackRules(applicationRules: [rule(editor, .running, .stop, enabled: false),
                                                     rule(game, .running, .keepRunning)])
        XCTAssertTrue(rules.applicationRules.isEmpty)
        XCTAssertFalse(rules.watchesApplications)
        XCTAssertEqual(playback(rules, running: [editor, game]), ["1": .run, "2": .run])
    }

    // MARK: Combining

    func testCombinesWithThePlaybackSettingsMostRestrictiveWins() {
        // "Other application fullscreen: mute" and a rule pausing while the editor runs.
        let rules = PlaybackRules(fullscreen: .mute, applicationRules: [rule(editor, .running, .pause)])
        let result = playback(rules, ["2": DisplayConditions(fullscreen: true)], running: [editor])
        XCTAssertEqual(result, ["1": .pause, "2": .pause])
        // A stricter global rule keeps its stop on its display.
        let strict = PlaybackRules(fullscreen: .stop, applicationRules: [rule(editor, .running, .mute)])
        XCTAssertEqual(playback(strict, ["2": DisplayConditions(fullscreen: true)], running: [editor]),
                       ["1": .mute, "2": .stop])
    }

    func testSeveralRulesTheStricterWins() {
        let rules = PlaybackRules(applicationRules: [rule(editor, .running, .mute), rule(game, .fullscreen, .stop)])
        XCTAssertEqual(playback(rules, ["2": DisplayConditions(fillingApplications: [game])], running: [editor, game]),
                       ["1": .mute, "2": .stop])
    }

    func testOnlyWindowConditionsReadTheWindowList() {
        XCTAssertFalse(PlaybackRules(applicationRules: [rule(editor, .running, .pause)]).applicationRulesWatchWindows)
        XCTAssertTrue(PlaybackRules(applicationRules: [rule(editor, .focused, .pause)]).applicationRulesWatchWindows)
        // Application rules never turn on the poll that the window settings use.
        XCTAssertFalse(PlaybackRules(applicationRules: [rule(editor, .fullscreen, .pause)]).watchesWindows)
    }

    // MARK: The desktop

    func testWindowLayoutNamesTheFocusedAndFillingApplications() {
        let display = DesktopDisplay(id: "1", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                     visibleFrame: CGRect(x: 0, y: 25, width: 1920, height: 1055))
        let windows = [
            DesktopWindow(ownerPID: 10, bounds: CGRect(x: 100, y: 100, width: 800, height: 600)),
            DesktopWindow(ownerPID: 20, bounds: display.frame),
        ]
        let conditions = DesktopWindowLayout.conditions(windows: windows, displays: [display], frontmostPID: 10,
                                                        ignoredPIDs: [1], bundleIdentifiers: [10: editor, 20: game])
        XCTAssertEqual(conditions["1"]?.focusedApplication, editor)
        XCTAssertEqual(conditions["1"]?.fillingApplications, [game])
    }

    // MARK: Storage

    func testSettingsRoundTripKeepsTheRules() throws {
        var settings = GlobalSettings()
        settings.applicationRules = [rule(editor, .focused, .mute), rule(game, .fullscreen, .stop, enabled: false)]
        let decoded = try JSONDecoder().decode(GlobalSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.applicationRules, settings.applicationRules)
        XCTAssertEqual(PlaybackRules(decoded).applicationRules.map(\.bundleIdentifier), [editor])
    }

    func testAnUnreadableRuleDoesNotDropTheOthers() throws {
        let json = """
        {"applicationRules": [
          {"bundleIdentifier": "com.example.editor", "condition": "focused", "action": "mute"},
          {"condition": "running"},
          "not a rule",
          {"bundleIdentifier": "com.example.game", "condition": "someday", "action": "stop"}
        ]}
        """
        let settings = try JSONDecoder().decode(GlobalSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.applicationRules.map(\.bundleIdentifier), [editor, game])
        XCTAssertEqual(settings.applicationRules[0].condition, .focused)
        XCTAssertEqual(settings.applicationRules[1].condition, .running, "an unknown condition keeps the default")
        XCTAssertEqual(settings.applicationRules[1].action, .stop)
    }

    func testExportImportRoundTrip() throws {
        var settings = GlobalSettings()
        settings.applicationRules = [rule(editor, .running, .pauseAll)]
        let suite = "owe-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let exported = SettingsTransfer.export(settings: settings, defaults: defaults, updates: nil, appVersion: "test")
        let imported = try SettingsTransfer.decode(exported.encoded())
        XCTAssertEqual(imported.settings.applicationRules, settings.applicationRules)
    }

    func testResetClearsTheRules() {
        var settings = GlobalSettings()
        settings.applicationRules = [rule(editor, .running, .pause)]
        XCTAssertTrue(SettingsTab.performance.fields.contains { $0.isChanged(settings) })
        XCTAssertEqual(SettingsTab.performance.resetting(settings).applicationRules, [])
        XCTAssertEqual(GlobalSettings().applicationRules, [])
    }
}
