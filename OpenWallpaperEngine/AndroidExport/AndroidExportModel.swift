import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// "Export for Android…": the sheet's state for one wallpaper or a library selection, as WE's
/// "Exporting … for usage on Android" dialog has it (`AndroidExportOptions`), the pre-rendered
/// crop's live preview in an isolated session (`IsolatedSceneEditSession`, never the desktop's
/// instance or stores), and the export queue (`AndroidExportQueue`).
@MainActor
final class AndroidExportModel: ObservableObject {
    /// The isolated session's purpose (`WallpaperPropertyScope.isolated`).
    static let purpose = "android-export"
    /// The folder exports last went to, and whether they go there without asking.
    static let folderKey = "AndroidExportFolder"
    static let usesFolderKey = "AndroidExportUsesFolder"

    struct Row: Identifiable, Equatable {
        let wallpaper: WEWallpaper
        /// Why it isn't exported; nil when it is.
        let skipReason: String?
        var id: String { wallpaper.identityPath }
        var kind: AndroidPackageBuilder.Kind? { AndroidPackageBuilder.kind(of: wallpaper) }
        var isScene: Bool { skipReason == nil && kind == .scene }

        static func == (lhs: Row, rhs: Row) -> Bool { lhs.id == rhs.id && lhs.skipReason == rhs.skipReason }
    }

    let rows: [Row]
    /// The options every scene shares; `modes` overrides a scene's mode.
    @Published var options = AndroidExportOptions(mode: .balanced) {
        didSet { if options.mode != oldValue.mode { modes = [:] } }
    }
    @Published var modes: [String: AndroidExportOptions.Mode] = [:]
    @Published var showsAdvancedSettings = false
    /// The scene the crop preview shows.
    @Published private(set) var previewID: String?
    @Published private(set) var sceneSize: SIMD2<Double>?
    @Published private(set) var session: IsolatedSceneEditSession?
    @Published private(set) var queue: AndroidExportQueue?
    @Published private(set) var batch: AndroidExportBatch?
    @Published var errorMessage: String?
    @Published var usesFolder: Bool {
        didSet { defaults.set(usesFolder, forKey: Self.usesFolderKey) }
    }
    @Published private(set) var folder: URL?

    private let defaults: UserDefaults
    private let scopes: (WEWallpaper) -> [WallpaperPropertyScope]
    private let worker: AndroidExportWorking
    private var sceneSizeTask: Task<Void, Never>?

    /// `scopes` names the stores whose values a wallpaper's pre-render starts from (the
    /// displays' that show it, as the Scene Editor (Live) copies them).
    init(wallpapers: [WEWallpaper], scopes: @escaping (WEWallpaper) -> [WallpaperPropertyScope],
         defaults: UserDefaults = .app, worker: AndroidExportWorking? = nil) {
        var seen = Set<String>()
        rows = wallpapers.filter { seen.insert($0.identityPath).inserted }
            .map { Row(wallpaper: $0, skipReason: AndroidExportPlan.skipReason($0)) }
        self.scopes = scopes
        self.defaults = defaults
        self.worker = worker ?? AndroidExporter()
        usesFolder = defaults.bool(forKey: Self.usesFolderKey)
        folder = defaults.string(forKey: Self.folderKey).map { URL(filePath: $0, directoryHint: .isDirectory) }
        showPreview(of: rows.first(where: \.isScene)?.id)
    }

    var title: String { rows.count == 1 ? rows[0].wallpaper.project.displayTitle : String(localized: "\(rows.count) wallpapers") }
    var exportable: [Row] { rows.filter { $0.skipReason == nil } }
    var hasScenes: Bool { rows.contains(where: \.isScene) }

    func mode(of row: Row) -> AndroidExportOptions.Mode { modes[row.id] ?? options.mode }

    func setMode(_ mode: AndroidExportOptions.Mode, of row: Row) {
        modes[row.id] = mode == options.mode ? nil : mode
        if mode == .preRendered { showPreview(of: row.id) }
    }

    /// Whether any scene is pre-rendered (the video options show).
    var hasPreRendered: Bool { rows.contains { $0.isScene && mode(of: $0) == .preRendered } }
    var hasDynamic: Bool { rows.contains { $0.isScene && mode(of: $0) != .preRendered } }

