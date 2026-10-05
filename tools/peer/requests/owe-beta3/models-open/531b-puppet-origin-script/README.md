# §5.531b-puppet-origin-script

WE 2.8.42, captured as the running wallpaper on monitor 2. The project is built by `../build_round2.py`. Large binaries (.mdl, .tex) are omitted; they come from the base projects in the repo.

**Setup:** the rope puppet (bone-physics A) with an `origin` script setting `x = 760 + min(t,4)*100`, running **as the wallpaper**, not the editor preview.

**Result: it moves.** The bar's x extent is 734-902 at t~1 s, 934-1102 at t~3 s, and 1047-1206 at t~5.5 s, following the script with about 0.3-0.5 s of load offset. So a script-written origin on a puppet layer is applied in wallpaper mode.
