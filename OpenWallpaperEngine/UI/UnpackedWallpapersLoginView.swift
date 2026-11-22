import SwiftUI

/// After an update, when wallpapers an earlier version unpacked wait for their package and there is
/// no Steam login to download it with: why, the login, and a way to keep the loose copies instead.
struct UnpackedWallpapersLoginView: View {
    @ObservedObject var account: SteamAccount
    let waiting: UnpackedBundleRestoreService.Waiting
    /// There is a login, or the loose copies aren't kept any more.
    let startDownloads: () -> Void
    let onDismiss: () -> Void
    @AppStorage(UnpackedBundleRestoreService.keepsLooseCopiesKey, store: .app) private var keepsLooseCopies = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text("Log in to Steam to download your wallpapers again")
                    .font(.title2.bold())
            } icon: {
                Image(systemName: "shippingbox")
            }
            Text("Earlier versions unpacked your Workshop scenes into loose files. This version plays a scene straight from its Workshop package, so each one is downloaded once more, then its loose files are deleted. Log in to Steam to start the downloads.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Wallpapers to download: \(waiting.count), about \(waiting.bytes.formatted(.byteCount(style: .file)))",
                 comment: "%lld is a number of wallpapers, %@ a size such as 4.2 GB")
                .font(.headline)
            SteamSignInView(account: account)
                .padding(.vertical, 6)
            Divider()
            KeepUnpackedWallpapersToggle(keepsLooseCopies: $keepsLooseCopies)
            HStack {
                Spacer()
                if account.isSignedIn || keepsLooseCopies {
                    Button("Done", action: onDismiss)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Not Now", action: onDismiss)
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(20)
        .frame(width: 520)
        .onChange(of: account.isSignedIn) { _, isSignedIn in
            if isSignedIn { startDownloads() }
        }
        .onChange(of: keepsLooseCopies) { _, keeps in
            if !keeps { startDownloads() }
        }
    }
}

/// The setting, as the login after an update and Settings › Assets show it.
struct KeepUnpackedWallpapersToggle: View {
    @Binding var keepsLooseCopies: Bool

    var body: some View {
        Toggle(isOn: $keepsLooseCopies) {
            Text("Don't re-download wallpapers that were unpacked before")
            Text("They keep playing from their loose files. New downloads are never unpacked.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
