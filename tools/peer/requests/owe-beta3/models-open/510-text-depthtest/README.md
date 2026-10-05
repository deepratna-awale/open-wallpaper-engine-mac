# §5.510-text-depthtest

WE 2.8.42, captured as the running wallpaper on monitor 2. Projects are built by `../build_round2.py`. Large binaries (.mdl, .tex) are omitted; they come from the base projects in the repo.

A perspective scene (camera eye 3,2,3 looking at 0,0.5,0) with the box model, plus a text object ("DEPTH TEST", font `systemfont_consolas`) placed behind the box at origin -1.5 0.6 -1.5, angled 45°. The object-level key is `"depthtest": "enabled"` vs `"disabled"`, with `depthwrite` disabled in both.

- **enabled:** the box **occludes** the part of the text behind it.
- **disabled:** the text is drawn **over** the box.

So the text object's own `depthtest` key is honoured, and it defaults to occlusion when enabled.
