"""E playback projects: p509e_box copy with response/e_offsetN.mdl, animation layer on clip 26, MG4 camera."""
import json, os, shutil, sys
M = r"C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine\projects\myprojects"
R = os.path.join(os.path.dirname(os.path.abspath(__file__)), "response")
for v in ("e_offset0", "e_offset10"):
    d = os.path.join(M, "p509_s_" + v)
    if os.path.exists(d): shutil.rmtree(d)
    shutil.copytree(os.path.join(M, "p509e_box"), d, ignore=shutil.ignore_patterns("shaders"))
    md = os.path.join(d, "models", "rootmotion_box")
    shutil.copy(os.path.join(R, v + ".mdl"), os.path.join(md, "rootmotion_box.mdl"))
    shutil.copy(os.path.join(R, v + ".json"), os.path.join(md, "rootmotion_box.json"))
    s = json.load(open(os.path.join(d, "scene.json"), encoding="utf-8"))
    s["camera"] = {"center": "0 1 0", "eye": "8 6 8", "up": "0 1 0"}
    for o in s["objects"]:
        if o.get("model"):
            o["scale"] = "0.01 0.01 0.01"; o["origin"] = "0 0 0"
            o["animationlayers"] = [{"additive": False, "animation": 26, "blend": 1.0, "blendin": False, "blendout": False,
                                     "blendtime": 0.5, "id": 900, "name": "clip", "rate": 1.0, "visible": True}]
    json.dump(s, open(os.path.join(d, "scene.json"), "w", encoding="utf-8"), indent=1)
    p = json.load(open(os.path.join(d, "project.json"), encoding="utf-8")); p["title"] = "p509_s_" + v
    json.dump(p, open(os.path.join(d, "project.json"), "w", encoding="utf-8"), indent=1)
    print(d)
