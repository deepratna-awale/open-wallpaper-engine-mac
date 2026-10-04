import AppKit
import MetalKit
import SwiftUI

/// The Scene Inspector's iPhone mode: the wallpaper as it plays, framed as an iPhone lock screen,
/// with the crop, the clip and the Live Photo export.
@MainActor
final class LivePhotoExportModel: NSObject, ObservableObject, NSSharingServiceDelegate {
    let wallpaper: WEWallpaper
    let properties: WallpaperPropertyScope
    let sceneSize: SIMD2<Double>

    @Published var device = DeviceModel.largest {
        didSet { crop = LivePhotoCrop(sceneSize: sceneSize, outputPixels: device.pixelSize, zoom: crop.zoom, center: crop.center) }
    }
    @Published var showsLockScreenGuide = true
    @Published private(set) var crop: LivePhotoCrop
    @Published private(set) var clip = LivePhotoClip()
    /// The clip's frames while it is previewed looping; empty shows the live scene.
    @Published private(set) var previewFrames: [CGImage] = []
    @Published private(set) var isRendering = false
    @Published private(set) var progress = 0.0
    @Published var errorMessage: String?

    private var task: Task<Void, Never>?
    private var sharedFiles: LivePhotoHelper.Files?

    init(wallpaper: WEWallpaper, properties: WallpaperPropertyScope, sceneSize: SIMD2<Double>) {
        self.wallpaper = wallpaper
        self.properties = properties
        self.sceneSize = sceneSize
        crop = LivePhotoCrop(sceneSize: sceneSize, outputPixels: DeviceModel.largest.pixelSize)
    }

    static func isEligible(_ wallpaper: WEWallpaper) -> Bool {
        wallpaper.project.type.caseInsensitiveCompare("scene") == .orderedSame
    }

    // MARK: Crop and clip

    var zoom: Double {
        get { crop.zoom }
        set { crop.setZoom(newValue); previewFrames = [] }
    }

    func pan(by delta: SIMD2<Double>) {
        crop.pan(by: delta)
        previewFrames = []
    }

    var clipStart: Double {
        get { clip.start }
        set { clip.setStart(newValue); previewFrames = [] }
    }

    // MARK: Rendering

    /// Renders the clip small and loops it in the frame.
    func previewClip() {
        let preview = LivePhotoCrop(sceneSize: sceneSize, outputPixels: device.pixelSize / 4, zoom: crop.zoom, center: crop.center)
        let clip = clip
        run { wallpaper, properties, progress in
            self.previewFrames = try await LivePhotoHelper.previewFrames(wallpaper, properties: properties, crop: preview,
                                                                         clip: clip, progress: progress)
        }
    }

    func stopPreview() { previewFrames = [] }

