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
    
    init() {
        let loaded: GlobalSettings
        if let data = UserDefaults.app.data(forKey: "GlobalSettings"),
           let settings = try? JSONDecoder().decode(GlobalSettings.self, from: data) {
            loaded = settings
        } else {
            loaded = GlobalSettings()
        }
        self.settings = loaded
        languageChange = LanguageChange(atLaunch: loaded.language)
        OWELog.apply(logLevel: settings.logLevel)

        // Add observers
        self.didFinishLaunchingNotificationCancellable =
        NotificationCenter.default.publisher(for: NSApplication.didFinishLaunchingNotification)
            .sink { [weak self] _ in self?.didFinishLaunchingNotification() }
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
            .map { $0.screenSaver }
            .removeDuplicates()
            .dropFirst()
            .sink { enabled in
                AppDelegate.shared.screenSaver.update(enabled: enabled,
                                                      wallpaper: AppDelegate.shared.wallpaperViewModel.currentWallpaper)
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
    
    private func saveAndValidate() {
        save()
        validate()
    }
}
