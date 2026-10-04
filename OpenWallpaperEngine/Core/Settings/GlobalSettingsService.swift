//
//  GlobalSettingsService.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/9/2.
//

import Cocoa
import Combine
import SwiftUI
import ServiceManagement

@MainActor
class GlobalSettingsViewModel: ObservableObject {
    private static let audioPermissionAlertDismissedKey = "SuppressAudioPermissionPrompt"

    /// The user chose "Don't Ask Again" on the missing Screen Recording permission alert.
    /// Nonisolated because the audio engine reads it off the settings view model's lifetime.
    nonisolated static var isAudioPermissionAlertDismissed: Bool {
        get { UserDefaults.app.bool(forKey: audioPermissionAlertDismissedKey) }
        set { UserDefaults.app.set(newValue, forKey: audioPermissionAlertDismissedKey) }
    }

    @Published var settings: GlobalSettings
    {
        didSet {
            save()
            validate()
            OWELog.apply(logLevel: settings.logLevel)
            // Only on a change: following the system mustn't clear a language set in System Settings.
            if settings.language != oldValue.language { settings.language.apply(to: .app) }
        }
    }
    
    /// The setup assistant is showing (at launch until finished, or from "Run setup again…").
    @Published var isFirstLaunch = OnboardingFlow.showsAtLaunch()

    /// The Terms of Use and Privacy Policy notice is due (`LegalNotice`): never confirmed, or the
    /// documents changed since. Shown once, on its own when setup is already done.
    @Published var needsLegalNotice = LegalNotice.isDue(in: .app)

    /// The language this process runs in; a different choice applies at the next launch.
    let languageChange: LanguageChange
    
    var didFinishLaunchingNotificationCancellable: Cancellable?
    var didCurrentWallpaperChangeCancellable: Cancellable?
    var didAddToLoginItemCancellable: Cancellable?
    var didChangeAdjustMenuBarTintCancellable: Cancellable?
    var didChangeLockScreenPictureCancellable: Cancellable?
    var didChangeScreenSaverCancellable: Cancellable?
    
    /// `followsLaunch`: at launch, the settings that act on the system (launch at login, the menu
    /// bar tint and lock-screen pictures, the screen saver) start following the app's wallpaper.
    /// Only Open Wallpaper Engine's own settings do; the Wallpaper Editor's process reads them.
    init(followsLaunch: Bool = true) {
        let loaded: GlobalSettings = Self.loadSettings(from: UserDefaults.app.data(forKey: "GlobalSettings"),
                                                       backupDirectory: AppStorageLocation.current.supportDirectory)
        self.settings = loaded
        languageChange = LanguageChange(atLaunch: loaded.language)
        OWELog.apply(logLevel: settings.logLevel)

        // Add observers
        guard followsLaunch else { return }
        self.didFinishLaunchingNotificationCancellable =
        NotificationCenter.default.publisher(for: NSApplication.didFinishLaunchingNotification)
            .sink { [weak self] _ in self?.didFinishLaunchingNotification() }
    }

    /// The stored settings. `GlobalSettings` reads each key on its own, so this only fails when
    /// the data isn't a settings object at all. The defaults are used then, and as the next save
    /// replaces the stored data, it is first copied to `settings.corrupt-<date>.json` in
    /// `backupDirectory`.
    nonisolated static func loadSettings(from data: Data?, backupDirectory: URL, now: Date = Date()) -> GlobalSettings {
        guard let data else { return GlobalSettings() }
        do {
            return try JSONDecoder().decode(GlobalSettings.self, from: data)
        } catch {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let backup: URL = backupDirectory.appending(path: "settings.corrupt-\(formatter.string(from: now)).json")
            do {
                try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
                try data.write(to: backup, options: .atomic)
                OWELog.error(.settings, "Settings can't be read and are reset to the defaults; the stored copy is at \(backup.path): \(error)")
            } catch let backupError {
                OWELog.error(.settings, "Settings can't be read and are reset to the defaults (\(error)); backing up the stored copy failed: \(backupError)")
            }
            return GlobalSettings()
        }
    }

    deinit {
        didFinishLaunchingNotificationCancellable?.cancel()
        didCurrentWallpaperChangeCancellable?.cancel()
        didAddToLoginItemCancellable?.cancel()
        didChangeAdjustMenuBarTintCancellable?.cancel()
        didChangeLockScreenPictureCancellable?.cancel()
        didChangeScreenSaverCancellable?.cancel()
    }
    
