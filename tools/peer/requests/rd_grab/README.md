# RenderDoc frame grabs (used while the Windows session is locked)
Start WE under RenderDoc:

    renderdoccmd capture -d <WE dir> -c rd_grab/cap/we <WE dir>/wallpaper64.exe

- The command prints the target ID.
- Write `job.json` with `{ident, out, name, count, gap}`, then run `qrenderdoc --python rd_grab.py`.
- For each trigger, the script saves the swapchain image of that frame as a PNG.
- It skips captures that were already in `cap/` before it started. Without that check, the target connection replays old captures.
- The `.rdc` files are not committed.
