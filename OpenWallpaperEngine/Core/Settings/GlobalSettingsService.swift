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
            Self.store(settings)
            scheduleSave()
            if settings.appearance != oldValue.appearance { validate() }
            OWELog.apply(logLevel: settings.logLevel)
            // Only on a change: following the system mustn't clear a language set in System Settings.
            if settings.language != oldValue.language { settings.language.apply(to: .app) }
        }
    }
    
    /// The settings as last set, readable from any thread without touching UserDefaults or the
    /// main actor (render and video loops, preparation jobs).
    nonisolated static var current: GlobalSettings {
        currentLock.lock(); defer { currentLock.unlock() }
        return _current ?? GlobalSettings()
    }
    nonisolated private static let currentLock = NSLock()
    nonisolated(unsafe) private static var _current: GlobalSettings?
    nonisolated private static func store(_ settings: GlobalSettings) {
        currentLock.lock(); _current = settings; currentLock.unlock()
    }

    /// Several changes in one turn of the run loop (a quality preset sets seven) save once.
    private var savePending = false

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
    
    init() {
        let loaded: GlobalSettings
        if let data = UserDefaults.app.data(forKey: "GlobalSettings"),
           let settings = try? JSONDecoder().decode(GlobalSettings.self, from: data) {
            loaded = settings
        } else {
            loaded = GlobalSettings()
        }
        self.settings = loaded
        Self.store(loaded)
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
        if newValue != true {
            if let wallpaper = UserDefaults.app.url(forKey: "OSWallpaper") {
                try? NSWorkspace.shared.setDesktopImageURL(wallpaper, for: .main!)
            }
        } else {
            DesktopSnapshotCache.restoreDesktopPicture(for: NSScreen.main.map { [$0] } ?? [])
        }
    }
    
    func didCurrentWallpaperChange(_ newValue: WEWallpaper) {
        AppDelegate.shared.setPlacehoderWallpaper(with: newValue)
    }
    
    func reset() {
        flushPendingSave()
        settings = (try? JSONDecoder()
            .decode(GlobalSettings.self,
                from: UserDefaults.app.data(forKey: "GlobalSettings")
            ?? Data()))
        ?? GlobalSettings()
    }
    
    private func scheduleSave() {
        guard !savePending else { return }
        savePending = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.flushPendingSave() }
        }
    }

    /// Writes a save still waiting for the end of the run-loop turn.
    func flushPendingSave() {
        guard savePending else { return }
        savePending = false
        save()
    }

    func save() {
        let data = try! JSONEncoder().encode(settings)
        OWELog.debug(.settings, "Saved settings: \(String(describing: String(data: data, encoding: .utf8)))")
        UserDefaults.app.set(data, forKey: "GlobalSettings")
    }

    func setQuality(_ quality: GSQuality) {
        self.settings.shadows = quality.shadows
        self.settings.volumetrics = quality.volumetrics
        switch quality {
        case .low:
            self.settings.antiAliasing = .none
            self.settings.postProcessing = .disabled
            self.settings.textureResolution = .highQuality
            self.settings.fps = 10
            self.settings.reflections = false
            self.settings.particleBudget = .low
        case .medium:
            self.settings.antiAliasing = .none
            self.settings.postProcessing = .enabled
            self.settings.textureResolution = .highQuality
            self.settings.fps = 15
            self.settings.reflections = true
            self.settings.particleBudget = .medium
        case .high:
            self.settings.antiAliasing = .msaa_x2
            self.settings.postProcessing = .enabled
            self.settings.textureResolution = .highQuality
            self.settings.fps = 25
            self.settings.reflections = true
            self.settings.particleBudget = .high
        case .ultra:
            self.settings.antiAliasing = .msaa_x2
            self.settings.postProcessing = .ultra
            self.settings.textureResolution = .highQuality
            self.settings.fps = 30
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
        flushPendingSave()
        save()
        validate()
    }
}
