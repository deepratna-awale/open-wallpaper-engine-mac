"""533 runtime projects: copies of p533_br with br_none / br_rule .mdl/.json and an animation layer on clip 28."""
import json, os, shutil
M = r"C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine\projects\myprojects"
H = os.path.dirname(os.path.abspath(__file__))
for v in ("br_none", "br_rule"):
    d = os.path.join(M, "p533_" + v)
    if os.path.exists(d): shutil.rmtree(d)
    shutil.copytree(os.path.join(M, "p533_br"), d, ignore=shutil.ignore_patterns("shaders"))
    shutil.copy(os.path.join(H, v + ".mdl"), os.path.join(d, "models", "bars_puppet.mdl"))
    shutil.copy(os.path.join(H, v + ".json"), os.path.join(d, "models", "bars_puppet.json"))
    s = json.load(open(os.path.join(d, "scene.json"), encoding="utf-8"))
    s["objects"][0]["animationlayers"] = [{"additive": False, "animation": 28, "blend": 1.0, "blendin": False, "blendout": False,
                                           "blendtime": 0.5, "id": 900, "name": "clip", "rate": 1.0, "visible": True}]
    json.dump(s, open(os.path.join(d, "scene.json"), "w", encoding="utf-8"), indent=1)
    p = json.load(open(os.path.join(d, "project.json"), encoding="utf-8")); p["title"] = "p533_" + v
    json.dump(p, open(os.path.join(d, "project.json"), "w", encoding="utf-8"), indent=1)
    print(d)
