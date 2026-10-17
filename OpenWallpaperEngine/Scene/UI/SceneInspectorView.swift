import SwiftUI
import AVFoundation
import OWEInspectorKit
import OWESceneEditing

/// Scene Edit / Export's modes: the wallpaper's objects, edited on the running wallpaper, or
/// the Screen Saver mode's version, the iPhone & iPad Export mode's lock screen or the Android
/// Export mode's screen, each edited on the mode's own copy (`IsolatedSceneEditSession`). The
/// picker lists them in this order.
enum SceneInspectorMode: CaseIterable {
    case wallpaper, screenSaver, deviceExport, androidExport

    var title: LocalizedStringResource {
        switch self {
        case .wallpaper: return LocalizedStringResource("Wallpaper", comment: "Scene Edit / Export: the mode that edits the running wallpaper")
        case .screenSaver: return LocalizedStringResource("Screen Saver", comment: "Scene Edit / Export: the mode that records the screen saver")
        case .deviceExport: return LocalizedStringResource("iPhone & iPad Export", comment: "Scene Edit / Export: the mode that exports a Live Photo")
        case .androidExport: return LocalizedStringResource("Android Export", comment: "Scene Edit / Export: the mode that exports a .mpkg for Wallpaper Engine's Android app")
        }
    }
}

/// Scene Edit / Export: its mode, and the editor for it. The Wallpaper mode edits the stores
/// the running wallpaper reads; the Screen Saver and iPhone & iPad Export modes each edit an
/// isolated copy of them made when the mode opens (`IsolatedSceneEditSession`), shown by the
/// mode's private instance and drawn by the screen saver or exported, and dropped when it closes. Every export
/// happens here, so a video opens it too, with the modes that apply to it (`SceneEditorModes`).
struct SceneInspectorView: View {
    private let wallpaper: WEWallpaper
    private let scopes: [WallpaperPropertyScope]
    @State private var exportModel: LivePhotoExportModel?
    @State private var screenSaverModel: ScreenSaverEditorModel?
    @State private var androidModel: AndroidExportEditorModel?
    @State private var videoScreenSaver: VideoScreenSaverModel?
    /// A mode shown but unavailable for this wallpaper, while it is chosen.
    @State private var unavailableMode: SceneInspectorMode?
    /// A video's picture size as it plays, which its export modes frame; read when the editor opens.
    @State private var videoSize: SIMD2<Double>?
    /// The mode the editor opens in, entered once its scene size is known.
    private let initialMode: SceneInspectorMode
    @State private var didEnterInitialMode = false

    init(wallpaper: WEWallpaper, scopes: [WallpaperPropertyScope] = [.shared], initialMode: SceneInspectorMode = .wallpaper) {
        self.wallpaper = wallpaper
        self.scopes = scopes
        self.initialMode = SceneEditorModes.initialMode(initialMode, for: wallpaper)
    }

    private var isVideo: Bool { SceneEditorModes.isVideo(wallpaper) }

    var body: some View {
        if isVideo, videoSize == nil {
            ProgressView()
                .frame(minWidth: 1120, minHeight: 560)
                .frostedWindowBackground()
                .task {
                    // A file AVFoundation can't read (WebM, a remote video) has no export to frame.
                    var size: SIMD2<Double>?
                    if ScreenSaverVideoSource.isEligible(wallpaper) { size = await SceneEditorModes.videoSize(of: wallpaper.mediaURL) }
                    videoSize = size ?? SIMD2<Double>(SceneContentLoader.defaultCanvas)
                }
        } else if let exportModel {
            SceneInspectorContent(wallpaper: wallpaper, scopes: [exportModel.session.scope], isolated: exportModel.session,
                                  exportModel: exportModel, screenSaverModel: nil, onModeChange: setMode,
                                  initialMode: .deviceExport)
                .id(SceneInspectorMode.deviceExport)
        } else if let androidModel {
            SceneInspectorContent(wallpaper: wallpaper, scopes: [androidModel.session.scope], isolated: androidModel.session,
                                  exportModel: nil, screenSaverModel: nil, androidModel: androidModel, onModeChange: setMode,
                                  initialMode: .androidExport)
                .id(SceneInspectorMode.androidExport)
        } else if let screenSaverModel {
            SceneInspectorContent(wallpaper: wallpaper, scopes: [screenSaverModel.session.scope],
                                  isolated: screenSaverModel.session, exportModel: nil, screenSaverModel: screenSaverModel,
                                  onModeChange: setMode, initialMode: .screenSaver)
                .id(SceneInspectorMode.screenSaver)
        } else if let videoScreenSaver {
            SceneInspectorContent(wallpaper: wallpaper, scopes: scopes, isolated: nil, exportModel: nil, screenSaverModel: nil,
                                  videoScreenSaver: videoScreenSaver, onModeChange: setMode, initialMode: .screenSaver)
                .id(SceneInspectorMode.screenSaver)
        } else if let unavailableMode {
            SceneInspectorContent(wallpaper: wallpaper, scopes: scopes, isolated: nil, exportModel: nil, screenSaverModel: nil,
                                  unavailableMode: unavailableMode, onModeChange: setMode, initialMode: unavailableMode)
                .id("unavailable-\(unavailableMode)")
        } else {
            SceneInspectorContent(wallpaper: wallpaper, scopes: scopes, isolated: nil, exportModel: nil,
                                  screenSaverModel: nil, onModeChange: setMode,
                                  initialMode: didEnterInitialMode ? .wallpaper : initialMode)
                .id(SceneInspectorMode.wallpaper)
        }
    }

