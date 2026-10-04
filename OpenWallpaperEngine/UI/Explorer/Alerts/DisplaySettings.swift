//
//  DisplaySettingsView.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/8/15.
//

import SwiftUI

struct DisplaySettings: SubviewOfContentView {
    @ObservedObject var viewModel: ContentViewModel
    @ObservedObject var wallpaperViewModel: WallpaperViewModel

    init(viewModel: ContentViewModel) {
        self.viewModel = viewModel
        self.wallpaperViewModel = AppDelegate.shared.wallpaperViewModel
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Display Settings")
                .font(.largeTitle)

            Text("Click a display to select it. Hold Shift while clicking to select multiple desktops.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Toggle("All Desktops", isOn: Binding(
                get: {
                    let screenIds = Set(NSScreen.screens.map(WallpaperViewModel.screenId(for:)))
                    return !screenIds.isEmpty && wallpaperViewModel.selectedScreenIds == screenIds
                },
                set: { selectAll in
                    let screenIds = Set(NSScreen.screens.map(WallpaperViewModel.screenId(for:)))
                    wallpaperViewModel.selectedScreenIds = selectAll ? screenIds : [wallpaperViewModel.selectedScreenId]
                }
            ))
            .toggleStyle(.checkbox)

            // Monitor layout
            MonitorLayoutView(wallpaperViewModel: wallpaperViewModel)
                .frame(maxHeight: 200)

            // Selected screen info
            if let screen = NSScreen.screens.first(where: { WallpaperViewModel.screenId(for: $0) == wallpaperViewModel.selectedScreenId }) {
                let screenId = wallpaperViewModel.selectedScreenId
                let wp = wallpaperViewModel.wallpaper(for: screenId)

                GroupBox {
                    VStack(spacing: 8) {
                        HStack {
                            Text(WallpaperViewModel.screenName(for: screen))
                                .font(.headline)
                            Text(verbatim: "\(Int(screen.frame.width))×\(Int(screen.frame.height))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Toggle("Enabled", isOn: Binding(
                                get: { wallpaperViewModel.isScreenEnabled(screenId) },
                                set: { _ in wallpaperViewModel.toggleScreen(screenId) }
                            ))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        }

                        if wallpaperViewModel.isScreenEnabled(screenId) {
                            HStack {
                                DisplayWallpaperPicture(wallpaper: wp,
                                                        displayName: WallpaperViewModel.screenName(for: screen),
                                                        displaySize: screen.frame.size,
                                                        displayScale: screen.backingScaleFactor,
                                                        placement: wallpaperViewModel.wallpaperPlacement)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(wp.project.title.isEmpty ? String(localized: "No wallpaper") : wp.project.title)
                                        .font(.callout)
                                        .fontWeight(.medium)
                                    Text(verbatim: wp.project.type.isEmpty ? "—" : LocalizedLabels.wallpaperType(wp.project.type))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Remove") {
                                    wallpaperViewModel.wallpapers.removeValue(forKey: screenId)
                                }
                                .glassButtonStyle()
                                .controlSize(.small)
                                .disabled(wp.project == .invalid)
                            }
                        } else {
                            Text("Wallpaper display is disabled on this screen.")
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(8)
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Done") {
                    viewModel.isDisplaySettingsReveal = false
                }
                .keyboardShortcut(.defaultAction)
                .glassButtonStyle(.prominent)
            }
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - Monitor Layout View

private struct MonitorLayoutView: View {
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

private struct MonitorRectangle: View {
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
