//
//  PluginsPage.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/8/12.
//

import SwiftUI

/// Settings › Plugins: optional features. Screen Saver; the Chromium engine and Depth Map
/// Generation, which are downloaded on demand; and the MCP Server, installed from the app's own
/// copy. Animated library previews are built in (`ThumbnailAnimation`).
struct PluginsPage: SettingsPage {
    @ObservedObject var viewModel: GlobalSettingsViewModel
    @StateObject private var chromium = ChromiumEngineInstaller()

    init(globalSettings viewModel: GlobalSettingsViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        SettingsForm {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Screen Saver", isOn: $viewModel.settings.screenSaver)
                        .changedFromDefault(viewModel.isChanged(\.screenSaver))
                        .help("Records a seamless loop of the current wallpaper in the background, at the largest display's pixels, and installs it as a screen saver; a video wallpaper plays its own file. Recording waits while your Mac is on battery or hot.")
                    Text("Records a seamless loop of the current wallpaper in the background (a video wallpaper plays its own file) and installs a screen saver that plays it. Choose Open Wallpaper Engine in Screen Saver settings to use it. Turning it off removes the screen saver and its videos.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if viewModel.settings.screenSaver {
                        Button("Open Screen Saver Settings…") {
                            ScreenSaverInstaller.current.openSettings()
                        }
                        if chromium.installedVersion == nil {
                            // The screen saver draws web pages and WebM videos through Chromium only
                            // (`ScreenSaverLiveWeb`).
                            Text("Web wallpapers and WebM videos move in the screen saver only with the Chromium engine. Without it, the screen saver shows their picture.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Install the Chromium Engine") { chromium.install() }
                                .disabled(chromium.isBusy || chromium.pin == nil)
                        }
                    }
                }
                ChromiumEngineSection(installer: chromium)
                    .settingsAnchor(SettingsAnchor.chromium)
                DepthMapPluginSection()
                    .settingsAnchor(SettingsAnchor.depthMaps)
                MCPServerPluginSection(plugin: AppDelegate.shared.mcpServerPlugin)
                    .settingsAnchor(SettingsAnchor.mcpServer)
            } header: {
                Label("Plugins", systemImage: "puzzlepiece.extension.fill")
            } footer: {
                Text("These settings take effect without saving.")
            }
            .settingsAnchor(SettingsAnchor.plugins)
        }
    }
}
