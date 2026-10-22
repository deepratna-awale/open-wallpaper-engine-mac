# OWE capture requests for Beta 8 (548–551)

Commit each result under `tools/peer/requests/owe-beta8/models-open/<id>-<name>/`, as for Beta 7:
- stills, plus RenderDoc where an item asks for it;
- the files WE writes;
- a `notes.txt`.

Ground rules:
- Use WE 2.8.42.
- SFW content only.
- Restore the user's wallpaper and config afterwards.
- Don't use the editor's File › Quit: it closes all of WE.

## 548 clipping-genericimage4

1. Take the 532c clipping-mask rig and set the puppet layer's material to `genericimage4`. The editor default, `genericimage2`, ignores `CLIPPINGTARGET`.
2. Take stills:
   - mask on;
   - mask off;
   - `invert`;
   - `hidemaskgeometry`.
3. Add a nested mask: limb B clipped by limb A's mask, and limb C clipped by B's. Take a still.
4. Take a RenderDoc capture of one frame that shows the passes writing and reading the mask.

## 549 (optional) FBX import

Cover three cases:
- (a) An FBX whose bones are sibling chains, not a single chain.
- (b) A static mesh without a skin.
- (c) Add Event in the timeline while a clip is selected.

For each, save the `.mdl` and `.json` that WE writes. Also save screenshots of the import dialog and the event dialog.

## 550 texture-variants-2

Cover three cases:
- (a) An image with two variant groups.
- (b) An option with no condition.
- (c) A video option.

Save the `.tex` and `.tex-json` that WE writes. Take a still of each option selected at runtime.

## 551 mdle-reference-pose

1. Use a puppet whose Puppet Warp › Optional › Reference pose differs from the bind pose on some bones. Save the `.mdl`.
2. Take stills:
   - with no clip;
   - with a clip playing, at frame 0;
   - with a clip playing, at a mid frame.

This settles whether `MDLE` ever changes the drawn pose against the bind pose (docs/models-plan.md §5 point 9).
