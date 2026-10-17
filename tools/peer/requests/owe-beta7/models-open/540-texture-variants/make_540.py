"""540 runtime copies of the editor-saved p540_var: only the variant_a image layer, with the 'shapesel' combo default 0/1/2."""
import json, os, shutil
M = r"C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine\projects\myprojects"
for v in ("0", "1", "2"):
    d = os.path.join(M, "p540_v" + v)
    if os.path.exists(d): shutil.rmtree(d)
    shutil.copytree(os.path.join(M, "p540_var"), d, ignore=shutil.ignore_patterns("shaders"))
    s = json.load(open(os.path.join(d, "scene.json"), encoding="utf-8-sig"))
    s["objects"] = [o for o in s["objects"] if "variant_a" in str(o.get("image", ""))]
    json.dump(s, open(os.path.join(d, "scene.json"), "w", encoding="utf-8"), indent=1)
    p = json.load(open(os.path.join(d, "project.json"), encoding="utf-8-sig")); p["title"] = "p540_v" + v
    p["general"]["properties"]["shapesel"]["value"] = v
    json.dump(p, open(os.path.join(d, "project.json"), "w", encoding="utf-8"), indent=1)
    print(d, [o.get("image") for o in s["objects"]])
