# §5.522: camera path key edge cases (editor-made path)

WE 2.8.42, ortho scene, running wallpaper. The camera layer has `visible: {value: true}`; see 519b.

## What the editor UI allows
- **Two keys at one timestamp: not possible from the UI.** With Auto Keyframe on, setting Eye x at frame 30 to 400 and then again to -400 at frame 30 just **overwrites** the key. The saved json has a single key, (30, -400).
- **Per-key enable: none.** Keys only have `back.enabled` and `front.enabled` (bezier handles) and `lockangle`/`locklength`. There's no per-key on/off.
- **Path visibility:** each path has an eye toggle in the editor (Camera path header), saved as path-level `"visible"`.
- **Hand-written duplicates survive:** the editor loaded and kept my hand-written duplicate keys at frame 0 of another path (`[(0,0),(0,500),(150,0)]`).

## Runtime, with two keys at frame 30 (hand-inserted into the editor-written json: 400 first, then -400)
- **Image x extent:** 374 @0.3 s → 223 @0.6 s → 129 @0.9 s → 134 @1.1 s → 248 @1.4 s → 499 @1.8 s.
- **What plays:** the view goes to eye x≈+400 at frame 30 (the image shifted about 391 px left) and eases back to 0. **It never visits -400** (that would shift the image right).
- **Conclusion:** with duplicate timestamps, **the first key in the array is used**, and the second is effectively ignored. Interpolation into and out of frame 30 uses 400.

## Runtime, with the path's `visible: false`
- `mo2_522_path_hidden`: the same editor path with `"visible": false` on the path. **It doesn't play;** the view stays at rest for the whole capture.
- So the path-level `visible` is honoured as an on/off switch, and there's no other per-key disable.
