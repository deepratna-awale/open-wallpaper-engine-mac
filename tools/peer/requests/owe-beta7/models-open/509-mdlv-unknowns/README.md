# Capture request 509: the `.mdl` fields OWE reads but doesn't understand (models-plan §1–§5, §5.9)

OWE parses every `.mdl` field WE's reader reads (`MDLReader`, `Scripts/mdl-reference.py`). Several fields have no known writer and no known consumer, and are tagged **[?]** or **[I]** in `docs/models-plan.md`. Only WE's editor writes them, so most of this request is **editor work**:
1. make the field appear in an `.mdl`;
2. send the file (we parse it here);
3. take a still or a clip where the field might change what WE draws.

## Every MDL-format [?] / [I] in models-plan §1–§5, and which this request covers

| § | Field | Tag | Here? |
|---|---|---|---|
| 1.2 | MDLV ≥ 21, first optional blob: `u32`, then 12·vertexCount bytes ("a second position set") | [I] | **A** |
| 1.2 | MDLV ≥ 21, second optional blob: 16 bytes per record ("zero in the library") | [?] | **B**. It isn't zero (below) |
| 1.2 | MDLV ≥ 23 groups `{u64 id; name; u32 flags; listA; listB}` | [?] | **B** |
| 1.2 | mesh flag 0x2 and its u32 | — | no: settled (texture channels, §5.17) |
| 1.3 | bone flag 0x1 (520 of 568 bones) | [?] | **D** |
| 1.3 | MDLS ≥ 2 per-bone `u32` arrays (S ≥ 2 and S ≥ 3) | [?] | **B** |
| 1.3 | MDLS ≥ 2 links, constraints, ID maps, IK sets | [?] | no. They are empty in every file, the editor's own puppets included: IK and physics go into the bone's props JSON (§2.14). There is no known editor action that writes them |
| 1.3 | MDLS per-bone `{vec3, mat4}` block | — | no: collision capsules (§2.12) |
| 1.3 | world bind = local · world(parent) | [I] | no: consistent with every capture so far |
| 1.5 | `MDLE0002` reference pose, its consumer | [I] | **C** |
| 1.4 / 2.8 / 5.3 / 5.28 | the clip record's frame offset (MDLA flags & 1) | [?] | **E** |
| 5.27 | mesh flag 0x4 `SKINNING_ALPHA`, `g_BonesAlpha` and the MDLA scalar tracks | [?] | **F** |
| 5.23 | bind pose taken apart as TRS | [I] | no: needs a sheared bind, which no library file has |

## What we read on this side first (so you know what to look for)

