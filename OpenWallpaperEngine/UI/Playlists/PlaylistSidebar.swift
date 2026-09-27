import SwiftUI

/// The playlists, in the main window's sidebar on the Playlists tab. Choosing one makes it the
/// active playlist.
struct PlaylistSidebar: View {
    @ObservedObject var wallpaperViewModel: WallpaperViewModel
    @State private var playlistName = ""
    @FocusState private var isNameFocused: Bool

    /// A click on empty space deselects a List; the active playlist stays set instead.
    private var selection: Binding<UUID?> {
        Binding(
            get: { wallpaperViewModel.activePlaylistID },
            set: { id in
                if let id { wallpaperViewModel.activePlaylistID = id }
            }
        )
    }

    var body: some View {
        List(selection: selection) {
            Section {
                ForEach(wallpaperViewModel.playlists) { playlist in
                    HStack {
                        Label(playlist.name, systemImage: playlist.id == wallpaperViewModel.activePlaylistID ? "checkmark" : "rectangle.stack")
                        Spacer()
                        Text("\(playlist.items.count)").foregroundStyle(.secondary)
                    }
                    .tag(playlist.id)
                }
            } header: {
                HStack {
                    Text("Playlists")
                    Spacer()
                    Button {
                        playlistName = ""
                        isNameFocused = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .help("Create playlist")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                TextField("New playlist", text: $playlistName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFocused)
                    .onSubmit(create)
                Button(action: create) {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.plain)
                .help("Create playlist")
                .disabled(playlistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(10)
        }
    }

    private func create() {
        guard !playlistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        wallpaperViewModel.createPlaylist(named: playlistName)
        playlistName = ""
    }
}
