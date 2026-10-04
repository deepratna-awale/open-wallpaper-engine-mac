import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// What the Android Export mode's Export Settings sheet was opened for.
enum AndroidEditorExportAction: String, Identifiable {
    case save, wifi

    var id: String { rawValue }
}

/// Which Android Export Settings sheet is open: opened from the toolbar, or before an export.
enum AndroidEditorSheet: Identifiable, Equatable {
    case settings
    case confirm(AndroidEditorExportAction)

    var id: String {
        switch self {
        case .settings: return "settings"
        case .confirm(let action): return action.rawValue
        }
    }
}

/// The Scene Editor (Live)'s Android Export mode: the wallpaper as it plays in the mode's private
/// instance (`IsolatedSceneEditSession`), framed as the chosen Android device's screen (or a
/// custom one), with the crop, the pointer and WE's `.mpkg` export (`AndroidExporter`):
/// Pre-Rendered renders this version as a video loop at the screen's pixels; Dynamic bakes its
/// layer edits and user properties into the package's files (`AndroidSceneBake`).
@MainActor
final class AndroidExportEditorModel: ObservableObject {
    /// The isolated session's purpose (`WallpaperPropertyScope.isolated`).
    static let purpose = "android-export-editor"
    /// The last device chosen ("custom" for the custom size) and the custom size, kept across launches.
    static let deviceKey = "AndroidExportEditorDevice"
    static let customSizeKey = "AndroidExportEditorCustomSize"
    static let customID = "custom"
    /// The loop's length: WE's 30 s by default.
    static let lengths = 5...60

    let wallpaper: WEWallpaper
    let sceneSize: SIMD2<Double>
    let session: IsolatedSceneEditSession
    let defaults: UserDefaults
    let identity: WallpaperSettingsIdentity
    /// The column of WE's preset table for this wallpaper (its resolution tags and size).
    let resolution: AndroidExportOptions.ResolutionClass
    private let worker: AndroidExportWorking

    /// The chosen device; nil is the custom size.
    @Published private(set) var device: AndroidDevice?
    /// The custom size's fields, as typed.
    @Published private(set) var customWidth: String
    @Published private(set) var customHeight: String
    /// The last valid custom size, which the preview and the export use.
    @Published private(set) var customSize: SIMD2<Int>
    /// Why the custom fields don't make a size; nil when they do.
    @Published private(set) var customIssue: AndroidCustomSize.Issue?
    /// A tablet in landscape: the video is made for the screen turned.
    @Published private(set) var isLandscape = false
    @Published var showsStatusBarGuide = true
    @Published private(set) var videoSize = AndroidVideoSize.screen
    @Published private(set) var crop: LivePhotoCrop
    /// Where the pointer rests in the preview and the video (`LivePhotoParallax`, kept per
    /// wallpaper, as the iPhone & iPad Export keeps it).
    @Published private(set) var parallaxPosition: SIMD2<Double>
    @Published private(set) var followsPointer: Bool?
    /// The package's options: Pre-Rendered (the default here) or Dynamic, and their settings.
    @Published var options = AndroidExportOptions(mode: .preRendered)
    /// The loop's length in seconds.
    @Published var seconds = AndroidExportOptions.videoSeconds
    @Published private(set) var queue: AndroidExportQueue?
    @Published private(set) var batch: AndroidExportBatch?
    @Published var errorMessage: String?
    @Published var sheet: AndroidEditorSheet?
    /// The batch "Send over Wi-Fi" serves while its sheet is open.
    @Published var wifiSend: AndroidWiFiSendRequest?

