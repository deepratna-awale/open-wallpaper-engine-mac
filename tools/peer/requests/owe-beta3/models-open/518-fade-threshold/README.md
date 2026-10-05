# §5.518: model fade threshold (editor's own opacity control)

WE 2.8.42, perspective scene with the box model, running wallpaper.

## Which key the editor writes
- **Where the control is:** model layer → Materials → (material) → **Shader → Opacity**. The model layer itself has no alpha control.
- **What it writes:** setting Opacity to 0.5 and saving writes **lowercase `"alpha": 0.5`** into the material pass's `constantshadervalues`, next to the existing `"Alpha": 1`:
  ```
  "constantshadervalues": {"Alpha": 1, "Color": "1 1 1", "alpha": 0.5}
  ```
- **Other pass keys** the editor added: `"alphawriting": "default"`, `"blending": "translucent"`, `cullmode`/`depthtest`/`depthwrite` set to `normal`/`enabled`/`enabled`.
- **Why round 1 saw nothing:** it set capital `"Alpha"` and the object-level `"alpha"`. Neither affects generic4; **lowercase `alpha` is the live uniform**.

## Threshold (`project_mo2_518e_alpha_0p5`; the series varies only `constantshadervalues.alpha`)

| alpha | box max delta vs alpha=0 frame (grey levels) | box mean |
|---|---|---|
| 1 | 102 | 103.2 |
| 0.5 | 51 | 140.6 |
| 0.1 | 10 | 170.7 |
| 0.01 | 1 | 177.3 |
| 0.001 | 0 | 178.0 |
| 0 | 0 | 178.0 (background) |

- **Linear blend:** the coverage scales linearly with alpha (102·a), down to the 8-bit quantisation floor.
- **No cut-off: the draw is still issued at alpha 0.001 and at alpha 0.** RenderDoc shows 1 `DrawIndexed(36)` for the model in each (`renderdoc/rd_draws_report.txt`).
- **Answer:** there is **no fade threshold**. WE keeps drawing translucent models at any alpha, including 0; it just blends to invisible.
