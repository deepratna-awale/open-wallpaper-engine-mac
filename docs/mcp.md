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
2. Open **Copy Configuration For** and pick your client. The snippet for that client, with the
   installed path, goes to the clipboard; paste it where [Client setup](#client-setup) says.
   Hovering a client in the menu shows where its configuration lives.
3. Ask the client to list your wallpapers. When Open Wallpaper Engine isn't running, the first tool
   call starts it in the background and waits for it (up to 30 seconds).

**Remove** in the same place deletes `owe-mcp`, closes the connection and every client's
connection, and stops accepting clients. An app update refreshes the installed `owe-mcp` the next
time the app starts.

## Client setup

Every snippet names the server `open-wallpaper-engine` and starts `owe-mcp` by its absolute path,
with no arguments. The path below is an example: **Copy Configuration For** fills in yours. Merge
the snippet into the file when it already has other servers. Formats checked against each client's
documentation in October 2026.

| Client | Where | Docs |
| --- | --- | --- |
| Claude Desktop | `~/Library/Application Support/Claude/claude_desktop_config.json` (Settings › Developer › Edit Config) | [modelcontextprotocol.io](https://modelcontextprotocol.io/docs/develop/connect-local-servers) |
| Claude Code | Terminal | [code.claude.com](https://code.claude.com/docs/en/mcp) |
| VS Code / GitHub Copilot | `.vscode/mcp.json`, or **MCP: Open User Configuration** | [code.visualstudio.com](https://code.visualstudio.com/docs/copilot/customization/mcp-servers) |
| Cursor | `~/.cursor/mcp.json`, or `.cursor/mcp.json` in a project | [cursor.com](https://cursor.com/docs/context/mcp) |
| Kiro | `~/.kiro/settings/mcp.json`, or `.kiro/settings/mcp.json` in a workspace | [kiro.dev](https://kiro.dev/docs/mcp/configuration/) |
| Windsurf | `~/.codeium/windsurf/mcp_config.json` (Devin Desktop, its successor: `~/.config/devin/mcp_config.json`) | [docs.devin.ai](https://docs.devin.ai/desktop/cascade/mcp) |
| Zed | Zed's `settings.json` | [zed.dev](https://zed.dev/docs/ai/mcp) |
| OpenAI Codex CLI | `~/.codex/config.toml` | [learn.chatgpt.com](https://learn.chatgpt.com/docs/extend/mcp?surface=cli) |
| Gemini CLI | `~/.gemini/settings.json`, or `.gemini/settings.json` in a project | [gemini-cli](https://github.com/google-gemini/gemini-cli/blob/main/docs/tools/mcp-server.md) |
| Cline | `cline_mcp_settings.json` (MCP Servers › Configure); the CLI reads `~/.cline/mcp.json` | [docs.cline.bot](https://docs.cline.bot/mcp/configuring-mcp-servers) |
| Continue | `.continue/mcpServers/open-wallpaper-engine.yaml` | [docs.continue.dev](https://docs.continue.dev/customize/deep-dives/mcp) |

**Claude Desktop, Cursor, Windsurf, Gemini CLI** (`mcpServers`):

```json
{
  "mcpServers": {
    "open-wallpaper-engine": {
      "command": "/Users/you/Library/Application Support/Open Wallpaper Engine/Plugins/MCP/owe-mcp"
    }
  }
}
```

**Kiro** adds `"args": []` and `"disabled": false`; **Cline** those and `"autoApprove": []`.

**Claude Code:**

```sh
claude mcp add open-wallpaper-engine -- '/Users/you/Library/Application Support/Open Wallpaper Engine/Plugins/MCP/owe-mcp'
```

**VS Code / GitHub Copilot** (`servers`):

```json
{
  "servers": {
    "open-wallpaper-engine": {
      "type": "stdio",
      "command": "/Users/you/Library/Application Support/Open Wallpaper Engine/Plugins/MCP/owe-mcp"
    }
  }
}
```

**Zed** (`context_servers`):

```json
{
  "context_servers": {
    "open-wallpaper-engine": {
      "command": "/Users/you/Library/Application Support/Open Wallpaper Engine/Plugins/MCP/owe-mcp",
      "args": [],
      "env": {}
    }
  }
}
```

**OpenAI Codex CLI:**

```toml
[mcp_servers.open-wallpaper-engine]
command = "/Users/you/Library/Application Support/Open Wallpaper Engine/Plugins/MCP/owe-mcp"
```

**Continue:**

```yaml
name: Open Wallpaper Engine
version: 0.0.1
schema: v1
mcpServers:
  - name: open-wallpaper-engine
    type: stdio
    command: "/Users/you/Library/Application Support/Open Wallpaper Engine/Plugins/MCP/owe-mcp"
```

**Any other client** that starts stdio servers: `{"type": "stdio", "command": "/Users/you/Library/Application Support/Open Wallpaper Engine/Plugins/MCP/owe-mcp", "args": []}`.

### Compatibility

- Protocol revisions 2025-06-18, 2025-03-26 and 2024-11-05: `owe-mcp` answers in the revision the
  client asks for (the latest for any other), and sends only what that revision has: titles and
  structured tool results from 2025-06-18, tool annotations from 2025-03-26, JSON-RPC batches
  before 2025-06-18. Every tool result also carries its JSON as text.
- Tool schemas are plain JSON Schema: an object of simply typed, described properties, enums for
  choices, no `$ref`, `oneOf`, `anyOf` or `additionalProperties` (unknown arguments are still
  refused). A number or boolean given for a text property is taken as its text.
- `snapshot` returns MCP image content; with `"format": "path"` it saves the PNG to a temporary
  file (owner-only) and returns its path instead, for clients that can't show images.
- stdout carries only JSON-RPC; diagnostics go to stderr.

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
| `set_user_property` | `id`, `key`, `value` (text; a JSON number or boolean works too) | Changes one user property, as the Details panel does, live on the displays showing the wallpaper (each display's own properties, or the shared ones while "Sync properties across displays" is on). The value must fit the property: a number within a slider's range (whole when it takes whole numbers), `true`/`false` for a checkbox, a combo option's value or label, a colour as `"r g b"` with each 0–1 (or `#rrggbb`, or `[r, g, b]`), text, or an existing absolute path for a file or folder. |
| `list_playlists` | none | Each playlist's `id`, `name`, `wallpapers`, `duration_seconds`, `active`, `rotating`, `shuffle` and the `displays` it last played on. |
| `play_playlist` | `name`, `display?` | Makes the playlist active and starts rotating it, as its shortcut does. Names match case-insensitively. |
| `next_wallpaper`, `previous_wallpaper` | `display?` | Next and Previous Wallpaper from the menu: the active playlist's next or previous item where it plays, else a random library wallpaper (next) or the one shown before (previous). |
| `import_wallpaper` | `path` | Import › From Folder: a wallpaper folder (with `project.json`), a folder of them, or a `.zip`. Returns the `imported` wallpapers and what was `skipped`, with why (a folder of that name is already in the library, for example). |
| `open_editor` | `id`, `editor` (`scene` or `wallpaper`) | Opens a scene wallpaper in the Scene Editor or the Wallpaper Editor, for you to edit. |
| `snapshot` | `display?` (the main display by default), `format?` (`image` by default, or `path`) | A PNG of the wallpaper on that display, at most 960 pixels wide, as image content (with `path`: saved to a temporary file whose path is returned). `source` says what it is: `loading_snapshot` (the scene's own frame, which the app captures for its loading screen), `video_frame`, or `preview` (the wallpaper's preview image, when there is no frame yet). |

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
- **The client says the server failed to start**: check the path in its configuration. Copy it
  again with **Copy Configuration For**; it must be absolute (clients don't expand `~`).
- **Paths with spaces.** The path contains spaces (`Application Support`). In JSON, TOML and YAML
  it is one quoted string, as the snippets write it: don't split it into `args`. In a shell, quote
  it. Run it by hand to see its messages on stderr:
  `"$HOME/Library/Application Support/Open Wallpaper Engine/Plugins/MCP/owe-mcp" --help`.
- **The app isn't running.** The first tool call starts it in the background and waits up to 30
  seconds. A client that times out sooner can simply try again once the app is up.
- **The plugin isn't installed** (or was removed): `owe-mcp` is gone from Application Support, so
  the client can't start it, or a running copy answers *"its MCP Server plugin isn't installed"*.
  Install it again in Settings › Plugins and copy the configuration again.
- **"MCP clients can't connect"** under the plugin in Settings: the socket couldn't be opened. The
  message says why; the app's log has the details:
  `/usr/bin/log show --last 10m --predicate 'process == "Open Wallpaper Engine"' | grep MCP`.
- **A development copy.** A copy launched isolated (`OWE_ISOLATED_STATE=<tag>`) keeps its own
  support folder, so the plugin it installs talks only to it. To point any `owe-mcp` at an isolated
  copy, run it with the same `OWE_ISOLATED_STATE`, or with `--socket <path>`.

## For developers

- `Packages/OWEControl` (`swift test --package-path Packages/OWEControl`): `OWEControlProtocol` is
  the wire format, the socket server and client and the plugin's layout; `OWEMCP` is the MCP
  server: JSON-RPC 2.0 over stdio (protocol versions 2025-06-18, 2025-03-26 and 2024-11-05,
  `MCPProtocolVersion`), the tools' schemas and the launcher; `MCPClientConfiguration` writes each
  client's snippet. `MCPCompatibilityTests` and `MCPClientConfigurationTests` keep them honest.
- `MCPServer/main.swift` is the `owe-mcp` executable (target OWEMCPServer), embedded in
  `Contents/Helpers`.
- `OpenWallpaperEngine/MCP/` is the app's side: the plugin (`MCPServerPlugin`), its Settings row,
  the request router (`ControlRequestRouter`) and the app model it drives (`AppControlModel`).
