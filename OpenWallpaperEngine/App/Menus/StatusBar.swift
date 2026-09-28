//
//  Status.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/8/8.
//

import Cocoa

extension AppDelegate {
    @objc func mute() {
        self.wallpaperViewModel.playVolume = 0
    }

    @objc func unmute() {
        self.wallpaperViewModel.playVolume = self.wallpaperViewModel.lastPlayVolume == 0 ? 1 : self.wallpaperViewModel.lastPlayVolume
    }

    @objc func pause() {
        self.wallpaperViewModel.playRate = 0
    }

    @objc func resume() {
        self.wallpaperViewModel.playRate = self.wallpaperViewModel.lastPlayRate == 0 ? 1 : self.wallpaperViewModel.lastPlayRate
    }

    @objc func takeScreenshot() {
        try! Process.run(URL(filePath: "/usr/sbin/screencapture"), arguments: ["-Cmup", "~/Picturesscreenshot.png"])
    }

    @objc func browseWorkshop() {
        // Change tab selection to `Workshop`
        self.contentViewModel.topTabBarSelection = 1
        openMainWindow()
    }

    @objc func openSupportWebpage() {
        NSWorkspace.shared.open(URL(string: "https://github.com/deepratna-awale/wallpaper-engine-mac/wiki/Troubleshooting")!)
    }

    @objc func selectRecentWallpaper(_ sender: NSMenuItem) {
        guard let wallpaper = sender.representedObject as? WEWallpaper else { return }
        wallpaperViewModel.nextCurrentWallpaper = wallpaper
    }

    func buildRecentWallpapersMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Recent Wallpapers"))
        let recents = wallpaperViewModel.recentWallpapers

        if recents.isEmpty {
            menu.addItem(NSMenuItem(title: String(localized: "No recent wallpapers"), action: nil, keyEquivalent: ""))
        } else {
            for wallpaper in recents {
                let title = wallpaper.project.displayTitle
                let type = LocalizedLabels.wallpaperType(wallpaper.project.type)
                let itemTitle = type.isEmpty ? title
                    : String(localized: "\(title) (\(type))", comment: "Recent Wallpapers menu item: a wallpaper's title and type")
                let item = NSMenuItem(title: itemTitle, action: #selector(selectRecentWallpaper(_:)), keyEquivalent: "")
                item.representedObject = wallpaper
                item.target = self
                menu.addItem(item)
            }
        }

        return menu
    }

    func setStatusMenu() {
        // Recent Wallpapers Submenu
        let recentWallpapersMenuItem = NSMenuItem(title: String(localized: "Recent Wallpapers"), action: nil, keyEquivalent: "")
        recentWallpapersMenuItem.submenu = buildRecentWallpapersMenu()

        let menu = NSMenu()
        menu.delegate = self
        menu.items = [
            .init(title: String(localized: "Show Open Wallpaper Engine"),
                  systemImage: "photo",
                  action: #selector(openMainWindow),
                  keyEquivalent: "o"),

            recentWallpapersMenuItem,

            .separator(),

            {
                let item = NSMenuItem(title: String(localized: "Set Up Assets…"),
                                      systemImage: "shippingbox",
                                      action: #selector(openAssetsSettings),
                                      keyEquivalent: "")
                item.identifier = Self.setUpAssetsMenuItem
                item.isHidden = !assets.isMissing
                return item
            }(),

            .init(title: String(localized: "Browse Workshop"),
                  systemImage: "globe",
                  action: #selector(browseWorkshop),
                  keyEquivalent: "w"),

            .init(title: String(localized: "Settings"),
                  systemImage: "gearshape.fill",
                  action: #selector(openSettingsWindow),
                  keyEquivalent: ","),

            .separator(),

            .init(title: String(localized: "Support & FAQ"),
                  systemImage: "person.fill.questionmark",
                  action: #selector(openSupportWebpage),
                  keyEquivalent: "i"),

            .separator(),

            .init(title: String(localized: "Mute"),
                  systemImage: "speaker.slash.fill",
                  action: #selector(AppDelegate.shared.mute),
                  keyEquivalent: "m"),

            .init(title: String(localized: "Pause"),
                  systemImage: "pause.fill",
                  action: #selector(pause),
                  keyEquivalent: "p"),

            .init(title: String(localized: "Quit"),
                  systemImage: "power",
                  action: #selector(NSApplication.terminate(_:)),
                  keyEquivalent: "q")
        ]

        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem.menu = menu

        if let button = self.statusItem.button {
            if let image = NSImage(named: "OWEStatusIcon") {
                image.isTemplate = true  // white on dark menu bars, black on light ones
                button.image = image
                button.imageScaling = .scaleProportionallyDown
            } else {
                button.image = NSImage(systemSymbolName: "play.desktopcomputer", accessibilityDescription: nil)
            }
        }
    }
}

// MARK: - NSMenuDelegate — refresh Recent Wallpapers on menu open

extension AppDelegate: NSMenuDelegate {
    static let setUpAssetsMenuItem = NSUserInterfaceItemIdentifier("setUpAssets")

    func menuWillOpen(_ menu: NSMenu) {
        // Offered only while scenes are missing their assets.
        assets.refresh()
        menu.items.first { $0.identifier == Self.setUpAssetsMenuItem }?.isHidden = !assets.isMissing
        // Update the Recent Wallpapers submenu each time the status bar menu opens
        if let recentItem = menu.items.first(where: { $0.title == String(localized: "Recent Wallpapers") }) {
            recentItem.submenu = buildRecentWallpapersMenu()
        }
    }
}
