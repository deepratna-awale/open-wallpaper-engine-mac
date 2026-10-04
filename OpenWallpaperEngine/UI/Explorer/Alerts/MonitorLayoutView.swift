import SwiftUI

// MARK: - Monitor Layout View

/// The displays as arranged in System Settings: click to select, Shift-click to add to the
/// selection, right-click for WE's monitor menu (clone groups, the main clone display, flip and
/// mute). Each clone is outlined around its displays.
struct MonitorLayoutView: View {
    @ObservedObject var wallpaperViewModel: WallpaperViewModel
    @State private var isFlipLimitationShown = false

    var body: some View {
        let screens = NSScreen.screens
        let bounds = combinedBounds(screens)

        GeometryReader { geo in
            let scale = min(
                geo.size.width / max(bounds.width, 1),
                geo.size.height / max(bounds.height, 1)
            ) * 0.85
            let origin = CGPoint(x: (geo.size.width - bounds.width * scale) / 2,
                                 y: (geo.size.height - bounds.height * scale) / 2)
            let rect = { (screen: NSScreen) -> CGRect in
                let frame = screen.frame
                return CGRect(x: origin.x + (frame.origin.x - bounds.origin.x) * scale,
                              y: origin.y + (bounds.height - (frame.origin.y - bounds.origin.y) - frame.height) * scale,
                              width: frame.width * scale, height: frame.height * scale)
            }

            ZStack {
                ForEach(wallpaperViewModel.layoutResolution.clones) { clone in
                    let members = screens.filter { clone.screens.contains(WallpaperViewModel.screenId(for: $0)) }
                    let outline = members.map(rect).reduce(CGRect.null) { $0.union($1) }.insetBy(dx: -6, dy: -6)
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.accentColor.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .frame(width: outline.width, height: outline.height)
                        .position(x: outline.midX, y: outline.midY)
                        .accessibilityLabel(Text("Clone Group"))
                }

                ForEach(screens, id: \.self) { screen in
                    let screenId = WallpaperViewModel.screenId(for: screen)
                    let frame = rect(screen)

                    MonitorRectangle(
                        name: WallpaperViewModel.screenName(for: screen),
                        wallpaperTitle: wallpaperViewModel.wallpaper(for: screenId).project.title,
                        isSelected: wallpaperViewModel.selectedScreenIds.contains(screenId),
                        isEnabled: wallpaperViewModel.isScreenEnabled(screenId),
                        isMain: screen == .main,
                        isMainCloneDisplay: wallpaperViewModel.isMainCloneDisplay(screenId),
                        isFlipped: wallpaperViewModel.isFlipped(screenId),
                        isMuted: wallpaperViewModel.isMuted(screenId)
                    )
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .onTapGesture {
                        wallpaperViewModel.selectScreen(
                            screenId,
                            extendingSelection: NSEvent.modifierFlags.contains(.shift)
                        )
                    }
                    .contextMenu { menu(for: screenId) }
                }
            }
        }
        .alert("Flip Clone Display", isPresented: $isFlipLimitationShown) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("At least one display must be the source display and cannot be flipped.")
        }
    }

    /// WE's monitor menu for `screenId`.
    @ViewBuilder
    private func menu(for screenId: String) -> some View {
        let model = wallpaperViewModel
        let isCloned = model.isCloned(screenId)
        if model.displayLayout.layout == .perDisplay {
            let selection = model.selectedScreenIds.union([screenId])
            Button("Add Clone Group") { model.addCloneGroup(selection) }
                .disabled(selection.count < 2)
            if isCloned {
                Button("Remove from Group") { model.removeFromGroup(screenId) }
            }
        }
        if isCloned {
            Divider()
            if model.isChosenMainCloneDisplay(screenId) {
                Button("Remove Main Clone Display") { model.setMainCloneDisplay(screenId, false) }
            } else {
                Button("Set as Main Clone Display") { model.setMainCloneDisplay(screenId, true) }
            }
            Toggle("Flip Clone Display", isOn: Binding(
                get: { model.isFlipped(screenId) },
                set: { _ in if !model.toggleFlip(screenId) { isFlipLimitationShown = true } }
            ))
        }
        Divider()
        if model.isMuted(screenId) {
            Button("Unmute") { model.toggleMute(screenId) }
        } else {
            Button("Mute") { model.toggleMute(screenId) }
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
    var isMainCloneDisplay = false
    var isFlipped = false
    var isMuted = false

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
                    badges
                }
                .padding(4)
            }
    }

    @ViewBuilder private var badges: some View {
        if isMainCloneDisplay || isFlipped || isMuted {
            HStack(spacing: 6) {
                if isMainCloneDisplay {
                    Image(systemName: "rectangle.on.rectangle")
                        .accessibilityLabel(Text("Main Clone Display"))
                        .help(Text("Main Clone Display"))
                }
                if isFlipped {
                    Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                        .accessibilityLabel(Text("Flipped"))
                        .help(Text("Flipped"))
                }
                if isMuted {
                    Image(systemName: "speaker.slash.fill")
                        .accessibilityLabel(Text("Muted"))
                        .help(Text("Muted"))
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}
