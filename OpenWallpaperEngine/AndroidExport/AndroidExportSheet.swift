import SwiftUI

/// The selection a library "Export for Android…" opens the sheet for.
struct AndroidExportSelection: Identifiable {
    let id = UUID()
    let wallpapers: [WEWallpaper]
}

/// WE's "Exporting … for usage on Android" dialog: Dynamic (High Quality, Balanced) or
/// Pre-Rendered (High Performance), the advanced settings, the video's cropping, preset, frame
/// rate and alignment over a live preview of the portrait crop, then the export's progress.
struct AndroidExportSheet: View {
    @StateObject var model: AndroidExportModel
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Exporting \(model.title) for usage on Android")
                .font(.title3.weight(.semibold))
            if let queue = model.queue {
                AndroidExportProgressView(queue: queue, model: model)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) { settings }
                }
            }
            footer
        }
        .padding(20)
        .frame(width: 640, height: 640)
        .onDisappear { model.close() }
        .sheet(item: $model.wifiSend) { request in
            AndroidWiFiSendSheet(session: AndroidWiFiSession(batch: request.batch), dismiss: { model.wifiSend = nil })
        }
    }

    @ViewBuilder
    private var settings: some View {
        Text("Wallpaper Engine will optimize your wallpapers for your device to achieve the best possible performance. Please choose the performance rating that best represents your device. You can change this selection at a later time and reupload the wallpapers to your device if either the visual quality or performance are not to your liking.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        if model.rows.count > 1 { rowList }
        if model.hasScenes {
            modeButtons
            if model.hasDynamic {
                Toggle("Show advanced settings", isOn: $model.showsAdvancedSettings)
                if model.showsAdvancedSettings { advancedSettings }
            }
            if model.hasPreRendered { videoSettings }
        }
        if let error = model.errorMessage {
            Text(error).font(.caption).foregroundStyle(.red)
        }
    }

    // MARK: Rows

    private var rowList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(model.rows) { row in
                HStack(spacing: 8) {
                    Text(row.wallpaper.project.displayTitle)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let reason = row.skipReason {
                        Label(reason, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if row.isScene {
                        Picker("Performance", selection: Binding(get: { model.mode(of: row) }, set: { model.setMode($0, of: row) })) {
                            ForEach(AndroidExportOptions.Mode.allCases, id: \.self) { mode in Text(Self.label(mode)).tag(mode) }
                        }
                        .labelsHidden()
                        .frame(width: 170)
                        if model.mode(of: row) == .preRendered {
                            Button {
                                model.showPreview(of: row.id)
                            } label: {
                                Image(systemName: model.previewID == row.id ? "eye.fill" : "eye")
                            }
                            .borderlessOnGlassButtonStyle()
                            .help("Preview")
                        }
                    } else {
                        Text(LocalizedLabels.wallpaperType(row.wallpaper.project.type))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(10)
        .glassBackground(in: RoundedRectangle(cornerRadius: 12, style: .continuous)) { $0.background(.quaternary, in: RoundedRectangle(cornerRadius: 12)) }
    }

    // MARK: Modes

    static func label(_ mode: AndroidExportOptions.Mode) -> LocalizedStringKey {
        switch mode {
        case .highQuality: return "High Quality"
        case .balanced: return "Balanced"
        case .preRendered: return "High Performance"
        }
    }

    private static func icon(_ mode: AndroidExportOptions.Mode) -> String {
        switch mode {
        case .highQuality: return "gauge.with.dots.needle.67percent"
        case .balanced: return "gauge.with.dots.needle.50percent"
        case .preRendered: return "film"
        }
    }

    private var modeButtons: some View {
        HStack(alignment: .top, spacing: 16) {
            group("Dynamic", modes: [.highQuality, .balanced])
            group("Pre-Rendered", modes: [.preRendered])
        }
        .frame(maxWidth: .infinity)
    }

    private func group(_ title: LocalizedStringKey, modes: [AndroidExportOptions.Mode]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            GlassGroup(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(modes, id: \.self) { mode in
                        Button {
                            model.choose(mode)
                        } label: {
                            VStack(spacing: 8) {
                                Text(Self.label(mode))
                                Image(systemName: Self.icon(mode)).font(.system(size: 28))
                            }
                            .frame(width: 130, height: 70)
                        }
                        .glassButtonStyle(model.options.mode == mode ? .prominent : .standard)
                    }
                }
            }
        }
    }

    // MARK: Advanced settings

    private var advancedSettings: some View {
        Form {
            Toggle("Pixel art optimization", isOn: $model.options.pixelArt)
            Picker("Texture Reduction", selection: $model.options.textureReduction) {
                Text("Highest Quality - (Don't reduce texture resolution)").tag(AndroidExportOptions.TextureReduction.original)
                Text("Better Performance - (Reduce textures to half their resolution)").tag(AndroidExportOptions.TextureReduction.half)
                Text("High Performance - (Reduce texture resolution by 4)").tag(AndroidExportOptions.TextureReduction.quarter)
            }
            .disabled(model.options.pixelArt)
        }
        .formStyle(.grouped)
    }

    // MARK: Video settings

    @ViewBuilder
    private var videoSettings: some View {
        Text("Pre-rendering a scene wallpaper can drastically improve performance, but dynamic elements like clocks or interactive touch events will not work.")
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
        Form {
            Picker("Video Cropping", selection: $model.options.cropping) {
                Text("Fit to phone screen").tag(AndroidExportOptions.Cropping.phone)
                Text("Keep original aspect ratio").tag(AndroidExportOptions.Cropping.original)
            }
            Picker("Video Preset", selection: $model.options.videoPreset) {
                Text("Original").tag(AndroidExportOptions.VideoPreset.original)
                Text("Full HD").tag(AndroidExportOptions.VideoPreset.fullHD)
                Text("4K UHD").tag(AndroidExportOptions.VideoPreset.uhd4K)
            }
            Picker("FPS", selection: $model.options.frameRate) {
                ForEach(AndroidExportOptions.frameRates, id: \.self) { Text(verbatim: "\($0)").tag($0) }
            }
        }
        .formStyle(.grouped)
        if let size = model.sceneSize {
            let pixels = model.options.videoPixelSize(sceneSize: size)
            Text(verbatim: "\(pixels.x) × \(pixels.y), \(model.options.frameRate) FPS, \(AndroidExportOptions.videoSeconds) s")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        if let session = model.session, let crop = model.crop {
            AndroidCropPreview(session: session, crop: crop)
                .frame(height: 200)
                .frame(maxWidth: .infinity)
        }
        if model.options.cropping == .phone {
            LabeledContent("Alignment") {
                Slider(value: $model.options.alignment, in: 0...1)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if model.queue == nil {
                Toggle("Save to the Same Folder Each Time", isOn: $model.usesFolder)
                if model.usesFolder {
                    Button(model.folder?.lastPathComponent ?? String(localized: "Choose…")) { model.chooseFolder() }
                        .help(model.folder?.path(percentEncoded: false) ?? "")
                }
            }
            Spacer()
            if let queue = model.queue, queue.isRunning {
                Button("Cancel", role: .cancel) { model.cancelExport() }
                    .glassButtonStyle()
            } else if let batch = model.batch {
                Button("Show in Finder") { model.showInFinder() }
                    .glassButtonStyle()
                if !batch.outputs.isEmpty {
                    Button {
                        model.sendOverWiFi()
                    } label: {
                        Label("Send over Wi-Fi…", systemImage: "wifi")
                    }
                    .glassButtonStyle()
                }
                Button("Done") { dismiss() }
                    .glassButtonStyle(.prominent)
                    .keyboardShortcut(.defaultAction)
            } else {
                if model.editableScene != nil {
                    Button("Edit in Scene Editor…") {
                        model.editInSceneEditor()
                        dismiss()
                    }
                    .glassButtonStyle()
                    .help("Open the Scene Editor (Live)'s Android Export tab: choose the device, crop, parallax and layers, then export")
                }
                Button("Cancel", role: .cancel) { dismiss() }
                    .glassButtonStyle()
                    .keyboardShortcut(.cancelAction)
                Button("Export…") { model.export() }
                    .glassButtonStyle(.prominent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.exportable.isEmpty)
            }
        }
    }
}

/// The pre-rendered video's window over the previewed scene: the private instance drawn whole,
/// dimmed outside the portrait crop the alignment slider moves.
struct AndroidCropPreview: View {
    let session: IsolatedSceneEditSession
    let crop: LivePhotoCrop

    var body: some View {
        GeometryReader { geometry in
            let scene = CGRect(x: 0, y: 0, width: crop.sceneSize.x, height: crop.sceneSize.y)
            let layout = LockScreenPreview.layout(window: scene, sceneSize: crop.sceneSize, in: geometry.size)
            let window = crop.cropRect
            ZStack(alignment: .topLeading) {
                Color.black
                LockScreenPreview.pinned(IsolatedSceneView(session: session, presentation: LivePhotoRenderer.presentation(hidesClockLayers: false)),
                                         size: layout.sceneViewSize, at: layout.sceneViewOffset, in: layout.frame)
                    .allowsHitTesting(false)
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: layout.frame))
                    path.addRect(CGRect(x: window.minX * layout.scale, y: window.minY * layout.scale,
                                        width: window.width * layout.scale, height: window.height * layout.scale))
                }
                .fill(.black.opacity(0.55), style: FillStyle(eoFill: true))
                Rectangle()
                    .strokeBorder(.white, lineWidth: 2)
                    .frame(width: window.width * layout.scale, height: window.height * layout.scale)
                    .offset(x: window.minX * layout.scale, y: window.minY * layout.scale)
            }
            .frame(width: layout.frame.width, height: layout.frame.height)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .accessibilityLabel(Text("Preview"))
    }
}

/// The export's progress: the whole batch, then each wallpaper with its own state.
struct AndroidExportProgressView: View {
    @ObservedObject var queue: AndroidExportQueue
    @ObservedObject var model: AndroidExportModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView(value: queue.progress) {
                Text(queue.isRunning ? "Converting wallpaper" : "Finished")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(queue.entries) { entry in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(entry.item.wallpaper.project.displayTitle).lineLimit(1)
                                Spacer()
                                status(entry.status)
                            }
                            if entry.status == .running { ProgressView(value: entry.progress) }
                        }
                    }
                    ForEach(queue.skipped, id: \.wallpaperID) { skipped in
                        HStack {
                            Text(skipped.title).lineLimit(1)
                            Spacer()
                            Label(skipped.reason, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if model.batch != nil {
                Text("Copy the .mpkg files to your Android device, then import them in the Wallpaper Engine app.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func status(_ status: AndroidExportQueue.Status) -> some View {
        switch status {
        case .waiting: Image(systemName: "clock").foregroundStyle(.secondary)
        case .running: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let reason): Label(reason, systemImage: "xmark.octagon.fill").foregroundStyle(.red).font(.caption).lineLimit(2)
        case .cancelled: Image(systemName: "xmark.circle").foregroundStyle(.secondary)
        }
    }
}
