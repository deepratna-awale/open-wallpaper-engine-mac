//
//  PluginsPage.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/8/12.
//

import SwiftUI

/// Settings › Plugins: optional features. Screen Saver works now; Depth Map Generation is coming
/// as downloadable plugins. Animated library previews are built in (`ThumbnailAnimation`).
struct PluginsPage: SettingsPage {
    @ObservedObject var viewModel: GlobalSettingsViewModel

    init(globalSettings viewModel: GlobalSettingsViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        SettingsForm {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Screen Saver", isOn: $viewModel.settings.screenSaver)
                        .changedFromDefault(viewModel.isChanged(\.screenSaver))
                        .help("Renders a seamless loop of the current scene in the background, at the largest display's point size and without clock and date layers, and installs it as a screen saver. Rendering waits while your Mac is on battery or hot.")
                    Text("Renders a seamless loop of the current scene wallpaper in the background and installs a screen saver that plays it. Choose Open Wallpaper Engine in Screen Saver settings to use it. Turning it off removes the screen saver and its videos.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if viewModel.settings.screenSaver {
                        Button("Open Screen Saver Settings…") {
                            ScreenSaverInstaller.current.openSettings()
                        }
                    }
                }
                ChromiumEngineSection()
                    .settingsAnchor(SettingsAnchor.chromium)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Depth Map Generation")
                        Spacer()
                        Text("Coming soon")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                    Text("Machine-learning models that generate depth maps for depth parallax in the scene editor, offered as downloadable plugins.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Label("Plugins", systemImage: "puzzlepiece.extension.fill")
            } footer: {
                Text("These settings take effect without saving.")
            }
            .settingsAnchor(SettingsAnchor.plugins)
        }
    }
}
