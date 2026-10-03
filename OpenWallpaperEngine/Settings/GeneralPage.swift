//
//  GeneralPage.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/8/12.
//

import Cocoa
import SwiftUI

/// Settings › General: startup, language, appearance, the macOS options, the setup assistant and
/// the keyboard shortcuts.
struct GeneralPage: SettingsPage {
    @ObservedObject var viewModel: GlobalSettingsViewModel

    init(globalSettings viewModel: GlobalSettingsViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        SettingsForm {
            // MARK: Automatic Startup
            Section {
                Toggle("Start with macOS", isOn: $viewModel.settings.autoStart)
                    .changedFromDefault(viewModel.isChanged(\.autoStart))
                    .help("Opens Open Wallpaper Engine when you log in to your Mac. Off by default.")
            } header: {
                Label("Automatic Startup", systemImage: "star.fill")
            }
            .settingsAnchor(SettingsAnchor.startup)
            // MARK: Language
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
                .changedFromDefault(viewModel.isChanged(\.language))
                .help("The language of the app's windows and menus. Follow System uses your Mac's language; a change applies after the app restarts.")
                if viewModel.languageChange.needsRelaunch(for: viewModel.settings.language) {
                    HStack {
                        Spacer()
                        Button("Restart Now") { AppRelauncher.relaunch() }
                    }
                }
            } header: {
                Label("Basic Setup", systemImage: "gearshape.fill")
            } footer: {
                Text("A new language takes effect the next time Open Wallpaper Engine opens.")
            }
            .settingsAnchor(SettingsAnchor.language)
            // MARK: Appearance
            Section {
                Picker("Theme", selection: $viewModel.settings.appearance) {
                    Text("Light").tag(GSAppearance.light)
                    Text("Dark").tag(GSAppearance.dark)
                    Text("Auto").tag(GSAppearance.followSystem)
                }
                .changedFromDefault(viewModel.isChanged(\.appearance))
                .help("Whether the app's windows are light or dark. Auto follows your Mac's appearance.")
            } header: {
                Label("Appearance", systemImage: "paintpalette.fill")
            }
            .settingsAnchor(SettingsAnchor.appearance)
            // MARK: macOS
            Section {
                Toggle("Adjust Menu Bar Color", isOn: $viewModel.settings.adjustMenuBarTint)
                    .changedFromDefault(viewModel.isChanged(\.adjustMenuBarTint))
                    .help("While a video or web wallpaper plays, sets the desktop picture to a frame of it, so macOS tints the menu bar to match. Off restores your own picture.")
                Toggle("Show Wallpaper on Lock Screen", isOn: $viewModel.settings.lockScreenPicture)
                    .changedFromDefault(viewModel.isChanged(\.lockScreenPicture))
                    .help("Sets each display's desktop picture to the scene wallpaper's snapshot, so the lock screen shows it. Turning it off restores your own pictures.")
            } header: {
                Label("macOS", systemImage: "apple.logo")
            }
            .settingsAnchor(SettingsAnchor.macOS)
            // MARK: Setup Assistant
            Section {
                HStack {
                    Text("Setup Assistant")
                    Spacer()
                    Button("Run Setup Again…") {
                        OnboardingFlow.reopen()
                        viewModel.isFirstLaunch = true
                        AppDelegate.shared.openMainWindow()
                    }
                    .help("Opens the setup assistant again, to redo the choices from the first launch.")
                }
            }
            .settingsAnchor(SettingsAnchor.setup)
            // MARK: Keyboard Shortcuts
            KeyboardShortcutsSection()
        }
    }
}

/// Every shortcut of the menu bar (`AppShortcut.all`), laid out like System Settings: a
/// disclosure row, then, while it is open, one grouped section per menu whose rows show
/// the action and its keys as key caps. Collapsed until the user opens it; the choice is
/// remembered. A search result for a shortcut (`SettingsAnchor.shortcuts`) opens it.
struct KeyboardShortcutsSection: View {
    @AppStorage("ShowsKeyboardShortcuts", store: .app) private var isExpanded = false
    @EnvironmentObject private var navigation: SettingsNavigation
    @ObservedObject private var wallpaperViewModel = AppDelegate.shared.wallpaperViewModel

    var body: some View {
        Section {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Label("Keyboard Shortcuts", systemImage: "keyboard")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Lists the keyboard shortcuts of every menu.")
        } footer: {
            Text("The same shortcuts are shown in the menus. You can change them in System Settings › Keyboard › Keyboard Shortcuts › App Shortcuts.")
        }
        .settingsAnchor(SettingsAnchor.shortcuts)
        .onAppear { expandIfSearched(navigation.highlight) }
        .onChange(of: navigation.highlight) { _, anchor in expandIfSearched(anchor) }
        if isExpanded {
            ForEach(groups, id: \.menu) { group in
                Section {
                    ForEach(group.shortcuts) { shortcut in
                        LabeledContent {
                            ShortcutKeyCaps(keys: shortcut.keys)
                        } label: {
                            Text(shortcut.title)
                        }
                    }
                } header: {
                    Text(group.menu.title)
                }
            }
            // The playlists' system-wide shortcuts, set in each playlist's header.
            Section {
                let playlists = wallpaperViewModel.playlists.filter { $0.shortcut != nil }
                if playlists.isEmpty {
                    Text("No playlist has a shortcut yet.").foregroundStyle(.secondary)
                }
                ForEach(playlists) { playlist in
                    LabeledContent {
                        ShortcutKeyCaps(keys: playlist.shortcut?.keys ?? [])
                    } label: {
                        Text(verbatim: playlist.name)
                    }
                }
            } header: {
                Text("Playlists")
            } footer: {
                Text("These work in every app and start the playlist. Set one in the playlist's header on the Playlists tab.")
            }
        }
    }

    /// The menus that have shortcuts, in menu-bar order.
    private var groups: [(menu: AppShortcut.Menu, shortcuts: [AppShortcut])] {
        AppShortcut.Menu.allCases.compactMap { menu in
            let shortcuts = AppShortcut.all.filter { $0.menu == menu }
            return shortcuts.isEmpty ? nil : (menu, shortcuts)
        }
    }

    private func expandIfSearched(_ anchor: String?) {
        if anchor == SettingsAnchor.shortcuts { isExpanded = true }
    }
}

/// A shortcut's keys, one small key cap each (⌥ ⌘ U), as System Settings draws them.
private struct ShortcutKeyCaps: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(verbatim: key)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 20, minHeight: 20)
                    .padding(.horizontal, key.count > 1 ? 4 : 0)
                    .background(.quaternary.opacity(0.8), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: keys.joined()))
    }
}
