import AppKit

/// The Wallpaper Editor process's menu bar: the app menu, File (Save as Local Wallpaper…,
/// Revert…, Close), Edit, Window and Help. File's document actions go to the key editor window
/// (`WallpaperEditorController`) through the responder chain.
@MainActor
enum WallpaperEditorMenu {
    /// File › Save as Local Wallpaper… (the key editor window answers it).
    static let saveAsLocalWallpaper = #selector(WallpaperEditorController.saveAsLocalWallpaper(_:))
    /// File › Revert… (the key editor window answers it).
    static let revert = #selector(WallpaperEditorController.revertEdits(_:))

    static func make(helpTarget: AnyObject, help: Selector) -> NSMenu {
        func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = NSMenu(title: title)
            item.submenu?.items = items
            return item
        }
        func item(_ name: AppShortcut.Name, _ action: Selector, target: AnyObject? = nil) -> NSMenuItem {
            NSMenuItem(AppShortcut[name], action: action, target: target)
        }
        func plain(_ title: String, _ action: Selector?, key: String = "",
                   modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            if !key.isEmpty { item.keyEquivalentModifierMask = modifiers }
            return item
        }

        let appMenu = submenu(String(localized: "Wallpaper Editor"), [
            plain(String(localized: "Hide Wallpaper Editor"), #selector(NSApplication.hide(_:)), key: "h"),
            item(.hideOthers, #selector(NSApplication.hideOtherApplications(_:))),
            plain(String(localized: "Show All"), #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            plain(String(localized: "Quit Wallpaper Editor"), #selector(NSApplication.terminate(_:)), key: "q"),
        ])

        let fileMenu = submenu(String(localized: "File"), [
            plain(String(localized: "Save as Local Wallpaper…"), saveAsLocalWallpaper, key: "s", modifiers: [.command, .shift]),
            plain(String(localized: "Revert…"), revert),
            .separator(),
            plain(String(localized: "Close"), #selector(NSWindow.performClose(_:)), key: "w"),
        ])

        let editMenu = submenu(String(localized: "Edit"), [
            item(.undo, Selector(("undo:"))),
            item(.redo, Selector(("redo:"))),
            .separator(),
            item(.cut, #selector(NSText.cut(_:))),
            item(.copy, #selector(NSText.copy(_:))),
            item(.paste, #selector(NSText.paste(_:))),
            plain(String(localized: "Delete"), #selector(NSText.delete(_:))),
            item(.selectAll, #selector(NSText.selectAll(_:))),
        ])

        let windowMenu = submenu(String(localized: "Window"), [
            item(.minimize, #selector(NSWindow.performMiniaturize(_:))),
            plain(String(localized: "Zoom"), #selector(NSWindow.performZoom(_:))),
            .separator(),
            plain(String(localized: "Bring All to Front"), #selector(NSApplication.arrangeInFront(_:))),
        ])

        let helpMenu = submenu(String(localized: "Help"), [
            item(.help, help, target: helpTarget),
        ])

        let menu = NSMenu()
        menu.items = [appMenu, fileMenu, editMenu, windowMenu, helpMenu]
        return menu
    }

    /// Installs `menu` as the app's, with AppKit's window list and Help search in their menus.
    static func install(_ menu: NSMenu) {
        NSApp.mainMenu = menu
        NSApp.windowsMenu = menu.items.first { $0.submenu?.title == String(localized: "Window") }?.submenu
        NSApp.helpMenu = menu.items.last?.submenu
    }
}
