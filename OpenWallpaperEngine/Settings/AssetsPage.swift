import SwiftUI
import AppKit

/// Settings › Assets: the Wallpaper Engine assets scenes need, from the user's own Steam copy.
/// Shows which copy is in use and installs, updates or removes it. Changes apply at once; the
/// window's OK and Cancel don't cover them.
struct AssetsPage: SettingsPage {
    var viewModel: GlobalSettingsViewModel
    @ObservedObject private var assets: WallpaperEngineAssetsService
    @ObservedObject private var steamCmd: SteamCmdService
    private let installer: SteamCmdInstaller
    @State private var confirmsRemoval = false
    @State private var folderError: String?

    init(globalSettings: GlobalSettingsViewModel) {
        self.viewModel = globalSettings
        self.assets = AppDelegate.shared.assets
        self.steamCmd = AppDelegate.shared.contentViewModel.steamCmd
        self.installer = AppDelegate.shared.steamCmdInstaller
    }

    var body: some View {
        Form {
            Section {
                Text("Scenes need Wallpaper Engine assets from your Steam copy: built-in effects, shaders, materials and fonts. Video and web wallpapers play without them.")
                    .foregroundStyle(.secondary)
                statusRows
            } header: {
                Label("Wallpaper Engine Assets", systemImage: "shippingbox")
            }

            Section {
                progress
                actions
            } footer: {
                Text("Downloads your Wallpaper Engine copy with SteamCMD, keeps only its assets and default wallpapers, and deletes the rest. Log in to Steam in the Workshop tab first.")
            }

            SteamCmdSection(steamCmd: steamCmd, installer: installer)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear { assets.refresh() }
        .confirmationDialog("Remove the assets?", isPresented: $confirmsRemoval) {
            if assets.defaultWallpapers.isEmpty {
                Button("Remove Assets", role: .destructive) { assets.removeCache(includingDefaultWallpapers: false) }
            } else {
                Button("Remove Assets and Default Wallpapers", role: .destructive) {
                    assets.removeCache(includingDefaultWallpapers: true)
                }
                Button("Remove Assets Only", role: .destructive) { assets.removeCache(includingDefaultWallpapers: false) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Scenes won't render until you install the assets again. Default wallpapers go to the Trash.")
        }
    }

    private var status: WallpaperEngineAssetsService.Status { assets.status }

    @ViewBuilder
    private var statusRows: some View {
        HStack {
            Text("Status")
            Spacer()
            if status.resolution != nil {
                Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Label("Missing", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
        if let resolution = status.resolution {
            row("Source", Text(sourceName(resolution.source)))
            row("Location", Text(verbatim: resolution.directory.path).font(.caption.monospaced()))
        }
        if status.resolution?.source == .cache, let info = status.info {
            if let build = info.steamBuildID {
                row("Steam build", Text(verbatim: build))
            }
            row("Updated", Text(info.installedAt, format: .dateTime))
            if let size = status.cacheSize {
                row("Size", Text(size.formatted(.byteCount(style: .file))))
            }
        }
        if !assets.defaultWallpapers.isEmpty {
            row("Default wallpapers added", Text(assets.defaultWallpapers.count, format: .number))
        }
        if let free = status.freeSpace {
            row("Free space", Text(free.formatted(.byteCount(style: .file))))
        }
    }

    private func sourceName(_ source: WallpaperEngineAssets.Source) -> LocalizedStringKey {
        switch source {
        case .chosenFolder, .testEnvironment: return "Chosen folder"
        case .cache: return status.info?.origin == .folder ? "Copied from a folder" : "Downloaded from Steam"
        }
    }

    @ViewBuilder
    private var progress: some View {
        switch assets.phase {
        case .idle:
            EmptyView()
        case .downloading(let text, let progress):
            VStack(alignment: .leading, spacing: 6) {
                if let progress {
                    ProgressView(value: progress.fraction)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
                HStack {
                    Text(text)
                    Spacer()
                    if let done = progress?.downloadedBytes, let total = progress?.totalBytes, total > 0 {
                        let doneText: String = done.formatted(.byteCount(style: .file))
                        let totalText: String = total.formatted(.byteCount(style: .file))
                        Text("\(doneText) of \(totalText)", comment: "Download progress: bytes done of bytes in total")
                            .monospacedDigit()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        case .copying:
            HStack {
                ProgressView().controlSize(.small)
                Text("Copying assets…")
            }
        case .failed(let message):
            Label(message, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
        if let folderError {
            Label(folderError, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        }
    }

    private var actions: some View {
        HStack {
            if assets.isBusy {
                Button("Cancel") { assets.cancel() }
            } else {
                if steamCmd.steamCmdPath == nil {
                    // Installing from Steam needs SteamCMD first; offer it here.
                    SteamCmdSetupView(installer: installer)
                } else {
                    Button(status.info == nil ? "Install from Steam" : "Update from Steam") { assets.installFromSteam() }
                        .glassButtonStyle(.prominent)
                }
                Button("Choose Folder…") { chooseFolder() }
                if status.chosenFolder != nil {
                    Button("Stop Using Folder") { assets.forgetChosenFolder() }
                }
                if status.info != nil || status.resolution?.source == .cache {
                    Button("Remove…") { confirmsRemoval = true }
                }
            }
            Spacer()
        }
    }

    private func row(_ title: LocalizedStringKey, _ value: Text) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer()
            value
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Choose a Wallpaper Engine folder or its assets folder.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try assets.chooseFolder(url)
            folderError = nil
        } catch {
            folderError = error.localizedDescription
        }
    }
}