    /// A row's options: the shared ones with its own mode.
    func options(for row: Row) -> AndroidExportOptions {
        var options = options
        options.mode = mode(of: row)
        return options
    }

    // MARK: Preview

    var previewWallpaper: WEWallpaper? { rows.first { $0.id == previewID }?.wallpaper }

    /// The portrait crop of the previewed scene.
    var crop: LivePhotoCrop? { sceneSize.map { options.crop(sceneSize: $0) } }

    func showPreview(of id: String?) {
        guard id != previewID else { return }
        session?.end()
        session = nil
        sceneSize = nil
        previewID = id
        sceneSizeTask?.cancel()
        guard let wallpaper = previewWallpaper else { return }
        session = IsolatedSceneEditSession(wallpaper: wallpaper, purpose: Self.purpose, seededFrom: scopes(wallpaper))
        sceneSizeTask = Task { [weak self] in
            do {
                let size = try await Task.detached(priority: .userInitiated) { try AndroidPackageBuilder.sceneSize(wallpaper) }.value
                guard let self, self.previewID == id else { return }
                self.sceneSize = size
            } catch {
                OWELog.error(.app, "Android export: \(wallpaper.wallpaperDirectory.lastPathComponent)'s size can't be read: \(error)")
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    /// Ends the preview's session (the sheet closed).
    func close() {
        queue?.cancel()
        sceneSizeTask?.cancel()
        session?.end()
        session = nil
    }

    // MARK: Export

    /// The values a scene's pre-render uses: the preview session's for the previewed scene,
    /// else what the Scene Editor (Live) would copy.
    func properties(of wallpaper: WEWallpaper) -> [String: String] {
        if let session, session.wallpaper.identityPath == wallpaper.identityPath, !session.isEnded { return session.values }
        return IsolatedSceneEditSession.seed(of: wallpaper, from: scopes(wallpaper), defaults: defaults)
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = folder
        panel.prompt = String(localized: "Choose")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        remember(url)
    }

    private func remember(_ url: URL) {
        folder = url
        defaults.set(url.path(percentEncoded: false), forKey: Self.folderKey)
    }

    /// Asks where the packages go (unless they go to the remembered folder) and exports them.
    func export() {
        guard queue == nil || queue?.isRunning == false else { return }
        let exportRows = exportable
        guard !exportRows.isEmpty else { return }
        var target: (folder: URL, taken: Set<String>?)?
        if usesFolder, let folder, FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) {
            target = (folder, nil)
        } else if exportRows.count == 1 {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = AndroidExportNaming.uniqueNames([exportRows[0].wallpaper.project.displayTitle], taken: []).first ?? ""
            panel.allowedContentTypes = [UTType(filenameExtension: AndroidExportNaming.fileExtension) ?? .data]
            panel.directoryURL = folder
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            remember(url.deletingLastPathComponent())
            start(rows: exportRows, folder: url.deletingLastPathComponent(), names: [url.lastPathComponent])
            return
        } else {
            chooseFolder()
            guard let folder else { return }
            target = (folder, nil)
        }
        guard let target else { return }
        start(rows: exportRows, folder: target.folder, names: nil, taken: target.taken)
    }

    private func start(rows exportRows: [Row], folder: URL, names: [String]?, taken: Set<String>? = nil) {
        let skipped = rows.compactMap { row in
            row.skipReason.map { AndroidExportBatch.Skipped(wallpaperID: row.id, title: row.wallpaper.project.displayTitle, reason: $0) }
        }
        let items = exportRows.map { row in
            var item = AndroidExportItem(wallpaper: row.wallpaper, options: options(for: row))
            if item.usesGPU { item.properties = properties(of: row.wallpaper) }
            return item
        }
        let queue = AndroidExportQueue(items: items, skipped: skipped, folder: folder, taken: names.map { _ in [] } ?? taken,
                                       names: names, worker: worker)
        self.queue = queue
        batch = nil
        errorMessage = nil
        Task { [weak self] in
            let batch = await queue.run()
            self?.batch = batch
        }
    }

    func cancelExport() { queue?.cancel() }

    func showInFinder() {
        guard let batch else { return }
        if batch.urls.isEmpty {
            NSWorkspace.shared.open(batch.folder)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(batch.urls)
        }
    }
}
