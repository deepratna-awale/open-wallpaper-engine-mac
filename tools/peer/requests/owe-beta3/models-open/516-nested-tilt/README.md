# §5.51.6-nested-tilt

WE 2.8.0.42. Projects come from `../build_variants.py`, shot on monitor 2 by `../shoot_all.ps1`. The Windows taskbar covers the bottom 48 px.

An ORTHO scene.

**Setup**

- **Parent:** the image at (700,540) with `angles "30 0 0"`.
- **Child:** `parent` set to the parent's id, `origin "500 0 200"`, `angles "0 30 0"`, scale 0.5.
- **Control (flat):** the same objects with no angles and z 0.

**Result:** the x tilt is applied in ortho.

- The parent is foreshortened vertically, to roughly 870 x 160 px on screen.
- The child is rotated nearly edge-on, a thin sliver near the parent's right edge.
- So tilts compose through the parent chain even in an orthographic scene.
