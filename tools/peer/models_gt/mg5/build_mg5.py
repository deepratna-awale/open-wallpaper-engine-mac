"""MG5 variants: the editor-authored puppet (blend shape id 31, vertex 196 offset +126.168 x) driven by a SceneScript
on the layer's origin property: constant weights 0/0.25/0.5/1 every frame, and 'persist' = weight 1 set only once."""
import json, os, shutil

WE = r"C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine\projects\myprojects"
SRC = os.path.join(WE, "fxgal_none")          # the saved editor project ("MG5 puppet test")
SCRIPTS = {
    "w0": "export function update(value) { thisLayer.setBlendShapeWeight(%s, 0); return value; }",
    "w025": "export function update(value) { thisLayer.setBlendShapeWeight(%s, 0.25); return value; }",
    "w05": "export function update(value) { thisLayer.setBlendShapeWeight(%s, 0.5); return value; }",
    "w1": "export function update(value) { thisLayer.setBlendShapeWeight(%s, 1); return value; }",
    "persist": "let done = false;\nexport function update(value) { if (!done) { thisLayer.setBlendShapeWeight(%s, 1); done = true; } return value; }",
}
for key_arg, suffix in (("31", ""), ("0", "_idx0")):
    for name, body in SCRIPTS.items():
        d = os.path.join(WE, "mg5_%s%s" % (name, suffix))
        if os.path.exists(d): shutil.rmtree(d)
        shutil.copytree(SRC, d)
        s = json.load(open(os.path.join(d, "scene.json")))
        o = s["objects"][0]
        o["origin"] = {"script": "'use strict';\n" + (body % key_arg), "scriptproperties": {}, "value": o["origin"]}
        json.dump(s, open(os.path.join(d, "scene.json"), "w"), indent=1)
        p = json.load(open(os.path.join(d, "project.json"))); p["title"] = "mg5_%s%s" % (name, suffix)
        json.dump(p, open(os.path.join(d, "project.json"), "w"), indent=1)
        print(os.path.basename(d))
