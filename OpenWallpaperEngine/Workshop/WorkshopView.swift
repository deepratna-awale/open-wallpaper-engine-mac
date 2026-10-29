import OWEInspectorKit
import SwiftUI

struct WorkshopView: SubviewOfContentView {
    var viewModel: ContentViewModel

    init(contentViewModel viewModel: ContentViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(spacing: 0) {
            // The browser ends its toolbar with the window's items; the login has only those.
            if viewModel.steamCmd.isLoggedIn {
                WorkshopBrowserView(
                    viewModel: viewModel.workshopVM,
                    contentViewModel: viewModel
                )
            } else {
                WorkshopLoginView(account: viewModel.steamAccount)
                    .toolbar { WindowActionsToolbar(viewModel: viewModel) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Steam Login

/// The Workshop's login: the Steam login, which browsing, searching and downloads go through.
private struct WorkshopLoginView: View {
    @ObservedObject var account: SteamAccount

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "person.badge.key")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)

                Text("Steam Login")
                    .font(.title2)
                    .bold()

                Text("Log in to Steam to browse and download Workshop wallpapers.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 420)

                SteamSignInView(account: account)
                    .frame(maxWidth: 420)
            }
            .padding(40)
            .frame(maxWidth: .infinity)
        }
    }
}