    init(session: IsolatedSceneEditSession, sceneSize: SIMD2<Double>, defaults: UserDefaults = .app,
         worker: AndroidExportWorking? = nil) {
        self.session = session
        wallpaper = session.wallpaper
        self.sceneSize = sceneSize
        self.defaults = defaults
        self.worker = worker ?? AndroidExporter()
        let stored = defaults.array(forKey: Self.customSizeKey) as? [Int]
        let custom = stored.flatMap { $0.count == 2 ? SIMD2($0[0], $0[1]) : nil }
            .flatMap { AndroidCustomSize.sides ~= $0.x && AndroidCustomSize.sides ~= $0.y ? $0 : nil } ?? AndroidCustomSize.defaultSize
        customSize = custom
        customWidth = String(custom.x)
        customHeight = String(custom.y)
        let id = defaults.string(forKey: Self.deviceKey)
        let device = id == Self.customID ? nil : AndroidDevice.device(id: id) ?? AndroidDevice.defaultDevice
        self.device = device
        crop = LivePhotoCrop(sceneSize: sceneSize, outputPixels: AndroidVideoSize.screen.pixels(for: device?.pixelSize ?? custom))
        identity = WallpaperSettingsIdentity.resolve(session.wallpaper, defaults: defaults)
        parallaxPosition = LivePhotoParallax.position(for: identity, defaults: defaults)
        resolution = .of(tags: session.wallpaper.project.tags ?? [], sceneSizes: [sceneSize])
        options = AndroidExportOptions(mode: .preRendered, resolution: resolution)
    }

    // MARK: Screen

    /// The screen the video is made for, in pixels, as it is held (a tablet turned in landscape).
    var screenPixels: SIMD2<Int> {
        let portrait = device?.pixelSize ?? customSize
        return isLandscape && device?.kind == .tablet ? SIMD2(portrait.y, portrait.x) : portrait
    }

    /// The video's pixels.
    var outputPixels: SIMD2<Int> { videoSize.pixels(for: screenPixels) }

    /// The screen's width over its height: the preview's shape.
    var aspect: Double { Double(screenPixels.x) / Double(max(screenPixels.y, 1)) }

    func choose(_ device: AndroidDevice?) {
        guard device != self.device else { return }
        self.device = device
        defaults.set(device?.id ?? Self.customID, forKey: Self.deviceKey)
        if device?.kind != .tablet { isLandscape = false }
        reframe()
    }

    func setLandscape(_ landscape: Bool) {
        guard device?.kind == .tablet, landscape != isLandscape else { return }
        isLandscape = landscape
        reframe()
    }

    func setVideoSize(_ size: AndroidVideoSize) {
        guard size != videoSize else { return }
        videoSize = size
        reframe()
    }

    /// The custom fields as typed: a valid size is used (and kept) at once.
    func setCustom(width: String, height: String) {
        customWidth = width
        customHeight = height
        switch AndroidCustomSize.validate(width: width, height: height) {
        case .success(let size):
            customIssue = nil
            guard size != customSize else { return }
            customSize = size
            defaults.set([size.x, size.y], forKey: Self.customSizeKey)
            if device == nil { reframe() }
        case .failure(let issue):
            customIssue = issue
        }
    }

    /// The crop at the new screen, keeping its zoom and centre.
    private func reframe() {
        crop = LivePhotoCrop(sceneSize: sceneSize, outputPixels: outputPixels, zoom: crop.zoom, center: crop.center)
    }

    // MARK: Crop and pointer

    var zoom: Double {
        get { crop.zoom }
        set { crop.setZoom(newValue) }
    }

    func pan(by delta: SIMD2<Double>) { crop.pan(by: delta) }

    func setParallaxPosition(_ position: SIMD2<Double>) {
        let position = LivePhotoParallax.clamped(position)
        guard position != parallaxPosition else { return }
        parallaxPosition = position
        LivePhotoParallax.setPosition(position, for: identity, defaults: defaults)
    }

    /// The private instance loaded `content`.
    func sceneLoaded(_ content: SceneMetalContent) {
        followsPointer = LivePhotoParallax.followsPointer(content)
    }

