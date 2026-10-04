//
//  ExplorerItemMenu.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/8/29.
//

import SwiftUI

struct ExplorerItemMenu: SubviewOfContentView {
    
    @ObservedObject var viewModel: ContentViewModel
    @ObservedObject var wallpaperViewModel: WallpaperViewModel
    @ObservedObject private var favorites = FavoritesStore.shared

    var hoveredWallpaper: WEWallpaper
    
    init(contentViewModel viewModel: ContentViewModel, wallpaperViewModel: WallpaperViewModel, current hoveredWallpaper: WEWallpaper) {
        self.wallpaperViewModel = wallpaperViewModel
        self.viewModel = viewModel
        self.hoveredWallpaper = hoveredWallpaper
    }
    
    /// The wallpaper's Workshop id; nil for a local wallpaper.
    private var workshopId: String? {
        SceneWallpaperViewModel.workshopId(of: hoveredWallpaper)
    }

    var body: some View {
        Group {
            Section {
                Menu("Add to Playlist") {
                    if wallpaperViewModel.playlists.isEmpty {
                        Text("Create a playlist first")
                    } else {
                        ForEach(wallpaperViewModel.playlists) { playlist in
                            Button {
                                let selected = viewModel.selectedWallpaperItems()
                                let wallpapers = selected.isEmpty ? [hoveredWallpaper] : selected
                                wallpaperViewModel.addToPlaylist(wallpapers, playlistID: playlist.id)
                            } label: {
                                Label(playlist.name, systemImage: playlist.id == wallpaperViewModel.activePlaylistID ? "checkmark" : "rectangle.stack")
                            }
                        }
                    }
                }
                Button {
                    viewModel.hoveredWallpaper = hoveredWallpaper
                    viewModel.isUnsubscribeConfirming = true
                } label: {
                    Label("Unsubscribe", systemImage: "xmark")
                }
                if viewModel.selectedWallpapers.count > 1 {
                    Button(role: .destructive) {
                        viewModel.isBatchUnsubscribeConfirming = true
                    } label: {
                        Label("Unsubscribe Selected (\(viewModel.selectedWallpapers.count))", systemImage: "xmark.circle")
                    }
                }
                Button {
                    favorites.toggle(hoveredWallpaper)
                } label: {
                    Label(favorites.contains(hoveredWallpaper) ? "Remove from Favorites" : "Add to Favorites",
                          systemImage: favorites.contains(hoveredWallpaper) ? "heart.slash" : "heart.fill")
                }
            }
            
            Section {
                Button {
                    if let id = workshopId { openWorkshopPage(for: id) }
                } label: {
                    Label("Open in Workshop", systemImage: "cloud.fill")
                }
                .disabled(workshopId == nil)
                Button {
                    NSWorkspace.shared.selectFile(nil,
                                                  inFileViewerRootedAtPath: hoveredWallpaper.wallpaperDirectory.path(percentEncoded: false))
                } label: {
                    Label("Open in Finder", systemImage: "folder.badge.gearshape")
                }
            }
        }
        .labelStyle(.titleAndIcon)
    }

    /// Opens the item's page in the Steam client, or on the web when Steam isn't installed.
    private func openWorkshopPage(for id: String) {
        if let steam = WorkshopItemAvailability.steamClientPageURL(for: id),
           NSWorkspace.shared.urlForApplication(toOpen: steam) != nil {
            NSWorkspace.shared.open(steam)
        } else if let page = WorkshopItemAvailability.workshopPageURL(for: id) {
            NSWorkspace.shared.open(page)
        }
    }
}
