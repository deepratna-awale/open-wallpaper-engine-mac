//
//  ExplorerItemMenu.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/8/29.
//

import SwiftUI

struct ExplorerItemMenu: SubviewOfContentView {
    
    var viewModel: ContentViewModel
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
                Button {
                    wallpaperViewModel.inspectAndApply(hoveredWallpaper)
                } label: {
                    Label {
                        Text("Set as Wallpaper", comment: "Context menu: applies the wallpaper to the selected displays")
                    } icon: {
                        Image(systemName: "checkmark.circle")
                    }
                }
                .disabled(!WallpaperSetAsRules.canSetWallpaper(hoveredWallpaper))
                Button {
                    AppDelegate.shared.showSceneInspector(for: hoveredWallpaper,
                                                          scopes: wallpaperViewModel.editedPropertyScopes(of: hoveredWallpaper),
                                                          mode: .screenSaver)
                } label: {
                    Label {
                        Text("Set as Screen Saver", comment: "Context menu: sets the wallpaper as the screen saver (Installed: opens Scene Edit / Export's Screen Saver mode)")
                    } icon: {
                        Image(systemName: "play.rectangle")
                    }
                }
                .disabled(!WallpaperSetAsRules.canSetScreenSaver(hoveredWallpaper))
            }

            Section {
                Menu("Add to Playlist") {
                    if wallpaperViewModel.playlists.isEmpty {
                        Text("Create a playlist first")
                    } else {
                        ForEach(wallpaperViewModel.playlists) { playlist in
                            Button {
                                let selected = viewModel.library.selectedWallpaperItems()
                                let wallpapers = selected.isEmpty ? [hoveredWallpaper] : selected
                                wallpaperViewModel.addToPlaylist(wallpapers, playlistID: playlist.id)
                            } label: {
                                Label(playlist.name, systemImage: playlist.id == wallpaperViewModel.activePlaylistID ? "checkmark" : "rectangle.stack")
                            }
                        }
                    }
                }
                Button {
                    viewModel.presentation.hoveredWallpaper = hoveredWallpaper
                    viewModel.presentation.isUnsubscribeConfirming = true
                } label: {
                    Label("Unsubscribe", systemImage: "xmark")
                }
                if viewModel.library.selectedWallpapers.count > 1 {
                    Button(role: .destructive) {
                        viewModel.presentation.isBatchUnsubscribeConfirming = true
                    } label: {
                        Label("Unsubscribe Selected (\(viewModel.library.selectedWallpapers.count))", systemImage: "xmark.circle")
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
                    if let id = workshopId { WorkshopPageLink.open(id) }
                } label: {
                    Label("Open in Workshop", systemImage: "cloud.fill")
                }
                .disabled(workshopId == nil)
                if let workshopId {
                    WorkshopRelatedMenu(viewModel: viewModel.workshopVM,
                                        authorId: WorkshopMetadataStore.shared.item(for: workshopId)?.creatorId,
                                        presetBase: presetBase)
                    Button {
                        WorkshopPageLink.open(workshopId)
                    } label: {
                        Label("Report…", systemImage: "exclamationmark.triangle")
                    }
                    .help("Opens the wallpaper's Steam Workshop page, where you can report it to Steam")
                }
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

    /// The wallpaper whose Workshop presets "Browse Presets" lists: a preset item's base, else a
    /// scene or web wallpaper itself, as WE offers it.
    private var presetBase: WorkshopPresetBase? {
        if hoveredWallpaper.isWorkshopPreset {
            let baseId = hoveredWallpaper.wallpaperDirectory.lastPathComponent
            guard WorkshopCollection.isID(baseId), hoveredWallpaper.wallpaperDirectory != hoveredWallpaper.presetDirectory
            else { return nil }
            return WorkshopPresetBase(id: baseId, title: WorkshopMetadataStore.shared.item(for: baseId)?.title ?? baseId)
        }
        guard let workshopId, ["scene", "web"].contains(hoveredWallpaper.project.type.lowercased()) else { return nil }
        return WorkshopPresetBase(id: workshopId, title: hoveredWallpaper.project.displayTitle)
    }
}
