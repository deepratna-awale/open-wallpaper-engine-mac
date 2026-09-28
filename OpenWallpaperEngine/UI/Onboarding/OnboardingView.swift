import SwiftUI

/// Where the Done step's shortcuts go once the assistant closes.
enum OnboardingShortcut: Equatable {
    case installed
    case workshop
    case displaySettings
}

/// The setup assistant: welcome and language, privacy, Steam and SteamCMD, the Wallpaper Engine
/// assets, bringing wallpapers in, and a summary. Every step can be skipped and visited again,
/// here with Back or the step list, or later with Settings › General › "Run setup again…".
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var globalSettingsViewModel: GlobalSettingsViewModel
    @StateObject private var flow = OnboardingFlow()
    @ObservedObject var steamCmd: SteamCmdService
    @ObservedObject var installer: SteamCmdInstaller
    @ObservedObject var assets: WallpaperEngineAssetsService
    @ObservedObject var imports: OnboardingImports
    /// Called with the shortcut the user picked on the Done step, before the sheet closes.
    let onShortcut: (OnboardingShortcut?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            stepList
            Divider()
            ScrollView {
                stepBody
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
            }
            .id(flow.step)
            .transition(.opacity)
            Divider()
            footer
        }
        .frame(width: 720, height: 640)
    }

    // MARK: Steps

    private var stepList: some View {
        HStack(spacing: 4) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { flow.go(to: step) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: icon(for: step))
                        Text(Self.title(of: step))
                    }
                    .font(.callout)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .foregroundStyle(step == flow.step ? Color.accentColor : (flow.skipped.contains(step) ? Color.secondary : Color.primary))
                    .background(step == flow.step ? Color.accentColor.opacity(0.15) : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .help(flow.skipped.contains(step) ? Text("Skipped. Click to set it up.") : Text(Self.title(of: step)))
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }

    private func icon(for step: OnboardingStep) -> String {
        if flow.completed.contains(step) && step != flow.step { return "checkmark.circle.fill" }
        switch step {
        case .welcome: return "hand.wave"
        case .privacy: return "hand.raised"
        case .steam: return "person.badge.key"
        case .assets: return "shippingbox"
        case .wallpapers: return "photo.on.rectangle.angled"
        case .done: return "flag.checkered"
        }
    }

    static func title(of step: OnboardingStep) -> LocalizedStringKey {
        switch step {
        case .welcome: return "Welcome"
        case .privacy: return "Privacy"
        case .steam: return "Steam"
        case .assets: return "Assets"
        case .wallpapers: return "Wallpapers"
        case .done: return "Done"
        }
    }

    @ViewBuilder
    private var stepBody: some View {
        switch flow.step {
        case .welcome:
            OnboardingWelcomeStep(settings: globalSettingsViewModel, onRelaunch: relaunch)
        case .privacy:
            OnboardingPrivacyStep(updater: AppDelegate.shared.updater)
        case .steam:
            OnboardingSteamStep(steamCmd: steamCmd, installer: installer)
        case .assets:
            OnboardingAssetsStep(assets: assets, steamCmd: steamCmd,
                                 logIn: { withAnimation(.easeInOut(duration: 0.15)) { flow.go(to: .steam) } })
        case .wallpapers:
            OnboardingWallpapersStep(steamCmd: steamCmd, imports: imports)
        case .done:
            OnboardingDoneStep(flow: flow, steamCmd: steamCmd, assets: assets, imports: imports,
                               language: globalSettingsViewModel.settings.language,
                               onShortcut: finish)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button("Back") {
                withAnimation(.easeInOut(duration: 0.15)) { flow.back() }
            }
            .disabled(flow.isFirst)
            Spacer()
            if let note = skipNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !flow.isLast {
                Button("Skip for Now") {
                    withAnimation(.easeInOut(duration: 0.15)) { flow.skip() }
                }
            }
            Button(flow.isLast ? "Finish" : "Continue") {
                if flow.isLast {
                    finish(nil)
                } else {
                    withAnimation(.easeInOut(duration: 0.15)) { flow.next() }
                }
            }
            .glassButtonStyle(.prominent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private var skipNote: LocalizedStringKey? {
        switch flow.step {
        case .steam where !steamCmd.isLoggedIn:
            return "Without Steam, video and web wallpapers still work."
        case .assets where assets.isBusy:
            return "The download continues in the background."
        default:
            return nil
        }
    }

    private func finish(_ shortcut: OnboardingShortcut?) {
        flow.finish()
        onShortcut(shortcut)
        dismiss()
    }

    private func relaunch() {
        flow.prepareForRelaunch()
        AppRelauncher.relaunch()
    }
}

extension AppDelegate {
    /// Help › Debug › Reset First Launch: shows the setup assistant again now.
    @objc func resetFirstLaunch() {
        OnboardingFlow.reopen()
        globalSettingsViewModel.isFirstLaunch = true
        openMainWindow()
    }
}
