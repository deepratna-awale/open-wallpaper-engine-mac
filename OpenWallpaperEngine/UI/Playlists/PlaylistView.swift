import SwiftUI

/// The selected playlist, in the main window's detail column; `PlaylistSidebar` lists them.
struct PlaylistView: View {
    @ObservedObject var wallpaperViewModel: WallpaperViewModel
    /// The playlist whose Delete button was clicked, until the confirmation is answered.
    @State private var playlistPendingDeletion: WallpaperPlaylist?

    var body: some View {
        playlistDetail
            .confirmationDialog(
                "Delete the playlist \u{201C}\(playlistPendingDeletion?.name ?? "")\u{201D}?",
                isPresented: Binding(
                    get: { playlistPendingDeletion != nil },
                    set: { if !$0 { playlistPendingDeletion = nil } }
                ),
                titleVisibility: .visible,
                presenting: playlistPendingDeletion
            ) { playlist in
                // Removes only the playlist; its wallpapers stay installed.
                Button("Delete", role: .destructive) {
                    wallpaperViewModel.deletePlaylist(playlist)
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Its wallpapers stay in your library.")
            }
    }

    @ViewBuilder private var playlistDetail: some View {
        if let playlist = wallpaperViewModel.activePlaylist {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(playlist.name).font(.largeTitle.bold())
                        Spacer()
                        Button(role: .destructive) {
                            playlistPendingDeletion = playlist
                        } label: {
                            Label("Delete playlist", systemImage: "trash")
                                .labelStyle(.iconOnly)
                        }
                        .glassButtonStyle()
                        .help("Delete playlist")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Rotate automatically", isOn: $wallpaperViewModel.playlistEnabled)
                        Toggle("Shuffle", isOn: $wallpaperViewModel.playlistShuffle)
                        Toggle("Repeat", isOn: $wallpaperViewModel.playlistRepeats)
                        Toggle("Change when video ends", isOn: Binding(
                            get: { playlist.changeWhenVideoEnds },
                            set: { wallpaperViewModel.setPlaylistChangeWhenVideoEnds($0) }
                        ))
                        HStack {
                            Text("Wallpaper duration")
                            // No `step:` (AppKit would draw a tick per step); the binding snaps instead.
                            Slider(value: Binding(
                                get: { playlist.duration },
                                set: { wallpaperViewModel.setPlaylistDuration(PlaylistDurationFormat.snapped($0)) }
                            ), in: PlaylistDurationFormat.range)
                            Text(PlaylistDurationFormat.label(playlist.duration))
                                .font(.caption.monospacedDigit())
                                .frame(width: 64, alignment: .trailing)
                        }
                    }
                    GlassGroup {
                        HStack {
                            Button { wallpaperViewModel.previousPlaylistWallpaper() } label: { Label("Previous", systemImage: "backward.fill") }
                                .glassButtonStyle()
                            Button { wallpaperViewModel.nextPlaylistWallpaper() } label: { Label("Next", systemImage: "forward.fill") }
                                .glassButtonStyle()
                            Text("\(playlist.items.count) wallpapers").foregroundStyle(.secondary)
                        }
                    }
                    ForEach(playlist.items) { item in
                        HStack(spacing: 10) {
                            GifImage(contentsOf: previewURL(for: item.wallpaper), animates: false)
                                .resizable()
                                .aspectRatio(1, contentMode: .fill)
                                .frame(width: 64, height: 64)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            Text(item.wallpaper.project.title.isEmpty ? "Untitled" : item.wallpaper.project.title)
                                .lineLimit(1)
                                .frame(width: 180, alignment: .leading)
                            Button { wallpaperViewModel.movePlaylistItem(itemID: item.id, offset: -1) } label: { Image(systemName: "chevron.up") }
                                .disabled(playlist.items.first?.id == item.id)
                                .help("Move up")
                            Button { wallpaperViewModel.movePlaylistItem(itemID: item.id, offset: 1) } label: { Image(systemName: "chevron.down") }
                                .disabled(playlist.items.last?.id == item.id)
                                .help("Move down")
                            Button(role: .destructive) { wallpaperViewModel.removeFromPlaylist(itemID: item.id) } label: { Image(systemName: "minus.circle") }
                                .help("Remove from playlist")
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                .padding(24)
            }
        } else {
            ContentUnavailableView("Create a Playlist", systemImage: "rectangle.stack.badge.plus",
                                   description: Text("Create a playlist to manage wallpaper rotation."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func previewURL(for wallpaper: WEWallpaper) -> URL {
        if wallpaper.project.type.lowercased() == "remote-video",
           let url = URL(string: wallpaper.project.file) {
            return url
        }
        if wallpaper.project.type.lowercased() == "remote-image",
           let url = URL(string: wallpaper.project.file) {
            return url
        }
        return wallpaper.project.previewURL(in: wallpaper.wallpaperDirectory)
            ?? Bundle.main.url(forResource: "WallpaperNotFound", withExtension: "mp4")!
    }
}
