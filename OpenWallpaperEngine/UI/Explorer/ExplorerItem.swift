//
//  ExplorerItem.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/8/25.
//

import OWEInspectorKit
import SwiftUI

struct ExplorerItem: SubviewOfContentView {
    @Environment(\.appAccentColor) private var accentColor
    
    var viewModel: ContentViewModel
    @ObservedObject var wallpaperViewModel: WallpaperViewModel
    @ObservedObject var safeRestart = AppDelegate.shared.safeRestart
    
    @ObservedObject var lowPowerMode = LowPowerModeState.shared
    @State var isHovered = false

    var wallpaper: WEWallpaper

    /// The tile's corner radius, which its selection stroke follows.
    static let cornerRadius: CGFloat = 8
    
    /// project.json's tags and the Workshop item's, as the Workshop cards show them.
    private var tags: [String] {
        viewModel.library.tags(of: wallpaper)
    }

    /// The tags as the UI names them (`LocalizedLabels`), in the user's language.
    private var tagLabels: [String] {
        tags.map { String(localized: LocalizedLabels.filterOption($0)) }
    }

    /// A tag in a first-strong isolate, so "2560 x 1440" keeps its order inside right-to-left text.
    private static func isolated(_ label: String) -> String { "\u{2068}\(label)\u{2069}" }

    /// The title, and all the tags under it.
    private var tooltip: String {
        tagLabels.isEmpty ? wallpaper.project.title
            : wallpaper.project.title + "\n" + tagLabels.formatted(.list(type: .and, width: .narrow))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // The library already decoded project.json; decoding it again per redraw made tab
            // switches slow.
            GifImage(contentsOf: wallpaper.previewURL
                        ?? AppBundleLayout.wallpaperNotFoundURL,
                     animates: ThumbnailAnimation.plays(isAppActive: viewModel.navigation.isApplicationActive,
                                                        isLowPowerMode: lowPowerMode.isEnabled,
                                                        isHovered: isHovered))
            .resizable()
            .scaleEffect(1.08)
            .aspectRatio(1.0, contentMode: .fill)
            .clipped()
            
            VStack(spacing: 2) {
                Text(wallpaper.project.title)
                    .lineLimit(2)
                    .font(.footnote)
                if !tags.isEmpty {
                    Text(verbatim: tagLabels.map(Self.isolated).joined(separator: " · "))
                        .lineLimit(1)
                        .font(.caption2)
                        .opacity(0.75)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 30)
            .padding(4)
            .background(Color(white: 0, opacity: 0.2))
            .multilineTextAlignment(.center)
            .foregroundStyle(Color(white: 0.7))
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .onHover { isHovered = $0 }
        .help(tooltip)
        .selectionHighlight(wallpaper.wallpaperDirectory == wallpaperViewModel.displayedWallpaper.wallpaperDirectory,
                            cornerRadius: Self.cornerRadius)
        .overlay(alignment: .topLeading) {
            if !viewModel.library.selectedWallpapers.isEmpty {
                Button {
                    viewModel.library.toggleSelection(for: wallpaper)
                } label: {
                    Image(systemName: viewModel.library.isSelected(wallpaper) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(viewModel.library.isSelected(wallpaper) ? accentColor : .white)
                }
                .buttonStyle(.plain)
                .shadow(color: .black.opacity(0.8), radius: 3, x: 0, y: 1)
                    .padding(4)
                .help("Select wallpaper")
            }
        }
        .overlay(alignment: .topTrailing) {
            if safeRestart.flaggedKeys.contains(SafeRestartLedger.key(for: wallpaper)) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .shadow(color: .black.opacity(0.8), radius: 3, x: 0, y: 1)
                    .padding(4)
                    .help("Open Wallpaper Engine didn't quit cleanly twice in a row while this wallpaper was showing")
            }
        }
        .onTapGesture {
            viewModel.library.selectWallpaper(
                wallpaper,
                from: viewModel.library.autoRefreshWallpapers,
                inspectingWith: wallpaperViewModel
            )
            wallpaperViewModel.inspect(wallpaper)
        }
        // Onto a folder tile or a breadcrumb: the selection when this tile is in it, as WE moves it.
        .draggable(InstalledDragPayload.wallpapers(
            viewModel.library.wallpapersActedOn(from: wallpaper).map(FavoritesStore.key(for:))).text)
        .onTapGesture(count: 2) {
            wallpaperViewModel.inspect(wallpaper)
            AppDelegate.shared.showWorkshopPreview(wallpaper)
        }
    }
}
