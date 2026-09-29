import Foundation

/// "Your Presets" for the wallpaper the Details panel shows, over the property stores it edits
/// (`WallpaperViewModel.editedPropertyScopes`).
@MainActor
final class WallpaperPresetsViewModel: ObservableObject {
    @Published private(set) var presets: [WallpaperPreset] = []
    /// The last failure, shown in an alert until dismissed.
    @Published var errorMessage: String?

    private let targets: WallpaperPropertyTargets
    private let store: WallpaperPresetStore
    private let title: String

    init(wallpaper: WEWallpaper, scopes: [WallpaperPropertyScope]) {
        targets = WallpaperPropertyTargets(wallpaper: wallpaper, scopes: scopes)
        store = WallpaperPresetStore(identity: targets.identity)
        title = wallpaper.project.displayTitle
        reload()
    }

    func reload() {
        perform("load the presets") { presets = try store.presets() }
    }

    /// Saves the shown display's properties, with its Scene Inspector edits, as `name`.
    func saveCurrent(named name: String) {
        perform("save preset \(name)") {
            try store.save(name: name, values: targets.storedValues)
            presets = try store.presets()
        }
    }

    /// Replaces the edited stores' properties with the preset's and applies them to the running
    /// wallpapers. False when the preset is gone.
    @discardableResult
    func apply(_ preset: WallpaperPreset) -> Bool {
        var applied = false
        perform("apply preset \(preset.name)") {
            guard let current = try store.presets().first(where: { $0.id == preset.id }) else {
                throw WallpaperPresetError.notFound
            }
            targets.apply(preset: current.values)
            applied = true
            OWELog.info(.library, "Applied preset \(current.name) to \(title)")
        }
        return applied
    }

    func rename(_ preset: WallpaperPreset, to name: String) {
        perform("rename preset \(preset.name)") {
            try store.rename(preset.id, to: name)
            presets = try store.presets()
        }
    }

    func delete(_ preset: WallpaperPreset) {
        perform("delete preset \(preset.name)") {
            try store.delete(preset.id)
            presets = try store.presets()
        }
    }

    func suggestedFileName(for preset: WallpaperPreset) -> String {
        WallpaperPresetTransfer(wallpaper: targets.identity.rawValue, preset: preset).suggestedFileName
    }

    func export(_ preset: WallpaperPreset, to url: URL) {
        perform("export preset \(preset.name) to \(url.path)") {
            try store.exportData(preset.id).write(to: url, options: .atomic)
        }
    }

    func importFile(at url: URL) {
        perform("import a preset from \(url.path)") {
            try store.importData(Data(contentsOf: url))
            presets = try store.presets()
        }
    }

    private func perform(_ action: String, _ body: () throws -> Void) {
        do {
            try body()
        } catch {
            OWELog.error(.library, "Could not \(action) for \(title): \(error)")
            errorMessage = error.localizedDescription
        }
    }
}
