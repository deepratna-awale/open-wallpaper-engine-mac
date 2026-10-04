import SwiftUI

// MARK: - Monitor Layout View

struct MonitorLayoutView: View {
    @ObservedObject var wallpaperViewModel: WallpaperViewModel

    var body: some View {
        let screens = NSScreen.screens
        let bounds = combinedBounds(screens)

        GeometryReader { geo in
            let scale = min(
                geo.size.width / max(bounds.width, 1),
                geo.size.height / max(bounds.height, 1)
            ) * 0.85

            ZStack {
                ForEach(screens, id: \.self) { screen in
                    let screenId = WallpaperViewModel.screenId(for: screen)
                    let isSelected = wallpaperViewModel.selectedScreenIds.contains(screenId)
                    let isEnabled = wallpaperViewModel.isScreenEnabled(screenId)
                    let frame = screen.frame

                    let x = (frame.origin.x - bounds.origin.x) * scale
                    let y = (bounds.height - (frame.origin.y - bounds.origin.y) - frame.height) * scale
                    let w = frame.width * scale
                    let h = frame.height * scale

                    MonitorRectangle(
                        name: WallpaperViewModel.screenName(for: screen),
                        wallpaperTitle: wallpaperViewModel.wallpaper(for: screenId).project.title,
                        isSelected: isSelected,
                        isEnabled: isEnabled,
                        isMain: screen == .main
                    )
                    .frame(width: w, height: h)
                    .position(x: x + w / 2 + (geo.size.width - bounds.width * scale) / 2,
                              y: y + h / 2 + (geo.size.height - bounds.height * scale) / 2)
                    .onTapGesture {
                        wallpaperViewModel.selectScreen(
                            screenId,
                            extendingSelection: NSEvent.modifierFlags.contains(.shift)
                        )
                    }
                }
            }
        }
    }

    private func combinedBounds(_ screens: [NSScreen]) -> CGRect {
        screens.reduce(.zero) { $0.union($1.frame) }
    }
}

// MARK: - Monitor Rectangle

struct MonitorRectangle: View {
    let name: String
    let wallpaperTitle: String
    let isSelected: Bool
    let isEnabled: Bool
    let isMain: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(isEnabled ? Color(nsColor: .controlBackgroundColor) : Color(nsColor: .separatorColor).opacity(0.3))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isSelected ? 3 : 1)
            )
            .overlay {
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        if isMain {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                        }
                        Text(name)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    if isEnabled {
                        Text(wallpaperTitle.isEmpty ? String(localized: "No wallpaper") : wallpaperTitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Disabled")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(4)
            }
    }
}
