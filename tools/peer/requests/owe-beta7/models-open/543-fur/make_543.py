"""543: fur4 on the centred cube (539's p539_click, no script, camera 0 0 3, scale 0.01). Variants: INSTANCECOUNT combo
default (not set, shader default 5) and 21 (Ultra), furdistance 0.3 so the shells are visible."""
import json, os, shutil
M = r"C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine\projects\myprojects"
H = os.path.dirname(os.path.abspath(__file__))
for name, combos in (("p543_fur_def", {}), ("p543_fur_21", {"INSTANCECOUNT": 21})):
    d = os.path.join(M, name)
    if os.path.exists(d): shutil.rmtree(d)
    shutil.copytree(os.path.join(M, "p539_click"), d, ignore=shutil.ignore_patterns("shaders"))
    mat = {"passes": [{"shader": "fur4", "textures": ["util/white", None, None, None, None, None, None, None, "util/fur"],
                       "combos": dict({"LIGHTING": 1}, **combos),
                       "constantshadervalues": {"furdistance": 0.3, "furdetail": 10.0, "furocclusion": 0.2}}]}
    mp = os.path.join(d, "materials", "models", "centered_cube", "DefaultMaterial.json")
    json.dump(mat, open(mp, "w", encoding="utf-8"), indent=1)
    json.dump(mat, open(os.path.join(H, name + "_material.json"), "w", encoding="utf-8"), indent=1)
    s = json.load(open(os.path.join(d, "scene.json"), encoding="utf-8-sig"))
    o = s["objects"][0]; o["origin"] = "0 0 0"; o["angles"] = "0.5 0.7 0"
    json.dump(s, open(os.path.join(d, "scene.json"), "w", encoding="utf-8"), indent=1)
    p = json.load(open(os.path.join(d, "project.json"), encoding="utf-8-sig")); p["title"] = name
    json.dump(p, open(os.path.join(d, "project.json"), "w", encoding="utf-8"), indent=1)
    print(name, combos)
