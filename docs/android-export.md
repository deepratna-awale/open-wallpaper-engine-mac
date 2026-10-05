# Export for Android

**Export for Android…** writes Wallpaper Engine's `.mpkg` packages for its Android app, as
Wallpaper Engine's own "Export .mpkg" does. It is in the library's context menu (for one
wallpaper or a whole selection) and in the Details panel. Copy the packages to the phone or
tablet, or send them over Wi-Fi (below), and import them in the Wallpaper Engine app.

The packages have the layout, files and JSON of Wallpaper Engine 2.8.42's own exports. How they
are built: [`architecture.md`](architecture.md), "Android export".

## What can be exported

| Type | Export |
|---|---|
| Scene | **Dynamic** or **Pre-Rendered** (below) |
| Video | The video file as it is, with its preview. Videos over 4 GB can't be packed. |
| Web, application | Skipped: "Wallpaper type not supported on Android devices", as in Wallpaper Engine. |

A selection lists what it will skip and why before it starts.

## Modes for scenes

The sheet is Wallpaper Engine's dialog: pick the performance rating that suits the device, per
wallpaper.

- **High Quality** (Dynamic): the scene itself, rendered live on the device. Everything a scene
  does keeps working there: animation, particles, effects, scripts, clocks and dates, audio
  response, touch and its user properties. Textures are converted to the compressed format
  phones read (ETC2), at full size. Shaders get the same small GLSL ES edits Wallpaper Engine
  makes.
- **Balanced** (Dynamic): as High Quality, with the textures at half their resolution. This is
  the default, both in the sheet and in the Scene Editor (Live)'s Android Export tab.
- **High Performance** (Pre-Rendered): the scene recorded as a seamless 30-second H.264 video,
  which any device plays cheaply. As Wallpaper Engine warns, the scene's dynamic parts are
  baked in: clocks and dates show the time of the recording, and touch, audio response and
  properties no longer change anything.

**Show advanced settings** adds, for Dynamic: **Pixel art optimization** (textures stay
full-size, uncompressed and sharp-edged) and **Texture Reduction** (full, half or a quarter of
the resolution). For Pre-Rendered:

- **Video Cropping**: **Fit to phone screen** (a 9:16 portrait crop) or **Keep original aspect
  ratio**.
- **Video Preset**: Original, Full HD or 4K UHD.
- **FPS**: 24, 30 or 60.
- An alignment slider moves the portrait crop across the scene, over a live preview.

The preview runs a private copy of the wallpaper, so nothing on your desktop changes. The
pre-rendered video uses the wallpaper's current user properties.

## Batches

A selection exports as a queue, with overall and per-wallpaper progress, and can be cancelled.
Pre-rendered videos render one at a time (they use the GPU) while the other packages are written
beside them. Each package is named `<title>.mpkg`, made unique within the batch and the folder.
**Save to the Same Folder Each Time** skips the folder panel, for example to export straight
into an iCloud Drive folder.

## Send over Wi-Fi

After a batch export, or from **Send over Wi-Fi…** in the export sheet, a sheet lets the phone or
tablet download the packages from the Mac over the local network, with no cable:

1. Scan the QR code with the device, or type the link it shows. With several networks, pick the
   one the device is on.
2. The page lists every package with its preview, title, type and size. Tap **Download** for one,
   or **Download All** (Chrome asks once to allow several downloads).
3. Import each file in the Wallpaper Engine app, as with a copied file.

The sheet shows each file's progress and which devices have downloaded it. The link lasts 15
minutes; **Send Again** makes a new one. Without a local network address on the Mac, the sheet
explains why and offers **Save to Folder…** instead.

If the page doesn't open on the device:

- macOS may ask whether Open Wallpaper Engine may accept incoming network connections. Allow it.
- Some networks (guest networks, many public ones) keep devices from reaching each other
  ("client isolation" or "AP isolation"). Use a network that doesn't, or copy the files.
- If a download stops, keep the sheet open and tap **Download** again: it resumes.

### Security

- The server is started only while the sheet is open, for at most 15 minutes, and serves only
  that batch. Closing the sheet ends it.
- It listens on one private or link-local IPv4 address of the Mac's local network, and only
  answers devices on that network. VPN, public and cellular addresses are never used, and nothing
  is advertised on the network.
- The link carries a random 128-bit token. A wrong or expired token, and any other path, get the
  same "not found". Files are addressed by their place in the batch, never by a path, so nothing
  else on the Mac can be reached.
- Only downloads are accepted. Connections and requests per device are limited, and a device that
  keeps guessing paths is refused until the session ends.
- The page loads nothing from the internet.

MCP clients get `export_android` and `android_send_wifi` ([`mcp.md`](mcp.md)).
