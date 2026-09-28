import SwiftUI
import AppKit

/// A step's heading: icon, title and one line under it.
struct OnboardingHeading: View {
    let systemImage: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .foregroundStyle(Color.accentColor)
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
    var body: some View {
        VStack(spacing: 18) {
            OnboardingHeading(systemImage: "hand.raised.fill",
                              title: "Privacy",
                              subtitle: "Everything stays on your Mac")
            OnboardingCard {
                Text("Everything Open Wallpaper Engine saves stays on your Mac: your settings, library, cache and SteamCMD's login. Open Wallpaper Engine has no server and collects no data or analytics. It only contacts Valve: Steam when you use the Workshop or install assets, and Valve's server to download SteamCMD. Web wallpapers may load their own online content.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            OnboardingCard {
                Label {
                    Text("Your password and Steam Guard code go straight to SteamCMD, Valve's official tool. Open Wallpaper Engine never stores, logs or sends them anywhere. It remembers only your account name, to reuse SteamCMD's saved login.")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "key.fill").foregroundStyle(.secondary)
                }
                Label {
                    Text("Needed to browse and search the Workshop. It is stored in your keychain and checked with Steam before saving. Without it, author names come from public Steam profiles.")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - 3. Steam and SteamCMD

struct OnboardingSteamStep: View {
    @ObservedObject var steamCmd: SteamCmdService
    @ObservedObject var installer: SteamCmdInstaller

    var body: some View {
        VStack(spacing: 18) {
            OnboardingHeading(systemImage: "person.badge.key.fill",
                              title: "Steam",
                              subtitle: "For the Workshop and the Wallpaper Engine assets")
            OnboardingCard {
                HStack {
                    Label("SteamCMD", systemImage: "terminal")
                        .font(.headline)
                    Spacer()
                    if steamCmd.steamCmdPath != nil {
                        Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else if installer.isBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Missing", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
                Text("Workshop downloads and the assets install use SteamCMD, Valve's command-line Steam client. When none is found, Open Wallpaper Engine downloads it from Valve. Homebrew's steamcmd works too.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if steamCmd.steamCmdPath == nil || installer.isBusy {
                    SteamCmdSetupView(installer: installer)
                        .frame(maxWidth: .infinity)
                }
            }
            .onAppear { installer.detectThenAutoInstall(steamCmd) }

            OnboardingCard {
                HStack {
                    Label("Steam Login", systemImage: "person.crop.circle")
                        .font(.headline)
                    Spacer()
                    if steamCmd.isLoggedIn {
                        Label {
                            Text("Logged in as \(steamCmd.steamUsername)", comment: "%@ is a Steam account name")
                        } icon: {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                }
                if !steamCmd.isLoggedIn {
                    if steamCmd.steamCmdPath == nil {
                        Text("Log in once SteamCMD is ready.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        SteamLoginForm(steamCmd: steamCmd)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

// MARK: - 4. Wallpaper Engine assets

struct OnboardingAssetsStep: View {
    @ObservedObject var assets: WallpaperEngineAssetsService
    @ObservedObject var steamCmd: SteamCmdService
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
                        .disabled(steamCmd.steamCmdPath == nil || !steamCmd.isLoggedIn)
                        Button("Choose a Wallpaper Engine Folder…") { chooseFolder() }
                    }
                    Spacer()
                }
                if !assets.isBusy && (steamCmd.steamCmdPath == nil || !steamCmd.isLoggedIn) {
                    Text("To install from Steam, log in on the Steam step first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                AssetsInstallProgressView(assets: assets)
                if let folderError {
                    Label(folderError, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                }
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
