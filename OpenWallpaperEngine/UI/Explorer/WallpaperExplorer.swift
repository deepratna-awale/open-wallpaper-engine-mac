//
//  WallpaperExplorer.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/8/15.
//

import SwiftUI

struct WallpaperExplorer: SubviewOfContentView {
    var viewModel: ContentViewModel
    @ObservedObject var wallpaperViewModel: WallpaperViewModel
    @State private var isCreatePlaylistPresented = false

    init(contentViewModel viewModel: ContentViewModel, wallpaperViewModel: WallpaperViewModel) {
        self.viewModel = viewModel
        self.wallpaperViewModel = wallpaperViewModel
    }

    var body: some View {
        VStack(spacing: 8) {
            if viewModel.library.displayedWallpapers.isEmpty {
                Text("No wallpapers found for your search.")
                    .font(.title)
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // The whole list in one scrolling grid; tiles are made as they scroll in.
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(
                            .adaptive(
                                minimum: viewModel.navigation.explorerIconSize,
                                maximum: viewModel.navigation.explorerIconSize
                            ),
                            spacing: 8
                        )
                    ], alignment: .leading, spacing: 8) {
                        ForEach(viewModel.library.displayedWallpapers, id: \.wallpaperDirectory) { wallpaper in
                            ExplorerItem(viewModel: viewModel, wallpaperViewModel: wallpaperViewModel, wallpaper: wallpaper)
                                .contextMenu {
                                    ExplorerItemMenu(contentViewModel: viewModel, wallpaperViewModel: wallpaperViewModel, current: wallpaper)
                                    ExplorerGlobalMenu(contentViewModel: viewModel, wallpaperViewModel: wallpaperViewModel)
                                }
                        }
                    }
                    .padding(.bottom, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            GlassGroup {
                HStack(spacing: 8) {
                    Button {
                        isCreatePlaylistPresented = true
                    } label: {
                        Label("Create Playlist", systemImage: "rectangle.stack.badge.plus")
                    }
                    .glassButtonStyle()
                    .disabled(viewModel.library.selectedWallpapers.isEmpty)
                    EditWallpaperButton(wallpaperViewModel: wallpaperViewModel)
                }
                .padding(.vertical, 8)
            }
        }
        .sheet(isPresented: $isCreatePlaylistPresented) {
            CreatePlaylistSheet(
                wallpapers: viewModel.library.selectedWallpaperItems(),
                wallpaperViewModel: wallpaperViewModel,
                onComplete: {
                    viewModel.library.clearSelection()
                    isCreatePlaylistPresented = false
                }
            )
            .frame(width: 480, height: 360)
            .presentationBackground(.regularMaterial)
        }
    }
}

private struct CreatePlaylistSheet: View {
    let wallpapers: [WEWallpaper]
    @ObservedObject var wallpaperViewModel: WallpaperViewModel
    let onComplete: () -> Void
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create Playlist").font(.title2.bold())
            TextField("Playlist name", text: $name)
                .textFieldStyle(.roundedBorder)
            Text("\(wallpapers.count) wallpapers will be added")
                .foregroundStyle(.secondary)
            List(wallpapers) { wallpaper in
                Text(verbatim: wallpaper.project.displayTitle)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onComplete)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    guard wallpaperViewModel.createPlaylist(named: name, wallpapers: wallpapers) else { return }
                    onComplete()
                }
                .keyboardShortcut(.defaultAction)
                .glassButtonStyle(.prominent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
    }
}
