import XCTest
@testable import OpenWallpaperEngine

/// The placeholder's text follows the app's language setting, then the system's languages, then English.
final class AppLanguageTests: XCTestCase {
    private let available = ["Base", "en", "de", "hi", "ar", "zh-Hans", "zh-Hant", "pt-BR"]

    func testEnglishSystemGetsEnglish() {
        XCTAssertEqual(AppLanguage.resolve(setting: .followSystem, systemPreferred: ["en-CA"], available: available), "en")
        XCTAssertEqual(AppLanguage.resolve(setting: .followSystem, systemPreferred: ["en-US", "hi-IN"], available: available), "en")
    }

    func testChosenLanguageWins() {
        XCTAssertEqual(AppLanguage.resolve(setting: .de, systemPreferred: ["en-CA"], available: available), "de")
        XCTAssertEqual(AppLanguage.resolve(setting: .hi, systemPreferred: ["en-CA"], available: available), "hi")
        XCTAssertEqual(AppLanguage.resolve(setting: .en_US, systemPreferred: ["hi-IN"], available: available), "en")
        XCTAssertEqual(AppLanguage.resolve(setting: .zh_CN, systemPreferred: ["en"], available: available), "zh-Hans")
    }

    func testUntranslatedSystemFallsBackToEnglish() {
        XCTAssertEqual(AppLanguage.resolve(setting: .followSystem, systemPreferred: ["fi-FI"], available: available), "en")
        XCTAssertEqual(AppLanguage.resolve(setting: .followSystem, systemPreferred: [], available: available), "en")
        XCTAssertEqual(AppLanguage.resolve(setting: .followSystem, systemPreferred: ["fi-FI", "de-AT"], available: available), "de")
    }

    func testSystemLanguagesIgnoreTheAppDomain() throws {
        let suite = "AppLanguageTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["hi"], forKey: "AppleLanguages")
        XCTAssertFalse(AppLanguage.systemPreferredLanguages(defaults).starts(with: ["hi"]),
                       "a stray app-level AppleLanguages isn't the system's choice")
    }
}
