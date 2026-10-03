# §5.51.8-fade

WE 2.8.0.42. Projects come from `../build_variants.py`, shot on monitor 2 by `../shoot_all.ps1`. The Windows taskbar covers the bottom 48 px.

An object-level `"alpha": x` on a model object, for x = 0.5, 0.05, 0.01, 0.004 and 0.

- **Result: no effect.** The box draws fully opaque in every case (darkest pixel 79 in all of them).
- So the scene.json `alpha` key is ignored for this model and material, which is opaque.
- **Inconclusive:** the fade threshold needs a translucent material, or a script-driven alpha. Not done yet.

## Script retry
- **Setup:** `alpha` driven by a script, stepping through 1, 0.5, 0.1, 0.05, 0.02, 0.01, 0.005, 0.002, 0.001 and 0, 1.5 s each.
- **Result:** the box looks **identical at every step** (darkest pixel 79, box mean 173.3 throughout).
- **Conclusion:** model alpha has no visible effect on this opaque (non-translucent) model material. The threshold needs a model whose material blends.
