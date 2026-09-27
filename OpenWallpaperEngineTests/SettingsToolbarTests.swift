import AppKit
import XCTest
@testable import OpenWallpaperEngine

/// The settings window's toolbar: every tab is selectable, so the one shown is highlighted.
final class SettingsToolbarTests: XCTestCase {
    /// The tabs in the order of `GlobalSettingsViewModel.selection` (`jumpToPerformance` 0 …
    /// `jumpToAbout` 5), Diagnostics included.
    func testEveryTabIsSelectableInSelectionOrder() {
        let expected: [NSToolbarItem.Identifier] = [
            SettingsToolbarIdentifiers.performance, SettingsToolbarIdentifiers.general,
            SettingsToolbarIdentifiers.plugins, SettingsToolbarIdentifiers.permissions,
            SettingsToolbarIdentifiers.diagnostics, SettingsToolbarIdentifiers.about,
        ]
        XCTAssertEqual(SettingsToolbarIdentifiers.all, expected)
        XCTAssertEqual(Set(SettingsToolbarIdentifiers.all).count, SettingsToolbarIdentifiers.all.count)
    }
}
