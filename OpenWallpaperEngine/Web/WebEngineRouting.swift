import Combine
import Foundation

extension Notification.Name {
    /// Posted when the Chromium engine is installed, updated or removed, or its switch changes.
    static let chromiumEngineChanged = Notification.Name("ChromiumEngineChanged")
}

/// Which engine plays web wallpapers (and WebM video through a web page).
enum WebEngine: String, Equatable {
    case webKit
    case chromium
}

/// The routing rule: every web wallpaper plays in Chromium while the engine is installed and
/// switched on (Settings › Plugins), otherwise in the system's WebKit. There is no per-wallpaper
/// choice: a wallpaper that needs Chromium is pointed out instead (`ChromiumFeatureAdvisor`).
enum WebEngineRouting {
    /// `UserDefaults.app`: whether an installed Chromium engine plays web wallpapers (default on).
    static let enabledKey = "ChromiumEngineEnabled"

    static func engine(installed: Bool, enabled: Bool) -> WebEngine {
        installed && enabled ? .chromium : .webKit
    }

    static func isEnabled(in defaults: UserDefaults = .app) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? true
    }

    /// The engine for web wallpapers now, read from disk and the setting.
    static func current(root: URL = ChromiumEngineInstaller.defaultRoot, defaults: UserDefaults = .app) -> WebEngine {
        engine(installed: ChromiumEngineInstallation.activeInstall(in: root) != nil, enabled: isEnabled(in: defaults))
    }
}

/// The active Chromium engine on disk, readable from anywhere (the installer is main-actor bound).
enum ChromiumEngineInstallation {
    /// The active install's folder, nil without a complete one.
    static func activeInstall(in root: URL = ChromiumEngineInstaller.defaultRoot) -> URL? {
        guard let active = ChromiumEngineInstallState.read(in: root).active else { return nil }
        let folder = root.appending(path: active, directoryHint: .isDirectory)
        return ChromiumEnginePackage.manifest(in: folder) != nil ? folder : nil
    }

    static func profileDirectory(in root: URL = ChromiumEngineInstaller.defaultRoot) -> URL {
        root.appending(path: ".profile", directoryHint: .isDirectory)
    }
}

/// The engine wallpaper views route by, republished when the engine or its switch changes so the
/// views showing web wallpapers are rebuilt on the other engine.
@MainActor
final class WebEngineRouter: ObservableObject {
    static let shared = WebEngineRouter()

    @Published private(set) var engine: WebEngine
    private var observer: NSObjectProtocol?
    private let resolve: () -> WebEngine

    init(resolve: @escaping () -> WebEngine = { WebEngineRouting.current() }) {
        self.resolve = resolve
        engine = resolve()
        observer = NotificationCenter.default.addObserver(forName: .chromiumEngineChanged, object: nil,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func refresh() {
        let engine = resolve()
        if engine != self.engine {
            OWELog.info(.web, "Web wallpapers now play in \(engine == .chromium ? "Chromium" : "WebKit")")
            self.engine = engine
        }
    }
}
