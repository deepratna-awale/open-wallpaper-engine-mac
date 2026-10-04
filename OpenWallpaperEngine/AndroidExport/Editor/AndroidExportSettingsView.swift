import SwiftUI

/// The Android Export mode's Export Settings: the device (or a custom size) and the status bar
/// guide, the crop's zoom, where the pointer rests, the output (Pre-Rendered's video size, frame
/// rate and length, or Dynamic's quality), then the selected layer's adjustments and the user
/// properties, all of them the mode's own (`IsolatedSceneEditSession`). The same view is the
/// mode's right-hand panel and the sheet shown before an export.
struct AndroidExportSettingsView<Layer: View>: View {
    @ObservedObject var model: AndroidExportEditorModel
    var showsExportButtons = true
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
                outputSection
                if showsExportButtons {
                    Divider()
                    exportSection
                }
                if let error = model.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
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
    }

    private static func pixels(_ size: SIMD2<Int>) -> String {
        let number = IntegerFormatStyle<Int>.number.grouping(.never)
        return "\(size.x.formatted(number)) × \(size.y.formatted(number))"
    }

    // MARK: Device

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Device")
                .font(.headline)
            AndroidDeviceComboBox(selection: model.device, onChoose: { model.choose($0) })
            if model.device == nil { customFields }
            Text("\(Self.pixels(model.screenPixels)) pixels · \(AndroidCustomSize.aspectText(model.screenPixels))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            if model.device?.kind == .tablet {
                Picker("Orientation", selection: Binding(get: { model.isLandscape }, set: { model.setLandscape($0) })) {
                    Text("Portrait").tag(false)
                    Text("Landscape").tag(true)
                }
                .pickerStyle(.segmented)
                .help("Make the wallpaper for the tablet held upright or sideways")
            }
            Toggle("Show Status Bar Guide", isOn: $model.showsStatusBarGuide)
                .help("Show where Android draws the status bar over the wallpaper")
        }
    }

    private var customFields: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                TextField("Width", text: Binding(get: { model.customWidth }, set: { model.setCustom(width: $0, height: model.customHeight) }))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 90)
                    .accessibilityLabel(Text("Width"))
                Text(verbatim: "×")
                    .foregroundStyle(.secondary)
                TextField("Height", text: Binding(get: { model.customHeight }, set: { model.setCustom(width: model.customWidth, height: $0) }))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 90)
                    .accessibilityLabel(Text("Height"))
                Text("pixels")
                    .foregroundStyle(.secondary)
            }
            if let issue = model.customIssue {
                Text(issue.message)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Crop and pointer

    private var zoomSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Zoom")
                .font(.headline)
            Slider(value: Binding(get: { model.zoom }, set: { model.zoom = $0 }), in: 1...LivePhotoCrop.maximumZoom) {
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
                    LivePhotoParallaxPad(position: model.parallaxPosition, aspect: model.aspect,
                                         onChange: { model.setParallaxPosition($0) })
                        .help("Drag the dot to where the pointer rests over the wallpaper")
                    Button("Reset to Center") { model.setParallaxPosition(LivePhotoParallax.centre) }
                        .glassButtonStyle()
                        .disabled(model.parallaxPosition == LivePhotoParallax.centre)
                        .help("Put the pointer back in the middle of the wallpaper")
                }
                Text("The preview and the video show the parallax as if the pointer rested here.")
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

    // MARK: Output

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output")
                .font(.headline)
            Picker("Output", selection: Binding(get: { model.isPreRendered }, set: { preRendered in
                model.chooseMode(preRendered ? .preRendered : .balanced)
            })) {
                Text("Pre-Rendered").tag(true)
                Text("Dynamic").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("Dynamic runs live on the phone, with its clock, audio and properties; Pre-Rendered is a fixed video")
            Text(model.isPreRendered
                 ? "Pre-Rendered: a fixed video loop of this version, framed as the preview shows it."
                 : "Dynamic: runs live on the phone. Clocks tick, audio-reactive layers follow the phone's sound, and the wallpaper's properties can be changed there.")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            if model.isPreRendered { videoSettings } else { dynamicSettings }
        }
    }

    @ViewBuilder
    private var videoSettings: some View {
        Picker("Video Size", selection: Binding(get: { model.videoSize }, set: { model.setVideoSize($0) })) {
            ForEach(AndroidVideoSize.allCases) { Text($0.title).tag($0) }
        }
        Picker("FPS", selection: $model.options.frameRate) {
            ForEach(AndroidExportOptions.frameRates, id: \.self) { Text(verbatim: "\($0)").tag($0) }
        }
        Stepper(value: Binding(get: { model.seconds }, set: { model.setSeconds($0) }), in: AndroidExportEditorModel.lengths, step: 5) {
            Text("Length: \(Duration.seconds(model.seconds).formatted(.units(allowed: [.seconds], width: .abbreviated)))")
        }
        let rate = (Double(model.bitRate) / 1_000_000).formatted(.number.precision(.fractionLength(1)))
        Text(verbatim: "\(Self.pixels(model.outputPixels)), \(model.options.frameRate) FPS, H.264, \(rate) Mbit/s")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        Text("Pre-rendering a scene wallpaper can drastically improve performance, but dynamic elements like clocks or interactive touch events will not work.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var dynamicSettings: some View {
        Picker("Quality", selection: Binding(get: { model.options.mode }, set: { model.chooseMode($0) })) {
            Text(AndroidExportSheet.label(.highQuality)).tag(AndroidExportOptions.Mode.highQuality)
            Text(AndroidExportSheet.label(.balanced)).tag(AndroidExportOptions.Mode.balanced)
        }
        Toggle("Pixel art optimization", isOn: $model.options.pixelArt)
        Picker("Texture Reduction", selection: $model.options.textureReduction) {
            Text("Highest Quality - (Don't reduce texture resolution)").tag(AndroidExportOptions.TextureReduction.original)
            Text("Better Performance - (Reduce textures to half their resolution)").tag(AndroidExportOptions.TextureReduction.half)
            Text("High Performance - (Reduce texture resolution by 4)").tag(AndroidExportOptions.TextureReduction.quarter)
        }
        .disabled(model.options.pixelArt)
        Label("Your layer edits are baked into the package's scene.json, and the property values you set become its project.json defaults, so the phone starts with them. The phone renders the scene itself, so the crop and the parallax position don't apply.",
              systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Export

    @ViewBuilder private var exportSection: some View {
        if let queue = model.queue {
            AndroidEditorExportProgress(queue: queue, model: model)
        } else {
            AndroidEditorExportButtons(model: model)
        }
    }
}

/// "Save .mpkg…" and "Send over Wi-Fi…", each after the Export Settings sheet.
private struct AndroidEditorExportButtons: View {
    @ObservedObject var model: AndroidExportEditorModel

    var body: some View {
        HStack {
            Button {
                model.requestExport(.wifi)
            } label: {
                Label("Send over Wi-Fi…", systemImage: "wifi")
            }
            .glassButtonStyle(.prominent)
            .help("Review the export settings, then export the .mpkg and serve it to your Android device on this network")
            Button("Save .mpkg…") { model.requestExport(.save) }
                .glassButtonStyle()
                .help("Review the export settings, then export the .mpkg to a file")
        }
    }
}

/// The export's progress, then what it made.
private struct AndroidEditorExportProgress: View {
    @ObservedObject var queue: AndroidExportQueue
    @ObservedObject var model: AndroidExportEditorModel

    var body: some View {
        if queue.isRunning {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: queue.progress) {
                    Text("Converting wallpaper")
                }
                Button("Cancel", role: .cancel) { model.cancel() }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                AndroidEditorExportButtons(model: model)
                if let batch = model.batch, !batch.outputs.isEmpty {
                    HStack {
                        Button("Show in Finder") { model.showInFinder() }
                            .glassButtonStyle()
                        if model.wifiSend == nil {
                            Button {
                                model.wifiSend = AndroidWiFiSendRequest(batch: batch)
                            } label: {
                                Label("Send Again", systemImage: "wifi")
                            }
                            .glassButtonStyle()
                            .help("Serve the exported .mpkg over Wi-Fi again")
                        }
                    }
                }
            }
        }
    }
}

