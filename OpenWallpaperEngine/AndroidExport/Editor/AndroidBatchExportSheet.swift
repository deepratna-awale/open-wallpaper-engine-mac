import SwiftUI

/// The Android Export mode's "Export More with These Settings…": pick wallpapers from the library,
/// then export them with the mode's device, output, quality and frame rate
/// (`AndroidExportEditorModel.batchPlan`), with the batch's and each package's progress. The
/// packages go into the Android exports list, for Send over Wi-Fi.
struct AndroidBatchExportSheet: View {
    @ObservedObject var model: AndroidExportEditorModel
    /// The library's wallpapers, read when the sheet opens.
    var library: @MainActor () -> [WEWallpaper] = { AppDelegate.shared.contentViewModel.allWallpapers }
    @State private var wallpapers: [WEWallpaper] = []
    @State private var selection: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Export More with These Settings")
                    .font(.title2.bold())
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let queue = model.batchQueue {
                AndroidBatchProgress(queue: queue)
            } else {
                ExportLibraryPicker(wallpapers: wallpapers, skipReason: AndroidExportPlan.skipReason, selection: $selection)
            }
            footer
        }
        .padding(20)
        .frame(width: 560, height: 620)
        .onAppear {
            wallpapers = ExportLibraryPicker.library(library(), with: model.wallpaper)
            selection = [model.wallpaper.identityPath]
        }
    }

    private var summary: String {
        let mode = model.isPreRendered
            ? String(localized: "Pre-Rendered, \(model.options.frameRate) FPS")
            : String(localized: "Dynamic")
        let device = model.device?.name ?? String(localized: "Custom")
        return String(localized: "\(device) · \(mode). Only “\(model.wallpaper.project.displayTitle)” keeps its edits; the others export as authored.")
    }

    @ViewBuilder private var footer: some View {
        HStack {
            if let queue = model.batchQueue {
                if queue.isRunning {
                    Spacer()
                    Button("Cancel", role: .cancel) { model.cancelBatch() }
                        .glassButtonStyle()
                } else {
                    Text("The packages are in the Android exports list.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        AndroidWiFiShareWindow.show()
                    } label: {
                        Label("Send over Wi-Fi…", systemImage: "wifi")
                    }
                    .glassButtonStyle()
                    .disabled(queue.batch.outputs.isEmpty)
                    Button("Done") { model.closeBatch() }
                        .glassButtonStyle(.prominent)
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                Spacer()
                Button("Cancel", role: .cancel) { model.closeBatch() }
                    .glassButtonStyle()
                    .keyboardShortcut(.cancelAction)
                Button {
                    model.exportMore(ExportLibraryPicker.picked(wallpapers, selection: selection, edited: model.wallpaper))
                } label: {
                    Text("Export \(selection.count)")
                }
                .glassButtonStyle(.prominent)
                .keyboardShortcut(.defaultAction)
                .disabled(selection.isEmpty)
            }
        }
    }
}

private struct AndroidBatchProgress: View {
    @ObservedObject var queue: AndroidExportQueue

    var body: some View {
        ExportBatchProgressView(
            progress: queue.progress, isRunning: queue.isRunning,
            rows: queue.entries.map { ExportBatchRow(id: $0.id, title: $0.item.wallpaper.project.displayTitle, status: $0.status, progress: $0.progress) },
            skipped: queue.skipped.map { (title: $0.title, reason: $0.reason) },
            accessory: { _ in EmptyView() })
    }
}
