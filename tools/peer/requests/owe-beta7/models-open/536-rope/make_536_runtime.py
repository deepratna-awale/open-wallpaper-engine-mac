"""536 runtime projects: copies of p536_rope (arm.png, 5-bone chain, "Rope with 4 elements" on the tip) per .mdl variant, with an animation layer on the empty clip 22 (puppet physics only runs while a clip plays);
p536_base_wind also sets scene general.windenabled true (direction/strength at WE's defaults)."""
import json, os, shutil
M = r"C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine\projects\myprojects"
H = os.path.dirname(os.path.abspath(__file__))
V = {"p536_base": "rope_base", "p536_nostretch": "rope_nostretch", "p536_nostretch_free": "rope_nostretch_free", "p536_base_wind": "rope_base"}
for name, v in V.items():
    d = os.path.join(M, name)
    if os.path.exists(d): shutil.rmtree(d)
    shutil.copytree(os.path.join(M, "p536_rope"), d, ignore=shutil.ignore_patterns("shaders"))
    shutil.copy(os.path.join(H, v + ".mdl"), os.path.join(d, "models", "arm_puppet.mdl"))
    shutil.copy(os.path.join(H, v + ".json"), os.path.join(d, "models", "arm_puppet.json"))
    s = json.load(open(os.path.join(d, "scene.json"), encoding="utf-8"))
    s["objects"][0]["animationlayers"] = [{"additive": False, "animation": 22, "blend": 1.0, "blendin": False, "blendout": False,
                                           "blendtime": 0.5, "id": 900, "name": "clip", "rate": 1.0, "visible": True}]
    if name.endswith("_wind"):
        s["general"].update({"windenabled": True, "winddirection": "0.70700 0.70700 0.00000", "windstrength": 1.0})
    json.dump(s, open(os.path.join(d, "scene.json"), "w", encoding="utf-8"), indent=1)
    p = json.load(open(os.path.join(d, "project.json"), encoding="utf-8")); p["title"] = name
    json.dump(p, open(os.path.join(d, "project.json"), "w", encoding="utf-8"), indent=1)
    print(name)
