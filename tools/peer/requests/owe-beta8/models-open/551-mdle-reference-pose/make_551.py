"""551 runtime copies of p551_ref (509 bars + b_clip clip 23: blue 0->180->0 over 2 s; red not animated).
ref_clip = reference pose red angle Z 30 (MDLE written); noref_clip = 509's b_clip (no MDLE).
Layer modes: none (no animationlayers), f0 (clip, rate 0 = frozen at frame 0), play (clip at rate 1)."""
import json, os, shutil
M = r"C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine\projects\myprojects"
H = os.path.dirname(os.path.abspath(__file__))
for v in ("ref_clip", "noref_clip"):
    for mode, rate in (("none", None), ("f0", 0.0), ("play", 1.0)):
        name = "p551_%s_%s" % (v, mode); d = os.path.join(M, name)
        if os.path.exists(d): shutil.rmtree(d)
        shutil.copytree(os.path.join(M, "p551_ref"), d, ignore=shutil.ignore_patterns("shaders"))
        shutil.copy(os.path.join(H, v + ".mdl"), os.path.join(d, "models", "bars_puppet.mdl"))
        shutil.copy(os.path.join(H, v + ".json"), os.path.join(d, "models", "bars_puppet.json"))
        s = json.load(open(os.path.join(d, "scene.json"), encoding="utf-8-sig")); o = s["objects"][0]
        if rate is None: o.pop("animationlayers", None)
        else: o["animationlayers"] = [{"additive": False, "animation": 23, "blend": 1.0, "blendin": False, "blendout": False,
                                       "blendtime": 0.5, "id": 900, "name": "clip", "rate": rate, "visible": True}]
        json.dump(s, open(os.path.join(d, "scene.json"), "w", encoding="utf-8"), indent=1)
        p = json.load(open(os.path.join(d, "project.json"), encoding="utf-8-sig")); p["title"] = name
        json.dump(p, open(os.path.join(d, "project.json"), "w", encoding="utf-8"), indent=1)
        print(name)
