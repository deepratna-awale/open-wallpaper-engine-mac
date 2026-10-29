import SwiftUI

/// Settings › Assets › Steam: the Steam login everything on Steam goes through (`SteamAccount`).
struct SteamAccountSection: View {
    @ObservedObject var account: SteamAccount

    var body: some View {
        Section {
            SteamSignInView(account: account)
        } header: {
            Label("Steam Login", systemImage: "person.crop.circle")
        } footer: {
            Text("With the Steam mobile app, you log in without typing your password. A password goes only to Steam. Your login is kept in your keychain on this Mac.")
        }
    }
}
