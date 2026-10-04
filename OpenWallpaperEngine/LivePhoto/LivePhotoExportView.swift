import AppKit
import SwiftUI

/// The Scene Editor (Live)'s iPhone & iPad Export mode: the wallpaper as it plays in the mode's
/// private instance (`IsolatedSceneEditSession`), framed as the chosen device's lock screen, with
/// the crop, the clip, the quality and the Live Photo export.
@MainActor
final class LivePhotoExportModel: NSObject, ObservableObject, NSSharingServiceDelegate {
    /// The last device chosen, kept across launches.
    static let deviceKey = "LivePhotoExportDevice"
    /// "Also Save to Photos Album" and the album's name, kept across launches.
    static let savesToPhotosKey = "LivePhotoExportSavesToPhotos"
    static let photosAlbumKey = "LivePhotoExportPhotosAlbum"

    /// The isolated session's purpose (`WallpaperPropertyScope.isolated`).
    static let purpose = "iphone-ipad-export"

    let wallpaper: WEWallpaper
    let sceneSize: SIMD2<Double>
    /// The mode's own store and private instance.
    let session: IsolatedSceneEditSession
    let defaults: UserDefaults
    /// The Photos library exports also go to (`LivePhotoAlbumSync`).
    let photos: LivePhotoLibrary

    @Published var device: DeviceModel {
        didSet {
            guard device != oldValue else { return }
            defaults.set(device.id, forKey: Self.deviceKey)
            crop = LivePhotoCrop(sceneSize: sceneSize, outputPixels: device.pixelSize, zoom: crop.zoom, center: crop.center)
            if device.family != .iPad { showsLandscape = false }
            previewFrames = []
        }
    }
    @Published var showsLockScreenGuide = true
    /// An iPad's lock screen previewed in landscape: the same picture, cropped by the iPad.
    @Published var showsLandscape = false
    @Published private(set) var crop: LivePhotoCrop
    @Published private(set) var clip = LivePhotoClip()
    @Published var quality = LivePhotoQuality.best
    /// The scene's measured motion (`LivePhotoMotion`), once measured.
    @Published var motion: LivePhotoMotion.Analysis?
    /// The clip is the window with the most motion; false once the user moves it.
    @Published var motionWindowIsAutomatic = false
    @Published var savesToPhotos: Bool {
        didSet { defaults.set(savesToPhotos, forKey: Self.savesToPhotosKey) }
    }
    @Published var photosAlbum: String {
        didSet { defaults.set(photosAlbum, forKey: Self.photosAlbumKey) }
    }
    /// Photos access was refused: the toggle went back off, and the panel says how to allow it.
    @Published var photosAccessDenied = false
    /// The last save to Photos, or why it failed (the export itself still succeeded).
    @Published var photosNotice: String?
    /// The clip's frames while it is previewed looping; empty shows the live scene.
    @Published private(set) var previewFrames: [CGImage] = []
    @Published private(set) var isRendering = false
    @Published private(set) var progress = 0.0
    @Published var errorMessage: String?
    /// The Export Settings sheet, while it is open.
    @Published var sheet: LivePhotoExportSheet?

    private var task: Task<Void, Never>?
    private var sharedFiles: LivePhotoHelper.Files?
    var hasMeasuredMotion = false

    init(session: IsolatedSceneEditSession, sceneSize: SIMD2<Double>, defaults: UserDefaults = .app,
         photos: LivePhotoLibrary = PhotoKitLibrary()) {
        self.session = session
        wallpaper = session.wallpaper
        self.sceneSize = sceneSize
        self.defaults = defaults
        self.photos = photos
        let device = DeviceModel.model(id: defaults.string(forKey: Self.deviceKey))
        self.device = device
        crop = LivePhotoCrop(sceneSize: sceneSize, outputPixels: device.pixelSize)
        savesToPhotos = defaults.bool(forKey: Self.savesToPhotosKey)
        photosAlbum = defaults.string(forKey: Self.photosAlbumKey) ?? LivePhotoAlbumSync.defaultAlbumName
    }

    static func isEligible(_ wallpaper: WEWallpaper) -> Bool {
        wallpaper.project.type.caseInsensitiveCompare("scene") == .orderedSame
    }

    /// What the export renders: the panel's device, crop, clip and quality.
    var settings: LivePhotoExportSettings {
        LivePhotoExportSettings(device: device, crop: crop, clip: clip, quality: quality)
    }

    /// The values the export renders with: the isolated store's, never the desktop's.
    var exportProperties: [String: String] { session.values }

    // MARK: Crop and clip

    var zoom: Double {
        get { crop.zoom }
        set { crop.setZoom(newValue); previewFrames = [] }
    }

    func pan(by delta: SIMD2<Double>) {
        crop.pan(by: delta)
        previewFrames = []
    }

    /// Setting the start by hand keeps it: the window is no longer the automatic one.
    var clipStart: Double {
        get { clip.start }
        set {
            clip.setStart(newValue)
            motionWindowIsAutomatic = false
            previewFrames = []
        }
    }