    func didFinishLaunchingNotification() {
        self.didCurrentWallpaperChangeCancellable =
        AppDelegate.shared.wallpaperViewModel.$wallpapers
            .sink { [weak self] wallpapers in
                let mainId = WallpaperViewModel.mainScreenId()
                if let wp = wallpapers[mainId] {
                    self?.didCurrentWallpaperChange(wp)
                }
            }
        
        self.didAddToLoginItemCancellable =
        self.$settings
            .removeDuplicates { $0.autoStart == $1.autoStart }
            .map { $0.autoStart }
            .sink { [weak self] in self?.didAddToLoginItem($0) }
        
        self.didChangeAdjustMenuBarTintCancellable =
        self.$settings
            .removeDuplicates { $0.adjustMenuBarTint == $1.adjustMenuBarTint }
            .map { $0.adjustMenuBarTint }
            .sink { [weak self] in self?.didChangeAdjustMenuBarTint($0) }

        self.didChangeLockScreenPictureCancellable =
        self.$settings
            .map { $0.lockScreenPicture }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] in self?.didChangeLockScreenPicture($0) }

        self.didChangeScreenSaverCancellable =
        self.$settings
            .map { [$0.screenSaver as AnyHashable, $0.renderResolution] }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                // `$settings` publishes before the property changes: the plugin reads the new
                // settings (on or off, Render Resolution) once they are set.
                DispatchQueue.main.async {
                    guard let enabled = self?.settings.screenSaver else { return }
                    // The loop follows Render Resolution, so a change re-renders it.
                    AppDelegate.shared.screenSaver.update(enabled: enabled,
                                                          wallpaper: AppDelegate.shared.wallpaperViewModel.currentWallpaper)
                }
            }
            
        
        self.validate()
    }
    
    func didAddToLoginItem(_ added: Bool) {
        let appService = SMAppService.mainApp
        do {
            if added {
                try appService.register()
            } else {
                try appService.unregister()
            }
        } catch {
            OWELog.error(.settings, "Launch-at-login update failed: \(error)")
        }
    }
    
    func didChangeAdjustMenuBarTint(_ newValue: Bool) {
        // A lock-screen picture stays either way: it is a setting of its own, and already the
        // scene's picture.
        let showsLockPicture = NSScreen.main.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
            .map(LockScreenPicture.current.isLockPicture) ?? false
        guard !showsLockPicture else { return }
        if newValue != true {
            if DesktopSnapshotCache.mayChangeDesktopPicture, let wallpaper = UserDefaults.app.url(forKey: "OSWallpaper") {
                try? NSWorkspace.shared.setDesktopImageURL(wallpaper, for: .main!)
            }
        } else {
            DesktopSnapshotCache.restoreDesktopPicture(for: NSScreen.main.map { [$0] } ?? [])
        }
    }
    
    /// The lock screen shows the scene again, or the user's own pictures come back (and the menu
    /// bar tint's picture of a video or web wallpaper, when that is on).
    func didChangeLockScreenPicture(_ newValue: Bool) {
        let wallpaper = AppDelegate.shared.wallpaperViewModel.currentWallpaper
        if newValue {
            LockScreenPicture.apply(wallpaper)
        } else {
            LockScreenPicture.restore()
            if settings.adjustMenuBarTint { AppDelegate.shared.setPlacehoderWallpaper(with: wallpaper) }
        }
    }

    func didCurrentWallpaperChange(_ newValue: WEWallpaper) {
        AppDelegate.shared.setPlacehoderWallpaper(with: newValue)
    }
    
    func reset() {
        settings = (try? JSONDecoder()
            .decode(GlobalSettings.self,
                from: UserDefaults.app.data(forKey: "GlobalSettings")
            ?? Data()))
        ?? GlobalSettings()
    }
    
    func save() {
        let data = try! JSONEncoder().encode(settings)
        OWELog.debug(.settings, "Saved settings: \(String(describing: String(data: data, encoding: .utf8)))")
        UserDefaults.app.set(data, forKey: "GlobalSettings")
    }

    func setQuality(_ quality: GSQuality) {
        self.settings.shadows = quality.shadows
        self.settings.volumetrics = quality.volumetrics
        self.settings.qualityEfficiency = QualityEfficiency(preset: quality).stop
        self.settings.fps = quality.fps
        self.settings.fpsSetByUser = false
        self.settings.applyResolutionPreset(quality)
        switch quality {
        case .low:
            self.settings.antiAliasing = .none
            self.settings.postProcessing = .disabled
            self.settings.textureResolution = .highQuality
            self.settings.reflections = false
            self.settings.particleBudget = .low
        case .medium:
            self.settings.antiAliasing = .none
            self.settings.postProcessing = .enabled
            self.settings.textureResolution = .highQuality
            self.settings.reflections = true
            self.settings.particleBudget = .medium
        case .high:
            self.settings.antiAliasing = .msaa_x2
            self.settings.postProcessing = .enabled
            self.settings.textureResolution = .highQuality
            self.settings.reflections = true
            self.settings.particleBudget = .high
        case .ultra:
            self.settings.antiAliasing = .msaa_x2
            self.settings.postProcessing = .ultra
            self.settings.textureResolution = .highQuality
            self.settings.reflections = true
            self.settings.particleBudget = .unlimited
        }
    }
    
    private func validate() {
        switch settings.appearance {
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        case .followSystem:
            NSApp.appearance = nil
        }
    }
}
