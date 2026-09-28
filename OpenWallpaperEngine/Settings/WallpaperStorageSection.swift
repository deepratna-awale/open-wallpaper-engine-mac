import AppKit
import SwiftUI

/// Settings › Assets › Wallpaper Storage: the folder Workshop downloads and imports go into, and
/// moving the library to a new one.
struct WallpaperStorageSection: View {
    @State private var pendingStorageDirectory: URL?
    @State private var isStorageMoveConfirming = false
    @State private var storageError: String?

    var body: some View {
        Section {
            HStack {
                Text(WallpaperStorage.directory.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Choose...") {
                    chooseStorageDirectory()
                }
            }
            if let volume = WallpaperStorage.unmountedVolume(of: WallpaperStorage.directory) {
                Text("\(volume.lastPathComponent) isn't connected. Workshop downloads fail until you connect it or choose another folder.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if WallpaperStorage.usesCustomDirectory {
                Button("Use Default Location") {
                    WallpaperStorage.resetToDefault()
                }
            }
            if let storageError {
                Text(storageError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Label("Wallpaper Storage", systemImage: "externaldrive")
        } footer: {
            Text("Workshop downloads, their dependencies and imported wallpapers go into this folder. You can move the current library to the new location.")
        }
        .confirmationDialog(
            "Move Current Wallpapers?",
            isPresented: $isStorageMoveConfirming,
            titleVisibility: .visible
        ) {
            Button("Move Current Wallpapers") {
                setStorageDirectory(moveExisting: true)
            }
            Button("Use Empty Folder") {
                setStorageDirectory(moveExisting: false)
            }
            Button("Cancel", role: .cancel) {
                pendingStorageDirectory = nil
            }
        } message: {
            Text("Move existing wallpapers to the selected folder, or leave them in the current location and use the new folder from now on?")
        }
    }

    private func chooseStorageDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Choose Wallpaper Storage Folder")
        if panel.runModal() == .OK, let directory = panel.url {
            pendingStorageDirectory = directory
            isStorageMoveConfirming = true
        }
    }

    private func setStorageDirectory(moveExisting: Bool) {
        guard let directory = pendingStorageDirectory else { return }
        do {
            let migration = try WallpaperStorage.setDirectory(directory, moveExisting: moveExisting)
            if let migration {
                AppDelegate.shared.wallpaperViewModel.relocateWallpapers(
                    from: migration.source,
                    to: migration.destination
                )
            }
            DownloadedWallpaperIndex.shared.reloadFromLibrary()
            AppDelegate.shared.contentViewModel.refresh()
            storageError = nil
        } catch {
            storageError = error.localizedDescription
        }
        pendingStorageDirectory = nil
    }
}