    /// How the preview draws the scene: as the video does (clocks drawn, as WE records them),
    /// with the same pointer.
    var presentation: SceneWallpaperInstance.Presentation {
        LivePhotoRenderer.presentation(pointer: parallaxPosition, hidesClockLayers: false)
    }

    // MARK: Output

    var isPreRendered: Bool { options.mode == .preRendered }

    /// Chooses the output's mode with WE's preset for this wallpaper.
    func chooseMode(_ mode: AndroidExportOptions.Mode) {
        guard mode != options.mode else { return }
        options.choose(mode, resolution: resolution)
    }

    func setSeconds(_ value: Int) { seconds = min(max(value, Self.lengths.lowerBound), Self.lengths.upperBound) }

    /// The package's item: this version's values and framing (Pre-Rendered), or the values baked
    /// into its files (Dynamic).
    var item: AndroidExportItem {
        var item = AndroidExportItem(wallpaper: wallpaper, options: options)
        let values = session.values
        if isPreRendered {
            item.properties = values
            item.framing = AndroidVideoFraming(crop: crop, pointer: parallaxPosition, seconds: seconds)
        } else {
            item.bakedValues = values
        }
        return item
    }

    /// The video's average bit rate: WE's ~8 Mbit/s at 1080×1920, 30 fps, in proportion to the pixels.
    var bitRate: Int { options.videoBitRate(pixelSize: outputPixels) }

    var isExporting: Bool { queue?.isRunning == true }

    // MARK: Export Settings sheet

    func requestExport(_ action: AndroidEditorExportAction) {
        guard !isExporting else { return }
        sheet = .confirm(action)
    }

    func showSettings() { sheet = .settings }

    /// Runs the export the sheet was opened for, once the sheet has closed.
    func confirm(_ action: AndroidEditorExportAction) {
        sheet = nil
        DispatchQueue.main.async { [weak self] in
            switch action {
            case .save: self?.save()
            case .wifi: self?.sendOverWiFi()
            }
        }
    }

    // MARK: Export

    /// Asks where the package goes and exports it.
    func save() {
        guard !isExporting else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = AndroidExportNaming.uniqueNames([wallpaper.project.displayTitle], taken: []).first ?? ""
        panel.allowedContentTypes = [UTType(filenameExtension: AndroidExportNaming.fileExtension) ?? .data]
        panel.canCreateDirectories = true
        if let folder = defaults.string(forKey: AndroidExportModel.folderKey) {
            panel.directoryURL = URL(filePath: folder, directoryHint: .isDirectory)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        defaults.set(url.deletingLastPathComponent().path(percentEncoded: false), forKey: AndroidExportModel.folderKey)
        export(to: url.deletingLastPathComponent(), name: url.lastPathComponent, then: nil)
    }

    /// Exports the package into the export cache and serves it over Wi-Fi.
    func sendOverWiFi() {
        guard !isExporting else { return }
        let folder = AndroidExporter.cacheDirectory.appending(path: "Packages", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        export(to: folder, name: nil) { [weak self] batch in
            self?.wifiSend = AndroidWiFiSendRequest(batch: batch)
        }
    }

    /// Exports `item` into `folder` (as `name`, else a unique name), then hands a finished batch to `then`.
    func export(to folder: URL, name: String?, then: ((AndroidExportBatch) -> Void)?) {
        let queue = AndroidExportQueue(items: [item], folder: folder, taken: name.map { _ in [] }, names: name.map { [$0] },
                                       worker: worker)
        self.queue = queue
        batch = nil
        errorMessage = nil
        Task { [weak self] in
            let batch = await queue.run()
            guard let self else { return }
            self.batch = batch
            if let failed = batch.failed.first { self.errorMessage = failed.reason }
            if !batch.outputs.isEmpty, !batch.wasCancelled { then?(batch) }
        }
    }

    func cancel() { queue?.cancel() }

    func showInFinder() {
        guard let batch, !batch.urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(batch.urls)
    }
}
