# §5.51.3-no-origin

WE 2.8.0.42. Projects come from `../build_variants.py`, shot on monitor 2 by `../shoot_all.ps1`. The Windows taskbar covers the bottom 48 px.

An ORTHO 1920x1080 scene with a 1024 px image at scale 0.85.

- **Control:** `origin "960 540 0"`. The image spans x 525-1394, y 105-974.
- **No origin:** the image is **centred on scene (0,0), the bottom-left corner**. Only its upper-right quarter shows: x 0-434, y 645-1080.
- **Conclusion:** the default origin is 0 0 0 in scene units, with y up.
