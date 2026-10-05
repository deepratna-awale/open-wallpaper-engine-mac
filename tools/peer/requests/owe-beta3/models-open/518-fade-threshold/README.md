# §5.518-fade-threshold

WE 2.8.42, captured as the running wallpaper on monitor 2. Projects are built by `../build_round2.py`. Large binaries (.mdl, .tex) are omitted; they come from the base projects in the repo.

**Setup:** the box model with its material pass set to `"blending": "translucent"`, shader generic4.

**Two series:**
- object `"alpha"`: 1, 0.5, 0.1, 0.01, 0.001, 0;
- material `constantshadervalues.Alpha`: 0.5, 0.1, 0.01, 0.001, 0.

**Result: no visible change in any frame.** The dark-pixel count is identical across all 11 captures.
- Neither key fades a generic4 model in wallpaper mode with these hand-edited files, so **the fade threshold could not be measured**.
- **Next step:** the editor's own alpha control, or a timeline on the model's alpha, may write a different key.