    /// A new length keeps the automatic window automatic (it is picked again for the length).
    var clipLength: Double {
        get { clip.length }
        set {
            clip.setLength(newValue)
            if motionWindowIsAutomatic, let motion { clip.setStart(LivePhotoMotion.bestStart(in: motion, length: clip.length)) }
            previewFrames = []
        }
    }

    /// The clip moved to the window with the most motion in `analysis`.
    func useMotion(_ analysis: LivePhotoMotion.Analysis) {
        motion = analysis
        clip.setStart(LivePhotoMotion.bestStart(in: analysis, length: clip.length))
        motionWindowIsAutomatic = true
        previewFrames = []
    }

    // MARK: Export Settings sheet

    /// Opens the Export Settings sheet before `action`, which its confirm button runs.
    func requestExport(_ action: LivePhotoExportAction) {
        guard !isRendering else { return }
        sheet = .confirm(action)
    }

    func showSettings() { sheet = .settings }

    /// Runs the export the sheet was opened for, once the sheet has closed.
    func confirm(_ action: LivePhotoExportAction) {
        sheet = nil
        DispatchQueue.main.async { [weak self] in
            switch action {
            case .airDrop: self?.sendWithAirDrop()
            case .save: self?.save()
            }
        }
    }

    // MARK: Rendering

    /// Renders the clip small and loops it in the frame.
    func previewClip() {
        var settings = settings
        settings.crop = LivePhotoCrop(sceneSize: sceneSize, outputPixels: device.pixelSize / 4, zoom: crop.zoom,
                                      center: crop.center)
        run { wallpaper, properties, progress in
            self.previewFrames = try await LivePhotoHelper.previewFrames(wallpaper, properties: properties, settings: settings,
                                                                         progress: progress)
        }
    }

    func stopPreview() { previewFrames = [] }

    /// Renders the Live Photo and offers it to AirDrop.
    func sendWithAirDrop() {
        renderLivePhoto { files in
            guard let service = NSSharingService(named: .sendViaAirDrop) else {
                LivePhotoHelper.remove(files)
                self.errorMessage = String(localized: "AirDrop isn't available on this Mac.")
                return
            }
            self.sharedFiles = files
            service.delegate = self
            service.perform(withItems: [files.still, files.movie])
        }
    }

    /// Renders the Live Photo and saves the pair into a chosen folder.
    func save() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Save")
        panel.message = String(localized: "Choose a folder for the Live Photo’s photo and movie.")
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        renderLivePhoto { files in
            defer { LivePhotoHelper.remove(files) }
            do {
                for source in [files.still, files.movie] {
                    let destination = folder.appending(path: source.lastPathComponent)
                    if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.copyItem(at: source, to: destination)
                }
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func cancel() {
        task?.cancel()
    }

    /// Renders the Live Photo, saves it to the Photos album when that is on, then hands it to `finish`.
    private func renderLivePhoto(then finish: @escaping (LivePhotoHelper.Files) -> Void) {
        let settings = settings
        let album: String? = savesToPhotos ? photosAlbum : nil
        run { wallpaper, properties, progress in
            if self.sharedFiles == nil { LivePhotoHelper.removeStaleExports() }
            let files = try await LivePhotoHelper.export(wallpaper, properties: properties, settings: settings,
                                                         progress: progress)
            if let album { await self.saveToPhotos(files, album: album) }
            finish(files)
        }
    }

    /// Measures the scene's motion through the crop and moves the clip to the window with the most.
    func measureMotion() {
        hasMeasuredMotion = true
        let settings = settings
        run { wallpaper, properties, progress in
            let analysis = try await LivePhotoHelper.analyseMotion(wallpaper, properties: properties, settings: settings,
                                                                   progress: progress)
            self.useMotion(analysis)
        }
    }

    /// Measures the motion the first time the mode's panel shows.
    func measureMotionIfNeeded() {
        guard !hasMeasuredMotion, !isRendering else { return }
        measureMotion()
    }

    /// Runs `work` with the wallpaper and a snapshot of the isolated store (the helper renders with
    /// exactly these values, the mode's user properties and layer adjustments).
    private func run(_ work: @escaping (WEWallpaper, [String: String], @escaping @MainActor (Double) -> Void) async throws -> Void) {
        guard !isRendering else { return }
        isRendering = true
        progress = 0
        errorMessage = nil
        let wallpaper = wallpaper
        let snapshot = exportProperties
        task = Task { [weak self] in
            do {
                try await work(wallpaper, snapshot) { value in self?.progress = value }
            } catch is CancellationError {
            } catch {
                self?.errorMessage = error.localizedDescription
            }
            self?.isRendering = false
            self?.task = nil
        }
    }

    // MARK: NSSharingServiceDelegate

    nonisolated func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        MainActor.assumeIsolated { removeSharedFiles() }
    }

    nonisolated func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        MainActor.assumeIsolated { removeSharedFiles() }
    }

    private func removeSharedFiles() {
        if let sharedFiles { LivePhotoHelper.remove(sharedFiles) }
        sharedFiles = nil
    }
}

