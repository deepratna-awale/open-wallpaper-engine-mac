"""542 runtime copies of p540_var: the tilted centred cube (angles 30/40 deg, scale 2.16) in the 1920x1080 2D scene
with perspective off / on (editor-saved scene_persp_*.json), and the same with general.clearenabled false and a
SceneScript spinning the cube (to show what an uncleared frame does)."""
import json, os, shutil
M = r"C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine\projects\myprojects"
H = os.path.dirname(os.path.abspath(__file__))
SPIN = "'use strict';\nexport function update(value) { value.y = engine.runtime * 1.5; return value; }\n"
V = {"p542_off": ("scene_persp_off.json", False), "p542_on": ("scene_persp_on.json", False),
     "p542_noclear": ("scene_persp_on.json", True), "p542_clear_spin": ("scene_persp_on.json", "spin")}
for name, (src, mode) in V.items():
    d = os.path.join(M, name)
    if os.path.exists(d): shutil.rmtree(d)
    shutil.copytree(os.path.join(M, "p540_var"), d, ignore=shutil.ignore_patterns("shaders"))
    s = json.load(open(os.path.join(H, src), encoding="utf-8-sig"))
    if mode:
        cube = [o for o in s["objects"] if "centered_cube" in str(o.get("model", ""))][0]
        cube["angles"] = {"script": SPIN, "scriptproperties": {}, "value": cube["angles"]}
    if mode is True:
        s["general"]["clearenabled"] = False
    json.dump(s, open(os.path.join(d, "scene.json"), "w", encoding="utf-8"), indent=1)
    if name == "p542_noclear": json.dump(s, open(os.path.join(H, "scene_noclear.json"), "w", encoding="utf-8"), indent=1)
    p = json.load(open(os.path.join(d, "project.json"), encoding="utf-8-sig")); p["title"] = name
    json.dump(p, open(os.path.join(d, "project.json"), "w", encoding="utf-8"), indent=1)
    print(name, s["general"].get("clearenabled"))
