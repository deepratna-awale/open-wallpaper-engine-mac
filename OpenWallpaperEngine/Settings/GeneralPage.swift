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
/// Collapsed until the user opens it; the choice is remembered. A search result for a shortcut
/// (`SettingsAnchor.shortcuts`) opens it, so the match shows.
struct KeyboardShortcutsSection: View {
    @AppStorage("ShowsKeyboardShortcuts", store: .app) private var isExpanded = false
    @EnvironmentObject private var navigation: SettingsNavigation

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(groups.enumerated()), id: \.element.menu) { index, group in
                        Text(group.menu.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, index == 0 ? 6 : 16)
                            .padding(.bottom, 4)
                        ForEach(group.shortcuts) { shortcut in
                            HStack {
                                Text(shortcut.title)
                                Spacer(minLength: 12)
                                ShortcutKeyCap(symbols: shortcut.symbols)
                            }
                            .padding(.vertical, 2.5)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Keyboard Shortcuts", systemImage: "keyboard")
            }
            .onAppear { expandIfSearched(navigation.highlight) }
            .onChange(of: navigation.highlight) { _, anchor in expandIfSearched(anchor) }
        } footer: {
            Text("The same shortcuts are shown in the menus. You can change them in System Settings › Keyboard › Keyboard Shortcuts › App Shortcuts.")
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

/// A shortcut's key symbols as a small key cap, in the style of the settings search field.
private struct ShortcutKeyCap: View {
    let symbols: String

    var body: some View {
        Text(verbatim: symbols)
            .font(.callout.monospaced())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
    }
}
