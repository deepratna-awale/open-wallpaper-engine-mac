# §5.515-attachment-depth

WE 2.8.42, captured as the running wallpaper on monitor 2. Projects are built by `../build_round2.py`. Large binaries (.mdl, .tex) are omitted; they come from the base projects in the repo.

**Setup:** the rope puppet with bones `root` and `tail`. Depth 1 is an image with `parent` = the puppet and `"attachment": "tail"`. Depths 2, 3 and 4 are plain children, each parented to the previous one, offset 1100 local units and scale 1.

**Result: all four render,** as a chain of 4 gradient tiles starting at the tail joint. So the attachment resolves, and nesting under it continues to at least depth 4; no cut-off past 3 was seen.
- **Caveat:** only depth 1 uses `attachment`. The others are ordinary parenting under the attached object.