    /// Opening an isolated mode copies the edited store's values into its isolated store (the
    /// Screen Saver mode then takes its own saved choices, when it has any); leaving it drops
    /// them, once its preview (and with it the private instance) is gone.
    private func setMode(_ mode: SceneInspectorMode, sceneSize: SIMD2<Double>) {
        didEnterInitialMode = true
        leaveIsolatedModes(except: mode)
        if case .unavailable = SceneEditorModes.availability(of: mode, for: wallpaper) {
            unavailableMode = mode
            return
        }
        unavailableMode = nil
        // A video's modes frame its picture as it plays.
        let sceneSize = isVideo ? videoSize ?? sceneSize : sceneSize
        switch mode {
        case .deviceExport:
            guard exportModel == nil else { return }
            let session = IsolatedSceneEditSession(wallpaper: wallpaper, purpose: LivePhotoExportModel.purpose,
                                                   seededFrom: scopes)
            exportModel = LivePhotoExportModel(session: session, sceneSize: sceneSize)
        case .androidExport:
            guard androidModel == nil else { return }
            let session = IsolatedSceneEditSession(wallpaper: wallpaper, purpose: AndroidExportEditorModel.purpose,
                                                   seededFrom: scopes)
            let model = AndroidExportEditorModel(session: session, sceneSize: sceneSize)
            androidModel = model
            #if DEBUG
            AndroidBatchPicker.runScreenshotFixture(on: model)
            #endif
        case .screenSaver where isVideo:
            guard videoScreenSaver == nil else { return }
            videoScreenSaver = VideoScreenSaverModel(wallpaper: wallpaper, selectionService: AppDelegate.shared.screenSaverSelection)
        case .screenSaver:
            guard screenSaverModel == nil else { return }
            let session = IsolatedSceneEditSession(wallpaper: wallpaper, purpose: ScreenSaverEditorModel.purpose,
                                                   seededFrom: scopes)
            let selectionService = AppDelegate.shared.screenSaverSelection
            screenSaverModel = ScreenSaverEditorModel(session: session, seededFrom: scopes, selectionService: selectionService,
                                                      store: selectionService.store)
        case .wallpaper:
            break
        }
    }

    private func leaveIsolatedModes(except mode: SceneInspectorMode) {
        if mode != .screenSaver { videoScreenSaver = nil }
        if mode != .deviceExport, let model = exportModel {
            exportModel = nil
            model.cancel()
            model.closeBatch()
            DispatchQueue.main.async { model.session.end() }
        }
        if mode != .screenSaver, let model = screenSaverModel {
            screenSaverModel = nil
            model.close()
            DispatchQueue.main.async { model.session.end() }
        }
        if mode != .androidExport, let model = androidModel {
            androidModel = nil
            model.cancel()
            model.closeBatch()
            DispatchQueue.main.async { model.session.end() }
        }
    }
}

private struct SceneInspectorContent: View {
    @StateObject private var model: SceneInspectorModel
    /// Depth maps and depth parallax, kept in the wallpaper's editor overlay.
    @StateObject private var depthMaps: SceneEditorDepthMapHost
    @State private var selectedID: String?
    @State private var searchText = ""
    @State private var didCopyPath = false
    /// The compact frame readout of the scene this mode runs (`SceneRenderStatsSampler`).
    @State private var statsFeed: RenderStatsFeed?
    @State private var isMovementPresented = true
    @State private var isConfirmingReset = false
    @State private var columnVisibility: NavigationSplitViewVisibility
    /// Moves when the Export Settings sheet closes, so the panel reads the properties it changed.
    @State private var exportPanelRevision = 0
    @FocusState private var isSearchFocused: Bool
    private let wallpaperDirectory: URL
    private let wallpaper: WEWallpaper
    /// The stores the editor edits: the running wallpaper's, or the isolated session's.
    private let scopes: [WallpaperPropertyScope]
    /// An isolated mode's session; nil in the Wallpaper mode.
    private let isolated: IsolatedSceneEditSession?
    private let exportModel: LivePhotoExportModel?
    private let screenSaverModel: ScreenSaverEditorModel?
    private let androidModel: AndroidExportEditorModel?
    private let videoScreenSaver: VideoScreenSaverModel?
    /// A mode shown but unavailable for this wallpaper (`SceneEditorModes`), while it is chosen.
    private let unavailableMode: SceneInspectorMode?
    private let onModeChange: (SceneInspectorMode, SIMD2<Double>) -> Void
    /// The mode to enter once the scene's size is known (`showSceneInspector(…mode:)`). An isolated
    /// mode's content passes its own mode, so appearing doesn't switch straight back to Wallpaper.
    private let initialMode: SceneInspectorMode

    private var mode: SceneInspectorMode {
        if let unavailableMode { return unavailableMode }
        if exportModel != nil { return .deviceExport }
        if androidModel != nil { return .androidExport }
        return screenSaverModel == nil && videoScreenSaver == nil ? .wallpaper : .screenSaver
    }

    /// Why the chosen mode can't be used for this wallpaper; nil when it can.
    private var unavailableReason: String? {
        guard let unavailableMode, case .unavailable(let reason) = SceneEditorModes.availability(of: unavailableMode, for: wallpaper)
        else { return nil }
        return reason
    }

    init(wallpaper: WEWallpaper, scopes: [WallpaperPropertyScope], isolated: IsolatedSceneEditSession?,
         exportModel: LivePhotoExportModel?, screenSaverModel: ScreenSaverEditorModel?, androidModel: AndroidExportEditorModel? = nil,
         videoScreenSaver: VideoScreenSaverModel? = nil, unavailableMode: SceneInspectorMode? = nil,
         onModeChange: @escaping (SceneInspectorMode, SIMD2<Double>) -> Void, initialMode: SceneInspectorMode = .wallpaper) {
        self.initialMode = initialMode
        self.videoScreenSaver = videoScreenSaver
        self.unavailableMode = unavailableMode
        // A video has no layers to list: its modes open on their preview alone.
        _columnVisibility = State(initialValue: SceneEditorModes.isVideo(wallpaper) ? .detailOnly : .all)
        wallpaperDirectory = wallpaper.wallpaperDirectory
        self.wallpaper = wallpaper
        self.scopes = scopes
        self.isolated = isolated
        self.exportModel = exportModel
        self.screenSaverModel = screenSaverModel
        self.androidModel = androidModel
        self.onModeChange = onModeChange
        _model = StateObject(wrappedValue: SceneInspectorModel(wallpaper: wallpaper, scopes: scopes))
        _depthMaps = StateObject(wrappedValue: SceneEditorDepthMapHost(wallpaper: wallpaper))
    }

