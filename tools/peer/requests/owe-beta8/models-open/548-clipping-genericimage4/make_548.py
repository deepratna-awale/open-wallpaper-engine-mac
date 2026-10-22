"""548 runtime copies of p548_clip (532c rig, material genericimage4, clip 29: circle x 0 -> +275 -> 0 over 2 s) per .mdl variant."""
import json, os, shutil
M = r"C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine\projects\myprojects"
H = os.path.dirname(os.path.abspath(__file__))
for v in ("c_mask_on", "c_mask_removed", "c_invert", "c_hide"):
    d = os.path.join(M, "p548_" + v)
    if os.path.exists(d): shutil.rmtree(d)
    shutil.copytree(os.path.join(M, "p548_clip"), d, ignore=shutil.ignore_patterns("shaders"))
    shutil.copy(os.path.join(H, v + ".mdl"), os.path.join(d, "models", "circle_rect_puppet.mdl"))
    shutil.copy(os.path.join(H, v + ".json"), os.path.join(d, "models", "circle_rect_puppet.json"))
    s = json.load(open(os.path.join(d, "scene.json"), encoding="utf-8-sig"))
    s["objects"][0]["animationlayers"] = [{"additive": False, "animation": 29, "blend": 1.0, "blendin": False, "blendout": False,
                                           "blendtime": 0.5, "id": 900, "name": "clip", "rate": 1.0, "visible": True}]
    json.dump(s, open(os.path.join(d, "scene.json"), "w", encoding="utf-8"), indent=1)
    p = json.load(open(os.path.join(d, "project.json"), encoding="utf-8-sig")); p["title"] = "p548_" + v
    json.dump(p, open(os.path.join(d, "project.json"), "w", encoding="utf-8"), indent=1)
    print(d)
