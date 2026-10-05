import AppKit

/// What each hotkey action (`GlobalHotKeyAction`) does when its shortcut is pressed.
extension AppDelegate {
    /// macOS's screen saver, which "Start screensaver" opens as WE starts Windows' own.
    static let screenSaverEngineURL = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")

    func performHotKey(_ action: GlobalHotKeyAction) {
        switch action {
        case .pause: togglePauseWallpapers()
        case .stop: toggleStopWallpapers()
        case .mute: toggleMuteWallpapers()
        case .nextWallpaper: nextWallpaper()
        case .previousWallpaper: previousWallpaper()
        case .toggleRecording:
            let capture = WallpaperServices.shared.audioCapture
            capture.isRecordingEnabled.toggle()
        case .toggleIcons: toggleDesktopIcons()
        case .screenshot: takeScreenshot()
        case .startScreensaver:
            NSWorkspace.shared.openApplication(at: Self.screenSaverEngineURL, configuration: .init()) { _, error in
                if let error { OWELog.error(.app, "Starting the screen saver failed: \(error)") }
            }
        case .windowBrowser:
            NSApp.activate()
            openMainWindow()
        case .windowSettings:
            NSApp.activate()
            openSettingsWindow()
        case .windowEditor:
            guard WallpaperEditorController.canEdit(wallpaperViewModel.displayedWallpaper) else {
                OWELog.info(.app, "Wallpaper Editor hotkey: the displayed wallpaper isn't a scene")
                NSSound.beep()
                return
            }
            showWallpaperEditorForDisplayedWallpaper()
        }
    }

    /// WE's "Hide desktop icons": the wallpaper windows move above the desktop icons, which they
    /// then cover, or back below them. Finder and its settings are left alone.
    func toggleDesktopIcons() {
        hidesDesktopIcons.toggle()
        let level = Self.wallpaperWindowLevel(hidingDesktopIcons: hidesDesktopIcons)
        for window in wallpaperWindows.values { window.level = level }
        OWELog.info(.app, "Desktop icons \(hidesDesktopIcons ? "hidden" : "shown")")
    }

    /// The wallpaper windows' level: the desktop's, below the icons, or just above the icons.
    static func wallpaperWindowLevel(hidingDesktopIcons: Bool) -> NSWindow.Level {
        hidingDesktopIcons
            ? NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            : NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)))
    }
}
