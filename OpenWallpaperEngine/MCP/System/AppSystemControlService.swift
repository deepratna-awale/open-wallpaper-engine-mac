import AppKit
import OWEControlProtocol

/// The app's system features for the control channel, through the code their own controls run:
/// the Screen Saver mode's store and service (`ScreenSaverSettingsStore`,
/// `ScreenSaverRecordingService`), Settings › General's lock-screen
/// setting (`LockScreenPicture`), and the iPhone & iPad Export mode's render
/// (`AppSystemControlService+LivePhoto`). Nothing here opens a window or System Settings, or asks
/// macOS for a permission.
@MainActor
final class AppSystemControlService: SystemControlService {
    private unowned let app: AppDelegate
    let model: AppControlModel
    /// A Live Photo export from the control channel is rendering.
    var isExporting = false
    /// The "Send over Wi-Fi" an MCP client started; a new one replaces it.
    var wifiSession: AndroidWiFiSession?

    init(app: AppDelegate, model: AppControlModel) {
        self.app = app
        self.model = model
    }

    private var recordings: ScreenSaverRecordingService { app.screenSaverRecordings }
    private var store: ScreenSaverSettingsStore { recordings.store }

    /// The library's wallpaper `wallpaper` names.
    func found(_ wallpaper: ControlWallpaper) throws -> WEWallpaper {
        guard let found = model.find(wallpaper) else { throw AppControlModel.missing(wallpaper) }
        return found
    }

    /// The values Scene Edit / Export's isolated modes start from: the stores the editor edits.
    func wallpaperValues(of wallpaper: WEWallpaper) -> [String: String] {
        IsolatedSceneEditSession.seed(of: wallpaper, from: model.scopes(of: wallpaper), defaults: store.defaults)
    }

    // MARK: - Screen saver

    var screenSaver: SystemScreenSaverState {
        SystemScreenSaverState(pluginEnabled: app.globalSettingsViewModel.settings.screenSaver, selection: selection)
    }

    private var selection: SystemScreenSaverSelection? {
        func wallpaper(at path: String) -> ControlWallpaper? {
            InstalledLibrary.wallpaper(at: URL(filePath: path, directoryHint: .isDirectory), hiding: []).map { model.control($0) }
        }
        if let pick = recordings.livePick {
            return SystemScreenSaverSelection(wallpaper: wallpaper(at: pick.wallpaperDirectory), folder: pick.wallpaperDirectory,
                                              kind: .live, picked: pick.picked)
        }
        guard let selection = recordings.selection else { return nil }
        return SystemScreenSaverSelection(wallpaper: wallpaper(at: selection.wallpaperDirectory), folder: selection.wallpaperDirectory,
                                          kind: .video, picked: selection.recorded)
    }

    func layers(of wallpaper: ControlWallpaper) throws -> [SystemSceneLayer] {
        SystemSceneFile.layers(of: try SystemSceneFile.scene(of: found(wallpaper)))
    }

    func screenSaverValues(of wallpaper: ControlWallpaper) throws -> SystemScreenSaverValues {
        let found = try found(wallpaper)
        let identity = WallpaperSettingsIdentity.resolve(found, defaults: store.defaults)
        if let saved = store.values(for: identity) { return SystemScreenSaverValues(values: saved, isOwn: true) }
        return SystemScreenSaverValues(values: wallpaperValues(of: found), isOwn: false)
    }

    /// As `ScreenSaverEditorModel.persist` saves the mode's changes.
    func setScreenSaverValues(_ values: [String: String], of wallpaper: ControlWallpaper) throws -> Bool {
        let found = try found(wallpaper)
        let identity = WallpaperSettingsIdentity.resolve(found, defaults: store.defaults)
        let saved = store.values(for: identity)
        guard saved != values else { return saved != nil }
        if saved == nil, values == wallpaperValues(of: found) { return false }
        store.setValues(values, for: identity)
        OWELog.info(.app, "MCP: saved the screen saver's choices for \(found.wallpaperDirectory.lastPathComponent)")
        return true
    }

    /// As the mode's Set as Screen Saver: a scene is drawn live with the screen saver's own
    /// choices, else the wallpaper's; a video's own file is put in place.
    func setScreenSaver(_ wallpaper: ControlWallpaper) async throws -> SystemScreenSaverSet {
        let found = try found(wallpaper)
        guard !recordings.isRecording else {
            throw ControlError(.unavailable, "A video is being set as the screen saver. Wait for it to finish, then try again.")
        }
        let values = try screenSaverValues(of: wallpaper).values
        let wasEnabled = app.globalSettingsViewModel.settings.screenSaver
        let recordings = recordings
        OWELog.info(.app, "MCP: setting \(found.wallpaperDirectory.lastPathComponent) as the screen saver")
        let succeeded = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            recordings.set(found, values: values) { continuation.resume(returning: $0) }
        }
        guard succeeded, let selection else {
            throw ControlError(.failed, "\"\(wallpaper.title)\" couldn't be set as the screen saver. The app's log says why: /usr/bin/log show --last 10m --predicate 'process == \"Open Wallpaper Engine\"' | grep 'Screen saver'.")
        }
        return SystemScreenSaverSet(selection: selection, enabledPlugin: !wasEnabled && screenSaver.pluginEnabled)
    }

    func stopUsingScreenSaver() {
        recordings.stopUsingSelection()
    }

    // MARK: - Lock screen

    var lockScreen: SystemLockScreenState {
        let picture = LockScreenPicture.current
        let current = app.wallpaperViewModel.currentWallpaper
        let displays = NSScreen.screens.map { screen in
            let id = WallpaperViewModel.screenId(for: screen)
            let url = NSWorkspace.shared.desktopImageURL(for: screen)
            return SystemLockScreenState.Display(id: id, name: WallpaperViewModel.screenName(for: screen),
                                                 wallpaper: model.wallpaper(onDisplay: id), picture: url,
                                                 isLockScreenPicture: url.map(picture.isLockPicture) ?? false)
        }
        return SystemLockScreenState(enabled: app.globalSettingsViewModel.settings.lockScreenPicture,
                                     mayChangeDesktopPicture: DesktopSnapshotCache.mayChangeDesktopPicture,
                                     follows: current.project == .invalid ? nil : model.control(current),
                                     displays: displays)
    }

    /// As the toggle does: the settings' observer applies or restores the pictures.
    func setLockScreenEnabled(_ enabled: Bool) {
        guard app.globalSettingsViewModel.settings.lockScreenPicture != enabled else { return }
        app.globalSettingsViewModel.settings.lockScreenPicture = enabled
    }

    /// Draws every display's desktop picture again from what it shows (`DesktopPictureController`).
    func refreshLockScreen() {
        app.desktopPictures.refresh()
    }
}
