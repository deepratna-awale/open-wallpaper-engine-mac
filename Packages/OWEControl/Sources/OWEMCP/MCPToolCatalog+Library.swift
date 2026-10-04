import Foundation
import OWEControlProtocol

/// The library and the app (`docs/mcp.md`): playlists, favourites, deleting wallpapers, the
/// displays wallpapers are shown on, the app's settings and the plugins' status. Each tool does
/// what the app's own control does; the deleting ones need `confirm: true`.
extension MCPToolCatalog {
    static let libraryTools: [MCPTool] = playlistTools + wallpaperTools + displayTools + settingsTools + pluginTools

    private static let libraryPlaylist = JSONSchema.string(
        "A playlist's name (case-insensitive) or id, from list_playlists.", minLength: 1)
    private static let libraryConfirm = JSONSchema.boolean(
        "Must be true: the client confirms the user asked for this removal.")

    // MARK: - Playlists

    private static let playlistTools: [MCPTool] = [
        MCPTool("playlist_create", title: "Create Playlist",
                description: "Creates a playlist, as the playlist sidebar does, optionally with wallpapers in it, and makes it the playlist shown and played next. A name another playlist has is refused.",
                input: JSONSchema.object([
                    "name": JSONSchema.string("The new playlist's name.", minLength: 1),
                    "wallpaper_ids": JSONSchema.stringArray("Wallpapers to put in it, in order: ids from list_wallpapers.", maxItems: 500),
                ], required: ["name"]), annotations: .change) { message($0) },
        MCPTool("playlist_update", title: "Update Playlist",
                description: "Changes a playlist's own options, as its view does: how long each wallpaper shows (snapped to the view's steps: 5 seconds below a minute, 15 from a minute on) and whether a video moves on when it ends. Rotate, shuffle and repeat are app-wide: settings_set's playlist_rotate, playlist_shuffle and playlist_repeat.",
                input: JSONSchema.object([
                    "playlist": libraryPlaylist,
                    "duration_seconds": JSONSchema.number("Seconds each wallpaper shows, 5 to 3600.", minimum: 5, maximum: 3600),
                    "change_when_video_ends": JSONSchema.boolean("true: a video wallpaper moves on to the next item when it ends."),
                ], required: ["playlist"]), annotations: .idempotent) { message($0) },
        MCPTool("playlist_add_items", title: "Add to Playlist",
                description: "Adds wallpapers to the end of a playlist, as Add to Playlist in the library's menu does. A wallpaper already in it is left where it is.",
                input: JSONSchema.object([
                    "playlist": libraryPlaylist,
                    "wallpaper_ids": JSONSchema.stringArray("The wallpapers to add: ids from list_wallpapers.", maxItems: 500),
                ], required: ["playlist", "wallpaper_ids"]), annotations: .change) { message($0) },
        MCPTool("playlist_remove_items", title: "Remove from Playlist",
                description: "Removes wallpapers from a playlist, as its Remove buttons do. The wallpapers stay in the library.",
                input: JSONSchema.object([
                    "playlist": libraryPlaylist,
                    "wallpaper_ids": JSONSchema.stringArray("The wallpapers to remove: ids from list_playlists.", maxItems: 500),
                ], required: ["playlist", "wallpaper_ids"]), annotations: .destructive) { message($0) },
        MCPTool("playlist_move_item", title: "Move Playlist Item",
                description: "Moves a wallpaper up (negative offset) or down (positive) in a playlist by that many places, as its Move Up and Move Down buttons do one place at a time.",
                input: JSONSchema.object([
                    "playlist": libraryPlaylist,
                    "wallpaper_id": JSONSchema.string("The wallpaper to move: an id from list_playlists.", minLength: 1),
                    "offset": JSONSchema.integer("Places to move: -1 is one up, 1 one down."),
                ], required: ["playlist", "wallpaper_id", "offset"]), annotations: .change) { message($0) },
        MCPTool("playlist_delete", title: "Delete Playlist",
                description: "Deletes a playlist, as its Delete button does. Its wallpapers stay in the library. Needs confirm: true.",
                input: JSONSchema.object(["playlist": libraryPlaylist, "confirm": libraryConfirm], required: ["playlist", "confirm"]),
                annotations: .destructive) { message($0) },
    ]

