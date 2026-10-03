# §5.51.4-short-vectors

WE 2.8.0.42. Projects come from `../build_variants.py`, shot on monitor 2 by `../shoot_all.ps1`. The Windows taskbar covers the bottom 48 px.

**Image layer**

- `scale "0.5 0.5"` draws exactly like `"0.5 0.5 1"`: same bounds, x 704-1215, y 284-795.
- So a 2D image draws fine, and the missing z doesn't matter for it.

**3D model** (box, base scale 0.01)

- `scale "0.02 0.02"` is **pixel-identical to `"0.02 0.02 0"`**: the box is flattened to a sliver.
- `"0.02 0.02 0.02"` gives a normal cube.
- `"0.02 0.02 1"` stretches the box hugely along z.
- **Conclusion:** the **missing component is 0**. It is not 1, and not the default.
