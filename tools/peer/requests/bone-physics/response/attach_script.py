"""Attach origin-script.js as the rope layer's origin script in the saved project's scene.json (argv: project name)."""
import json, os, sys

WE = r"C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine\projects\myprojects"
JS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "bone-physics", "origin-script.js")
p = os.path.join(WE, sys.argv[1], "scene.json")
scene = json.load(open(p, encoding="utf-8"))
src = open(JS, encoding="utf-8").read()
for o in scene["objects"]:
    if o.get("name") == "rope":
        val = o["origin"]["value"] if isinstance(o["origin"], dict) else o["origin"]
        o["origin"] = {"script": src, "scriptproperties": {}, "value": val}
json.dump(scene, open(p, "w", encoding="utf-8"), indent="\t")
print("attached to", p)
