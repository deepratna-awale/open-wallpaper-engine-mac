# MG4 retry: root motion through WE's own model importer (WE 2.8.0.42)

## Source and import
- **Source model:** `rootmotion_box.fbx`, made with Blender 5.2.2 portable by `make_rootmotion_fbx.py`. It is a box skinned to one bone `root`; its 1 s clip at 30 fps moves `root` by (1,2,3)·t and turns it by (0.3,0.6,0.9)·t rad.
- **Import:** through the editor's Create Wallpaper flow. The resulting project is in `we_import_project/`.
- The import dialog itself only offers material and texture settings. **Root motion lives in the Model Editor (Configure Model) → Animation → Add Clip → Clip options**:
  - Name; Start frame / End frame (0 / 30); Frame offset; **Match loop** (default on);
  - **Motion root bone**: None / RootNode / Rig / root, i.e. every node of the FBX hierarchy;
  - once a bone is chosen, **Position X / Y / Z** and **Rotation X / Y / Z** toggles appear. **Rotation X and Rotation Z could not be switched on**; only Y (yaw) toggles.

## Where the flags are stored
The editor wrote one .mdl per setting (`mdl_variants/rootmotion_*.mdl`, all 9533 bytes, saved by `rootmotion_variants.ps1`). They differ from the root-bone-None version only here:
- **Clip flags byte at 0x17D4.** It sits inside the MDLA clip record, after the clip name `Scene (Clip 5)`, then fps (f32 30.0 = `00 00 f0 41`), frame count (u32 30), and a byte `01`.
  - The base value is `0x04`, most likely Match loop.
  - Position X `0x08`, Position Y `0x10`, Position Z `0x20`, Rotation Y `0x80`. All axes on gives `0xBC`.
  - Rotation X would presumably be `0x40` and Rotation Z `0x100`, but the editor won't set them.
- **Motion root bone:** a u32 at **0x2534**, `FF FF FF FF` (−1) for None and **2** for `root`. The editor's list order is RootNode = 0, Rig = 1, root = 2.
- **Animation ids:** the MDLA section lists the base animation "Scene" (**id 16**) and the clip "Scene (Clip 5)" (**id 26**, 0x1A). Scene animation layers must reference **26**; with the wrong id the model doesn't animate at all.
- **The audit's earlier synthetic flags** (0x800 to 0x10000 in its own layout) made WE refuse the model. The real bits are the ones above.

## Playback
Clips are in `clips/mg4p_<variant>.mp4`, 6 s each. The projects come from `build_playback.py`: model scale 0.01, camera eye 8,6,8 → 0,1,0, animation layer id 26. The table gives the dark box's centroid on the 960×540-scaled frame:

| Variant | Loop point (whole seconds) | Mid-cycle (0.5 s) |
|---|---|---|
| bone None | (926, 549) | (769, 506) |
| root, all off | (905, 542) | (743, 499) |
| posX | (920, 546) | (706, 479) |
| posY | (891, 558) | (561, 564) |
| posZ | (905, 613) | (772, 772) |
| rotX | (921, 547) | (764, 505), same as base because the toggle can't be set |
| rotY | (927, 549) | (785, 529) |
| rotZ | (938, 553) | (778, 508), same as base |
| all on | (857, 627) | (743, 940) |

- **No variant drifts across loops**: every one returns to about the same point each second. So **in wallpaper playback, WE does not accumulate root motion into the object transform.**
- The flags change the in-loop trajectory on the flagged axes. This is consistent with the root bone's motion on those axes being extracted and removed from the pose.
- Blender Z-up to FBX Y-up axis conversion applies to X/Y/Z.
