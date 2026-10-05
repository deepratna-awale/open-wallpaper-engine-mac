# §5.520: camera layer origin script vs camera path (editor-made path). The path wins.

WE 2.8.42, ortho scene, running wallpaper.

## Setup
- **Camera layer:** "Probe Cam", with `visible: {value: true}`.
- **Path:** an editor-made path, Eye/Center x 0 → 400 → 0 over 60 frames.
- **Origin script:** `value.x = -400 * min(t/5, 1)`, written every frame.

## Results
**With the path** (`mo2_520_writeback_vs_script`), the image x extent is:

| t (s) | x extent |
|---|---|
| 0.3 | 419 |
| 0.7 | 187 |
| 1 | 125 |
| 1.5 | 308 |
| 2 | 525 (rest) |
| 3 | 125 |
| 4.5 | 343 |
| 6 | 525 |

- It follows **only the path**. The path also **repeats**: the queue mode "random" re-picks it after it ends.
- The origin script's drift (camera to -400 by 5 s) is **not visible at all**.

**Script only, no path** (`mo2_520b_script_only`, same camera and script, empty paths): the image moves right 80 / 234 / 400 px at 1 / 3 / 6 s, so the origin script **does** drive the camera when no path is active.

## Conclusion
While a path is playing, and between repeats, the path's eye/center fully override the camera layer's script-written origin. The script only takes effect when the camera layer has no path.
