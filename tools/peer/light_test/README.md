# What makes a light affect an image layer (WE 2.8.0.42)

`build_lighttest.py` makes 8 generated 2D scenes:
- one 1024 checkerboard image with material shader `genericimage4` and combo `LIGHTING` 0 or 1;
- one `lpoint` light: origin 700 700 200, colour 1 0.3 0.3, intensity 5, radius 600;
- ambient 0.3, 1920×1080.

Captures are in `captures/`, the overview in `contact_lighttest.png`, and the load log in `captures.log`. All loaded with no errors. The `.tex` files are omitted; rebuild them by re-running the builder.

| Scene | LIGHTING | castshadow | general.lightconfig | Diff vs no-light control | Mean R−G (red tint) |
|---|---|---|---|---|---|
| control_nolight_lit1 | 1 | – | none | 0 | 0.9 |
| lit1_cs0_cfgP1 | 1 | false | `{"point":1}` | 4.78 | **6.6 (lit)** |
| lit1_cs1_cfgP1S1 | 1 | true | `{"point":1,"pointshadow":1}` | 4.78 | **6.6 (lit)** |
| lit1_cs1_cfgP1 | 1 | true | `{"point":1}` | 4.78 | **6.6 (lit)** |
| lit1_cs0_nocfg | 1 | false | missing | 0.00 | 0.9 (not lit) |
| lit1_cs1_nocfg | 1 | true | missing | 0.00 | 0.9 (not lit) |
| lit0_cs0_cfgP1 | 0 | false | `{"point":1}` | 63 (unlit, full bright) | 4.2 |
| lit0_cs1_cfgP1S1 | 0 | true | `{"point":1,"pointshadow":1}` | 63 (identical to the row above) | 4.2 |

## Conclusions
- **`general.lightconfig` gates lighting.** With LIGHTING=1, a light affects the image only when `lightconfig` counts that light type. Without `lightconfig`, the light is ignored.
- **`castshadow` has no effect on whether the surface is lit.** The three lit variants are pixel-identical in the mean.
- **LIGHTING=0 ignores lights entirely.** The image renders full-bright, while LIGHTING=1 with no lights is darkened to ambient.
- **The user's editor observation** ("lit only after Cast shadow") is most likely the editor rewriting `lightconfig` when the light's settings changed, not the shadow flag itself. This agrees with the Audit session's binary finding that `castshadow` is never used for surface lighting.
