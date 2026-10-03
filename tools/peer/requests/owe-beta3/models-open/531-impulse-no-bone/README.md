# §5.31 applyBonePhysicsImpulse with no bone

On the first frame, the probe script (`../524-bone-angle-units/probe-script.js`) calls these on the rope puppet (translation-physics tail):
- `thisLayer.applyBonePhysicsImpulse()`;
- `applyBonePhysicsImpulse(new Vec3(0,0,0), new Vec3(0,0,45))`, with no bone name;
- `resetBonePhysicsSimulation()`.

## Result
- **All three return `undefined` and throw nothing.** No error appears in the Log window.
- In the preview there was no visible kick on the tail.
- So a missing bone argument is **silently ignored**: it hits neither all bones nor raises an error.
- **Log:** `probe_log_bind0.txt`.
