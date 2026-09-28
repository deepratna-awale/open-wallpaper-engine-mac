import Cocoa
import SwiftUI
import AVKit
import WebKit

enum SettingsToolbarIdentifiers {
    static let performance = NSToolbarItem.Identifier(rawValue: "performance")
    static let general = NSToolbarItem.Identifier(rawValue: "general")
    static let assets = NSToolbarItem.Identifier(rawValue: "assets")
    static let plugins = NSToolbarItem.Identifier(rawValue: "plugins")
    static let permissions = NSToolbarItem.Identifier(rawValue: "permissions")
    static let diagnostics = NSToolbarItem.Identifier(rawValue: "diagnostics")
    static let about = NSToolbarItem.Identifier(rawValue: "about")

    /// Every tab in toolbar order. Each is shown, allowed and selectable, so the selected tab
    /// highlights whichever it is.
    static let all: [NSToolbarItem.Identifier] = [performance, general, assets, plugins, permissions, diagnostics, about]
}
