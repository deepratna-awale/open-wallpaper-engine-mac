"""Blend shape driven by name 'Shape 31' (the MDMP name). Origin value is returned unchanged."""
import json, os, shutil

WE = r"C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine\projects\myprojects"
SRC = os.path.join(WE, "fxgal_none")
def every(w):
    return ("let i = -1;\nexport function update(value) {\n"
            "  if (i < 0) i = thisLayer.getBlendShapeIndex('Shape 31');\n"
            "  thisLayer.setBlendShapeWeight(i, %s);\n  return value;\n}" % w)
V = {"named_w025": every("0.25"), "named_w05": every("0.5"), "named_w1": every("1"),
     "named_once": ("let done = false;\nexport function update(value) {\n"
                    "  if (!done) { thisLayer.setBlendShapeWeight(thisLayer.getBlendShapeIndex('Shape 31'), 1); done = true; }\n"
                    "  return value;\n}")}
for n, body in V.items():
    d = os.path.join(WE, "mg5_" + n)
    if os.path.exists(d): shutil.rmtree(d)
    shutil.copytree(SRC, d)
    s = json.load(open(os.path.join(d, "scene.json")))
    o = s["objects"][0]
    o["origin"] = {"script": "'use strict';\n" + body, "scriptproperties": {}, "value": o["origin"]}
    json.dump(s, open(os.path.join(d, "scene.json"), "w"), indent=1)
    print(n)
