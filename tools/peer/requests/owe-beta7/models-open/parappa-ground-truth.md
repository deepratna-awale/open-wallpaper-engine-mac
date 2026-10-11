# PaRappa the Rapper (workshop 3159348391): 3D model animation in WE 2.8.0.42

The wallpaper was already installed; nothing was subscribed or downloaded. It was played on monitor 2 with WE started under RenderDoc, and the frames were taken from the swapchain (`parappa/`, `rd_timed_report.txt`). Stills are at 4/4.5/5, 12/12.5/13 and 20/20.5/21 s after load, and `parappa/sheet.png` puts all nine together.

## 1. What WE plays

- **Every character animates.** PaRappa and Master Onion do karate moves; PJ, Sunny, Boxy Boy and Joe Chin loop their idle.
  - t = 4–5 s: both sway in an idle and Wait pose, and the camera cuts at 5 s.
  - t = 12.5 s: PaRappa **kicks** (a leg high, a ○ particle).
  - t = 13 s: PaRappa raises an arm (△).
  - t = 12/20 s: a ✕ appears for a chop.
  - Master Onion closes his eyes and shifts his pose between stills.
- **The moves are driven by time, not by audio input.**
  - The "Music" object (id 14) has a timeline animation whose events (`beat`, `rap1`…) run its property scripts.
  - Those scripts start the music `.wav` layers and pick a random move with `Math.random()`.
  - They then call `thisScene.getLayer("parappa"|"master_onion").getAnimationLayer("Punch"|"Kick"|"Chop"|"Pose").getAnimation("go").play()`, and for Chop also `.setFrame(0)`.
  - The audio visualiser is the only thing that uses audio input.
- **WE logs:** WE wrote no log lines about models or animations; the only `.log` files are the UI's Chromium cache.

## 2. How `animationlayers` select and play a clip (3D .mdl)

- **`animation` is the MDLA clip's own id, not an index.** Each clip record in the MDLA starts with `u32 id, u32 0, name, mode…`.
  - parappa.mdl's ids are 118 chop, 119 idle, 120 kick, 121 pose, 122 punch, 123 wait, 26 intro_1, 27 intro_2.
  - Its layers use exactly those: Idle 119, Wait 123, Punch 122, Kick 120, Chop 118, Pose 121, Intro 1 26, Intro 2 27.
  - The same holds for pj 228, sunny 268, joe_chin 186, boxy_boy 286 and master_onion 164–169/23/24.
  - The MDLA count field says 14 records but holds only 8 distinct clips; the 6 ids from 118 to 123 are listed twice, first in id order and then in name order.
- **Every layer in this scene has `"visible": true`,** a plain bool, so this file can't show whether a layer **without** `visible` plays by default. An earlier capture, 519b, found that a camera layer without `visible` plays no path.
- **`blend` does the choosing.** PaRappa has 8 layers, all `rate`-scaled and all `additive: false`.
  - Idle has a constant `blend 1.0` and `rate 4.0`.
  - Every other layer has `blend` as an **animated property**: `"blend": {"value": 0.0, "animation": {"options": {"name": "go", "mode": "single", "fps": 30, "length": 15/66, "startpaused": true, "events": [{frame 0, "punch"}]}, "c0": [keys]}, "script": …}`.
    - The keys are, for example, Punch 0 → 1.5 → 0 over 15 frames, and Wait 0 → 1 (f10) → 1 (f56) → 0 (f66).
  - So a move clip plays all the time underneath, at weight 0. Scripts start the blend timeline with `getAnimationLayer(name).getAnimation("go").play()`, and its keys raise the move's weight over the idle for about 0.5 s.
  - The blend's own `animationEvent` script plays the SFX and emits particles; Chop's script also calls `thisLayer.getAnimationLayer("Chop").setFrame(8)` on the clip itself.
  - Intro 1 (rate 1.5) is the only blend timeline that isn't `startpaused`, so it runs at load, and its event `intro1end` hands over to the loop.
- **Likely reason OWE shows no dancing:** if OWE plays only the first layer, ignores animated `blend` values, or doesn't implement `getAnimationLayer(...).getAnimation("go").play()` and `setFrame`, PaRappa and Master Onion stay in Idle with every move at weight 0.
  - The background characters have one Idle layer each (rates 2–4), so they should loop even without any of that. If they don't in OWE either, the clip-id lookup is the first thing to check.
