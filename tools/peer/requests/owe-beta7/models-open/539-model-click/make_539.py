"""539: p539_click = MG4's model project with only centered_cube (a 1x1x1 cube centred on its origin, imported by WE's
editor from centered_cube.fbx), the camera looking straight down -z at it, and a SceneScript logging cursor events."""
import json, os
d = r"C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine\projects\myprojects\p539_click"
SCRIPT = r"""'use strict';
function show(e) { return JSON.stringify({hitBox: e.hitBox, local: e.localPosition, world: e.worldPosition}); }
export function cursorClick(e) { console.log('click ' + show(e)); }
export function cursorDown(e) { console.log('down ' + show(e)); }
export function cursorEnter(e) { console.log('enter ' + show(e)); }
export function cursorLeave(e) { console.log('leave ' + show(e)); }
export function update(value) { return value; }
"""
s = json.load(open(os.path.join(d, "scene.json"), encoding="utf-8"))
s["objects"] = [o for o in s["objects"] if "centered_cube" in str(o.get("model", ""))]
o = s["objects"][0]
print("cube object as saved:", json.dumps(o))
o["origin"] = {"script": SCRIPT, "scriptproperties": {}, "value": "0 0 0"}
o["scale"] = "0.01 0.01 0.01"; o["angles"] = "0 0 0"
s["camera"] = {"center": "0 0 0", "eye": "0 0 3", "up": "0 1 0"}
json.dump(s, open(os.path.join(d, "scene.json"), "w", encoding="utf-8"), indent=1)
