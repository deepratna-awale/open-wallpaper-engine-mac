//
//  Menu.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/8/8.
//

import Cocoa

extension AppDelegate {
    func setMainMenu() {
        NSApplication.shared.mainMenu = Self.makeMainMenu()
        NSApp.servicesMenu = NSApplication.shared.mainMenu?.items.first?.submenu?.item(withTag: MainMenuTag.services)?.submenu
        NSApp.windowsMenu = NSApplication.shared.mainMenu?.item(withTag: MainMenuTag.window)?.submenu
        NSApp.helpMenu = NSApplication.shared.mainMenu?.item(withTag: MainMenuTag.help)?.submenu
    }

    /// The menu bar: the standard App, File, Edit, View, Window and Help menus, with a Playback
    /// menu for the wallpapers. Shortcuts come from `AppShortcut.all`.
    static func makeMainMenu() -> NSMenu {
        func submenu(_ title: String, tag: Int = 0, _ items: [NSMenuItem]) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.tag = tag
            item.submenu = NSMenu(title: title)
            item.submenu?.items = items
            return item
        }
        func item(_ name: AppShortcut.Name, _ action: Selector, target: AnyObject? = nil) -> NSMenuItem {
            NSMenuItem(AppShortcut[name], action: action, target: target)
        }
        func plain(_ title: LocalizedStringResource, _ action: Selector?) -> NSMenuItem {
            NSMenuItem(title: String(localized: title), action: action, keyEquivalent: "")
        }

        let servicesItem = plain("Services", nil)
        servicesItem.submenu = NSMenu()
        servicesItem.tag = MainMenuTag.services

        let appMenu = submenu("Open Wallpaper Engine", [
            plain("About Open Wallpaper Engine", #selector(showAboutUs)),
            item(.checkForUpdates, #selector(checkForUpdates)),
            .separator(),
            item(.settings, #selector(openSettingsWindow)),
            .separator(),
            servicesItem,
            .separator(),
            item(.hide, #selector(NSApplication.hide(_:))),
            item(.hideOthers, #selector(NSApplication.hideOtherApplications(_:))),
            plain("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item(.quit, #selector(NSApplication.terminate(_:))),
        ])

        let fileMenu = submenu(String(localized: "File"), [
            item(.importFolder, #selector(openImportFromFolderPanel)),
            .separator(),
            item(.closeWindow, #selector(NSWindow.performClose(_:))),
        ])

        let editMenu = submenu(String(localized: "Edit"), [
            item(.undo, Selector(("undo:"))),
            item(.redo, Selector(("redo:"))),
            .separator(),
            item(.cut, #selector(NSText.cut(_:))),
            item(.copy, #selector(NSText.copy(_:))),
            item(.paste, #selector(NSText.paste(_:))),
            plain("Delete", #selector(NSText.delete(_:))),
            item(.selectAll, #selector(NSText.selectAll(_:))),
            .separator(),
            item(.find, #selector(focusSearch)),
        ])

        let viewMenu = submenu(String(localized: "View"), [
            item(.installed, #selector(showInstalledTab)),
            item(.workshop, #selector(browseWorkshop)),
            item(.downloads, #selector(showDownloadsTab)),
            item(.playlists, #selector(showPlaylistsTab)),
            .separator(),
            item(.showFilters, #selector(toggleFilter)),
            .separator(),
            item(.fullScreen, #selector(NSWindow.toggleFullScreen(_:))),
        ])

        let playbackMenu = submenu(String(localized: "Playback"), [
            item(.pauseResume, #selector(togglePauseWallpapers)),
            item(.muteUnmute, #selector(toggleMuteWallpapers)),
            .separator(),
            item(.nextWallpaper, #selector(nextPlaylistWallpaper)),
            item(.previousWallpaper, #selector(previousPlaylistWallpaper)),
        ])

        let windowMenu = submenu(String(localized: "Window"), tag: MainMenuTag.window, [
            item(.minimize, #selector(NSWindow.performMiniaturize(_:))),
            plain("Zoom", #selector(NSWindow.performZoom(_:))),
            .separator(),
            item(.wallpaperExplorer, #selector(openMainWindow)),
            item(.sceneInspector, #selector(showSceneInspectorForDisplayedWallpaper)),
            .separator(),
            plain("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))),
        ])

        let debugMenu = submenu(String(localized: "Debug"), [
            plain("Reset First Launch", #selector(resetFirstLaunch)),
            plain("Toggle Desktop Wallpaper Window (Debug)", #selector(toggleDesktopWallpaperWindow)),
            plain("Reset All Trusted Wallpapers", #selector(resetTrustedWallpapers)),
        ])

        let helpMenu = submenu(String(localized: "Help"), tag: MainMenuTag.help, [
            item(.help, #selector(openHelp)),
            plain("Support & FAQ", #selector(openSupportWebpage)),
            plain("Keyboard Shortcuts", #selector(showKeyboardShortcuts)),
            .separator(),
            plain("Terms of Use", #selector(showTermsOfUse)),
            plain("Privacy Policy", #selector(showPrivacyPolicy)),
            plain("Report a Security Issue", #selector(openSecurityReport)),
            .separator(),
            debugMenu,
        ])

        let mainMenu = NSMenu()
        mainMenu.items = [appMenu, fileMenu, editMenu, viewMenu, playbackMenu, windowMenu, helpMenu]
        return mainMenu
    }

    @objc func toggleDesktopWallpaperWindow() {
        if wallpaperWindows.values.first?.isVisible == true {
            for window in wallpaperWindows.values { window.orderOut(nil) }
        } else {
            for window in wallpaperWindows.values { window.orderFront(nil) }
        }
    }

    /// Disabled (see `validateMenuItem`) while Sparkle is off or busy.
    @objc func checkForUpdates() {
        updater.checkForUpdates()
    }

    @objc func resetTrustedWallpapers() {
        UserDefaults.app.set([String](), forKey: "TrustedWallpapers")
    }
}

/// Tags that find the menus AppKit manages (the window list, Help's search field).
enum MainMenuTag {
    static let window = 9001
    static let help = 9002
    static let services = 9003
}

extension NSMenuItem {
    public convenience init(title: String, systemImage: String, action: Selector?, keyEquivalent: String) {
        self.init(title: title, action: action, keyEquivalent: keyEquivalent)
        self.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)

    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(checkForUpdates):
            return updater.canCheckForUpdates
        case #selector(togglePauseWallpapers):
            menuItem.title = wallpaperViewModel.playRate == 0
                ? String(localized: "Resume Wallpapers") : String(localized: "Pause Wallpapers")
            return true
        case #selector(toggleMuteWallpapers):
            menuItem.title = wallpaperViewModel.playVolume == 0 ? String(localized: "Unmute") : String(localized: "Mute")
            return true
        case #selector(nextPlaylistWallpaper), #selector(previousPlaylistWallpaper):
            return wallpaperViewModel.activePlaylist?.items.isEmpty == false
        default:
            return true
        }
    }
}
