//
//  PluginsPage.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/8/12.
//

import SwiftUI

/// Settings › Plugins: optional features. Animated Thumbnails and Screen Saver work now; Depth
/// Map Generation is coming as downloadable plugins.
struct PluginsPage: SettingsPage {
    @ObservedObject var viewModel: GlobalSettingsViewModel

    @AppStorage("TestAnimates", store: .app) var animates = false

    @State var isExpanded = false

    init(globalSettings viewModel: GlobalSettingsViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        SettingsForm {
            Section {
                VStack(spacing: 20) {
                    Toggle("Animated Thumbnails", isOn: $animates)
                        .changedFromDefault(animates)
                        .help("Plays animated GIF previews in the wallpaper explorer. Uses more CPU while the explorer is open.")
                    if isExpanded {
                        HStack {
                            GifImage("maxwell-cat", animates: animates)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 100, maxHeight: 100)
                                .padding(4)
                                .glassBackground(in: RoundedRectangle(cornerRadius: 16.0)) { tile in
                                    tile
                                        .background(Material.thin)
                                        .clipShape(RoundedRectangle(cornerRadius: 16.0))
                                }
                            VStack(alignment: .leading, spacing: 10) {
                                Text("This plugin animates the GIF thumbnails in the wallpaper explorer.")
                                Spacer()
                                Text("􀄪 Toggle it to see a preview.")
                                Spacer()
                                Text("This may affect performance.")
                                    .bold()
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    Button {
                        withAnimation {
                            isExpanded.toggle()
                        }
                    } label: {
                        VStack {
                            if isExpanded {
                                Image(systemName: "chevron.up")
                                    .bold()
                                    .imageScale(.large)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Description…")
                            }
                        }
                    }
                    .tint(.accentColor)
                    .buttonStyle(.borderless)
                    .frame(maxWidth: .infinity)
                }
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
