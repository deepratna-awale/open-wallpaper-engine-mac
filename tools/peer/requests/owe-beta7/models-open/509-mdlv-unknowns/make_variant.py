"""Copy p509_bars into a capture project <name> using response/<variant>.mdl/.json, with an animation layer (clip id)."""
import json, os, shutil, sys
M = r"C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine\projects\myprojects"
R = os.path.join(os.path.dirname(os.path.abspath(__file__)), "response")
name, variant, clip = sys.argv[1], sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else None
d = os.path.join(M, name)
if os.path.exists(d): shutil.rmtree(d)
shutil.copytree(os.path.join(M, "p509_bars"), d, ignore=shutil.ignore_patterns("shaders"))
shutil.copy(os.path.join(R, variant + ".mdl"), os.path.join(d, "models", "bars_puppet.mdl"))
shutil.copy(os.path.join(R, variant + ".json"), os.path.join(d, "models", "bars_puppet.json"))
s = json.load(open(os.path.join(d, "scene.json"), encoding="utf-8"))
o = s["objects"][0]
if clip is not None:
    o["animationlayers"] = [{"additive": False, "animation": clip, "blend": 1.0, "blendin": False, "blendout": False,
                             "blendtime": 0.5, "id": 900, "name": "clip", "rate": 1.0, "visible": True}]
else:
    o.pop("animationlayers", None)
json.dump(s, open(os.path.join(d, "scene.json"), "w", encoding="utf-8"), indent=1)
p = json.load(open(os.path.join(d, "project.json"), encoding="utf-8")); p["title"] = name
json.dump(p, open(os.path.join(d, "project.json"), "w", encoding="utf-8"), indent=1)
print(name, o.get("puppet") or o.get("image"))
