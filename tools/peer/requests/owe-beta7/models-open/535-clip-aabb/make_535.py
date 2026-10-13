"""535: p535_* projects from MG4's root-motion box with 509 E's e_offset0.mdl (clip 26); aabb_far sets both clip AABBs to 10000."""
import json, os, shutil, struct
M = r"C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine\projects\myprojects"
H = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(H, "..", "..", "..", "..", "models_gt", "mg4", "we_import_project")
E = os.path.join(H, "..", "509-mdlv-unknowns", "response")
d = bytearray(open(os.path.join(E, "e_offset0.mdl"), "rb").read())
open(os.path.join(H, "aabb_base.mdl"), "wb").write(d)
for o in (0x1796, 0x250D): struct.pack_into("<6f", d, o, *([10000.0] * 6))
open(os.path.join(H, "aabb_far.mdl"), "wb").write(d)
shutil.copy(os.path.join(E, "e_offset0.json"), os.path.join(H, "aabb_far.json"))
for v in ("aabb_base", "aabb_far"):
    p = os.path.join(M, "p535_" + v)
    if os.path.exists(p): shutil.rmtree(p)
    shutil.copytree(SRC, p, ignore=shutil.ignore_patterns("shaders"))
    md = os.path.join(p, "models", "rootmotion_box")
    shutil.copy(os.path.join(H, v + ".mdl"), os.path.join(md, "rootmotion_box.mdl"))
    shutil.copy(os.path.join(E, "e_offset0.json"), os.path.join(md, "rootmotion_box.json"))
    s = json.load(open(os.path.join(p, "scene.json"), encoding="utf-8"))
    s["camera"] = {"center": "0 1 0", "eye": "8 6 8", "up": "0 1 0"}
    for o in s["objects"]:
        if o.get("model"):
            o["scale"] = "0.01 0.01 0.01"; o["origin"] = "0 0 0"
            o["animationlayers"] = [{"additive": False, "animation": 26, "blend": 1.0, "blendin": False, "blendout": False,
                                     "blendtime": 0.5, "id": 900, "name": "clip", "rate": 1.0, "visible": True}]
    json.dump(s, open(os.path.join(p, "scene.json"), "w", encoding="utf-8"), indent=1)
    j = json.load(open(os.path.join(p, "project.json"), encoding="utf-8")); j["title"] = "p535_" + v
    json.dump(j, open(os.path.join(p, "project.json"), "w", encoding="utf-8"), indent=1)
    print(p)
