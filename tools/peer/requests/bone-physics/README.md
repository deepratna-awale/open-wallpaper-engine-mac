# Capture request: puppet bone physics

**This needs you at WE's editor.** A person has to build the puppet in the Puppet Warp editor. No script or command line can make one, because the constraints only reach the `.mdl` through the editor and `resourcecompiler64.exe`.

## Why

OpenWallpaperEngine now simulates physics bones: spring and rigid bones, with gravity, limits, `applyBonePhysicsImpulse` and `resetBonePhysicsSimulation`. The model comes from `wallpaper64.exe` (the update at 0x14020136e…0x140203648, and the loader at 0x140265c30; see `docs/models-plan.md` §2.14). It has only been checked against its own formulas and the library's 17 physics bones, which never play in a scripted, measurable way. This capture gives the answers the binary can't:

- how far and how fast a bone swings after its parent moves, per frame;
- that the impulse and the reset do what the host code says;
- the compiled constraint JSON the editor writes into the `.mdl`, including `tp` from the tip size.

## Build the project (one project, two variants)

Files here: `bone-physics/rope.png` (a 96×512 striped bar with a blue tip) and `bone-physics/origin-script.js`.

1. **Create the scene.** Make a new 2D scene wallpaper at 1920×1080. Import `rope.png` as an image layer, put it at (960, 540), and keep its scale at 1 and its angle at 0. Add no effects.
2. **Add the bones.** Open **Puppet Warp** on the layer and generate the mesh with the defaults.
   - Add a bone named **`root`** at the top of the bar, (48, 16) in the image.
   - Add a child bone named **`tail`** from the middle of the bar, (48, 256), pointing down.
   - Skin the lower half to `tail` and the upper half to `root`, or use automatic weights.
3. **Set the constraints on `tail`.** Open Bone Constraints and choose **Advanced**.
   - **Variant A, spring rotation:** Simulation mode *Spring physics*, *Physics rotation* on, *Physics translation* off, the defaults otherwise (rotational stiffness 200, friction 20, inertia 30), *Gravity enabled* on, tip mass 20, gravity direction down, tip size 0, *Limit rotation* off.
   - **Variant B, spring position:** Simulation preset *Bouncy position*. That gives spring, translation only, translational stiffness 300.
4. **Add the script.** Paste `origin-script.js` as the layer's **Origin** script. It moves the layer 200 px right at 2 s and back at 5 s. At 6 s it gives `tail` a 45° angular impulse, and at 8 s it resets it. Until 9 s it logs one `BP …` line per frame: the time, the frame time, the layer's x, six elements of `tail`'s world matrix, and its local z angle.
5. Add no animation layer, so the bones rest in their bind pose apart from the physics.

## Capture (for each variant)

1. **The project folder.** Save the project and copy the whole folder: `project.json`, `scene.json`, `models/*.mdl`, the puppet's `.json`, `materials/`. The `.mdl` holds the compiled constraint JSON, which is the main thing we need.
2. **The log.** Apply the wallpaper, or run it in the editor, and copy every `BP …` line from the editor's log or console, from load to 9 s.
3. **The clip.** Record 10 s from the wallpaper's load at 60 fps, for example with OBS, cropped to 800×800 around the bar. Keep the frame rate fixed (WE's FPS setting at 60). Note the offset between the recording and the load if the start isn't exact.
4. Note WE's version and the FPS setting.

Put everything in `/Volumes/980Pro/agentBP-out/response/bone-physics/A` and `…/B`.

## What we expect

- The first frame after load doesn't move (WE has no last-frame bones yet).
- **A:**
  - At 2 s, `tail`'s tip lags left and then swings back under the spring, with friction. It hangs slightly towards gravity, but it already points down, so the sag is small.
  - The 45° impulse at 6 s turns it by 45° over the first frame at 60 fps, and then it springs back.
  - The reset at 8 s snaps it to the rest angle on the next frame.
- **B:**
  - At 2 s the tip stays behind by 70 % of the move (`ti` 30), about 140 px, and the spring of 300 pulls it back over a few tenths of a second, overshooting.
  - It is capped at `tm` × the layer's scale (the default `tm` is 200).
  - Gravity is off in the preset.

Any difference in the size of the lag, the swing's period or damping, or the frame the motion starts on points at a specific step in §2.14.