    /// Renders the Live Photo and offers it to AirDrop.
    func sendToIPhone() {
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

    private func renderLivePhoto(then finish: @escaping (LivePhotoHelper.Files) -> Void) {
        let crop = crop, clip = clip
        run { wallpaper, properties, progress in
            if self.sharedFiles == nil { LivePhotoHelper.removeStaleExports() }
            finish(try await LivePhotoHelper.export(wallpaper, properties: properties, crop: crop, clip: clip,
                                                    progress: progress))
        }
    }

    /// Runs `work` with the wallpaper and a snapshot of the user properties the inspector edits (the
    /// helper renders with exactly these).
    private func run(_ work: @escaping (WEWallpaper, [String: String], @escaping @MainActor (Double) -> Void) async throws -> Void) {
        guard !isRendering else { return }
        isRendering = true
        progress = 0
        errorMessage = nil
        let wallpaper = wallpaper
        let snapshot = WallpaperPropertyTargets(wallpaper: wallpaper, scopes: [properties]).storedValues
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

/// The lock screen: the live scene (or the clip's preview) through the portrait crop.
struct LockScreenPreview: View {
    @ObservedObject var model: LivePhotoExportModel
    @State private var dragStart: SIMD2<Double>?
    @State private var zoomStart: Double?

    var body: some View {
        GeometryReader { geometry in
            let frame = Self.frameSize(fitting: geometry.size, aspect: model.crop.aspect)
            let scale = frame.height / model.crop.cropSize.y
            let crop = model.crop.cropRect
            ZStack(alignment: .topLeading) {
                Color.black
                if model.previewFrames.isEmpty {
                    LivePhotoExportScene(wallpaper: model.wallpaper, properties: model.properties)
                        .frame(width: model.sceneSize.x * scale, height: model.sceneSize.y * scale)
                        .offset(x: -crop.minX * scale, y: -crop.minY * scale)
                        .allowsHitTesting(false)
                } else {
                    TimelineView(.animation) { context in
                        let frames = model.previewFrames
                        let index = Int(context.date.timeIntervalSinceReferenceDate * Double(LivePhotoClip.frameRate)) % frames.count
                        Image(decorative: frames[index], scale: 1)
                            .resizable()
                            .frame(width: frame.width, height: frame.height)
                    }
                }
                if model.showsLockScreenGuide {
                    LockScreenGuide(height: frame.height)
                        .frame(width: frame.width, height: frame.height)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: frame.width, height: frame.height)
            .clipShape(RoundedRectangle(cornerRadius: frame.width * 0.12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: frame.width * 0.12, style: .continuous)
                    .strokeBorder(.secondary.opacity(0.6), lineWidth: 4)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture()
                .onChanged { value in
                    let start = dragStart ?? model.crop.center
                    if dragStart == nil { dragStart = start }
                    let moved = SIMD2(Double(value.translation.width), Double(value.translation.height)) / scale
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
            .accessibilityLabel(Text("iPhone lock screen preview"))
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .padding(24)
    }

    /// The largest frame at `aspect` inside `size`.
    static func frameSize(fitting size: CGSize, aspect: Double) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        if size.width / size.height > aspect {
            return CGSize(width: size.height * aspect, height: size.height)
        }
        return CGSize(width: size.width, height: size.width / aspect)
    }
}

/// A faint lock screen: where iOS draws the date and the clock.
private struct LockScreenGuide: View {
    let height: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.system(size: height * 0.022, weight: .semibold))
            Text(Date.now, format: .dateTime.hour().minute())
                .font(.system(size: height * 0.11, weight: .bold, design: .rounded))
            Spacer()
        }
        .padding(.top, height * 0.07)
        .foregroundStyle(.white.opacity(0.55))
        .shadow(color: .black.opacity(0.3), radius: 2)
        .frame(maxWidth: .infinity)
    }
}

/// The wallpaper's shared instance (`SceneWallpaperInstance`) drawn in a view of the scene's
/// aspect: the same renderer and properties as the desktop, or a new instance when no display
/// shows it with these properties.
private struct LivePhotoExportScene: NSViewRepresentable {
    let wallpaper: WEWallpaper
    let properties: WallpaperPropertyScope
    static let screenID = SceneWallpaperInstance.previewScreenIDs.first!

    func makeCoordinator() -> SceneWallpaperPresenter { SceneWallpaperPresenter() }

    func makeNSView(context: Context) -> MTKView {
        let view = SceneRenderLoop.makeView()
        let wallpapers = AppDelegate.shared.wallpaperViewModel
        let environment = SceneWallpaperEnvironment(wallpapers: wallpapers,
                                                    settings: AppDelegate.shared.globalSettingsViewModel,
                                                    scriptServices: AppDelegate.shared.sceneScriptServices,
                                                    loadingSnapshots: wallpapers.loadingSnapshots)
        let key = WallpaperInstanceKey(wallpaper, properties: properties)
        let wallpaper = wallpaper, properties = properties
        // The preview never makes the instance audible: silent while it is the only user
        // (`SceneWallpaperInstance.isPreviewOnly`), as usual once a display shows it too.
        let lease = SceneWallpaperPresenter.Lease(wallpapers.sceneInstances, key: key) {
            SceneWallpaperInstance(wallpaper: wallpaper, environment: environment, screenID: Self.screenID,
                                   properties: properties)
        }
        context.coordinator.show(lease, in: view, screenID: Self.screenID)
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.instance?.update()
    }

    static func dismantleNSView(_ view: MTKView, coordinator: SceneWallpaperPresenter) {
        coordinator.stop()
    }
}

/// The iPhone mode's controls: device, guide, crop, clip and export, then the user properties.
struct LivePhotoExportSettingsView: View {
    @ObservedObject var model: LivePhotoExportModel
    let scopes: [WallpaperPropertyScope]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Device", selection: $model.device) {
                    ForEach(DeviceModel.allCases) { device in
                        Text(verbatim: device.name).tag(device)
                    }
                }
                Text("\(model.device.pixelSize.x) × \(model.device.pixelSize.y) pixels")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Show Lock Screen Guide", isOn: $model.showsLockScreenGuide)
                    .help("Show where iOS draws the date and the clock")
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Zoom")
                        .font(.headline)
                    Slider(value: Binding(get: { model.zoom }, set: { model.zoom = $0 }),
                           in: 1...LivePhotoCrop.maximumZoom) {
                        Text("Zoom")
                    } minimumValueLabel: {
                        Text(verbatim: "1×")
                    } maximumValueLabel: {
                        Text(verbatim: "3×")
                    }
                    Text("Drag the preview to move the picture.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Motion")
                        .font(.headline)
                    Slider(value: Binding(get: { model.clipStart }, set: { model.clipStart = $0 }),
                           in: 0...LivePhotoClip.latestStart, step: 1.0 / Double(LivePhotoClip.frameRate)) {
                        Text("Clip Start")
                    }
                    Text("\(model.clipStart.formatted(.number.precision(.fractionLength(1)))) s – \(model.clip.end.formatted(.number.precision(.fractionLength(1)))) s")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("A Live Photo moves for about 3 seconds; its photo is the middle frame.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if model.previewFrames.isEmpty {
                        Button("Preview Clip") { model.previewClip() }
                            .disabled(model.isRendering)
                            .help("Render the clip and play it in a loop")
                    } else {
                        Button("Show Live Wallpaper") { model.stopPreview() }
                            .help("Stop the clip and show the wallpaper as it plays")
                    }
                }
                Divider()
                if model.isRendering {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: model.progress) {
                            Text("Rendering…")
                        }
                        Button("Cancel", role: .cancel) { model.cancel() }
                    }
                } else {
                    HStack {
                        Button {
                            model.sendToIPhone()
                        } label: {
                            Label("Send to iPhone", systemImage: "iphone.radiowaves.left.and.right")
                        }
                        .glassButtonStyle(.prominent)
                        .help("Render the Live Photo and send it with AirDrop")
                        Button("Save…") { model.save() }
                            .glassButtonStyle()
                            .help("Render the Live Photo and save its photo and movie to a folder")
                    }
                }
                if let error = model.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Divider()
                SceneUserPropertiesView(wallpaper: model.wallpaper, scopes: scopes)
            }
            .padding()
        }
    }
}
