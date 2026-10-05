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

Every Android export (from the library's sheet, the Scene Editor's Android Export tab or MCP) is
also added to the **Android exports** list, with its title, type, size, the device it was framed
for, the date and a copy of the wallpaper's preview. The list is kept in
`~/Library/Application Support/Open Wallpaper Engine/Android Exports/`; entries whose file is gone
are dropped.

**Send over Wi-Fi…** (after an export, in the export sheets, or **File › Send Android Exports over
Wi-Fi…** and the menu bar icon's menu) opens a window with the whole list as a grid of previews.
Everything not downloaded yet starts selected. **Add .mpkg Files…** adds packages exported
earlier; each tile's menu has **Show in Finder** and **Remove from List**. **Start Sharing** lets
the phone or tablet download the selected packages from the Mac over the local network, with no
cable:

1. Scan the QR code with the device, or type the link it shows,
   `http://owe-fileshare.<mac>.local:<port>/<token>/`. With several networks, pick the one the
   device is on.
2. The page shows the import steps, **Download All**, and a card per package with its preview
   (animated when the wallpaper's is a GIF), title, type, device and size. Tap **Download** for
   one, or **Download All** (Chrome asks once to allow several downloads). Downloaded cards are
   marked.
3. Import each file in the Wallpaper Engine app, as with a copied file.

While it shares, each tile shows its progress and which devices downloaded it; selecting,
adding or removing packages updates the page within a few seconds. The link lasts until 15
minutes pass without the page or a download being opened; **Send Again** makes a new one.
Without a local network address on the Mac, the window explains why and offers **Save to
Folder…** instead.

If the page doesn't open on the device:

- The sheet also shows the link with the Mac's IP address. **Use IP address in QR code** puts it
  in the QR code, for devices that can't look up `.local` names.
- macOS may ask whether Open Wallpaper Engine may accept incoming network connections. Allow it.
- macOS may ask whether Open Wallpaper Engine may find devices on local networks. Allow it: until
  then the link and the QR code use the IP address, and they switch to the name once it's allowed.
- Some networks (guest networks, many public ones) keep devices from reaching each other
  ("client isolation" or "AP isolation"). Use a network that doesn't, or copy the files.
- If a download stops, keep the window open and tap **Download** again: it resumes.

### Security

- The server is started only while the window shares, until 15 minutes pass without a request,
  and serves only the selected packages. Closing the window ends it.
- It listens on one private or link-local IPv4 address of the Mac's local network, and only
  answers devices on that network. VPN, public and cellular addresses are never used.
- While it runs, the Mac advertises the name `owe-fileshare.<mac>.local` (`<mac>` is its
  LocalHostName, the Bonjour name, as a DNS label) for that address over multicast DNS, with an
  `_http._tcp` service on it and no TXT record, so the token is never advertised. When the name is
  taken (another Mac sharing), it uses `owe-fileshare-2.<mac>.local`, and so on. The name is
  withdrawn when the share stops.
- The link carries a random token: 10 base32 characters (50 bits), short enough to type and far
  beyond guessing in a 15-minute share that limits requests and refuses a device after 20 wrong
  paths. A wrong or expired token, and any other path, previews included, get the
  same "not found". Files are addressed by number, never by a path, so nothing else on the Mac
  can be reached.
- Only downloads are accepted. Connections and requests per device are limited, and a device that
  keeps guessing paths is refused until the session ends.
- The page loads nothing from the internet.
- It is plain HTTP on purpose: public certificate authorities don't issue certificates for
  `.local` names and a self-signed one shows a full-page browser warning, while the packages
  only cross the local network, for 15 minutes, behind the random token.

MCP clients get `export_android` and `android_send_wifi` ([`mcp.md`](mcp.md)).
