# MCP Server

Open Wallpaper Engine can be controlled by MCP clients: AI assistants and other tools that speak
the [Model Context Protocol](https://modelcontextprotocol.io). The **MCP Server** plugin adds
`owe-mcp`, a server the client starts, which passes each tool call to the running app. Nothing is
installed or listening until you install the plugin.

## Setup

1. Open **Settings › Plugins › MCP Server** and click **Install**. This copies the `owe-mcp` the
   app ships (signed and notarized with it) to
   `~/Library/Application Support/Open Wallpaper Engine/Plugins/MCP/owe-mcp`, and the app starts
   accepting MCP clients.
2. Click **Copy MCP Client Configuration** and paste it into your client's MCP settings. It looks
   like this:

   ```json
   {
     "mcpServers": {
       "open-wallpaper-engine": {
         "command": "/Users/you/Library/Application Support/Open Wallpaper Engine/Plugins/MCP/owe-mcp"
       }
     }
   }
   ```

   With Claude Code, one command does it (the plugin's row shows it with your path):

   ```sh
   claude mcp add open-wallpaper-engine -- "$HOME/Library/Application Support/Open Wallpaper Engine/Plugins/MCP/owe-mcp"
   ```

3. Ask the client to list your wallpapers. When Open Wallpaper Engine isn't running, the first tool
   call starts it in the background and waits for it (up to 30 seconds).

**Remove** in the same place deletes `owe-mcp`, closes the connection and every client's
connection, and stops accepting clients. An app update refreshes the installed `owe-mcp` the next
time the app starts.

## Tools

Every tool returns structured content (the JSON below) with a one-line summary, and the same JSON as
text for clients that don't read structured content. Ids come from `list_wallpapers` (a wallpaper's
folder name; its Workshop id or folder path also work) and `list_displays`. Where a tool takes
`display`, leaving it out means every display wallpapers are shown on.

| Tool | Arguments | What it does |
|---|---|---|
| `list_displays` | none | The displays: `id`, `name`, `main`, `enabled` (wallpapers shown), `width`/`height` in points, `scale`, `rule` (Settings › Performance › Playback's state: `run`, `mute`, `pause`, `stop`) and the `wallpaper` each shows. |
| `get_status` | `display?` | Per display, the wallpaper (`id`, `title`, `type`) and whether it is `playing`; `paused`, `volume` (0–1), `muted`, and the active `playlist`. |
| `list_wallpapers` | `query?`, `type?` (`scene`, `video`, `web`, `application`), `tags?`, `limit?` (1–500, 50 by default), `offset?` | Searches the library (the Installed tab, without its filters), by title, tags and description. Returns `total` and each wallpaper's `id`, `title`, `type`, `tags`, `folder` and `workshop_id`. |
| `get_wallpaper` | `id` | The wallpaper's details, the `displays` showing it, and its user `properties`: `key`, `title`, `type`, `value`, `default`, `condition`; sliders add `min`, `max`, `step`, `whole_numbers`; combos add `options` (`label`, `value`) and `free_text`. |
| `set_wallpaper` | `id`, `display?` | Shows the wallpaper, as applying it in the library does. A web wallpaper must have been trusted in the app once ("Don't ask again for this wallpaper"); the app never skips that question for a client. |
| `pause`, `resume`, `toggle_playback` | none | Pauses or resumes every wallpaper, as the menu bar does. Returns `paused`. |
| `set_volume` | `level` (0–1) | The wallpapers' volume. Returns `volume` and `muted`. |
| `set_muted` | `muted` | Mute and Unmute from the menu bar; unmuting brings back the volume from before. |
| `set_user_property` | `id`, `key`, `value` | Changes one user property, as the Details panel does, live on the displays showing the wallpaper (each display's own properties, or the shared ones while "Sync properties across displays" is on). The value must fit the property: a number within a slider's range (whole when it takes whole numbers), `true`/`false` for a checkbox, a combo option's value or label, a colour as `"r g b"` with each 0–1 (or `#rrggbb`, or `[r, g, b]`), text, or an existing absolute path for a file or folder. |
| `list_playlists` | none | Each playlist's `id`, `name`, `wallpapers`, `duration_seconds`, `active`, `rotating`, `shuffle` and the `displays` it last played on. |
| `play_playlist` | `name`, `display?` | Makes the playlist active and starts rotating it, as its shortcut does. Names match case-insensitively. |
| `next_wallpaper`, `previous_wallpaper` | `display?` | Next and Previous Wallpaper from the menu: the active playlist's next or previous item where it plays, else a random library wallpaper (next) or the one shown before (previous). |
| `import_wallpaper` | `path` | Import › From Folder: a wallpaper folder (with `project.json`), a folder of them, or a `.zip`. Returns the `imported` wallpapers and what was `skipped`, with why (a folder of that name is already in the library, for example). |
| `open_editor` | `id`, `editor` (`scene` or `wallpaper`) | Opens a scene wallpaper in the Scene Editor or the Wallpaper Editor, for you to edit. |
| `snapshot` | `display?` (the main display by default) | A PNG of the wallpaper on that display, at most 960 pixels wide, as image content. `source` says what it is: `loading_snapshot` (the scene's own frame, which the app captures for its loading screen), `video_frame`, or `preview` (the wallpaper's preview image, when there is no frame yet). |

Playback and volume are app-wide in Open Wallpaper Engine (as in the menu bar), so `pause`,
`resume`, `toggle_playback`, `set_volume` and `set_muted` take no display.

The plugin never touches Steam accounts, logins or Workshop subscriptions, and has no tool that
deletes anything.

### Resources

`resources/list` offers `owe://library` (every wallpaper, as `list_wallpapers` returns them) and
`owe://status` (what `get_status` returns).

## Security model

- **Opt-in.** Nothing listens until the plugin is installed. Removing it closes the socket and
  every connection, and deletes `owe-mcp`.
- **Local only.** `owe-mcp` talks to the app over a Unix domain socket,
  `~/Library/Application Support/Open Wallpaper Engine/Control/control.sock`. There is no network
  port. A socket's path is limited to 103 bytes; when that path is longer (a long user name, or an
  isolated copy's folder), the socket goes in your own temporary folder instead
  (`/var/folders/…/T/owe-<hash>/control.sock`, which only you can enter), and `owe-mcp` finds it
  the same way.
- **Owner-only.** The socket's folder is `0700` and the socket `0600`, and the app checks that each
  connection comes from your own user account (`getpeereid`) before reading from it. Other users
  on the Mac can't connect.
- **No more than the app's own controls.** Every request goes through what the app's buttons and
  menus do, on the app's main thread: a web wallpaper still needs your trust in the app before a
  client can set it, safe restart still holds back a wallpaper that stopped the app, and an import
  copies only wallpaper folders, as the Import button does.
- **What a client can reach.** Anything running as your user could already change the app's
  settings files; the socket adds no access beyond that. Treat an MCP client like any program you
  run: it can change your wallpapers and import folders it can read.

The wire format between `owe-mcp` and the app is one JSON object per line, with a `version`
(`ControlRequest`, `ControlResponse` in `Packages/OWEControl`); the app refuses requests of another
version, so an `owe-mcp` from a different release says so instead of misbehaving.

## Troubleshooting

- **"Open Wallpaper Engine is running but doesn't accept MCP clients"**: the plugin isn't installed
  in this copy of the app. Install it in Settings › Plugins.
- **"didn't start within 30 seconds"**: the app couldn't be started, or started without the plugin
  (it was removed). Start the app yourself and check Settings › Plugins › MCP Server.
- **The client says the server failed to start**: check the path in its configuration. Copy the
  configuration again from Settings › Plugins; the path contains spaces, so in a shell quote it.
  Run it by hand to see its messages on stderr:
  `"$HOME/Library/Application Support/Open Wallpaper Engine/Plugins/MCP/owe-mcp" --help`.
- **"MCP clients can't connect"** under the plugin in Settings: the socket couldn't be opened. The
  message says why; the app's log has the details:
  `/usr/bin/log show --last 10m --predicate 'process == "Open Wallpaper Engine"' | grep MCP`.
- **A development copy.** A copy launched isolated (`OWE_ISOLATED_STATE=<tag>`) keeps its own
  support folder, so the plugin it installs talks only to it. To point any `owe-mcp` at an isolated
  copy, run it with the same `OWE_ISOLATED_STATE`, or with `--socket <path>`.

## For developers

- `Packages/OWEControl` (`swift test --package-path Packages/OWEControl`): `OWEControlProtocol` is
  the wire format, the socket server and client and the plugin's layout; `OWEMCP` is the MCP
  server: JSON-RPC 2.0 over stdio (protocol version 2025-06-18; 2025-03-26 and 2024-11-05 are
  accepted), the tools' schemas and the launcher.
- `MCPServer/main.swift` is the `owe-mcp` executable (target OWEMCPServer), embedded in
  `Contents/Helpers`.
- `OpenWallpaperEngine/MCP/` is the app's side: the plugin (`MCPServerPlugin`), its Settings row,
  the request router (`ControlRequestRouter`) and the app model it drives (`AppControlModel`).
