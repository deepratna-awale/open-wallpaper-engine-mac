"""One project per editor-written root-motion .mdl: the imported model with an animation layer playing the clip."""
import json, os, shutil, sys

WE = r"C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine\projects\myprojects"
SRC = os.path.join(WE, "mg4_rootmotion_i")
VAR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mdl_variants")
clip = int(sys.argv[1]) if len(sys.argv) > 1 else 5
for f in sorted(os.listdir(VAR)):
    tag = f[len("rootmotion_"):-4]
    d = os.path.join(WE, "mg4p_" + tag)
    if os.path.exists(d): shutil.rmtree(d)
    shutil.copytree(SRC, d)
    shutil.copy(os.path.join(VAR, f), os.path.join(d, "models", "rootmotion_box", "rootmotion_box.mdl"))
    s = json.load(open(os.path.join(d, "scene.json")))
    for o in s["objects"]:
        if o.get("model"):
            o["animationlayers"] = [{"additive": False, "animation": clip, "blend": 1.0, "blendin": False, "blendout": False,
                                     "blendtime": 0.5, "id": 900, "name": "clip", "rate": 1.0, "visible": True}]
    s["camera"] = {"center": "0 1 0", "eye": "8 6 8", "up": "0 1 0"}
    for o in s["objects"]:
        if o.get("model"): o["scale"] = "0.01 0.01 0.01"; o["origin"] = "0 0 0"
    json.dump(s, open(os.path.join(d, "scene.json"), "w"), indent=1)
    p = json.load(open(os.path.join(d, "project.json"))); p["title"] = "mg4p_" + tag
    json.dump(p, open(os.path.join(d, "project.json"), "w"), indent=1)
    print("mg4p_" + tag)

