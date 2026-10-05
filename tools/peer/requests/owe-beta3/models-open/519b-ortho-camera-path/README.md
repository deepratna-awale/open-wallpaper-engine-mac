# §5.519b-ortho-camera-path

WE 2.8.42, captured as the running wallpaper on monitor 2. Projects are built by `../build_round2.py`. Large binaries (.mdl, .tex) are omitted; they come from the base projects in the repo.

**Setup:** a camera object (`"camera": "default"`, `"path": "scripts/camera_paths_950.json"`), with the path written by hand in the same format as Workshop 3159348391 (eye/center/up c0..c2 key tracks, fps 30, length 150, mode loop).

**Result: inconclusive.** The view does not move in the ortho scene, but it **also doesn't move in a perspective control** (`mo2_ctl_persp_campath`). So my hand-written path or camera object isn't being activated at all; it's not evidence about ortho.
- **Next step:** create a camera path in the editor. Its activation is probably an editor-assigned id or scene binding that I can't reproduce by hand.
