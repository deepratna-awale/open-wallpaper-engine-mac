import AppKit

/// The actions of the menu bar's app items (`makeMainMenu`) and the status menu.
extension AppDelegate {
    static let helpURL = URL(string: "https://github.com/deepratna-awale/open-wallpaper-engine-mac/wiki")!
    static let securityReportURL = URL(string: "https://github.com/deepratna-awale/open-wallpaper-engine-mac/security")!

    @objc func togglePauseWallpapers() {
        if wallpaperViewModel.playRate == 0 { resume() } else { pause() }
    }

    @objc func toggleMuteWallpapers() {
        if wallpaperViewModel.playVolume == 0 { unmute() } else { mute() }
    }

    @objc func nextPlaylistWallpaper() {
        wallpaperViewModel.nextPlaylistWallpaper()
    }

    @objc func previousPlaylistWallpaper() {
        wallpaperViewModel.previousPlaylistWallpaper()
    }

    @objc func showSceneInspectorForDisplayedWallpaper() {
        let wallpaper = wallpaperViewModel.displayedWallpaper
        showSceneInspector(for: wallpaper, scopes: wallpaperViewModel.editedPropertyScopes(of: wallpaper))
    }

    @objc func showInstalledTab() { showLibraryTab(0) }
    @objc func showDownloadsTab() { showLibraryTab(2) }
    @objc func showPlaylistsTab() { showLibraryTab(3) }

    private func showLibraryTab(_ tab: Int) {
        contentViewModel.topTabBarSelection = tab
        openMainWindow()
    }

    /// Edit › Find: the search field of the settings window when it's in front, otherwise the
    /// library's.
    @objc func focusSearch() {
        if settingsWindow.isKeyWindow {
            settingsNavigation.focusesSearch = true
            return
        }
        if contentViewModel.topTabBarSelection > 1 { contentViewModel.topTabBarSelection = 0 }
        openMainWindow()
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.mainWindowController.window else { return }
            if let field = Self.searchField(in: window) { window.makeFirstResponder(field) }
        }
    }

    /// The window's search field: the toolbar's search item, or one in its views.
    private static func searchField(in window: NSWindow) -> NSSearchField? {
        if let item = window.toolbar?.items.lazy.compactMap({ $0 as? NSSearchToolbarItem }).first {
            return item.searchField
        }
        func find(_ view: NSView) -> NSSearchField? {
            if let field = view as? NSSearchField { return field }
            for subview in view.subviews { if let field = find(subview) { return field } }
            return nil
        }
        return window.contentView?.superview.flatMap(find)
    }

    @objc func openHelp() {
        NSWorkspace.shared.open(Self.helpURL)
    }

    @objc func openSecurityReport() {
        NSWorkspace.shared.open(Self.securityReportURL)
    }

    @objc func showKeyboardShortcuts() {
        openSettings(.general, anchor: SettingsAnchor.shortcuts)
    }

    @objc func showTermsOfUse() {
        LegalDocumentWindow.show(.termsOfUse)
    }

    @objc func showPrivacyPolicy() {
        LegalDocumentWindow.show(.privacyPolicy)
    }
}
