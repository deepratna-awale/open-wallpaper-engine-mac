import SwiftUI

/// The Export Settings: the device, the lock-screen guide, the crop and zoom, where the pointer
/// rests (for a scene with parallax), the clip (its motion timeline, start and length), the
/// movie's quality, the Photos album, then the selected
/// layer's adjustments and the user properties, all of them the export mode's own (`IsolatedSceneEditSession`). The same view is the
/// mode's right-hand panel and the sheet shown before an export.
struct LivePhotoExportSettingsView<Layer: View>: View {
    @ObservedObject var model: LivePhotoExportModel
    /// The panel has the export buttons and progress; the sheet has its own buttons.
    var showsExportButtons = true
    /// The selected layer's adjustments (the Scene Editor (Live)'s own controls, on the isolated store).
    @ViewBuilder let layer: () -> Layer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                deviceSection
                Divider()
                zoomSection
                if let followsPointer = model.followsPointer {
                    Divider()
                    parallaxSection(followsPointer)
                }
                Divider()
                motionSection
                Divider()
                qualitySection
                Divider()
                photosSection
                if showsExportButtons {
                    Divider()
                    exportSection
                }
                if let error = model.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Layer Adjustments")
                        .font(.headline)
                    layer()
                }
                Divider()
                Text("Only this export changes. The wallpaper on your desktop keeps its properties and edits.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SceneUserPropertiesView(wallpaper: model.wallpaper, scopes: [model.session.scope])
            }
            .padding()
        }
        .onAppear { if showsExportButtons { model.measureMotionIfNeeded() } }
    }

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Device")
                .font(.headline)
            DeviceComboBox(selection: $model.device)
            Text("\(model.device.pixelSize.x) × \(model.device.pixelSize.y) pixels")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Toggle("Show Lock Screen Guide", isOn: $model.showsLockScreenGuide)
                .help("Show where the lock screen draws the date and the clock")
            if model.device.family == .iPad {
                Toggle("Preview in Landscape", isOn: $model.showsLandscape)
                    .help("Show the part of the picture an iPad shows when it is turned sideways")
                Text("The Live Photo is exported in portrait. In landscape, iPad turns the lock screen and crops the picture to fill it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var zoomSection: some View {
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
    }

    @ViewBuilder
    private func parallaxSection(_ followsPointer: Bool) -> some View {
        if followsPointer {
            VStack(alignment: .leading, spacing: 6) {
                Text("Parallax Position")
                    .font(.headline)
                HStack(alignment: .bottom, spacing: 12) {
                    LivePhotoParallaxPad(position: model.parallaxPosition,
                                         aspect: Double(model.device.pixelSize.x) / Double(max(model.device.pixelSize.y, 1)),
                                         onChange: { model.setParallaxPosition($0) })
                        .help("Drag the dot to where the pointer rests over the wallpaper")
                    Button("Reset to Center") { model.setParallaxPosition(LivePhotoParallax.centre) }
                        .glassButtonStyle()
                        .disabled(model.parallaxPosition == LivePhotoParallax.centre)
                        .help("Put the pointer back in the middle of the wallpaper")
                }
                Text("The preview and the Live Photo show the parallax as if the pointer rested here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text("Parallax Position: this wallpaper doesn't follow the pointer.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var motionSection: some View {
        let frame = 1.0 / Double(LivePhotoClip.frameRate)
        let latestStart = max(LivePhotoClip.timelineLength - model.clipLength, 0)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Motion")
                .font(.headline)
            LivePhotoMotionTimeline(model: model)
            Slider(value: Binding(get: { model.clipStart }, set: { model.clipStart = $0 }),
                   in: 0...latestStart, step: frame) {
                Text("Clip Start")
            }
            Slider(value: Binding(get: { model.clipLength }, set: { model.clipLength = $0 }),
                   in: LivePhotoClip.shortestChosen...LivePhotoClip.duration, step: frame) {
                Text("Clip Length")
            }
            Text("\(model.clipStart.formatted(.number.precision(.fractionLength(1)))) s – \(model.clip.end.formatted(.number.precision(.fractionLength(1)))) s")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text("A Live Photo moves for up to 3 seconds; its photo is the middle frame.")
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
    }

    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Quality", selection: $model.quality) {
                ForEach(LivePhotoQuality.allCases) { quality in
                    Text(quality.title).tag(quality)
                }
            }
            Text("Lower quality makes a smaller movie.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Also Save to Photos Album", isOn: Binding(get: { model.savesToPhotos },
                                                              set: { model.setSavesToPhotos($0) }))
                .help("Appears on your iPhone and iPad when iCloud Photos is on in Photos settings.")
            if model.savesToPhotos {
                TextField("Album", text: $model.photosAlbum, prompt: Text(verbatim: LivePhotoAlbumSync.defaultAlbumName))
                    .textFieldStyle(.roundedBorder)
                Text("Appears on your iPhone and iPad when iCloud Photos is on in Photos settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.photosAccessDenied {
                Text("Open Wallpaper Engine isn't allowed to add to your Photos library. Allow it in Privacy & Security, then turn this on again.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Privacy Settings") { model.openPhotosPrivacySettings() }
            }
            if let notice = model.photosNotice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var exportSection: some View {
        if model.isRendering {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: model.progress) {
                    Text("Rendering…")
                }
                Button("Cancel", role: .cancel) { model.cancel() }
            }
        } else {
            // Side by side, or stacked at full width when the panel is too narrow for both labels.
            ViewThatFits(in: .horizontal) {
                HStack { exportButtons(fill: false) }
                VStack(alignment: .leading) { exportButtons(fill: true) }
            }
        }
    }

    @ViewBuilder private func exportButtons(fill: Bool) -> some View {
        Button {
            model.requestExport(.airDrop)
        } label: {
            Label("Send with AirDrop", systemImage: "square.and.arrow.up")
                .frame(maxWidth: fill ? .infinity : nil)
        }
        .glassButtonStyle(.prominent)
        .help("Review the export settings, then render the Live Photo and send it with AirDrop")
        Button {
            model.requestExport(.save)
        } label: {
            Text("Save…")
                .frame(maxWidth: fill ? .infinity : nil)
        }
        .glassButtonStyle()
        .help("Review the export settings, then render the Live Photo and save its photo and movie to a folder")
    }
}

/// The Export Settings as a sheet: before an export (Cancel, and the export as the confirm
/// button), or opened from the toolbar (Done, and both exports).
struct LivePhotoExportSheetView<Layer: View>: View {
    @ObservedObject var model: LivePhotoExportModel
    let sheet: LivePhotoExportSheet
    @ViewBuilder let layer: () -> Layer

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Export Settings")
                    .font(.title2.bold())
                Text(verbatim: model.wallpaper.project.displayTitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding([.horizontal, .top])
            LivePhotoExportSettingsView(model: model, showsExportButtons: false, layer: layer)
            Divider()
            footer
                .padding()
        }
        .frame(width: 440, height: 680)
    }

    @ViewBuilder private var footer: some View {
        HStack {
            switch sheet {
            case .settings:
                Spacer()
                Button("Save…") { model.confirm(.save) }
                    .glassButtonStyle()
                Button {
                    model.confirm(.airDrop)
                } label: {
                    Label("Send with AirDrop", systemImage: "square.and.arrow.up")
                }
                .glassButtonStyle()
                Button("Done") { model.sheet = nil }
                    .glassButtonStyle(.prominent)
                    .keyboardShortcut(.defaultAction)
            case .confirm(let action):
                Spacer()
                Button("Cancel", role: .cancel) { model.sheet = nil }
                    .glassButtonStyle()
                    .keyboardShortcut(.cancelAction)
                confirmButton(action)
            }
        }
    }

    private func confirmButton(_ action: LivePhotoExportAction) -> some View {
        Button {
            model.confirm(action)
        } label: {
            switch action {
            case .airDrop: Label("Send with AirDrop", systemImage: "square.and.arrow.up")
            case .save: Text("Save…")
            }
        }
        .glassButtonStyle(.prominent)
        .keyboardShortcut(.defaultAction)
    }
}

/// Presents the Export Settings sheet while `model` asks for it (`LivePhotoExportModel.sheet`);
/// `onClose` runs when it closes. Without a model (another mode) it does nothing.
struct LivePhotoExportSheetHost<Layer: View>: ViewModifier {
    let model: LivePhotoExportModel?
    let onClose: () -> Void
    @ViewBuilder let layer: () -> Layer

    func body(content: Content) -> some View {
        if let model {
            content.modifier(LivePhotoExportSheetPresenter(model: model, onClose: onClose, layer: layer))
        } else {
            content
        }
    }
}

private struct LivePhotoExportSheetPresenter<Layer: View>: ViewModifier {
    @ObservedObject var model: LivePhotoExportModel
    let onClose: () -> Void
    @ViewBuilder let layer: () -> Layer

    func body(content: Content) -> some View {
        content.sheet(item: $model.sheet, onDismiss: onClose) { sheet in
            LivePhotoExportSheetView(model: model, sheet: sheet, layer: layer)
        }
    }
}
