import SwiftUI
import UniformTypeIdentifiers

/// WE's "Your Presets" in the Details panel: save the properties as a named preset, then apply,
/// rename, delete, export and import presets of this wallpaper.
struct WallpaperPresetsSection: View {
    @StateObject private var model: WallpaperPresetsViewModel
    /// Called after a preset is applied, so the property rows reload the new values.
    private let onApply: () -> Void

    @State private var isNamingNewPreset = false
    @State private var newPresetName = ""
    @State private var renaming: WallpaperPreset?
    @State private var renameText = ""
    @State private var deleting: WallpaperPreset?

    init(wallpaper: WEWallpaper, scopes: [WallpaperPropertyScope], onApply: @escaping () -> Void) {
        _model = StateObject(wrappedValue: WallpaperPresetsViewModel(wallpaper: wallpaper, scopes: scopes))
        self.onApply = onApply
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.presets.isEmpty {
                Text("No presets saved yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.presets) { preset in
                    presetRow(preset)
                }
            }
            HStack(spacing: 3) {
                Button {
                    newPresetName = ""
                    isNamingNewPreset = true
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down.fill")
                        .frame(maxWidth: .infinity)
                }
                .glassButtonStyle()
                .help("Save the current properties as a preset")
                Button {
                    importPreset()
                } label: {
                    Label("Import…", systemImage: "square.and.arrow.down.on.square")
                        .frame(maxWidth: .infinity)
                }
                .glassButtonStyle()
                .help("Import a preset file exported for this wallpaper")
            }
        }
        .alert("Save Preset", isPresented: $isNamingNewPreset) {
            TextField("Preset Name", text: $newPresetName)
            Button("Save") { model.saveCurrent(named: newPresetName) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Saves the current properties and Scene Inspector edits. A preset with the same name is replaced.")
        }
        .alert("Rename Preset", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Preset Name", text: $renameText)
            Button("Rename") {
                if let renaming { model.rename(renaming, to: renameText) }
            }
            Button("Cancel", role: .cancel) { }
        }
        .alert("Delete Preset", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) {
                if let deleting { model.delete(deleting) }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            if let deleting {
                Text("Do you want to delete the preset “\(deleting.name)”?")
            }
        }
        .alert("Preset Error", isPresented: Binding(get: { model.errorMessage != nil },
                                                    set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(verbatim: model.errorMessage ?? "")
        }
    }

    private func presetRow(_ preset: WallpaperPreset) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: preset.name)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                if model.apply(preset) { onApply() }
            } label: {
                Label("Apply", systemImage: "checkmark.circle")
            }
            .glassButtonStyle()
            .help("Apply this preset's properties")
            Menu {
                Button {
                    renameText = preset.name
                    renaming = preset
                } label: {
                    Label("Rename…", systemImage: "pencil")
                }
                Button {
                    exportPreset(preset)
                } label: {
                    Label("Export…", systemImage: "square.and.arrow.up")
                }
                Divider()
                Button(role: .destructive) {
                    deleting = preset
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Label("Preset Actions", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func exportPreset(_ preset: WallpaperPreset) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = model.suggestedFileName(for: preset)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.export(preset, to: url)
    }

    private func importPreset() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.importFile(at: url)
    }
}
