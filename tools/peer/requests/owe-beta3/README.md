# OWE Beta 3 ground truth (models-plan §5): WE 2.8.0.42, Windows

## 1. `general.zoom` in a perspective scene (§5.1): **no effect**
- **Static test:** `owe_zoombox1/2`, a static box in a perspective scene.
  - Camera: eye 8,6,8 → 0,1,0, fov 50, `orthogonalprojection` null, no animation.
  - Rendered at `general.zoom` 1.0 and 2.0 and captured 4 s after load.
  - The frames are **pixel-identical** (max diff 0). The box covers x 927–992, y 527–596 in both.
  - Files: `zoom/zoombox1_t4.png`, `zoom/zoombox2_t4.png`, `zoom/zoombox_compare.png`.
- **Workshop scene:** 3657770939 (WE_Phys α_01), unpacked and loaded loose with zoom 1 / 2, in `zoom/zoom{1,2}_t{2,5,10}.png`.
  - Its physics bodies fall differently on every run, but the static background light is the same size and position at both zooms.
- **Answer:** zoom is neither FOV-like nor dolly-like in perspective. It is ignored. It only acts on orthographic projection.

## 2. Root motion with yaw only (§5.3)
Taken from the earlier MG4 run (`../../models_gt/mg4/`, clips `mg4p_root_{rotY,all_on,all_off}.mp4`).
- **Storage:** the flags byte is at 0x17D4: base 0x04, posX 0x08, posY 0x10, posZ 0x20, rotY 0x80, all = 0xBC. Your 0x8401 / 0xbc01 are that byte next to the 0x01 that precedes it.
- **Strip:** `rootmotion_strips.png` shows frames at 4 fps from t = 2 s. Rows: all off / yaw only / all on.

**Yaw only (0x80)**
- The box **keeps a constant yaw**: the root bone's yaw is removed from the pose.
- Position and the other rotations still play.
- The extracted yaw is **not applied to the object** either: it doesn't turn.

**All on (0xBC)**
- The root's translation and yaw are stripped from the pose, and the box stays near the origin.
- No motion is accumulated into the object transform across loops. Every variant returns to the same point each second (MG4 README table).

**Conclusion:** in wallpaper playback, WE extracts root motion from the pose but never applies it to the object, for yaw as well as position.

## 3. Instancing: **none**
- **Projects:** `owe_inst1` and `owe_inst10`, 1 vs 10 copies of the same .mdl with the same material.
- **Method:** captured with RenderDoc 1.46 (`../rd_grab/rd_draws.py`); reports are in `instancing/rd_draws_inst{1,10}.txt`.
- **1 copy:** 1 `DrawIndexed` (36 indices) plus 4 fullscreen `Draw(3)` post passes.
- **10 copies:** **10 separate `DrawIndexed`** calls (36 indices each, instance count 0, i.e. non-instanced), then the same 4 post passes.
- WE issues one draw per model object.

## 4. MDLV mesh flag 0x2 / bone flag 0x1 (§5.9): **not found in installed items**
- **Search:** none of the installed Workshop items contain `BLENDROWCOUNT`, `g_BlendMap` or `PRELIGHTINGDUALVERTEX`.
- **Shaders:** in WE's own `assets/shaders`, those names appear only in `genericimage4.vert` and `puppettexturechannels.vert`.
- **Likely source:** that points to the **Puppet Warp → Texture Channels** option (an optional step in the puppet editor) as what produces the blend-map path.
- **Not done yet:** a test puppet with Texture Channels enabled could be built in the editor to confirm the flag. It needs the editor driven by hand.
