# §5.5 getCameraTransforms with a camera path: **returns the static scene camera**

## Setup
- **Scene:** a loose copy of Workshop 3159348391 (PaRappa dojo, rated Everyone). It has 13 camera paths in `scripts/camera_paths_203.json`.
- **Logger:** an extra tiny image layer whose origin script logs `thisScene.getCameraTransforms()` every 0.5 s.
- **Run:** in the editor's Run Preview.

## Result
- **Log (`campath_log.txt`):** from t = 0.25 to 10 s, every line reads `eye=-0.171,1.759,3.836 center=-0.144,1.683,2.839 up=0,1,0`. That is exactly the scene.json `camera`.
- **View:** the frames at about 2, 6 and 10 s (`campath_preview_strip.png`) show the camera path clearly moving it: wide shot, then close-up, then another angle.
- **Conclusion:** `getCameraTransforms()` reports the static default camera, **not** the path-driven pose.
