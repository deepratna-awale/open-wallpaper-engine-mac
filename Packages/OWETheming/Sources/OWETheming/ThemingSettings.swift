import Foundation

/// Settings › General › Theming. Every target is off by default, as is the master switch.
public struct ThemingSettings: Equatable, Codable, Sendable {
    /// The master switch: off, nothing is themed and everything theming changed is restored.
    public var isEnabled = false
    /// Fills the menu bar's strip of the desktop picture OWE sets with the colour.
    public var menuBar = false
    /// System Settings › Appearance › Color (the nearest palette entry) and the text highlight.
    public var accentColor = false
    /// Appearance › Icon & widget style › Tinted, in the colour.
    public var tintedIcons = false
    /// Appearance › Icon, widget & folder color.
    public var folderColor = false
    /// Without a scheme colour, the main colour of the wallpaper's snapshot is used.
    public var usesDominantColor = false
    /// Quitting puts the user's preferences back. On by default.
    public var restoresOnQuit = true
    /// The Dock restarts by itself once a new icon or folder colour settles, so it shows it. On by
    /// default; off, Settings offers a button instead.
    public var restartsDockAutomatically = true

    public init() {}

    /// Whether any system preference is wanted (the menu bar strip is a picture, not a preference).
    public var wantsPreferences: Bool { isEnabled && (accentColor || tintedIcons || folderColor) }

    /// Whether the menu bar strip is drawn.
    public var wantsMenuBarStrip: Bool { isEnabled && menuBar }

    /// Whether anything at all is themed, which is when the colour needs finding.
    public var wantsColor: Bool { wantsPreferences || wantsMenuBarStrip }

    enum CodingKeys: String, CodingKey {
        case isEnabled, menuBar, accentColor, tintedIcons, folderColor, usesDominantColor, restoresOnQuit
        case restartsDockAutomatically
    }

    /// Reads each key on its own: a missing or unreadable one keeps its default.
    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func read(_ key: CodingKeys, _ value: inout Bool) {
            if let stored = try? container.decodeIfPresent(Bool.self, forKey: key) { value = stored } // Optional: a bad key keeps its default.
        }
        read(.isEnabled, &isEnabled)
        read(.menuBar, &menuBar)
        read(.accentColor, &accentColor)
        read(.tintedIcons, &tintedIcons)
        read(.folderColor, &folderColor)
        read(.usesDominantColor, &usesDominantColor)
        read(.restoresOnQuit, &restoresOnQuit)
        read(.restartsDockAutomatically, &restartsDockAutomatically)
    }
}