- **A:** Only one library rig has the first blob: Workshop 3803167460's 65-bone puppet, MDLV0023, with `u32` = 1 and 17333 × 12 bytes. Its values are **the vertices' texture-layout positions**, `(uv − ½) · imageSize` with v flipped (vertex 100: uv (0.565, 0.101) → (250, 1198)). Its `a_Position` holds the **rearranged** figure (vertex 100 at (204.7, 321.0)). That is also the one rig whose bind pose isn't its texture's layout (§2.13), so we guess the editor writes this blob when mesh parts are moved away from where they are in the image.
- **B:** The 16-byte records are **four `u32`, not floats**: (bone, 0, firstIndex, indexCount). They split the index buffer into one range per bone, and the counts add up to the index count (the rope: (0, 0, 0, 1215), (1, 0, 1215, 1260), 2475 indices). There is one record per bone, in an order that the MDLS per-bone array A repeats (Samurai: 15, 4, 5, 6, …). Array B steps by 100 (0, 100, 200, …; the Samurai's starts 900, 1000, 1100, 1200, 100…), like a **draw order or depth per bone**. Every editor puppet has them; FBX imports don't. The groups list is empty in every file.
- **D:** Flag 0x1 is off only on non-bone FBX nodes: `RootNode`, the object node and the armature node (28 bones in the library, none weighted). It is on for every armature bone, including 35 unweighted leaves, and on every puppet bone.

## Setup

WE 2.8.0.42, as for owe-beta3/models-open, with stills of the running wallpaper on monitor 2.

Files here:
- `bars.png` (512×256): a red bar (x 40–219) and a blue bar (x 292–471), both at y 98–157, each with a black tick at its outer end. It is made by `make_bars.py`.
- `make_bone_flags_fbx.py`: a Blender script, run as `make_rootmotion_fbx.py` was for MG4.

**The base puppet "bars"** is used by A, B, C and F:
1. Create a 2D scene at 1920×1080. Import `bars.png` as an image layer at (960, 540), scale 1, no effects. Save it as project `p509_bars`.
2. **Puppet Warp:** generate the mesh with the defaults. Add the bone **`red`** at (130, 128) in the image, and a child bone **`blue`** with its head at (256, 128), pointing right. Skin the red bar to `red` and the blue bar to `blue`, by painting or by automatic weights.
3. Save, and keep a copy of `models/*.mdl` as **`base.mdl`**.

After each step below, save, then copy the `.mdl` (and the puppet's `.json` if the editor wrote one) under the name given. **Change only that one thing from `base`**, so the files differ only in the field asked about.

## A: the second position set

1. On `base`, find the Puppet Warp tool that **moves mesh vertices or parts without moving the texture** (for example a mesh-edit mode, "move parts", or a transform of the selected triangles). Move the whole blue bar's mesh 150 px up, so the image's pixels go with it. Save **`a_moved.mdl`** and write down the tool's name.
2. If there is no such tool, write down which mesh tools exist, and whether any of them writes this blob (`MDLV` ≥ 21, after the index blob: a `u8` 1, a `u32`, then a 12·vertexCount blob). We check every file here.
3. **Stills of `a_moved`** as the running wallpaper, 3 s after load:
   - `mo2_509a_moved.png`;
   - the same layer with WE's **Tint** effect at its defaults added: `mo2_509a_moved_tint.png`;
   - the base for comparison: `mo2_509a_base.png`.

**We need to know:**
- the editor action that writes the blob;
- what the `u32` is (try it twice, e.g. moving once and moving twice, to see if it changes);
- **where the blue bar is drawn**, with and without an effect: at its moved place, or at its image place.

OWE now decides from the vertex positions whether a rig's bind pose is its texture layout (`ScenePuppetPlan.bindPoseIsTextureLayout`, a heuristic). If the blob is what marks such a rig, OWE can test for it instead, and use its positions where WE runs the effects in texture space.

## B: per-bone index ranges, the per-bone arrays and the groups

1. On `base`, find the Puppet Warp setting that sets **which part draws on top**: a bone's draw order, depth, layer or sort, or a "bring forward / send back" action. Make the **blue** part draw **under** the red one. Save **`b_order.mdl`** and write down the setting's name and values.
2. **A clip:** on `base`, add an animation where **`blue` turns 0° → 180° → 0°** about its head at frames 0/30/60 (30 fps, loop). That swings the blue bar over the red one. Save it as **`b_clip.mdl`**, then a second copy with the order from step 1, **`b_clip_order.mdl`**.
3. If the editor can **key the draw order inside the clip**, key blue under red at frame 0 and over red at frame 30. Save **`b_clip_keyed_order.mdl`**.
4. **Groups:** look for any panel that makes **named sets of bones or mesh parts**, such as bone groups, layers, selections or folders. Make one named `grpA` holding `blue`, save **`b_group.mdl`**, and write down where it is.
5. **Clips** of `b_clip` and `b_clip_order` (and `b_clip_keyed_order` if it exists) as the running wallpaper: 3 s at 30 fps, `mo2_509b_<name>.mp4`, plus a still at the overlap (around 1 s), `mo2_509b_<name>_t1.png`.

**We need to know:**
- which part WE draws on top when they overlap, for each file;
- which editor setting changes the records (bone, 0, firstIndex, indexCount), array A and array B, and what array B's numbers are (we expect 0/100 → swapped);
- whether the order can be animated;
- what writes a group.

OWE draws a puppet's triangles in index order, so a reordered rig would come out wrong. With the answers, OWE sorts the per-bone ranges as WE does.

## C: the reference pose (`MDLE0002`)

1. On `base`, find the setting that stores a **reference** or **rest pose** separate from the bind pose, for example "set as reference pose", a pose mode, or "reset to reference". Turn `blue` by 90° and store that as the reference pose. Leave the clip empty. Save **`c_refpose.mdl`** and write down the action.
2. **Stills** 3 s after load:
   - `c_refpose` with no animation layer, `mo2_509c_refpose.png`;
   - the same file with `b_clip`'s clip added (or `b_clip` with the reference pose stored), playing: `mo2_509c_refpose_clip_t1.png` at 1 s.

**We need to know:**
- which action writes `MDLE0002`;
- whether a wallpaper **without** an animation layer shows the bind pose or the reference pose.

OWE ignores `MDLE` today. If the reference pose shows, OWE poses a rig without layers with it.

## D: bone flag 0x1

1. Run `blender -b -P make_bone_flags_fbx.py -- bone_flags.fbx`. The armature `Rig` under an empty `Pivot` has `root → mid → tip`, plus `loose`, which nothing is weighted to. The box is weighted to `root` and `mid`.
2. Import it through Create Wallpaper as MG4 did, and send the written **`d_bone_flags.mdl`** and the model's `.json`.
3. Also write down the Model Editor's bone list as shown, the names in order.

Nothing needs capturing. We read the flags of `RootNode`, `Pivot`, `Rig`, `root`, `mid`, `tip` and `loose` here, which settles whether 0x1 means "an armature bone" or "a bone with weights". If any node with flag 0 has a track in the clip, also take a 3 s clip of the model playing (`mo2_509d_bone_flags.mp4`, camera as in MG4's `build_playback.py`), so we see whether WE animates a flag-0 node.

## E: the clip record's frame offset

Use MG4's `mg4_rootmotion_i` project (the root-motion box, clip "Scene", 30 frames: one second of motion).
1. Model Editor → Animation → **Add Clip**:
   - Start 0, End 30, **Frame offset 10**, Match loop on;
   - Motion root bone **None**.
   
   Save **`e_offset10.mdl`**. Make a second copy with **Frame offset 0**, `e_offset0.mdl`, otherwise the same.
2. Play each as in MG4's `build_playback.py` (an animation layer on the new clip's id; the id is in the model's `.json`, `editor.clips[].id`): a 3 s clip at 30 fps, `mo2_509e_offset10.mp4` and `mo2_509e_offset0.mp4`, plus stills at 0.5 s.

**We need to know:**
- that the offset lands in the record's third `u32` (we read it as `u0` start, `u1` end, `u2` frame offset, `u3` root bone);
- what it does when played: a shift of 10 frames (1/3 s) in where the loop starts, a delay, or nothing.

OWE reads it but doesn't use it (`MDLAnimation.Reference.frameOffset`).

## F: per-bone alpha (`SKINNING_ALPHA`, mesh flag 0x4) and the scalar tracks

1. On `b_clip`, look for a **per-bone opacity, alpha or visibility** that can be keyed in the clip. Key `blue` at opacity 1 at frame 0 and 0 at frame 30. Save **`f_alpha.mdl`**.
2. If the editor has it, take a 3 s clip, `mo2_509f_alpha.mp4`, plus a still at 1 s.

**We need to know:**
- whether an editor action sets mesh flag 0x4 or writes MDLA scalar tracks (we check the file);
- whether the blue bar fades in WE.

`g_BonesAlpha`'s source wasn't traced (§5.27). OWE would feed it from whichever track the file shows.

## Send back

Put everything in this folder, under `response/`:
- every `.mdl` named above, with the puppet or model `.json` next to it;
- the stills and clips;
- a `notes.txt` with each editor setting's name and where it is, and "not found" for any step that has nothing to set.

The project folders of the stills are welcome, as before (`.tex` files can be left out).
