"""Debug variants: does the layer script run (dbg_shift moves the layer +200 x), and does name lookup find the shape."""
import json, os, shutil

WE = r"C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine\projects\myprojects"
SRC = os.path.join(WE, "fxgal_none")
V = {
    "dbg_shift": "export function update(value) { value.x += 200; thisLayer.setBlendShapeWeight(0, 1); return value; }",
    "dbg_byname": (
        "let i = -1;\n"
        "export function update(value) {\n"
        "  if (i < 0) { i = thisLayer.getBlendShapeIndex('Blend shape 31'); if (i < 0) i = thisLayer.getBlendShapeIndex(''); }\n"
        "  thisLayer.setBlendShapeWeight(i < 0 ? 0 : i, 1);\n"
        "  value.y += 150 * (i + 2);\n"   # encodes the looked-up index as a vertical shift
        "  return value;\n}"),
}
for n, body in V.items():
    d = os.path.join(WE, "mg5_" + n)
    if os.path.exists(d): shutil.rmtree(d)
    shutil.copytree(SRC, d)
    s = json.load(open(os.path.join(d, "scene.json")))
    o = s["objects"][0]
    o["origin"] = {"script": "'use strict';\n" + body, "scriptproperties": {}, "value": o["origin"]}
    json.dump(s, open(os.path.join(d, "scene.json"), "w"), indent=1)
    print(n)
