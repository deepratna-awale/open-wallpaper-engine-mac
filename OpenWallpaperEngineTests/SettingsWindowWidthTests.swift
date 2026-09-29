import AppKit
import XCTest
@testable import OpenWallpaperEngine

/// The settings window is wide enough for every tab's toolbar item in the widest language.
@MainActor
final class SettingsWindowWidthTests: XCTestCase {
    func testTheWindowFitsEveryTabInEveryLanguage() {
        let languages = Bundle.main.localizations.filter { $0 != "Base" }
        XCTAssertFalse(languages.isEmpty)
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        for language in languages {
            let labels = SettingsTab.allCases.map { tab -> CGFloat in
                let title = tab.title(in: language)
                XCTAssertFalse(title.isEmpty, "\(tab) has no \(language) title")
                return (title as NSString).size(withAttributes: [.font: font]).width
            }
            XCTAssertLessThan(labels.reduce(0, +), SettingsTab.toolbarFittingWidth, language)
        }
        XCTAssertGreaterThanOrEqual(SettingsTab.toolbarFittingWidth, 720)
    }
}
