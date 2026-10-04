import AppKit
import Combine
import OWETheming

/// Settings › General › Theming: macOS follows the main display's wallpaper's scheme colour
/// (docs/theming.md). The colour and the system preferences come from `OWETheming`; this owns
/// when they apply: when the wallpaper, its scheme colour, the screens or the settings change,
/// debounced. The preferences go through `SystemThemeApplier` (originals saved first, restored
/// when a checkbox or the master switch goes off, on quit when chosen, and after a crash at the
/// next launch). The menu bar strips are drawn into the desktop pictures OWE sets
/// (`DesktopPictureTheming`).
@MainActor
final class ThemingController: ObservableObject {
    /// The colour applied now; nil when theming is off or the wallpaper has none.
    @Published private(set) var color: ThemeColor?
    /// Whether the colour is the snapshot's main colour rather than a scheme colour.
    @Published private(set) var isDerivedColor = false
    /// The icon style or tint changed since the Dock last started: it shows once the Dock restarts.
    @Published private(set) var needsDockRestart = false

    private let writer: SystemAppearanceWriter
    private let applier: SystemThemeApplier
    private let services: WallpaperServices
    /// Shows the current wallpaper's desktop pictures again, so they get (or lose) the strip.
    private let refreshDesktopPictures: () -> Void
    private var settings = ThemingSettings()
    private weak var wallpaperViewModel: WallpaperViewModel?
    private var cancellables: [AnyCancellable] = []
    private var observers: [NSObjectProtocol] = []
    private var pending: DispatchWorkItem?
    /// Bumped by every update, so a dominant colour found for an older one is dropped.
    private var generation = 0
    private(set) var strips: DesktopPictureStrips?

    static let debounce: TimeInterval = 0.4
    private static let queue = DispatchQueue(label: "OWE.Theming", qos: .utility)

    init(writer: SystemAppearanceWriter, store: ThemingJournalStore, services: WallpaperServices = .shared,
         refreshDesktopPictures: @escaping () -> Void) {
        self.writer = writer
        applier = SystemThemeApplier(writer: writer, store: store)
        self.services = services
        self.refreshDesktopPictures = refreshDesktopPictures
    }

    /// The app's controller: the real preferences, or none written in an isolated copy (tests,
    /// development copies), which never change the Mac's settings.
    static func make(refreshDesktopPictures: @escaping () -> Void) -> ThemingController {
        let isolated: Bool = AppStorageLocation.current.isIsolated
        let writer: SystemAppearanceWriter = isolated ? ReadOnlyAppearanceWriter() : GlobalPreferencesWriter()
        let store = UserDefaultsJournalStore(defaults: .app, logError: { OWELog.error(.settings, "\($0)") })
        return ThemingController(writer: writer, store: store, refreshDesktopPictures: refreshDesktopPictures)
    }

    // MARK: Lifecycle

