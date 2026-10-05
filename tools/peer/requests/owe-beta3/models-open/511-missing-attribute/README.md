# §5.511-missing-attribute

WE 2.8.42, captured as the running wallpaper on monitor 2. Projects are built by `../build_round2.py`. Large binaries (.mdl, .tex) are omitted; they come from the base projects in the repo.

The box material uses a custom shader, `shaders/probe_missing.vert/.frag`, that reads `attribute vec4 a_Color` and `attribute vec2 a_TexCoordC1`. The mesh has neither.

**Result: the model is not drawn at all.** Only the clear colour is visible.

**Log:** **nothing** is logged in log.txt; there's no "Shader expecting more vertex data" or any other message.
- **Not confirmed:** whether the failure is the missing attribute or the custom-shader compile itself. A control with a custom shader that reads only `a_Position` was not run.