    // MARK: - Wallpapers

    private static let wallpaperTools: [MCPTool] = [
        MCPTool("wallpaper_set_favorite", title: "Set Favorite",
                description: "Marks a wallpaper as a favourite or not, as the heart in the library does (the Installed tab's My Favourites filter).",
                input: JSONSchema.object([
                    "id": wallpaperID,
                    "favorite": JSONSchema.boolean("true to favourite it, false to stop."),
                ], required: ["id", "favorite"]), annotations: .idempotent) { message($0) },
        MCPTool("wallpaper_delete", title: "Delete Wallpaper",
                description: "Deletes a wallpaper from the library, as Unsubscribe in the library does: its folder goes to the Trash (or is deleted at once with to_trash false), it leaves the displays showing it, and Workshop dependencies nothing else uses are removed. Steam subscriptions are not touched. Needs confirm: true.",
                input: JSONSchema.object([
                    "id": wallpaperID,
                    "confirm": libraryConfirm,
                    "to_trash": JSONSchema.boolean("true (the default) moves the folder to the Trash; false deletes it immediately."),
                ], required: ["id", "confirm"]), annotations: .destructive) { message($0) },
    ]

    // MARK: - Displays

    private static let displayTools: [MCPTool] = [
        MCPTool("display_settings_get", title: "Get Display Settings",
                description: "Each display's own settings, as Display Settings shows them: whether wallpapers are shown on it (enabled), the wallpaper it shows and its playback rule state. App-wide appearance (placement, render resolution, FPS, menu bar tint) is in settings_get.",
                input: JSONSchema.object(["display": display]), annotations: .readOnly) { message($0) },
        MCPTool("display_settings_set", title: "Set Display Settings",
                description: "Turns wallpapers on or off for one display, as Display Settings' Enabled switch does.",
                input: JSONSchema.object([
                    "display": JSONSchema.string("A display's id or name from list_displays.", minLength: 1),
                    "enabled": JSONSchema.boolean("true shows wallpapers on the display, false shows the desktop picture."),
                ], required: ["display", "enabled"]), annotations: .idempotent) { message($0) },
    ]

    // MARK: - Settings

    private static let settingsTools: [MCPTool] = [
        MCPTool("settings_get", title: "Get Settings",
                description: "The app settings settings_set can change (performance, quality, playback rules, audio, appearance, playlists), each with its value, its type, its allowed values or range, and what it does.",
                input: JSONSchema.object([
                    "keys": JSONSchema.stringArray("Only these settings' keys. Omit for all of them.", maxItems: 100),
                ]), annotations: .readOnly) { message($0) },
        MCPTool("settings_set", title: "Set Setting",
                description: "Changes one app setting, as its control in Settings does. settings_get lists the keys, their allowed values and ranges. Launch at login, the language, the log level, restart after crashing, the screen saver and lock screen, web wallpaper trust and plugins are not settable here.",
                input: JSONSchema.object([
                    "key": JSONSchema.string("The setting's key, from settings_get.", minLength: 1),
                    "value": JSONSchema.string("The new value as text: true or false, a number within the range, or one of the allowed values. A JSON number or boolean is accepted too."),
                ], required: ["key", "value"]), annotations: .idempotent) { message($0) },
    ]

    // MARK: - Plugins

    private static let pluginTools: [MCPTool] = [
        MCPTool("plugin_status", title: "Plugin Status",
                description: "The plugins Settings › Plugins lists (MCP Server, Depth Map Generation, Screen Saver, Chromium web engine) with whether each is installed or on, its version and whether an update is due. Installing and removing plugins stays in the app.",
                annotations: .readOnly) { message($0) },
    ]
}
