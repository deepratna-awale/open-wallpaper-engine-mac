# Bone physics: WE 2.8.0.42 ground truth

## Setup
- **Project:** built in WE's editor (Puppet Warp) with the default mesh. `build_base.py` makes the base scene: `rope.png` at (960,540) in a 1920×1080 ortho scene.
- **Bones:**
  - `root` at image (48,16), local origin (0, 239.72);
  - `tail` at image (48,256), a child of root, local origin (0, −0.00006).
  - Weights are the editor's automatic weights: upper half on root, lower half on tail.
- **Script:** `attach_script.py` puts `origin-script.js` in as the rope layer's origin script. The editor shows it as bound (the blue cog).
- **WE:** version 2.8.0.42, FPS setting **60** (temporarily; restored afterwards together with the playback rules).

## Per variant (`A/`, `B/`)
- `project/`: project.json, scene.json (with the script), models/rope_puppet.json + **rope_puppet.mdl**, materials/.
- `mdl_constraint_json.txt`: the constraint JSON strings found in the compiled `.mdl`. The first is `root`, the second is `tail`.
- `bp_log_editor_preview.txt`: every `BP …` line from load to 9 s, one per frame, with no gaps.
  - Source: the editor's **Run Preview**. console.log from a running *wallpaper* never reaches WE's log.txt, and the editor's Log window is the only sink. That window keeps only about the last 77 lines, so `collect_editor_log.ps1` polls it every ~100 ms through UIA.
  - Editor frame time is about 0.017–0.018 s (~57 fps). There are occasional short frames of 1–5 ms.
- `clip_60fps_800x800.mp4`: the running **wallpaper** on monitor 1, recorded with ffmpeg `ddagrab` (Desktop Duplication) at 60 fps.
  - Crop: scene x 660–1460, y 140–940.
  - Timing: recording starts about 0.7 s before the openWallpaper command, and the first ~1 s still shows the previous wallpaper. The load is visible about 1.0 s into the clip.
  - Frame count: about 600 frames in 11 s, since ddagrab drops frames that don't change.
  - `capture_notes.txt` has the timestamps.
- An earlier gdigrab attempt only reached 15–25 fps and was replaced.

## Findings
### Compiled constraints (`tp`)
- `tail` compiles `"tp":"100.00000 0.00000 0.00000"` in both variants. It's a leaf bone, so the editor gives it a default 100-unit tip along bone +X, even with tip size 0.
- In **B**, `root` gets `"tp":"0 -239.7196 0"`, the vector to its child. In **A**, root's `tp` is `-nan(ind)`, apparently uninitialized, and root has `"tm":10`.
- **B** (preset `bouncyposition`): `r` false, `t` true, `ts` 300, `ti` 30, `tf` 20, `tm` 200, `ge` false. This matches the request.

### A (spring rotation, gravity on, tip mass 20)
**Rest angle is not zero.**
- From the first frame, gravity rotates the tail from identity to a steady `m0 = 0.8596, m1 = −0.5110`, about **−30.7°**, by 0.3 s.
- Reason: the tip points along +X (100 units) and gravity pulls it down. It reaches equilibrium against the spring (rs 200).
- In the clip, the lower half hangs bent to the lower left.

**Move right at 2.014 s** (logged x becomes 1160). The tail's world translation updates one frame later:

| t (s) | m0 | m1 |
|---|---|---|
| 2.031 | 0.5847 | −0.8113 |
| 2.049 | 0.3868 | −0.9222 |
| 2.067 | 0.3127 | −0.9498 |

- The minimum, about −71.8°, comes at about 3 frames.
- It then springs back: 0.43 at 2.107 s, and so on.

**Move back at 5.003 s:** at 5.020 s, m0 = 0.8919 (the opposite direction).

**Impulse at 6.001 s** (applied that frame; it shows the next frame):

| t (s) | angle |
|---|---|
| 6.019 | m0 0.9691, m1 +0.2465, i.e. +14.3° |
| 6.036 | +40° |
| 6.054 | +53° |
| 6.074 | peak about +57.3° |

- It then returns.
- The change from −30.7° over the first frame is **+45°**, which fits a 45° impulse (deg/s-scaled?). The swing overshoots to a peak about 88° from rest.

**Reset at 8.008 s:**
- At 8.026 s the tail is m0 0.9892 (−8.4°), not the rest angle. The reset snaps it to its *bind* pose (0°), and gravity then pulls it back down: −15.4° at 8.043 s, −21.1° at 8.060 s.

**Logged angle:** `getLocalBoneAngles('tail').z` logs **0.00000 on every frame**. The physics rotation isn't reflected in the local angles API.

### B (bouncy position)
**Move right at 2.009 s** (x = 1160). The tail's world x per frame:

| t (s) | x |
|---|---|
| 2.027 | 1033.61 (**lag 126 px ≈ 63 %**) |
| 2.045 | 1054.74 |
| 2.062 | 1076.37 |
| 2.079 | 1098.23 |
| 2.097 | 1119.40 |
| 2.114 | 1135.66 |

- Overshoot follows (see the log). The matrix rotation stays identity throughout.
- **Impulse:** the angular impulse at 6 s produces only a tiny translation, 960 → 959.9996.
- **Reset:** it at 8 s has nothing visible to undo.

### Wallpaper vs. editor
- The tail's reactions at about 2 s and 6 s (A) are visible in the wallpaper clips.
- The whole bar does **not** visibly shift 200 px in the wallpaper clip, although the log (editor) shows the layer's x at 1160 for 2–5 s. Please check this against your renderer. It may be a script/origin difference between the editor preview and the wallpaper.

## Scripts
`build_base.py`, `attach_script.py`, `set_config.py` (fps + playback rules), `capture_bp.ps1`, `collect_editor_log.ps1`.
