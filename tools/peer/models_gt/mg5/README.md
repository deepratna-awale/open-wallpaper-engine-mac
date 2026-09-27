# MG5: puppet with a blend shape, made in the WE 2.8.0.42 editor

## The project (`project_mg5_puppet/`)
- **How it was built:** a transparent 512×768 shape, Puppet Warp geometry, a 3-bone skeleton, auto weights, the geometry locked, then **Edit Blend Shapes → + Add**.
- **The shape:** the editor labels it "Blend shape 31"; its **MDMP name is "Shape 31"**, id 31, with script access on.
- **Known offset:** vertex 196 moves by **+126.168 x**. Mask painting also gave 61 other vertices z offsets (0–8.7), which are invisible in 2D.
- **`models/checkerboard_puppet.mdl` sections:** `MDLV0023`, `MDLS0004` @0x4DBB, `MDLA0006` @0x4FC0, and **`MDMP0001` @0x69F1**. The MDMP header is `4D44 4D50 3030 3031 00 116C0000 01 00 1E F1 FC 42 3E 00 00 00 1F 00 ...`, followed by the name "Shape 31".
- **Per-vertex offsets:** the editor-side `models/checkerboard_puppet.json`, in `puppet.blendshapes[0].vertices`.

## Weights
- The editor's puppet animation timeline offers bones and poses only, **not blend-shape tracks**, so weight-over-time in a clip could not be authored.
- **Instead:** layer scripts called `thisLayer.setBlendShapeWeight(...)` with weights 0 / 0.25 / 0.5 / 1 every frame, and once only to test persistence. The shape was addressed by index 0, by id 31, and by `getBlendShapeIndex('Shape 31')`. The scripts are `build_mg5.py`, `build_dbg.py` and `build_named.py`; the stills are `mg5_*.png`.
- **No variant showed any deformation.** The tip stays at the undeformed edge (x = 588 on screen, versus about 621 expected at weight 1).
- **The scripts do run:** a debug script that altered `value` moved the layer.
- **Conclusion:** in 2.8.0.42, script-set weights on this editor-made blend shape had no visible effect. It may need an expression, or a shape named in the editor.
- **Unresolved:** whether weights are linear, and whether a script-set weight persists past its frame.
