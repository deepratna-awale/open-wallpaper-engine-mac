import SwiftUI

/// Says that scenes need the Wallpaper Engine assets and opens Settings › Assets to set them up.
/// Shown in the main window and the welcome sheet while no assets are installed.
struct AssetsMissingBanner: View {
    @ObservedObject var assets: WallpaperEngineAssetsService

    var body: some View {
        if assets.isMissing {
            HStack(spacing: 10) {
                Image(systemName: "shippingbox")
                    .foregroundStyle(.orange)
                Text("Scenes need Wallpaper Engine assets from your Steam copy.")
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Set Up Assets…") { AppDelegate.shared.openAssetsSettings() }
                    .glassButtonStyle(.prominent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }
}

/// A scene on the desktop while no assets are installed: it can't draw, so it says why.
struct AssetsMissingWallpaperView: View {
    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 10) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 40))
                Text("This scene needs Wallpaper Engine assets from your Steam copy. Set them up in Settings › Assets.")
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            .foregroundStyle(.white.opacity(0.75))
        }
        .ignoresSafeArea()
    }
}
