import SwiftUI

/// The selected playlist, in the main window's detail column; `PlaylistSidebar` lists them.
struct PlaylistView: View {
    @ObservedObject var wallpaperViewModel: WallpaperViewModel
    /// The playlist whose Delete button was clicked, until the confirmation is answered.
    @State private var playlistPendingDeletion: WallpaperPlaylist?
    @ObservedObject private var shortcuts = AppDelegate.shared.playlistShortcuts
    @State private var isRecordingShortcut = false
    /// A recorded shortcut something else uses, until the warning is answered.
    @State private var pendingShortcut: PendingShortcut?

    private struct PendingShortcut {
        let shortcut: GlobalShortcut
        let playlistID: UUID
        let conflicts: [GlobalShortcutConflict]
    }

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
            .alert(
                Text("\(pendingShortcut?.shortcut.symbols ?? "") is already in use"),
                isPresented: Binding(
                    get: { pendingShortcut != nil },
                    set: { if !$0 { pendingShortcut = nil } }
                ),
                presenting: pendingShortcut
            ) { pending in
                Button("Use Anyway") {
                    shortcuts.assign(pending.shortcut, to: pending.playlistID, resolving: pending.conflicts)
                }
                Button("Choose Another") { isRecordingShortcut = true }
                Button("Cancel", role: .cancel) {}
            } message: { pending in
                Text(verbatim: pending.conflicts.map(\.message).joined(separator: "\n\n"))
            }
    }

    /// Saves a recorded shortcut, or first warns about what already uses it.
    private func record(_ shortcut: GlobalShortcut, for playlistID: UUID) {
        let conflicts = shortcuts.conflicts(for: shortcut, playlistID: playlistID)
        if conflicts.isEmpty {
            shortcuts.assign(shortcut, to: playlistID)
        } else {
            pendingShortcut = PendingShortcut(shortcut: shortcut, playlistID: playlistID, conflicts: conflicts)
        }
    }

    @ViewBuilder private var playlistDetail: some View {
        if let playlist = wallpaperViewModel.activePlaylist {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(playlist.name).font(.largeTitle.bold())
                        Spacer()
                        ShortcutRecorderField(
                            shortcut: playlist.shortcut,
                            isRecording: $isRecordingShortcut,
                            onRecord: { record($0, for: playlist.id) },
                            onClear: { shortcuts.assign(nil, to: playlist.id) },
                            onRecordingChange: { $0 ? shortcuts.suspend() : shortcuts.resume() }
                        )
                        Button(role: .destructive) {
                            playlistPendingDeletion = playlist
                        } label: {
                            Label("Delete playlist", systemImage: "trash")
                                .labelStyle(.iconOnly)
                        }
                        .glassButtonStyle()
                        .help("Delete playlist")
                    }
                    if playlist.shortcut != nil, shortcuts.unregisteredPlaylists.contains(playlist.id) {
                        Label("This shortcut may not work: another app uses it.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.secondary)
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
                                .frame(minWidth: 64, alignment: .trailing)
                                .fixedSize()
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
                            Text(verbatim: item.wallpaper.project.displayTitle)
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
        return wallpaper.previewURL
            ?? AppBundleLayout.wallpaperNotFoundURL
    }
}