/// Which Export Settings sheet is open: opened from the toolbar, or before an export.
enum LivePhotoExportSheet: Identifiable, Equatable {
    case settings
    case confirm(LivePhotoExportAction)

    var id: String {
        switch self {
        case .settings: return "settings"
        case .confirm(let action): return action.rawValue
        }
    }
}

/// The lock screen: the private instance's live scene (or the clip's preview) through the
/// device's portrait crop, or, for an iPad in landscape, the band of it the iPad shows.
struct LockScreenPreview: View {
    @ObservedObject var model: LivePhotoExportModel
    @State private var dragStart: SIMD2<Double>?
    @State private var zoomStart: Double?

    private var isLandscape: Bool { model.showsLandscape && model.device.family == .iPad }

    var body: some View {
        GeometryReader { geometry in
            let window = isLandscape ? model.crop.landscapeRect : model.crop.cropRect
            let layout = Self.layout(window: window, sceneSize: model.sceneSize, in: geometry.size)
            screen(frame: layout.frame, window: window, scale: layout.scale)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .padding(24)
    }

    private func screen(frame: CGSize, window: CGRect, scale: CGFloat) -> some View {
        let corner = min(frame.width, frame.height) * (model.device.family == .iPhone ? 0.12 : 0.05)
        return ZStack(alignment: .topLeading) {
            Color.black
            content(frame: frame, window: window, scale: scale)
            if model.showsLockScreenGuide {
                LockScreenGuide(layout: LockScreenLayout.layout(for: model.device.family, landscape: isLandscape), size: frame)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(.secondary.opacity(0.6), lineWidth: 4)
        }
        .contentShape(Rectangle())
        .gesture(DragGesture()
            .onChanged { value in
                let start = dragStart ?? model.crop.center
                if dragStart == nil { dragStart = start }
                let moved = SIMD2(Double(value.translation.width), Double(value.translation.height)) / Double(scale)
                model.pan(by: start - moved - model.crop.center)
            }
            .onEnded { _ in dragStart = nil })
        .simultaneousGesture(MagnifyGesture()
            .onChanged { value in
                let start = zoomStart ?? model.zoom
                if zoomStart == nil { zoomStart = start }
                model.zoom = start * value.magnification
            }
            .onEnded { _ in zoomStart = nil })
        .help("Drag to move the picture; pinch to zoom")
        .accessibilityLabel(Text("Lock screen preview"))
    }

    @ViewBuilder
    private func content(frame: CGSize, window: CGRect, scale: CGFloat) -> some View {
        if model.previewFrames.isEmpty {
            if !model.session.isEnded {
                let layout = Self.Layout(window: window, sceneSize: model.sceneSize, scale: scale)
                IsolatedSceneView(session: model.session, presentation: LivePhotoRenderer.presentation)
                    .frame(width: layout.sceneViewSize.width, height: layout.sceneViewSize.height)
                    .offset(x: layout.sceneViewOffset.x, y: layout.sceneViewOffset.y)
                    .allowsHitTesting(false)
            }
        } else {
            // The preview's frames are the portrait crop; in landscape the band in its middle shows.
            let crop = model.crop.cropRect
            let width = crop.width * scale, height = crop.height * scale
            TimelineView(.animation) { context in
                let frames = model.previewFrames
                let index = Int(context.date.timeIntervalSinceReferenceDate * Double(LivePhotoClip.frameRate)) % frames.count
                Image(decorative: frames[index], scale: 1)
                    .resizable()
                    .frame(width: width, height: height)
                    .offset(x: (crop.minX - window.minX) * scale, y: (crop.minY - window.minY) * scale)
            }
        }
    }

    /// The preview's geometry: the screen's frame, its points per scene unit, and the scene's
    /// view (the whole scene at that scale, drawn as the export draws it,
    /// `LivePhotoRenderer.presentation`) moved so the window's top-left is the frame's.
    struct Layout {
        let frame: CGSize
        let scale: CGFloat
        let sceneViewSize: CGSize
        let sceneViewOffset: CGPoint

        init(window: CGRect, sceneSize: SIMD2<Double>, scale: CGFloat) {
            self.scale = scale
            frame = CGSize(width: window.width * scale, height: window.height * scale)
            sceneViewSize = CGSize(width: sceneSize.x * scale, height: sceneSize.y * scale)
            sceneViewOffset = CGPoint(x: -window.minX * scale, y: -window.minY * scale)
        }
    }

    /// `window` (scene units) shown as large as it fits in `size`.
    static func layout(window: CGRect, sceneSize: SIMD2<Double>, in size: CGSize) -> Layout {
        let frame = frameSize(fitting: size, aspect: window.width / max(window.height, 1))
        return Layout(window: window, sceneSize: sceneSize, scale: frame.width / max(window.width, 1))
    }

    /// The largest frame at `aspect` inside `size`.
    static func frameSize(fitting size: CGSize, aspect: Double) -> CGSize {
        guard size.width > 0, size.height > 0, aspect > 0 else { return .zero }
        if size.width / size.height > aspect {
            return CGSize(width: size.height * aspect, height: size.height)
        }
        return CGSize(width: size.width, height: size.width / aspect)
    }
}