    private func matches(_ item: SceneInspectorItem) -> Bool {
        guard !searchText.isEmpty else { return true }
        if item.name.localizedCaseInsensitiveContains(searchText)
            || item.kind.localizedCaseInsensitiveContains(searchText)
            || item.sourcePath.localizedCaseInsensitiveContains(searchText)
            || (item.materialPath?.localizedCaseInsensitiveContains(searchText) ?? false)
            || (item.versionName?.localizedCaseInsensitiveContains(searchText) ?? false) {
            return true
        }
        if item.texturePaths.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
            || item.shaderPaths.contains(where: { $0.localizedCaseInsensitiveContains(searchText) }) {
            return true
        }
        return item.effects.contains { effect in
            effect.name.localizedCaseInsensitiveContains(searchText)
                || effect.title.localizedCaseInsensitiveContains(searchText)
                || (effect.maskPath?.localizedCaseInsensitiveContains(searchText) ?? false)
                || effect.controls.contains { $0.title.localizedCaseInsensitiveContains(searchText) || $0.key.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        inspectorSplitView
            .frame(minWidth: 1120, minHeight: 560)
            .frostedWindowBackground()
            .onAppear {
                selectedID = model.initiallySelectedID
                loadSelectedTextures()
                if statsFeed == nil { statsFeed = Self.statsFeed(wallpaper: wallpaper, scopes: scopes, isolated: isolated) }
                if initialMode != mode, SceneEditorModes.availability(of: initialMode, for: wallpaper) != nil {
                    onModeChange(initialMode, model.sceneSize)
                }
            }
            .onChange(of: selectedID) { _, _ in loadSelectedTextures() }
            .onDisappear {
                // The screen saver's last choices are saved before its store goes.
                screenSaverModel?.close()
                // The library's export selection for this mode ends with it.
                androidModel?.closeBatch()
                isolated?.end()
            }
    }

    /// Both side columns (the object list and the movement controls) start at one width.
    private static let sidebarWidth: CGFloat = 300

    /// The frame readout's feed: an isolated mode's private instance, else the desktop's.
    private static func statsFeed(wallpaper: WEWallpaper, scopes: [WallpaperPropertyScope],
                                  isolated: IsolatedSceneEditSession?) -> RenderStatsFeed {
        SceneRenderStatsSampler(instance: { [weak isolated] in
            if let isolated { return isolated.instances.instance(for: isolated.instanceKey) }
            return AppDelegate.shared.wallpaperViewModel.sceneInstances
                .instance(for: WallpaperInstanceKey(wallpaper, properties: scopes.first ?? .shared))
        }).makeFeed()
    }

    /// The symbol for an item's kind: particle systems and effects as everywhere in the editors.
    private static func kindSymbol(_ kind: String) -> String {
        switch kind {
        case "Particle": return "sparkles"
        case "Effect Stack": return "slider.horizontal.3"
        default: return "photo"
        }
    }

    /// The name shown for an item's kind; `kind` itself stays English, as the code matches on it.
    private static func kindLabel(_ kind: String) -> String {
        switch kind {
        case "Image": return String(localized: "Image", comment: "Scene Edit / Export: the kind of a scene object")
        case "Particle": return String(localized: "Particle System", comment: "Scene Edit / Export: the kind of a scene object")
        case "Video": return String(localized: "Video")
        case "Audio": return String(localized: "Audio")
        case "Effect Stack": return String(localized: "Effect Stack", comment: "Scene Edit / Export: the effects applied to a video")
        default: return String(localized: "Other", comment: "Scene Edit / Export: the kind of a scene object that is neither an image nor particles")
        }
    }

    private var inspectorSplitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarColumn
                // On the column, not the split view: there, with the right-hand inspector, the
                // search field's place in the toolbar and the columns' widths kept re-laying each
                // other out, and AppKit stopped the window's first layout after 300 passes.
                .searchable(text: $searchText, placement: .sidebar, prompt: "Search")
                .modifier(SearchFieldFocus(isFocused: $isSearchFocused))
                // `sidebarToggle` takes its place, right before the modes.
                .toolbar(removing: .sidebarToggle)
                // Outermost, after `toolbar(removing:)`: inside it the width never reached the
                // column, which then opened at AppKit's default of about 140 points.
                .navigationSplitViewColumnWidth(min: 240, ideal: Self.sidebarWidth, max: 440)
        } detail: {
            modeDetail
                .overlay(alignment: .bottomTrailing) {
                    if let statsFeed { RenderStatsFeedBadge(feed: statsFeed).padding(10) }
                }
                .inspector(isPresented: $isMovementPresented) {
                    Group {
                        if let exportModel {
                            LivePhotoExportLayerPanel(model: exportModel) {
                                layerAdjustments(for: model.items.first(where: { $0.id == selectedID }))
                            }
                            .id(exportPanelRevision)
                        } else if let androidModel {
                            AndroidExportLayerPanel(model: androidModel) {
                                layerAdjustments(for: model.items.first(where: { $0.id == selectedID }))
                            }
                            .id(exportPanelRevision)
                        } else if let screenSaverModel {
                            ScreenSaverEditorPanel(model: screenSaverModel) {
                                layerAdjustments(for: model.items.first(where: { $0.id == selectedID }))
                            }
                        } else if let videoScreenSaver {
                            VideoScreenSaverPanel(model: videoScreenSaver)
                        } else if let unavailableReason {
                            Text(unavailableReason)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding()
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        } else {
                            movementColumn(for: model.items.first(where: { $0.id == selectedID }))
                        }
                    }
                    .inspectorColumnWidth(min: 260, ideal: Self.sidebarWidth, max: 400)
                }
                .modifier(LivePhotoExportSheetHost(model: exportModel, onClose: { exportPanelRevision += 1 }))
                .modifier(AndroidExportSheetHost(model: androidModel, onClose: { exportPanelRevision += 1 }))
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        sidebarToggle
                    }
                    if #available(macOS 26, *) {
                        ToolbarSpacer(.fixed, placement: .navigation)
                    }
                    ToolbarItem(placement: .navigation) {
                        modePicker
                    }
                    // Separate items at the trailing end: on macOS 26 a fixed spacer keeps them
                    // from sharing one glass capsule.
                    if #available(macOS 26, *) {
                        ToolbarSpacer(.flexible)
                    }
                    ToolbarItem(placement: .automatic) {
                        pathControl
                    }
                    if #available(macOS 26, *) {
                        ToolbarSpacer(.fixed)
                    }
                    ToolbarItem(placement: .automatic) {
                        modeAction
                    }
                    if #available(macOS 26, *) {
                        ToolbarSpacer(.fixed)
                    }
                    // The right-hand panel's toggle is the last item, at the trailing edge of the
                    // window, as macOS places an inspector toggle.
                    ToolbarItem(placement: .automatic) {
                        panelToggle
                    }
                }
                .alert("Reset Scene Edits", isPresented: $isConfirmingReset) {
                    Button("Reset", role: .destructive) {
                        model.removeEdits()
                        // Rebuilt from the stored values, now without the edits, once this view's
                        // alert has closed.
                        let wallpaper = wallpaper, scopes = scopes
                        DispatchQueue.main.async { AppDelegate.shared.showSceneInspector(for: wallpaper, scopes: scopes) }
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("Do you want to undo every scene edit of “\(wallpaper.project.displayTitle)”? Its properties are kept.")
                }
        }
        .background {
            Button("") { focusSearch() }
                .keyboardShortcut("k", modifiers: .command)
                .hidden()
            Button("") { toggleSidebar() }
                .keyboardShortcut("s", modifiers: [.command, .control])
                .hidden()
        }
    }

    private var isSidebarShown: Bool { columnVisibility != .detailOnly }

    private func toggleSidebar() {
        withAnimation { columnVisibility = isSidebarShown ? .detailOnly : .all }
    }

    /// Shows or hides the object list; the system's own toggle is removed so this one sits right
    /// before the modes whether the list is shown or not.
    private var sidebarToggle: some View {
        let title: LocalizedStringKey = isSidebarShown ? "Hide Sidebar" : "Show Sidebar"
        return Button(action: toggleSidebar) {
            Label(title, systemImage: "sidebar.left")
        }
        .help(Text(title))
        .accessibilityLabel(Text(title))
    }

    /// The detail column: the selected object, or the device's lock screen.
    @ViewBuilder
    private var modeDetail: some View {
        if let exportModel {
            LockScreenPreview(model: exportModel)
        } else if let androidModel {
            AndroidScreenPreview(model: androidModel)
        } else if let screenSaverModel {
            ScreenSaverEditorPreview(model: screenSaverModel)
        } else if videoScreenSaver != nil {
            VideoScreenSaverPreview(wallpaper: wallpaper)
        } else if let unavailableMode, let unavailableReason {
            ContentUnavailableView {
                Label { Text(unavailableMode.title) } icon: { Image(systemName: "nosign") }
            } description: {
                Text(unavailableReason)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            detailColumn
        }
    }

    /// Shows or hides the right-hand panel: Move & Align, the Screen Saver panel, or an export mode's Layer Adjustments.
    private var panelToggle: some View {
        Button {
            withAnimation { isMovementPresented.toggle() }
        } label: {
            switch mode {
            case .wallpaper: Label("Move & Align", systemImage: "sidebar.right")
            case .screenSaver: Label("Screen Saver Panel", systemImage: "sidebar.right")
            case .deviceExport, .androidExport: Label("Layer Adjustments Panel", systemImage: "sidebar.right")
            }
        }
        .help(panelToggleHelp)
    }

    private var panelToggleHelp: Text {
        switch mode {
        case .wallpaper: return Text("Show or hide the move, size and align controls")
        case .screenSaver: return Text("Show or hide the Screen Saver panel")
        case .deviceExport, .androidExport: return Text("Show or hide the Layer Adjustments panel")
        }
    }

    /// The Wallpaper mode's Reset Edits, or the export mode's Export Settings.
    @ViewBuilder
    private var modeAction: some View {
        if let exportModel {
            Button {
                exportModel.showSettings()
            } label: {
                Label("Export Settings", systemImage: "square.and.arrow.up")
            }
            .help("Open the export settings and export: device, crop, clip, quality and properties")
        } else if let androidModel {
            Button {
                androidModel.showSettings()
            } label: {
                Label("Export Settings", systemImage: "square.and.arrow.up")
            }
            .help("Open the export settings and export: device, crop, output and properties")
        } else if let screenSaverModel {
            Button {
                screenSaverModel.setAsScreenSaver()
            } label: {
                Label("Set as Screen Saver", systemImage: "display")
            }
            .help("Make this version of the wallpaper the screen saver")
        } else if videoScreenSaver != nil || unavailableMode != nil {
            EmptyView()
        } else {
            Button {
                isConfirmingReset = true
            } label: {
                Label("Reset Edits", systemImage: "arrow.triangle.2.circlepath")
            }
            .help("Undo every change made to this wallpaper in Scene Edit / Export")
        }
    }

    /// The modes this wallpaper shows (`SceneEditorModes`): all of them for a scene, a video's
    /// screen saver and exports, a web wallpaper's Wallpaper mode and its unavailable Android Export.
    private var modePicker: some View {
        let entries = SceneEditorModes.entries(for: wallpaper)
        return Picker("Mode", selection: Binding(get: { mode }, set: { newValue in
            guard newValue != mode else { return }
            onModeChange(newValue, model.sceneSize)
        })) {
            ForEach(entries, id: \.mode) { entry in
                Text(entry.mode.title).tag(entry.mode)
            }
        }
        .pickerStyle(.segmented)
        .help(Text("Edit the running wallpaper, set it as your screen saver, preview it as an iPhone or iPad lock screen and export a Live Photo, or frame it for an Android device and export a .mpkg, without changing your desktop"))
    }

    /// ⌘K. macOS 15 focuses a search field through `searchFocused`; macOS 14 has no API for it,
    /// so the window's search field is made first responder directly.
    private func focusSearch() {
        if #available(macOS 15, *) {
            isSearchFocused = true
        } else {
            guard let window = NSApp.keyWindow,
                  let field = Self.searchField(in: window.contentView?.superview ?? window.contentView) else { return }
            window.makeFirstResponder(field)
        }
    }

    private static func searchField(in view: NSView?) -> NSSearchField? {
        guard let view else { return nil }
        if let field = view as? NSSearchField { return field }
        for subview in view.subviews {
            if let field = searchField(in: subview) { return field }
        }
        return nil
    }

    /// A row's name takes the width beside its switch, cut in the middle (names often differ only
    /// at their ends), with the whole name in its tooltip.
    private static func rowTitle(_ name: String, caption: String? = nil, systemImage: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let caption {
                    Text(verbatim: caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        } icon: {
            Image(systemName: systemImage)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
        .help(Text(verbatim: name))
    }

    private var sidebarColumn: some View {
        List(selection: $selectedID) {
            let versions = model.shownVersionProperties.filter { searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(searchText) }
            if !versions.isEmpty {
                Section("Versions") {
                    ForEach(versions) { property in
                        HStack(spacing: 8) {
                            Self.rowTitle(property.title, systemImage: "square.stack.3d.up")
                            Picker(property.title, selection: Binding(
                                get: { model.propertyValue(property.id) },
                                set: { model.setProperty(property.id, to: $0) }
                            )) {
                                ForEach(property.options, id: \.value) { option in
                                    Text(verbatim: option.title).tag(option.value)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .fixedSize()
                        }
                    }
                }
            }
            Section("Scene Objects") {
                // The hierarchy as the Wallpaper Editor lists it; a search lists the matches flat.
                if searchText.isEmpty, !model.objectTree.isEmpty {
                    OutlineGroup(model.objectTree, children: \.children) { node in
                        if let item = model.items.first(where: { $0.id == String(node.id) }) {
                            objectRow(item, symbol: node.layer.listSymbol)
                        }
                    }
                } else {
                    ForEach(model.items.filter(matches)) { item in
                        objectRow(item, symbol: Self.kindSymbol(item.kind))
                    }
                }
            }
        }
    }

    /// A scene object: its name (with the version it belongs to, if any) and its visibility switch.
    private func objectRow(_ item: SceneInspectorItem, symbol: String) -> some View {
        HStack(spacing: 8) {
            Self.rowTitle(item.name, caption: model.versionCaption(item), systemImage: symbol)
                .opacity(item.visible && !model.isHiddenByParent(item) ? 1 : 0.5)
            Toggle("Visible", isOn: Binding(
                get: { item.isSwitchedOn },
                set: { model.setObjectVisible($0, item: item) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .fixedSize()
            .help(Self.visibilityHelp(item))
        }
        .contentShape(Rectangle())
        .tag(item.id)
    }

    /// The switch's help; on an object a user property shows, what showing it again does.
    private static func visibilityHelp(_ item: SceneInspectorItem) -> String {
        guard let property = item.visibility?.property else {
            return item.isSwitchedOn ? String(localized: "Hide object") : String(localized: "Show object")
        }
        return item.isSwitchedOn
            ? String(localized: "Hide this object; “\(property)” sets it again when you show it",
                     comment: "Scene Edit / Export: help of the switch of an object a user property shows; the property's key")
            : String(localized: "Show this object; “\(property)” sets it again",
                     comment: "Scene Edit / Export: help of the switch of an object hidden over the user property that shows it; the property's key")
    }

    private var detailColumn: some View {
        let selectedItem = model.items.first(where: { $0.id == selectedID })
        return Group {
            if let item = selectedItem {
                selectedItemDetail(item)
            } else if let error = model.errorMessage {
                ContentUnavailableView("Scene Unavailable", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                ContentUnavailableView("Select a Scene Object", systemImage: "square.stack.3d.up")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(ArrowKeyMove { direction in
            if let selectedItem { move(selectedItem, direction: direction) }
        })
    }

    /// Shows where the wallpaper lives and copies that path, so its files can be opened elsewhere.
    private var pathControl: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(wallpaperDirectory.path, forType: .string)
            didCopyPath = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { didCopyPath = false }
        } label: {
            Label(didCopyPath ? "Copied" : "Copy Path", systemImage: didCopyPath ? "checkmark" : "doc.on.doc")
                .labelStyle(.titleAndIcon)
        }
        .help(didCopyPath ? "Copied" : "Copy wallpaper folder path\n\(wallpaperDirectory.path)")
    }

    private func selectedItemDetail(_ item: SceneInspectorItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                LabeledContent("Type", value: Self.kindLabel(item.kind))
                if item.isVersion {
                    Button {
                        model.useVersion(item)
                    } label: {
                        Label("Use This Version", systemImage: "checkmark.circle")
                    }
                }
                if !item.sourcePath.isEmpty { LabeledContent("Source", value: item.sourcePath) }
                if let material = item.materialPath { LabeledContent("Material", value: material) }
                detailList("Textures", values: item.texturePaths)
                decodedTextureList(for: item)
                detailList("Shaders", values: item.shaderPaths)
                effectList(for: item)
                if !item.isSynthetic, let objectID = Int(item.id) {
                    SceneEditorDepthMapSection(host: depthMaps, objectID: objectID)
                }
                editableObjectBlock(for: item)
                if let particle = item.rawParticle {
                    editableAssetBlock(title: "Particle System", isParticle: true, text: particle, path: item.sourcePath)
                }
                if let material = item.rawMaterial, let materialPath = item.materialPath {
                    editableAssetBlock(title: "Material Properties", isParticle: false, text: material, path: materialPath)
                }
            }
            .padding()
        }
    }

    @ViewBuilder private func effectList(for item: SceneInspectorItem) -> some View {
        if !item.effects.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Effects").font(.title3.bold())
                ForEach(item.effects) { effect in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 10) {
                            if let maskPath = effect.maskPath {
                                HStack(spacing: 5) {
                                    Text("Mask").font(.headline)
                                    InfoTip(String(localized: "Limits this effect to the white areas of the mask. Black areas are left untouched."))
                                }
                                Text(maskPath).font(.caption.monospaced()).foregroundStyle(.secondary)
                                if let mask = model.decodedMasks[effect.id] {
                                    Image(nsImage: mask.image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxWidth: .infinity, maxHeight: 300)
                                        .background(Color.black)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                } else if model.loadingItemID == item.id {
                                    ProgressView()
                                }
                            } else {
                                Text("No mask").font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(effect.combos.filter { model.requirementsHold($0, in: effect) }) { combo in
                                effectComboControl(combo, effect: effect)
                            }
                            ForEach(effect.controls) { control in
                                if control.isColor {
                                    if control.component == 0 {
                                        ColorPicker(selection: Binding(
                                            get: { model.effectColor(for: control) },
                                            set: { model.setEffectColor($0, control: control) }
                                        ), supportsOpacity: false) {
                                            parameterLabel(control.title, help: parameterHelp(control, effect: effect.name))
                                        }
                                        .anchorsColorPanel()
                                    }
                                } else {
                                    effectSlider(control, effect: effect)
                                }
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        HStack {
                            Toggle("Enabled", isOn: Binding(
                                get: { model.effectEnabled[effect.id] ?? true },
                                set: { model.setEffectEnabled($0, effect: effect) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                            Label(effect.title, systemImage: "slider.horizontal.3")
                            InfoTip(SceneHelp.effect(effect.name))
                        }
                    }
                }
            }
        }
    }

    /// WE's material slider: the annotation's range, step 0.01 (1 for `int`), and a number field
    /// that accepts values past the range.
    @ViewBuilder private func effectSlider(_ control: SceneInspectorEffectControl, effect: SceneInspectorEffect) -> some View {
        let value = Binding<Double>(
            get: { model.displayedEffectValue(for: control) },
            set: { model.setDisplayedEffectValue($0, control: control) }
        )
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                parameterLabel(control.title, help: parameterHelp(control, effect: effect.name))
                if control.isLinked, control.component == 0 {
                    Toggle(isOn: Binding(get: { model.isLinked(control) },
                                         set: { model.setLinked($0, control: control) })) {
                        Image(systemName: "link")
                    }
                    .toggleStyle(.button)
                    .help("Edit X and Y together")
                }
            }
            NumericSliderInput(value: value,
                               range: control.minimum...max(control.maximum, control.minimum + 0.001),
                               defaultValue: control.defaultValue,
                               step: control.isInteger ? 1 : 0.01,
                               fractionDigits: control.isInteger ? 0 : 2, fieldWidth: 76,
                               clampsTypedValue: false)
            inspectorMusicSyncControls(for: control)
        }
    }

    @ViewBuilder private func effectComboControl(_ combo: SceneInspectorEffectCombo, effect: SceneInspectorEffect) -> some View {
        let selection = Binding<Int>(get: { model.comboValue(combo) }, set: { model.setComboValue($0, combo: combo) })
        if combo.options.isEmpty {
            Toggle(combo.title, isOn: Binding(get: { selection.wrappedValue != 0 },
                                              set: { selection.wrappedValue = $0 ? 1 : 0 }))
                .toggleStyle(.checkbox)
        } else {
            Picker(combo.title, selection: selection) {
                ForEach(Self.optionGroups(combo), id: \.offset) { group in
                    if let heading = group.heading {
                        Section(heading) {
                            ForEach(group.options, id: \.value) { option in Text(option.title).tag(option.value) }
                        }
                    } else {
                        ForEach(group.options, id: \.value) { option in Text(option.title).tag(option.value) }
                    }
                }
            }
        }
    }

    /// The combo's options in runs of one editor group (WE's "Native (fast)" / "Emulated (slow)"
    /// blend modes), in order; one run without a heading for authored options.
    private static func optionGroups(_ combo: SceneInspectorEffectCombo)
        -> [(offset: Int, heading: String?, options: [(title: String, value: Int)])] {
        // Shared with the Wallpaper Editor (`InspectorOptionGroups`).
        InspectorOptionGroups.groups(combo.options.map { InspectorOption(title: $0.title, value: $0.value, group: $0.group) })
            .map { group -> (offset: Int, heading: String?, options: [(title: String, value: Int)]) in
                (group.id, group.heading, group.options.map { (title: $0.title, value: $0.value) })
            }
    }

    @ViewBuilder private func inspectorMusicSyncControls(for control: SceneInspectorEffectControl) -> some View {
        let isEnabled = Binding<Bool>(
            get: { model.musicSyncEnabled(for: control) },
            set: { model.setMusicSyncEnabled($0, for: control) }
        )
        Toggle("Sync to Music", isOn: isEnabled)
            .toggleStyle(.checkbox)
            .font(.caption)
            .help(SceneHelp.musicSyncSource)
        if isEnabled.wrappedValue {
            let span = max(control.maximum - control.minimum, 0.001)
            let amount = Binding<Double>(
                get: { model.musicAmount(for: control) },
                set: { model.setMusicAmount($0, for: control) }
            )
            HStack {
                Text("Music Amount")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                NumericSliderInput(value: amount, range: -span...span,
                                   defaultValue: 0, fractionDigits: 3,
                                   sliderWidth: 100, fieldWidth: 64)
            }
        }
    }

    @ViewBuilder private func movementControls(for item: SceneInspectorItem?) -> some View {
        let origin = item.map(model.origin(for:))
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Move Element", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.title3.bold())
                Spacer()
                if let origin {
                    Text("X \(Int(origin.x))  Y \(Int(origin.y))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Color.clear.frame(width: 48, height: 40)
                    moveButton(systemImage: "arrow.up", title: "Move Up",
                               help: "Move up. Shift = 50 px, Control = 1 px, default = 10 px") {
                        guard let item else { return }
                        model.moveObject(item, deltaX: 0, deltaY: movementStep())
                    }
                    Color.clear.frame(width: 48, height: 40)
                }
                GridRow {
                    moveButton(systemImage: "arrow.left", title: "Move Left",
                               help: "Move left. Shift = 50 px, Control = 1 px, default = 10 px") {
                        guard let item else { return }
                        model.moveObject(item, deltaX: -movementStep(), deltaY: 0)
                    }
                    Text("Move")
                        .font(.callout.weight(.semibold))
                        .frame(width: 58, height: 40)
                    moveButton(systemImage: "arrow.right", title: "Move Right",
                               help: "Move right. Shift = 50 px, Control = 1 px, default = 10 px") {
                        guard let item else { return }
                        model.moveObject(item, deltaX: movementStep(), deltaY: 0)
                    }
                }
                GridRow {
                    Color.clear.frame(width: 48, height: 40)
                    moveButton(systemImage: "arrow.down", title: "Move Down",
                               help: "Move down. Shift = 50 px, Control = 1 px, default = 10 px") {
                        guard let item else { return }
                        model.moveObject(item, deltaX: 0, deltaY: -movementStep())
                    }
                    Color.clear.frame(width: 48, height: 40)
                }
            }
            // The arrows point at screen directions, so the pad doesn't mirror in right-to-left languages.
            .environment(\.layoutDirection, .leftToRight)
            .disabled(item == nil)
            .opacity(item == nil ? 0.4 : 1)
            Text(item == nil ? "Select an object to move it." : "Arrow keys work when this panel is focused. Shift moves faster, Control moves slower.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(GroupBoxed())
    }

    private func moveButton(systemImage: String, title: LocalizedStringKey, help: LocalizedStringKey,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.title3.weight(.semibold))
                .frame(width: 48, height: 40)
        }
        .glassButtonStyle(.prominent)
        .help(help)
    }

    @ViewBuilder private func scaleControls(for item: SceneInspectorItem?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Size", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.headline)
                Spacer()
                if let item {
                    Text(verbatim: model.scale(for: item).formatted(.number.precision(.fractionLength(2))) + "×")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if let item {
                let binding = Binding(
                    get: { model.scale(for: item) },
                    set: { model.setObjectScale(item, scale: $0) })
                NumericSliderInput(value: binding, range: 0.05...5,
                                   defaultValue: 1, step: 0.05, suffix: "x",
                                   fractionDigits: 2, sliderWidth: 120, fieldWidth: 52)
                Button("Reset to 1x") { model.setObjectScale(item, scale: 1) }
                    .buttonStyle(.link)
                    .font(.caption)
                if item.kind == "Image" {
                    appearanceControls(for: item)
                    blendModePicker(for: item)
                }
                if !SceneInspectorModel.blendingOptions(for: item).isEmpty {
                    materialBlendingPicker(for: item)
                }
            } else {
                Text("Select an object to resize it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The image layer's opacity and colour (its `alpha` and `color`), when nothing else sets them.
    @ViewBuilder private func appearanceControls(for item: SceneInspectorItem) -> some View {
        if let alpha = model.alpha(for: item) {
            SceneLayerOpacitySlider(value: alpha) { model.setAlpha($0, for: item) }
        }
        if let color = model.color(for: item) {
            ColorPicker(selection: Binding(get: { Color(red: color.x, green: color.y, blue: color.z) },
                                           set: { model.setColor($0, for: item) }),
                        supportsOpacity: false) {
                Text("Color")
            }
            .anchorsColorPanel()
        }
    }

    /// The selected layer's adjustments in an isolated mode's panel: the Wallpaper mode's own
    /// controls (visibility, move, size, opacity and colour, blending, alignment, effects), on the
    /// isolated store.
    @ViewBuilder private func layerAdjustments(for item: SceneInspectorItem?) -> some View {
        if let item, !item.isSynthetic {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(get: { item.isSwitchedOn }, set: { model.setObjectVisible($0, item: item) })) {
                    Text(verbatim: item.name)
                        .font(.headline)
                        .lineLimit(1)
                }
                .toggleStyle(.switch)
                .help(Self.visibilityHelp(item))
                movementControls(for: item)
                scaleControls(for: item)
                alignmentControls(for: item)
                effectList(for: item)
            }
            .modifier(ArrowKeyMove { direction in move(item, direction: direction) })
        } else {
            Text("Select a layer in the list to adjust it here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// The image layer's blend mode, WE's 33 in its editor's order and groups.
    private func blendModePicker(for item: SceneInspectorItem) -> some View {
        let combo = model.blendModeCombo
        return Picker(combo.title, selection: Binding(get: { model.blendMode(for: item) },
                                                      set: { model.setBlendMode($0, for: item) })) {
            ForEach(Self.optionGroups(combo), id: \.offset) { group in
                Section(group.heading ?? "") {
                    ForEach(group.options, id: \.value) { option in Text(option.title).tag(option.value) }
                }
            }
        }
    }

    /// The blending the layer's material draws with, of those its kind of layer draws
    /// (`WEMaterialBlending`), and a reset to its material's own.
    private func materialBlendingPicker(for item: SceneInspectorItem) -> some View {
        HStack {
            Picker("Blending", selection: Binding(get: { model.materialBlending(for: item) },
                                                  set: { model.setMaterialBlending($0, for: item) })) {
                ForEach(SceneInspectorModel.blendingOptions(for: item), id: \.self) { blending in
                    Self.title(of: blending).tag(blending)
                }
            }
            Button("Reset") { model.resetMaterialBlending(for: item) }
                .buttonStyle(.link)
                .font(.caption)
                .disabled(model.materialBlending(for: item) == model.authoredBlending(for: item))
        }
    }

    private static func title(of blending: WEMaterialBlending) -> Text {
        switch blending {
        case .normal: Text("Normal")
        case .translucent: Text("Translucent")
        case .additive: Text("Additive")
        case .alphaToCoverage: Text("Alpha to Coverage")
        }
    }

    private func movementColumn(for item: SceneInspectorItem?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                movementControls(for: item)
                Divider()
                scaleControls(for: item)
                Divider()
                alignmentControls(for: item)
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Step")
                        .font(.headline)
                    Text("Default 10 px")
                    Text("Shift 50 px")
                    Text("Control 1 px")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .modifier(ArrowKeyMove { direction in
            if let item { move(item, direction: direction) }
        })
    }

    private func alignmentControls(for item: SceneInspectorItem?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Align Element", systemImage: "align.horizontal.center")
                .font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                Text("Horizontal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    alignmentButton("Left", help: "Align Left", systemImage: "align.horizontal.left") {
                        guard let item else { return }
                        model.alignObject(item, horizontal: .left)
                    }
                    alignmentButton("Center", help: "Align Center", systemImage: "align.horizontal.center") {
                        guard let item else { return }
                        model.alignObject(item, horizontal: .center)
                    }
                    alignmentButton("Right", help: "Align Right", systemImage: "align.horizontal.right") {
                        guard let item else { return }
                        model.alignObject(item, horizontal: .right)
                    }
                }
                // Left, centre, right on screen, in every language.
                .environment(\.layoutDirection, .leftToRight)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Vertical")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    alignmentButton("Top", help: "Align Top", systemImage: "align.vertical.top") {
                        guard let item else { return }
                        model.alignObject(item, vertical: .top)
                    }
                    alignmentButton("Middle", help: "Align Middle", systemImage: "align.vertical.center") {
                        guard let item else { return }
                        model.alignObject(item, vertical: .center)
                    }
                    alignmentButton("Bottom", help: "Align Bottom", systemImage: "align.vertical.bottom") {
                        guard let item else { return }
                        model.alignObject(item, vertical: .bottom)
                    }
                }
            }
        }
        .disabled(item == nil)
        .opacity(item == nil ? 0.4 : 1)
    }

    private func alignmentButton(_ title: LocalizedStringKey, help: LocalizedStringKey, systemImage: String,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.callout.weight(.semibold))
                Text(title)
                    .font(.caption2)
            }
            .frame(width: 68, height: 46)
        }
        .glassButtonStyle()
        .help(help)
    }

    private func move(_ item: SceneInspectorItem, direction: MoveCommandDirection) {
        let step = movementStep()
        switch direction {
        case .up:
            model.moveObject(item, deltaX: 0, deltaY: step)
        case .down:
            model.moveObject(item, deltaX: 0, deltaY: -step)
        case .left:
            model.moveObject(item, deltaX: -step, deltaY: 0)
        case .right:
            model.moveObject(item, deltaX: step, deltaY: 0)
        @unknown default:
            break
        }
    }

    private func movementStep() -> Double {
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift) { return 50 }
        if flags.contains(.control) { return 1 }
        return 10
    }

    private func parameterLabel(_ title: String, help: String) -> some View {
        HStack(spacing: 5) {
            Text(title)
            InfoTip(help)
        }
    }

    private func parameterHelp(_ control: SceneInspectorEffectControl, effect: String? = nil) -> String {
        SceneHelp.parameter(effect: effect, key: control.key, title: control.title,
                            displaysDegrees: control.displaysDegrees)
    }


    @ViewBuilder private func decodedTextureList(for item: SceneInspectorItem) -> some View {
        if model.loadingItemID == item.id {
            ProgressView("Decoding textures...")
        } else if model.decodedItemID == item.id {
            ForEach(model.decodedTextures) { texture in
                VStack(alignment: .leading, spacing: 6) {
                    Text(texture.path).font(.caption.monospaced()).foregroundStyle(.secondary)
                    Image(nsImage: texture.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 420)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            if !item.texturePaths.isEmpty && model.decodedTextures.isEmpty {
                ContentUnavailableView("Texture Unavailable", systemImage: "photo.badge.exclamationmark")
            }
        }
    }

    private func loadSelectedTextures() {
        guard let item = model.items.first(where: { $0.id == selectedID }) else { return }
        model.loadTextures(for: item)
    }

    @ViewBuilder private func detailList(_ title: LocalizedStringKey, values: [String]) -> some View {
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                ForEach(values, id: \.self) { Text($0).font(.caption.monospaced()) }
            }
        }
    }

    @ViewBuilder private func editableAssetBlock(title: LocalizedStringKey, isParticle: Bool, text: String,
                                                path: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button("Save") {
                    model.saveAssetJSON(text, path: path)
                }
                .buttonStyle(.borderedProminent)
            }
            TextEditor(text: Binding(
                get: { text },
                set: { value in
                    if let itemIndex = model.items.firstIndex(where: { $0.id == selectedID }) {
                        if isParticle {
                            model.items[itemIndex].rawParticle = value
                        } else {
                            model.items[itemIndex].rawMaterial = value
                        }
                    }
                }
            ))
            .font(.system(.caption, design: .monospaced))
            .frame(minHeight: 220)
            .padding(6)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    @ViewBuilder private func editableObjectBlock(for item: SceneInspectorItem) -> some View {
        if item.isSynthetic {
            VStack(alignment: .leading, spacing: 6) {
                Text("Layer Details").font(.headline)
                Text(model.items.first(where: { $0.id == item.id })?.rawObject ?? item.rawObject)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Object Properties").font(.headline)
                    Spacer()
                    Button("Save") {
                        let current = model.items.first(where: { $0.id == item.id })?.rawObject ?? item.rawObject
                        model.saveObjectJSON(current, item: item)
                    }
                    .buttonStyle(.borderedProminent)
                }
                TextEditor(text: Binding(
                    get: { model.items.first(where: { $0.id == item.id })?.rawObject ?? item.rawObject },
                    set: { value in
                        guard let index = model.items.firstIndex(where: { $0.id == item.id }) else { return }
                        model.items[index].rawObject = value
                    }
                ))
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 220)
                .padding(6)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}

/// A layer's opacity: the slider shows the value as it moves and saves it when the drag ends (an
/// object JSON edit reloads the scene).
private struct SceneLayerOpacitySlider: View {
    let value: Double
    let onCommit: (Double) -> Void
    @State private var draft: Double?

    var body: some View {
        let shown = draft ?? value
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Opacity")
                Spacer()
                Text(shown, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { draft ?? value }, set: { draft = $0 }), in: 0...1, onEditingChanged: { editing in
                guard !editing, let draft else { return }
                onCommit(draft)
                self.draft = nil
            })
        }
    }
}

/// Arrow keys nudge the selected object while this panel has keyboard focus.
private struct ArrowKeyMove: ViewModifier {
    let onMove: (MoveCommandDirection) -> Void

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .onMoveCommand(perform: onMove)
    }
}

/// A native group box around a block of controls.
private struct GroupBoxed: ViewModifier {
    func body(content: Content) -> some View {
        GroupBox { content }
    }
}

/// Ties a `FocusState` to the window's search field, where the OS can (`searchFocused`, macOS 15).
private struct SearchFieldFocus: ViewModifier {
    let isFocused: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.searchFocused(isFocused)
        } else {
            content
        }
    }
}
