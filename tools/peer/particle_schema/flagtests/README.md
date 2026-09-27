# Particle flag render tests (WE 2.8.0.42), built by `../build_flagtests.py`

Projects are in `projects/`, captures in `captures/`, and the overview in `contact_flagtests.png`.

## D) Child `flags` 0 vs 2 (`pf_childflags_0/2`)
- Setup: a parent sphererandom at x-400; a static child at x+800 whose emitter is periodic (flags 4, 0.5 s on / 1 s delay); the layer's `instanceoverride` has `colorn` "1 0 0".
- The **parent is red in both.**
- **Q1:** the **child is red in both** (mean colour 133,12,14 vs 134,12,14). So child flags bit 2 does **not** keep the child's own colours: the instance colour override reaches the child either way.
- **Q2:** the child emits in periodic bursts about every 1.5 s in both captures. Coverage cycles 0 ? 3% ? 0 identically. Bit 2 shows no visible effect on periodic restart in this setup.

## E) Remapvalue clamp (`pf_remapclamp_*`, `pf_remapsanity_*`)
- Setup: static particles with base size 60 and lifetime 4 s; remapvalue input `lifetimefraction` ? output `size`, operation `multiply`, input 0–0.5 ? output 0–1.
- Sanity check: the operator works. Output 1–5 makes particles about 6× larger in area.
- Median particle area relative to no remap:

| flags | area ratio |
|---|---|
| absent | 0.54 |
| 1 | 0.52 |
| 0 | 0.54 |
| 2 | 0.57 |

- Expected area ratio (area ? size², averaged over life): about **0.67 if clamped** (grows to 1× at half life, then holds); about **1.33 if unclamped** (keeps growing to 2×).
- **Every variant is about 0.54, which is consistent with clamping, and identical regardless of flags.** The runtime clamps the remap input no matter what the `flags` value is, or the clamp is controlled by a bit other than 1 or 2.
