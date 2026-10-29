import OWEInspectorKit
import SwiftUI
import AppKit

/// A step's heading: icon, title and one line under it.
struct OnboardingHeading: View {
    @Environment(\.appAccentColor) private var accentColor
    let systemImage: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .foregroundStyle(accentColor)
            Text(title)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

/// A rounded panel, Liquid Glass on macOS 26 and a material below.
struct OnboardingCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassBackground(in: RoundedRectangle(cornerRadius: 14),
                         padding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)) { panel in
            panel
                .padding(14)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

// MARK: - 1. Welcome and language

struct OnboardingWelcomeStep: View {
    @ObservedObject var settings: GlobalSettingsViewModel
    let onRelaunch: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            OnboardingHeading(systemImage: "sparkles",
                              title: "Welcome to Open Wallpaper Engine",
                              subtitle: "A few steps to set things up. Skip any of them and come back later.")
            OnboardingCard {
                Picker("Language", selection: $settings.settings.language) {
                    ForEach(GSLocalization.allCases) { language in
                        if let endonym = language.endonym {
                            Text(verbatim: endonym).tag(language)
                        } else {
                            Text("Follow System").tag(language)
                        }
                    }
                }
                if settings.languageChange.needsRelaunch(for: settings.settings.language) {
                    HStack {
                        Text("A new language takes effect the next time Open Wallpaper Engine opens.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Restart Now", action: onRelaunch)
                            .glassButtonStyle(.prominent)
                    }
                }
            }
            OnboardingCard {
                OnboardingTour()
            }
        }
    }
}

// MARK: - 2. Privacy

struct OnboardingPrivacyStep: View {
    @ObservedObject var updater: AppUpdater

    var body: some View {
        VStack(spacing: 18) {
            OnboardingHeading(systemImage: "hand.raised.fill",
                              title: "Privacy",
                              subtitle: "Everything stays on your Mac")
            OnboardingCard {
                Label("Everything Open Wallpaper Engine saves stays on your Mac: your settings, library, cache and your Steam login.",
                      systemImage: "internaldrive")
                Label("There are no servers, accounts, analytics or tracking.", systemImage: "hand.raised")
                Label("The app contacts Valve (Steam), GitHub (app updates) and, when you install an optional plugin, its publisher. Web wallpapers and URLs you add load their own online content.",
                      systemImage: "network")
                Label("You can turn update checks off in Settings › Updates.", systemImage: "arrow.down.circle")
            }
            OnboardingCard {
                Label {
                    Text("With the Steam mobile app, you log in without typing your password. A password goes only to Steam. Your login is kept in your keychain on this Mac.")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "key.fill").foregroundStyle(.secondary)
                }
            }
            if updater.isEnabled {
                OnboardingCard {
                    Toggle("Keep Open Wallpaper Engine up to date automatically", isOn: $updater.updatesAutomatically)
                }
            }
        }
    }
}

// MARK: - 3. Steam

struct OnboardingSteamStep: View {
    @ObservedObject var account: SteamAccount

    var body: some View {
        VStack(spacing: 18) {
            OnboardingHeading(systemImage: "person.badge.key.fill",
                              title: "Steam",
                              subtitle: "For the Workshop and the Wallpaper Engine assets")
            OnboardingCard {
                Label("Steam Login", systemImage: "person.crop.circle")
                    .font(.headline)
                Text("Log in to Steam to browse and download Workshop wallpapers.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                SteamSignInView(account: account)
            }
        }
    }
}

// MARK: - 4. Wallpaper Engine assets

struct OnboardingAssetsStep: View {
    @ObservedObject var assets: WallpaperEngineAssetsService
    @ObservedObject var workshopDownloads: WorkshopDownloadService
    /// Goes back to the Steam step.
    let logIn: () -> Void
    @AppStorage(WallpaperEngineAssetsService.addsDefaultWallpapersKey, store: .app) private var addsDefaultWallpapers = true
    @State private var folderError: String?

    var body: some View {
        VStack(spacing: 18) {
            OnboardingHeading(systemImage: "shippingbox.fill",
                              title: "Wallpaper Engine Assets",
                              subtitle: "Scenes need them; video and web wallpapers don't")
            OnboardingCard {
                HStack {
                    Text("Status")
                        .font(.headline)
                    Spacer()
                    if assets.status.resolution != nil {
                        Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Label("Missing", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
                Text("Scenes need Wallpaper Engine assets from your Steam copy: built-in effects, shaders, materials and fonts. Video and web wallpapers play without them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Also add Wallpaper Engine's default wallpapers", isOn: $addsDefaultWallpapers)
                    .disabled(assets.isBusy)
                Text("Application wallpapers are always left out.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    if assets.isBusy {
                        Button("Cancel") { assets.cancel() }
                    } else {
                        Button(assets.status.info == nil ? "Install from Steam" : "Update from Steam") {
                            assets.installFromSteam(includingDefaultWallpapers: addsDefaultWallpapers)
                        }
                        .glassButtonStyle(.prominent)
                        .disabled(!workshopDownloads.isLoggedIn)
                        Button("Choose a Wallpaper Engine Folder…") { chooseFolder() }
                    }
                    Spacer()
                }
                if !assets.isBusy && !workshopDownloads.isLoggedIn {
                    Text("To install from Steam, log in on the Steam step first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                AssetsInstallProgressView(assets: assets, logIn: logIn)
                if let folderError {
                    Label(folderError, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                }
            }
            OnboardingCard {
                Label("Wallpaper Engine Favourites", systemImage: "heart")
                    .font(.headline)
                WallpaperEngineFavoritesImportView(assets: assets, workshopDownloads: workshopDownloads)
            }
            OnboardingCard {
                Label("Wallpaper Engine Folders", systemImage: "folder")
                    .font(.headline)
                WallpaperEngineFoldersImportView(assets: assets, library: AppDelegate.shared.contentViewModel.library)
            }
        }
        .onAppear { assets.refresh() }
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
