# §5.519b: camera path in an ORTHO scene (editor-made). It plays.

WE 2.8.42, captured as the running wallpaper.

## Setup
- **Scene:** an ortho 1920x1080 scene with the gradient image. Camera layer "Probe Cam" (`camera: default`).
- **Path:** a camera path added with the editor's own **Paths → + Add**, keyed with Auto Keyframe. Eye x and Center x are 0 @ frame 0, 400 @ 30, 0 @ 60. The editor wrote `mode: single`, `length: 60`, `fps: 30` and center z -5.

## Result
**The path plays in ortho.**
- The image's x extent goes 525–1394 (rest) → 369–1239 @0.5 s → 134–1003 @1 s, a **391 px shift** for eye x=400 (scene units ≈ px) → 249–1118 @1.5 s → back to rest by 2.5 s.
- The perspective control (`mo2_ctl_persp_campath`, box, eye x 3 → -3 → 3) also visibly orbits.

## What activates a path: `visible` on the camera layer
- **Without `visible`, nothing plays.** With the camera object missing `"visible"`, neither hand-written nor editor-made paths play, in ortho or perspective.
- **With it, they play.** After adding `"visible": {"value": true}` to the camera object, they do.
- **The editor drops the key.** It **removes `visible` from the camera object on save** (see the saved scene.json before the fix). Workshop scenes that work (e.g. 3159348391) all have an explicit `visible` (often a user-property binding).

## Hand-written vs editor-written paths
- **Hand-written:** my hand-written path (mode loop, length 150, ids 900/950) never played, even with `visible`. Adding `"magic": true` to the handles didn't help either.
- **Editor-written:** paths add `"magic": true` on the key handles and use `mode: single` and `wraploop: false`.
- **Undetermined:** the exact field that makes the hand-written one fail is not determined. Candidates are `mode: loop` with `wraploop: true`, the length, or the id. The editor-written one is in `project_*/scripts/camera_paths_950.json`.
