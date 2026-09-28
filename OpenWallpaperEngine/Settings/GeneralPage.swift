//
//  GeneralPage.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/8/12.
//

import Cocoa
import SwiftUI

struct GeneralPage: SettingsPage {
    @ObservedObject var viewModel: GlobalSettingsViewModel
    @State private var pendingStorageDirectory: URL?
    @State private var isStorageMoveConfirming = false
    @State private var storageError: String?
    @AppStorage("ReclaimOriginalPackages", store: .app) private var reclaimOriginalPackages = false
    @State private var reclaimableBytes: Int64 = 0
    @State private var reclaimedCount: Int?
    @State private var isReclaiming = false

    private var reclaimableDescription: String {
        guard reclaimableBytes > 0 else { return String(localized: "No originals ready to remove") }
        let formatted = ByteCountFormatter.string(fromByteCount: reclaimableBytes, countStyle: .file)
        return String(localized: "\(formatted) of originals can be removed", comment: "%@ is a file size, e.g. 1.2 GB")
    }

    init(globalSettings viewModel: GlobalSettingsViewModel) {
        self.viewModel = viewModel
    }
    
    var body: some View {
        Form {
            // MARK: Automatic Startup
            Section {
                Toggle("Start with macOS", isOn: $viewModel.settings.autoStart)
//                Toggle("Safe start after hibernation", isOn: $viewModel.settings.safeMode)
            } header: {
                Label("Automatic Startup", systemImage: "star.fill")
            }
            // MARK: Basic Setup
            Section {
                Picker("Language", selection: $viewModel.settings.language) {
                    ForEach(GSLocalization.allCases) { language in
                        if let endonym = language.endonym {
                            Text(verbatim: endonym).tag(language)
                        } else {
                            Text("Follow System").tag(language)
                        }
                    }
                }
            } header: {
                Label("Basic Setup", systemImage: "gearshape.fill")
            } footer: {
                Text("A new language takes effect the next time Open Wallpaper Engine opens.")
            }
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
            Section {
                Toggle("Remove original packages after conversion", isOn: $reclaimOriginalPackages)
                HStack {
                    Text(reclaimableDescription)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reclaim Now") {
                        isReclaiming = true
                        DispatchQueue.global(qos: .utility).async {
                            let removed = WallpaperPackageConverter.reclaimEligibleSources()
                            let remaining = WallpaperPackageConverter.reclaimableBytes()
                            DispatchQueue.main.async {
                                reclaimedCount = removed
                                reclaimableBytes = remaining
                                isReclaiming = false
                            }
                        }
                    }
                    .disabled(isReclaiming || reclaimableBytes == 0)
                }
                if let reclaimedCount {
                    Text("Removed \(reclaimedCount) original packages.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("Converted Wallpapers", systemImage: "arrow.triangle.2.circlepath")
            } footer: {
                Text("Wallpapers are unpacked into plain files when imported. The original package is kept until the wallpaper has rendered from those files, reported no conversion warnings, and no other wallpaper depends on it.")
            }
            // MARK: Steam Workshop
            Section {
                SteamWebAPIKeyView()
            } header: {
                Label("Steam Web API Key", systemImage: "key")
            } footer: {
                Text("Needed to browse and search the Workshop. It is stored in your keychain and checked with Steam before saving. Without it, author names come from public Steam profiles.")
            }
            // MARK: Privacy
            Section {
                Text("Everything Open Wallpaper Engine saves stays on your Mac: your settings, library, cache and SteamCMD's login. Open Wallpaper Engine has no server and collects no data or analytics. It only contacts Valve: Steam when you use the Workshop or install assets, and Valve's server to download SteamCMD. Web wallpapers may load their own online content.")
                    .foregroundStyle(.secondary)
            } header: {
                Label("Privacy", systemImage: "hand.raised")
            }
            // MARK: macOS
            Section {
                Toggle("Adjust Menu Bar Color", isOn: $viewModel.settings.adjustMenuBarTint)
            } header: {
                Label("macOS", systemImage: "apple.logo")
            }
            // MARK: Appearance
            Section {
                Picker("Theme", selection: $viewModel.settings.appearance) {
                    Text("Light").tag(GSAppearance.light)
                    Text("Dark").tag(GSAppearance.dark)
                    Text("Auto").tag(GSAppearance.followSystem)
                }
            } header: {
                Label("Appearance", systemImage: "paintpalette.fill")
            }
            // MARK: Displays
            Section {
                Toggle("Sync properties across displays", isOn: $viewModel.settings.syncPropertiesAcrossDisplays)
            } header: {
                Label("Displays", systemImage: "display.2")
            } footer: {
                Text("Off, a wallpaper shown on several displays keeps each display's properties, as Wallpaper Engine does. On, one set of properties applies to every display.")
            }
            // MARK: Audio
            Section {
                Toggle(isOn: $viewModel.settings.audioOutput) {
                    Text("Audio Output")
                }
                Toggle(isOn: $viewModel.settings.reloadWhenChangingOutputDevice) {
                    Text("Reload when changing output device")
                }.disabled(true)
                Toggle("Media integration support", isOn: $viewModel.settings.mediaIntegration)
            } header: {
                Label("Audio", systemImage: "speaker.3.fill")
            } footer: {
                Text("Media integration lets wallpapers read the title, artist and album cover of the music playing now.")
            }
            // MARK: Video
            Section {
                Picker("Video Framework", selection: $viewModel.settings.videoFramework) {
                    Text("Apple AVKit").tag(GSVideoFramework.avkit)
                    Text("Metal (effects apply to video)").tag(GSVideoFramework.metal)
                }
            } header: {
                Label("Video", systemImage: "film")
            } footer: {
                Text("Metal draws video through the scene renderer so effects and music sync apply to it, the way Wallpaper Engine does. Experimental.")
            }
            // MARK: Advanced
            Section {
                Picker("Process Priority", selection: $viewModel.settings.processPiority) {
                    Text("Normal").tag(GSProcessPiority.normal)
                    Text("Below Normal").tag(GSProcessPiority.belowNormal)
                }
                Toggle("Pause when VRAM is exhausted", isOn: $viewModel.settings.pauseOnVRAMExhausted)
                Toggle("Restart after crashing", isOn: $viewModel.settings.restartAfterCrashing)
            } header: {
                Label("Advanced", systemImage: "wrench.and.screwdriver.fill")
            }
            // MARK: Developers
            Section {
                Picker("Log Level", selection: $viewModel.settings.logLevel) {
                    Text("None").tag(GSLogLevel.none)
                    Text("Errors Only").tag(GSLogLevel.error)
                    Text("Verbose").tag(GSLogLevel.verbose)
                }
            } header: {
                Label("Developer", systemImage: "number")
            }
            // MARK: Reset
            Section {
                HStack {
                    Text("Reset Config")
                    Spacer()
                    Button {
                        viewModel.settings = GlobalSettings()
                    } label: {
                        Text("Reset").frame(minWidth: 100)
                    }
                    .tint(Color.red)
                    .glassButtonStyle(.prominent)
                }
            } header: {
                Label("Reset", systemImage: "exclamationmark.triangle.fill")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear {
            DispatchQueue.global(qos: .utility).async {
                let bytes = WallpaperPackageConverter.reclaimableBytes()
                DispatchQueue.main.async { reclaimableBytes = bytes }
            }
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
