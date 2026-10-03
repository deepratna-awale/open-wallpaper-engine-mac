# models-plan §5 open points: WE ground truth (partial)

## Done (scene.json + screenshots)
513-no-origin, 514-short-vectors, 519-ortho-zoom (zoom part), 517-puppet-cull, 516-nested-tilt, 518-fade (inconclusive).

## Done (editor log or scripts)
524-bone-angle-units (radians), 531-impulse-no-bone (silently ignored), 505-path-camera (static camera), 521-auto-size (script wins; size comes from the texture).

## Not done yet
- **Need editor or log work:** 5.22 timeline keys, 5.15 attachment depth, 5.10 text depthtest, 5.20 camera write-back, 5.11 missing vertex attributes, 5.19 camera path in ortho, 5.18 fade threshold (needs a translucent model).
- **Texture Channels puppet:** the editor's Texture Channels dialog would not add a second channel through automation. The file picker opens and accepts a 96x512 PNG, but no channel is added and nothing is logged.

`shots/` has every capture and `shots/shots.log`.
