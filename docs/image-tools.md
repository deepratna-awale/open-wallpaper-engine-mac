# Image tools

The Wallpaper Editor's image preparation tools, as Wallpaper Engine's editor has them
([Image Preparation](https://docs.wallpaperengine.io/en/scene/image-preparation/foreground-separation.html),
[Real-Time Lighting](https://docs.wallpaperengine.io/en/scene/lighting/introduction.html)). Their
algorithms follow WE's editor (`wallpaperui.exe`, which runs OpenCV 4.4 on the picture), read from
its UI (`ui/dist/scripts/scripts.js`, `EditorCharacterSeparationModalCtrl`) and its binary. The
pieces live in `Packages/OWEEditor`: the image work in `OWESceneEditing/ImageTools`
(`ImagePlane`, `DistanceTransform`, `Inpainting`), the windows in `OWEEditor/ImageTools`.
Everything runs on the Mac, off the main thread, with no downloads.

## Normal Map Generation

An image layer's inspector has a **Normal Map** section: the layer's normal map (its material's
`g_Texture1`, WE's genericimage shaders' `NORMALMAP`), **Generate…** and **Remove**.
Generate opens WE's Normal Map Generation window with WE's options and defaults:

| Option | Range | Default |
|---|---|---|
| Shape › Blur | 1–63, odd | 63 |
| Shape › Depth | 0–1 | 1 |
| Shape › Exponent | 1–8 | 4 |
| Shape › Threshold | 0–1 | 1 |
| Details › Blur | 1–255, odd | 21 |
| Details › Depth | 0–1 | 1 |
| Details › Invert | | off |

WE's hidden "Filter size" (the Sobel kernel) stays at its default, 13. The options are remembered
per material while the window is open, as WE's editor does.

How the map is made (`NormalMapGenerator`, WE's `performGenerateNormalMap`):

- **Shape**, worked out with the long side at 512 pixels: the picture's alpha above 250, bordered
  with `64 / min(scale, 1)` transparent pixels, gives an inside distance (cut at Threshold of its
  range, normalised, rounded by Exponent as `1 − (1 − d)^e`) and an outside distance (the same,
  scaled by the ratio of the two ranges) whose difference, normalised and blurred by Blur, is the
  height. Its 13-tap Sobel gradients, normalised to −1…1, become normals with Depth. An opaque
  picture has a flat shape.
- **Details**, at the picture's size: the transparent part filled from the opaque one (Telea), the
  mean of red, green and blue normalised, blurred by Details › Blur; its gradients, divided by
  their largest magnitude, become normals with Details › Depth (Invert flips them), faded out
  towards the outline (the inside distance clamped to 1–7 % of its range, blurred).
- The details are turned onto the shape (the rotation taking straight up onto the shape's normal),
  kept facing forward and written as `n × 0.5 + 0.5` in red, green and blue (x right, y up), with
  the picture's alpha.

OK writes the map as WE imports one (`rg88n`, the image importer's `EditorTEXEncoder.normalMap`)
named after the picture's texture with `_normal`, as WE does (`<texture>_normal`, plus the
content hash the editor's files carry), and makes it the layer's normal map in one undo step. The
layer's material and model are copied into the edits' files with the map as `g_Texture1`, and the
layer's `image` names the copy, so the wallpaper's files never change. WE draws a normal map only
with Lighting or Reflection on (its Generate button shows after one is turned on), so when neither
is, the copy turns Lighting on (`LIGHTING: 1`).
