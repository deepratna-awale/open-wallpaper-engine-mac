"""538: p538_hit = p533_br_none (bars puppet + anchor, clip 28 playing) with a SceneScript on the layer's origin that logs
the cursor events' hitBox (and positions) for click, down, up, enter, leave and move."""
import json, os, shutil
M = r"C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine\projects\myprojects"
SCRIPT = r"""'use strict';
let last = '';
function show(e) { return JSON.stringify({hitBox: e.hitBox, local: e.localPosition, world: e.worldPosition}); }
export function cursorClick(e) { console.log('click ' + show(e)); }
export function cursorDown(e) { console.log('down ' + show(e)); }
export function cursorUp(e) { console.log('up ' + show(e)); }
export function cursorEnter(e) { console.log('enter ' + show(e)); }
export function cursorLeave(e) { console.log('leave ' + show(e)); }
export function cursorMove(e) { const h = JSON.stringify(e.hitBox); if (h !== last) { last = h; console.log('move ' + show(e)); } }
export function update(value) { return value; }
"""
d = os.path.join(M, "p538_hit")
if os.path.exists(d): shutil.rmtree(d)
shutil.copytree(os.path.join(M, "p533_br_none"), d, ignore=shutil.ignore_patterns("shaders"))
s = json.load(open(os.path.join(d, "scene.json"), encoding="utf-8"))
o = s["objects"][0]
o["origin"] = {"script": SCRIPT, "scriptproperties": {}, "value": o["origin"] if isinstance(o["origin"], str) else o["origin"]["value"]}
json.dump(s, open(os.path.join(d, "scene.json"), "w", encoding="utf-8"), indent=1)
p = json.load(open(os.path.join(d, "project.json"), encoding="utf-8")); p["title"] = "p538_hit"
json.dump(p, open(os.path.join(d, "project.json"), "w", encoding="utf-8"), indent=1)
print(d)