    /// At launch: puts back what a crashed session changed, then follows the settings and the
    /// main display's wallpaper.
    func start(settings: AnyPublisher<ThemingSettings, Never>, wallpapers: WallpaperViewModel) {
        if applier.recoverAfterUncleanExit() {
            OWELog.info(.settings, "Theming: restored the system colours a session that didn't quit left changed")
        }
        wallpaperViewModel = wallpapers
        cancellables = [
            settings.removeDuplicates().sink { [weak self] value in
                self?.settings = value
                self?.schedule()
            },
            wallpapers.$wallpapers.map { _ in () }.sink { [weak self] in self?.schedule() },
        ]
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .sceneUserPropertiesDidChange, object: nil, queue: .main) { [weak self] note in
                let keys = note.userInfo?["keys"] as? [String] ?? []
                guard keys.contains(SchemeColorSource.propertyName) else { return }
                MainActor.assumeIsolated { self?.schedule() }
            },
            center.addObserver(forName: .wallpaperPropertiesDidSave, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.schedule() }
            },
            center.addObserver(forName: .sceneLoadingSnapshotSaved, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.settings.usesDominantColor, !self.isUsingSchemeColor else { return }
                    self.schedule()
                }
            },
            center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil,
                               queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.schedule() }
            },
        ]
    }

    /// On quit: the originals go back when the user chose "Restore on quit".
    func stop() {
        pending?.cancel()
        cancellables = []
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        applier.endSession(restoring: settings.restoresOnQuit)
    }

    // MARK: Updating

    private var isUsingSchemeColor: Bool { color != nil && !isDerivedColor }

    /// Updates after the changes settle.
    func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.update() } }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounce, execute: work)
    }

    private func update() {
        generation &+= 1
        guard settings.wantsColor, let model = wallpaperViewModel else {
            apply(nil, derived: false)
            return
        }
        let screenId = WallpaperViewModel.mainScreenId()
        let wallpaper = model.wallpaper(for: screenId)
        let scope = model.propertyScope(for: screenId)
        let scheme = SchemeColorSource.resolve(
            running: services.userProperties(wallpaper: scope.runtimeKey(directory: wallpaper.settingsDirectory)),
            userSet: WallpaperSettingsIdentity.resolve(wallpaper).userSetValues(scope: scope),
            projectValue: wallpaper.project.general?.properties.schemecolor?.value)
        if let scheme {
            apply(scheme, derived: false)
            return
        }
        guard settings.usesDominantColor else {
            apply(nil, derived: false)
            return
        }
        let generation = generation
        let candidates = pictureCandidates(for: wallpaper)
        Self.queue.async { [weak self] in
            let dominant: ThemeColor? = Self.dominantColor(of: candidates)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.generation == generation else { return }
                    self.apply(dominant, derived: dominant != nil)
                }
            }
        }
    }

    private func apply(_ newColor: ThemeColor?, derived: Bool) {
        let desired = ThemePlan.preferences(for: newColor, settings: settings,
                                            currentIconTheme: writer.value(for: .iconAppearanceTheme))
        let written = applier.apply(desired)
        if written.contains(where: { $0.change == .iconAppearance }) { needsDockRestart = true }
        if !written.isEmpty { OWELog.info(.settings, "Theming: wrote \(written.map(\.rawValue).sorted())") }
        if color != newColor { color = newColor }
        if isDerivedColor != derived { isDerivedColor = derived }

        let newStrips: DesktopPictureStrips? = settings.wantsMenuBarStrip ? newColor.map {
            DesktopPictureStrips(color: $0, displays: Self.stripDisplays(NSScreen.screens))
        } : nil
        guard newStrips != strips else { return }
        strips = newStrips
        refreshDesktopPictures()
    }

    /// Restarts the Dock, which shows a new icon style or tint when it starts. Only on the user's
    /// click ("Apply now"); never automatically.
    func restartDock() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        do {
            try process.run()
            needsDockRestart = false
        } catch {
            OWELog.error(.settings, "Theming: restarting the Dock failed: \(error)")
        }
    }

    // MARK: Pictures

    /// The menu bar strip geometry of `screens`, by display id.
    static func stripDisplays(_ screens: [NSScreen]) -> [UInt32: MenuBarStripDisplay] {
        var displays: [UInt32: MenuBarStripDisplay] = [:]
        for screen in screens {
            guard let id = DesktopSnapshotCache.displayID(screen) else { continue }
            let height = MenuBarStrip.height(frame: screen.frame, visibleFrame: screen.visibleFrame,
                                             safeAreaTop: screen.safeAreaInsets.top)
            guard height > 0 else { continue }
            displays[id] = MenuBarStripDisplay(size: screen.frame.size, menuBarHeight: height)
        }
        return displays
    }

    /// Where the main display's wallpaper has a picture, best first: its scene snapshot, the
    /// desktop picture OWE made of it, its Workshop preview. Resolved off the main thread.
    private func pictureCandidates(for wallpaper: WEWallpaper) -> PictureCandidates {
        let main = NSScreen.main
        let size = main.map { SIMD2(Int($0.frame.width * $0.backingScaleFactor), Int($0.frame.height * $0.backingScaleFactor)) }
        return PictureCandidates(
            isScene: wallpaper.project.type.caseInsensitiveCompare("scene") == .orderedSame,
            directory: wallpaper.wallpaperDirectory,
            pixelSize: size ?? SIMD2(1920, 1080),
            displayID: main.flatMap(DesktopSnapshotCache.displayID),
            preview: wallpaper.project.preview.map { wallpaper.wallpaperDirectory.appending(path: $0) })
    }

    struct PictureCandidates: Sendable {
        var isScene: Bool
        var directory: URL
        var pixelSize: SIMD2<Int>
        var displayID: CGDirectDisplayID?
        var preview: URL?
    }

    nonisolated private static func dominantColor(of candidates: PictureCandidates) -> ThemeColor? {
        ThreadGuards.assertBackground("ThemingController.dominantColor")
        var urls: [URL] = []
        if candidates.isScene, let snapshot = SceneLoadingSnapshotStore.current.bestSnapshot(
            forWallpaperAt: candidates.directory, pixelSize: candidates.pixelSize) {
            urls.append(snapshot)
        }
        if !candidates.isScene, let id = candidates.displayID,
           let desktop = DesktopSnapshotCache.current.existingURL(display: id) {
            urls.append(desktop)
        }
        if let preview = candidates.preview { urls.append(preview) }
        for url in urls {
            if let color = DominantColor.of(fileAt: url) { return color }
        }
        return nil
    }
}