/// The Export Settings as a sheet: before an export (Cancel, and the export as the confirm
/// button), or opened from the toolbar (Done, and both exports).
struct AndroidExportSettingsSheetView<Layer: View>: View {
    @ObservedObject var model: AndroidExportEditorModel
    let sheet: AndroidEditorSheet
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
            AndroidExportSettingsView(model: model, showsExportButtons: false, layer: layer)
            Divider()
            footer
                .padding()
        }
        .frame(width: 440, height: 680)
    }

    @ViewBuilder private var footer: some View {
        HStack {
            Spacer()
            switch sheet {
            case .settings:
                Button("Save .mpkg…") { model.confirm(.save) }
                    .glassButtonStyle()
                Button {
                    model.confirm(.wifi)
                } label: {
                    Label("Send over Wi-Fi…", systemImage: "wifi")
                }
                .glassButtonStyle()
                Button("Done") { model.sheet = nil }
                    .glassButtonStyle(.prominent)
                    .keyboardShortcut(.defaultAction)
            case .confirm(let action):
                Button("Cancel", role: .cancel) { model.sheet = nil }
                    .glassButtonStyle()
                    .keyboardShortcut(.cancelAction)
                Button {
                    model.confirm(action)
                } label: {
                    switch action {
                    case .wifi: Label("Send over Wi-Fi…", systemImage: "wifi")
                    case .save: Text("Save .mpkg…")
                    }
                }
                .glassButtonStyle(.prominent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// Presents the Android Export Settings sheet and the Wi-Fi sheet while `model` asks for them;
/// `onClose` runs when the settings sheet closes. Without a model (another mode) it does nothing.
struct AndroidExportSheetHost<Layer: View>: ViewModifier {
    let model: AndroidExportEditorModel?
    let onClose: () -> Void
    @ViewBuilder let layer: () -> Layer

    func body(content: Content) -> some View {
        if let model {
            content.modifier(AndroidExportSheetPresenter(model: model, onClose: onClose, layer: layer))
        } else {
            content
        }
    }
}

private struct AndroidExportSheetPresenter<Layer: View>: ViewModifier {
    @ObservedObject var model: AndroidExportEditorModel
    let onClose: () -> Void
    @ViewBuilder let layer: () -> Layer

    func body(content: Content) -> some View {
        content
            .sheet(item: $model.sheet, onDismiss: onClose) { sheet in
                AndroidExportSettingsSheetView(model: model, sheet: sheet, layer: layer)
            }
            .sheet(item: $model.wifiSend) { request in
                AndroidWiFiSendSheet(session: AndroidWiFiSession(batch: request.batch), dismiss: { model.wifiSend = nil })
            }
    }
}
