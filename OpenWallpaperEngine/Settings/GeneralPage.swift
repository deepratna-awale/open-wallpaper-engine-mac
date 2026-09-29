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
            } header: {
                Label("Appearance", systemImage: "paintpalette.fill")
            }
            .settingsAnchor(SettingsAnchor.appearance)
            // MARK: macOS
            Section {
                Toggle("Adjust Menu Bar Color", isOn: $viewModel.settings.adjustMenuBarTint)
                    .changedFromDefault(viewModel.isChanged(\.adjustMenuBarTint))
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
                }
            }
            .settingsAnchor(SettingsAnchor.setup)
            // MARK: Keyboard Shortcuts
            KeyboardShortcutsSection()
                .settingsAnchor(SettingsAnchor.shortcuts)
        }
    }
}

/// Every shortcut of the menu bar, grouped by menu (`AppShortcut.all`).
/// Collapsed until the user opens it; the choice is remembered.
struct KeyboardShortcutsSection: View {
    @AppStorage("ShowsKeyboardShortcuts", store: .app) private var isExpanded = false

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(AppShortcut.Menu.allCases, id: \.self) { menu in
                    let shortcuts = AppShortcut.all.filter { $0.menu == menu }
                    if !shortcuts.isEmpty {
                        Text(menu.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(shortcuts) { shortcut in
                            HStack {
                                Text(shortcut.title)
                                Spacer()
                                Text(verbatim: shortcut.symbols)
                                    .font(.body.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } label: {
                Label("Keyboard Shortcuts", systemImage: "keyboard")
            }
        } footer: {
            Text("The same shortcuts are shown in the menus. You can change them in System Settings › Keyboard › Keyboard Shortcuts › App Shortcuts.")
        }
    }
}
