import SwiftUI

/// Signing in to Steam: a QR code for the Steam mobile app, or an account name and password with
/// a Steam Guard code. Shows the account and Log Out once signed in.
struct SteamSignInView: View {
    @ObservedObject var account: SteamAccount
    @Environment(\.displayScale) private var displayScale
    @State private var accountName = ""
    @State private var password = ""
    @State private var guardCode = ""
    @State private var usesPassword = false

    var body: some View {
        VStack(spacing: 12) {
            switch account.status {
            case .signedIn(let name), .restoring(let name):
                signedIn(name)
            case .signedOut:
                signedOut
            case .signingIn(let step):
                signingIn(step)
            }
            if account.isSignedIn, account.ownsWallpaperEngine == false {
                Label {
                    Text("This Steam account can't download Wallpaper Engine items.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(.orange)
                .font(.callout)
            }
            if let error = account.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func signedIn(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label {
                    Text("Logged in to Steam as \(name)", comment: "%@ is the Steam account name")
                } icon: {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                }
                Spacer()
                if case .restoring = account.status { ProgressView().controlSize(.small) }
                Button("Log Out") { account.signOut() }
            }
            SteamLoginExpiryNotice(account: account)
        }
    }

    private var signedOut: some View {
        VStack(spacing: 12) {
            Button("Log In with the Steam Mobile App") { account.signInWithQR() }
                .glassButtonStyle(.prominent)
            DisclosureGroup("Log in with your account name and password instead", isExpanded: $usesPassword) {
                VStack(spacing: 8) {
                    TextField("Steam Username", text: $accountName)
                        .textContentType(.username)
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                    Button("Log In") {
                        account.signIn(accountName: accountName, password: password)
                        password = ""
                    }
                    .disabled(accountName.isEmpty || password.isEmpty)
                }
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
                .padding(.top, 8)
            }
            .frame(maxWidth: 420)
        }
    }

    @ViewBuilder
    private func signingIn(_ step: SteamAccount.SignInStep) -> some View {
        switch step {
        case .starting:
            ProgressView("Waiting for Steam…")
        case .scanQRCode(let url):
            qrCode(url)
            Text("In the Steam mobile app, open Steam Guard and scan this code.")
                .multilineTextAlignment(.center)
        case .guardCode(let email, let previousCodeWasIncorrect):
            guardCodeForm(email: email, previousCodeWasIncorrect: previousCodeWasIncorrect)
        case .confirmOnPhone:
            ProgressView("Approve the login in the Steam mobile app.")
        }
        Button("Cancel") { account.cancelSignIn() }
    }

    private func qrCode(_ url: URL) -> some View {
        let side: CGFloat = 196
        return ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white)
            if let image = AndroidWiFiQRCode.image(for: url.absoluteString, side: Int((side - 8) * displayScale), logo: nil) {
                Image(decorative: image, scale: displayScale)
                    .resizable()
                    .padding(4)
                    .accessibilityLabel(Text("QR code to log in to Steam"))
            }
        }
        .frame(width: side, height: side)
    }

    private func guardCodeForm(email: String?, previousCodeWasIncorrect: Bool) -> some View {
        VStack(spacing: 8) {
            if let email {
                Text("Enter the Steam Guard code Steam sent to \(email).", comment: "%@ is an email address")
            } else {
                Text("Enter the Steam Guard code from the Steam mobile app.")
            }
            if previousCodeWasIncorrect {
                Text("That code didn't work. Try again.")
                    .foregroundStyle(.red)
            }
            TextField("Steam Guard Code", text: $guardCode)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
                .onSubmit(submitGuardCode)
            Button("Continue", action: submitGuardCode)
                .disabled(guardCode.isEmpty)
        }
        .multilineTextAlignment(.center)
    }

    private func submitGuardCode() {
        guard !guardCode.isEmpty else { return }
        account.submitGuardCode(guardCode)
        guardCode = ""
    }
}

/// Steam's login ends after about 200 days and is never renewed: within two weeks of that, says
/// when, and offers to log in again (Log Out shows the login in its place).
struct SteamLoginExpiryNotice: View {
    @ObservedObject var account: SteamAccount

    var body: some View {
        if let login = account.login, login.endsSoon(), let expiresAt = login.expiresAt {
            HStack {
                Label {
                    Text("Your Steam login ends on \(expiresAt.formatted(date: .abbreviated, time: .omitted)). Log in again to keep using the Workshop.",
                         comment: "%@ is a date")
                } icon: {
                    Image(systemName: "clock.badge.exclamationmark")
                }
                .foregroundStyle(.orange)
                Spacer()
                Button("Log In Again") { account.signOut() }
            }
            .font(.callout)
        }
    }
}
