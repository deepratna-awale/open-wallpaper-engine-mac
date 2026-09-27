import SwiftUI

/// The selected playlist, in the main window's detail column; `PlaylistSidebar` lists them.
struct PlaylistView: View {
    @ObservedObject var wallpaperViewModel: WallpaperViewModel

    var body: some View {
        playlistDetail
    }

    @ViewBuilder private var playlistDetail: some View {
        if let playlist = wallpaperViewModel.activePlaylist {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(playlist.name).font(.largeTitle.bold())
                        Spacer()
                        Button(role: .destructive) {
                            wallpaperViewModel.deletePlaylist(playlist)
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
                            Slider(value: Binding(
                                get: { playlist.duration },
                                set: { wallpaperViewModel.setPlaylistDuration($0) }
                            ), in: 5...3600)
                            Text("\(Int(playlist.duration))s")
                                .font(.caption.monospacedDigit())
                                .frame(width: 48, alignment: .trailing)
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
