"""509 base: bars.png (512x256) as an image layer at (960,540) in a 1920x1080 scene."""
import json, os, shutil, sys
sys.path.insert(0, r"K:\DeepWorkspace\wem-images2\tools\peer\effect_gallery")
import build_gallery as bg

WE = r"C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine\projects\myprojects"
ROPE = r"K:\DeepWorkspace\wem-images2\tools\peer\requests\owe-beta7\models-open\509-mdlv-unknowns\bars.png"
name = sys.argv[1] if len(sys.argv) > 1 else "p509_bars"
d = os.path.join(WE, name)
if os.path.exists(d): shutil.rmtree(d)
os.makedirs(os.path.join(d, "materials")); os.makedirs(os.path.join(d, "models"))
bg.write_tex(ROPE, os.path.join(d, "materials", "bars.tex"))
json.dump({"clampuvs": True, "format": "rgba8888", "nomip": True, "nonpoweroftwo": True}, open(os.path.join(d, "materials", "bars.tex-json"), "w"))
json.dump({"passes": [{"blending": "translucent", "cullmode": "nocull", "depthtest": "disabled", "depthwrite": "disabled",
                       "shader": "genericimage2", "textures": ["bars"]}]}, open(os.path.join(d, "materials", "bars.json"), "w"), indent=1)
json.dump({"autosize": True, "material": "materials/bars.json"}, open(os.path.join(d, "models", "bars.json"), "w"), indent=1)
scene = {"camera": {"center": "0 0 -1", "eye": "0 0 0", "up": "0 1 0"},
         "general": {"clearcolor": "0.15 0.15 0.15", "ambientcolor": "0.3 0.3 0.3", "skylightcolor": "0.3 0.3 0.3",
                     "orthogonalprojection": {"width": 1920, "height": 1080}},
         "objects": [{"id": 10, "name": "bars", "image": "models/bars.json", "origin": "960 540 0", "angles": "0 0 0",
                      "scale": "1 1 1", "size": "512 256", "visible": True}]}
json.dump(scene, open(os.path.join(d, "scene.json"), "w"), indent=1)
json.dump({"file": "scene.json", "title": name, "type": "scene", "general": {"properties": {}}}, open(os.path.join(d, "project.json"), "w"), indent=1)
print(d)
