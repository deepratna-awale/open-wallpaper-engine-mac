import AppKit
import Combine

extension Notification.Name {
    /// A web wallpaper's page drew a snapshot for the desktop picture; the object is a
    /// `WebWallpaperPageSnapshot`. Posted on the main thread.
    static let webWallpaperPageSnapshot = Notification.Name("OpenWallpaperEngine.webWallpaperPageSnapshot")
}

/// A web wallpaper page's snapshot (`Notification.Name.webWallpaperPageSnapshot`).
struct WebWallpaperPageSnapshot {
    var wallpaperDirectory: URL
    var image: CGImage
}

/// The app's side of the desktop pictures (`DesktopPictureSync`): on while Settings shows the
/// wallpaper on the lock screen or tints the menu bar with it (both read the desktop picture), and
/// only in a copy that may change it (`DesktopSnapshotCache.mayChangeDesktopPicture`).
///
/// It plans every display from the wallpapers each one shows (clones, stretches, splits, display
/// options), and updates after any of those change, a scene saves a snapshot or a page draws one.
/// A Space change, a wake or a display change shows the current pictures again, since macOS
/// sets a picture on the current Space only. Turning both settings off, or quitting, puts the
/// user's pictures back. Theming's menu bar strips (`DesktopPictureTheming`) are read at each
/// refresh, and theming refreshes when they change.
@MainActor
final class DesktopPictureController {
    private static let fallbackKey = "OSWallpaper"

    let sync: DesktopPictureSync
    private let mayChange: Bool
    private weak var viewModel: WallpaperViewModel?
    private weak var settings: GlobalSettingsViewModel?
    private var cancellables = Set<AnyCancellable>()
    private var wasActive = false

    init(sync: DesktopPictureSync, mayChange: Bool = DesktopSnapshotCache.mayChangeDesktopPicture) {
        self.sync = sync
        self.mayChange = mayChange
    }

    static func system() -> DesktopPictureController {
        DesktopPictureController(sync: DesktopPictureSync(setter: SystemDesktopPictures(), files: .current,
                                                          loader: .current))
    }

    /// Whether the desktop pictures follow the wallpapers.
    var isActive: Bool {
        guard mayChange, let settings = settings?.settings else { return false }
        return settings.lockScreenPicture || settings.adjustMenuBarTint
    }

    private var displays: [DesktopPicturePlan.Display] {
        NSScreen.screens.compactMap { screen in
            DesktopSnapshotCache.displayID(screen).map {
                DesktopPicturePlan.Display(id: $0, frame: screen.frame, scale: screen.backingScaleFactor)
            }
        }
    }

    func observe(_ viewModel: WallpaperViewModel, settings: GlobalSettingsViewModel) {
        self.viewModel = viewModel
        self.settings = settings
        guard mayChange else { return }
        saveUsersPicture()
        let center = NotificationCenter.default
        center.publisher(for: .webWallpaperPageSnapshot)
            .sink { [weak self] note in
                MainActor.assumeIsolated {
                    guard let page = note.object as? WebWallpaperPageSnapshot else { return }
                    self?.sync.webFrameCaptured(page.image, wallpaperDirectory: page.wallpaperDirectory)
                }
            }
            .store(in: &cancellables)
        let changes: [AnyPublisher<Void, Never>] = [
            viewModel.$wallpapers.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$layoutResolution.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$wallpaperPlacement.map { _ in () }.eraseToAnyPublisher(),
            viewModel.displayOptions.$entries.map { _ in () }.eraseToAnyPublisher(),
            settings.$settings.map { [$0.lockScreenPicture, $0.adjustMenuBarTint] }.removeDuplicates()
                .map { _ in () }.eraseToAnyPublisher(),
            center.publisher(for: .sceneLoadingSnapshotSaved).map { _ in () }.eraseToAnyPublisher(),
            center.publisher(for: .webWallpaperPageSnapshot).map { _ in () }.eraseToAnyPublisher(),
        ]
        // `@Published` emits before it stores: the debounce reads the stored values.
        Publishers.MergeMany(changes)
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] in MainActor.assumeIsolated { self?.refresh() } }
            .store(in: &cancellables)
        let workspace = NSWorkspace.shared.notificationCenter
        let reasserts: [AnyPublisher<Void, Never>] = [
            workspace.publisher(for: NSWorkspace.activeSpaceDidChangeNotification).map { _ in () }.eraseToAnyPublisher(),
            workspace.publisher(for: NSWorkspace.didWakeNotification).map { _ in () }.eraseToAnyPublisher(),
            workspace.publisher(for: NSWorkspace.screensDidWakeNotification).map { _ in () }.eraseToAnyPublisher(),
            center.publisher(for: NSApplication.didChangeScreenParametersNotification).map { _ in () }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(reasserts)
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] in MainActor.assumeIsolated { self?.reassert() } }
            .store(in: &cancellables)
    }

    /// Updates every display's picture, or puts the user's back when the pictures were just
    /// turned off.
    func refresh() {
        guard isActive else {
            if wasActive { restoreUsersPictures() }
            return
        }
        wasActive = true
        guard let viewModel else { return }
        let plans = DesktopPicturePlan.plans(
            displays: displays, resolution: viewModel.layoutResolution,
            wallpaper: { id in
                let wallpaper = viewModel.wallpaper(for: id)
                return wallpaper.project == .invalid ? nil : wallpaper
            },
            options: { viewModel.displayOptions(on: $0) })
        let placement = viewModel.wallpaperPlacement
        let strips = DesktopPictureTheming.strips()
        Task { await sync.update(plans, placement: placement, strips: strips) }
    }

    /// The current Space, a wake or a display change may show another picture: shows each
    /// display's own again, and draws the displays that have none yet.
    func reassert() {
        guard isActive else { return }
        if !sync.reassert(displays.map(\.id)).isEmpty { refresh() }
    }

    /// Puts the user's pictures back on the connected displays (Settings turned the pictures off,
    /// or the app quits).
    func restoreUsersPictures() {
        wasActive = false
        guard mayChange else { return }
        sync.restoreUsersPictures(displays.map(\.id), fallback: UserDefaults.app.url(forKey: Self.fallbackKey))
    }

    /// Saves the main display's picture as the user's (`OSWallpaper`), the fallback for a
    /// display with no recorded picture, unless it is one of OWE's (an earlier run that ended
    /// without restoring it) or gone.
    private func saveUsersPicture() {
        let showing = NSScreen.screens.first.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
        let saved = UserDefaults.app.url(forKey: Self.fallbackKey)
        if let picture = sync.files.userPicture(saved: saved, showing: showing) {
            UserDefaults.app.set(picture, forKey: Self.fallbackKey)
        } else if saved != nil {
            UserDefaults.app.removeObject(forKey: Self.fallbackKey)
        }
    }
}
