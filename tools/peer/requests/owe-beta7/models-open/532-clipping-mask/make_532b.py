"""532 follow-up runtime projects: copies of p532_mask with a given .mdl/.json and mask texture set."""
import os, shutil, json
M = r"C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine\projects\myprojects"
H = os.path.dirname(os.path.abspath(__file__))
B = os.path.join(H, "..", "509-mdlv-unknowns", "response")
full = os.path.join(H, "project", "materials", "masks")
half = os.path.join(H, "project_mask2", "materials", "masks")
V = {"p532_invert": (os.path.join(H, "g_mask_invert"), full), "p532_hide": (os.path.join(H, "g_mask_hide"), full),
     "p532_mask2": (os.path.join(H, "g_mask2"), half), "p532_locked": (os.path.join(H, "g_locked"), full),
     "p532_unlocked": (os.path.join(B, "b_clip"), full)}
for name, (src, masks) in V.items():
    d = os.path.join(M, name)
    if os.path.exists(d): shutil.rmtree(d)
    shutil.copytree(os.path.join(M, "p532_mask"), d, ignore=shutil.ignore_patterns("shaders"))
    shutil.copy(src + ".mdl", os.path.join(d, "models", "bars_puppet.mdl")); shutil.copy(src + ".json", os.path.join(d, "models", "bars_puppet.json"))
    shutil.rmtree(os.path.join(d, "materials", "masks")); shutil.copytree(masks, os.path.join(d, "materials", "masks"))
    p = json.load(open(os.path.join(d, "project.json"), encoding="utf-8")); p["title"] = name
    json.dump(p, open(os.path.join(d, "project.json"), "w", encoding="utf-8"), indent=1)
    print(name)
