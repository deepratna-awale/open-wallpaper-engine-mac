# iPhone & iPad Export

**iPhone & iPad Export** is the third tab of the Scene Editor (Live) (Wallpaper | Screen Saver |
iPhone & iPad Export | Android Export). It frames a scene wallpaper as an iPhone or iPad lock screen and exports
it as a Live Photo, which iOS and iPadOS 17 or later can set as a moving lock screen. Video and
web wallpapers show the tab disabled. How it is built: [`architecture.md`](architecture.md),
"Isolated edits" and "Live Photo export".

## Your desktop doesn't change

The tab runs its own private copy of the wallpaper, started from the wallpaper's properties and
Scene Editor (Live) edits when it opens. Changing user properties, hiding, moving, resizing,
recolouring or fading layers, blending and effects there changes only the preview and the
export. The desktop, its properties and the Wallpaper Editor's edits stay as they were.

## Framing

- **Device**: any of 33 iPhones and 30 iPads with Live Photo lock screens. Type a name, family,
  year or resolution to find one; the last choice is kept. The export has that device's exact
  pixels, in portrait.
- **Show Lock Screen Guide** draws the clock and date where the device shows them. For an iPad,
  **Preview in Landscape** shows the part iPadOS keeps when the iPad is turned.
- Drag the preview to move the picture; pinch or **Zoom** to zoom in.
- **Parallax Position**: for a scene that follows the pointer (camera parallax, a depth parallax
  effect, or a shader that reads the pointer), a small pad shaped like the screen sets where the
  pointer rests in the Live Photo. **Reset to Center** puts it back. Other scenes say they don't
  follow the pointer.

## The clip

A Live Photo moves for up to 3 seconds. The scene's first seconds are measured, and the clip moves
to its 1–3 s with the most motion, avoiding a cut in the middle of a burst; the **Motion**
timeline shows it and can be dragged (**Clip Start**, **Clip Length**). **Preview Clip** plays it
in the frame; **Show Live Wallpaper** goes back.

The still photo is the sharpest frame near the middle of the clip, at full resolution, and the
movie blends in from it and back into it, so the Live Photo never jumps. The movie is HEVC at a
bitrate for the device's resolution (**Quality**). The clock, day and date layers are left out,
since the lock screen draws its own, and the export is silent.

## Exporting

**Send with AirDrop** or **Save…** first show the Export Settings: everything above, plus the
layer adjustments and the user properties. The same panel is the tab's right-hand column and the
Export Settings toolbar button.

**Also Save to Photos Album** (off by default) also adds each export to an album in the Mac's
Photos library ("Open Wallpaper Engine" unless you name another; made when missing). With
iCloud Photos on, it reaches your iPhone and iPad. Photos access is asked for only when you turn
it on; if it's refused, the switch turns off and offers **Open Privacy Settings**. A save that
fails is reported without failing the export. Apps can't write iCloud Shared Albums, so this is a
regular album.

On the iPhone or iPad, open the photo, then Share › Use as Wallpaper, and turn Live Photo on.

MCP clients get `devices_list`, `export_settings_get` and `export_live_photo` ([`mcp.md`](mcp.md)).
