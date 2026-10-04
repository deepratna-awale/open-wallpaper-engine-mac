# Depth maps

The **Depth Map Generation** plugin makes a depth map of a layer or a whole scene on your Mac and
binds Wallpaper Engine's own **Depth Parallax** effect to it, so a flat picture shifts in depth
as the pointer moves, as in Wallpaper Engine. It works in the Scene Editor (Live) and in the
Wallpaper Editor.

## The plugin

Settings › Plugins › **Depth Map Generation** (off until installed) downloads Depth Anything V2
Small, Apple's Core ML release of it (Apache-2.0), from Apple's Hugging Face repository at a
pinned commit. Every file is checked against its pinned SHA-256 before it is kept, then the model
is prepared for the Mac. **Update** and **Remove** are in the same place; the About window credits
the model.

The model runs only on the Mac, and only while generating: it is loaded for a generation and
released five minutes after the last one. Nothing is loaded while wallpapers just play.

## Making a depth map

Select a layer (or nothing, for the whole scene) and open its **Depth Map** section. Without the
plugin, the section offers **Install Depth Map Generation**.

- **Generate** makes the depth map; **Preview Depth Map** shows it (near is white). **Smoothing**
  softens it.
- **Apply Depth Parallax** adds Wallpaper Engine's Depth Parallax effect bound to the map;
  **Strength** sets how far it moves, and **Remove Depth Parallax** takes it off.
- **Scene Depth Parallax** adds a fullscreen layer with the effect on top of the scene.

Where the depth comes from:

- An image layer: its own picture.
- Text, solid, composition and fullscreen layers, and animated images: the layer as it is drawn,
  at a still frame.
- A particle system: one frame of the scene so far, under a fullscreen layer added above the
  system.

The effect follows the pointer and the scene's parallax as in Wallpaper Engine. On a scene
without camera parallax, applying it turns parallax on, with the other layers' own movement at 0,
and removing the last depth parallax turns it off again.

## Where depth maps are kept

Every action is one undo step. Depth maps are kept with the wallpaper's edits, beside it, never in
its files, so both editors see the same ones. **Save as Local Wallpaper** writes them into the
copy as a normal effect and texture, which Wallpaper Engine reads as well.

MCP clients get `depth_generate` and `depth_apply` ([`mcp.md`](mcp.md)).
