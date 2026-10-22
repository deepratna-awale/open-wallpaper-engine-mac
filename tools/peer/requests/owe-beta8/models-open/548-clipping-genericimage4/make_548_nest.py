"""548 nested: abc.png (A red square 20-180, B green circle c(260,128) r50, C blue square 370-420; separate islands), material genericimage4, and project p532c (image layer at 960,540)."""
import json, os, shutil, sys
from PIL import Image, ImageDraw
H = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, r"K:\DeepWorkspace\wem-images2\tools\peer\effect_gallery")
import build_gallery as bg
png = os.path.join(H, "abc.png")
im = Image.new("RGBA", (512, 256), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
d.rectangle((20, 48, 180, 208), fill=(230, 30, 30, 255)); d.ellipse((210, 78, 310, 178), fill=(40, 200, 60, 255)); d.rectangle((370, 103, 420, 153), fill=(40, 90, 240, 255))
im.save(png)
WE = r"C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine\projects\myprojects"
name = sys.argv[1] if len(sys.argv) > 1 else "p548_nest"
p = os.path.join(WE, name)
if os.path.exists(p): shutil.rmtree(p)
os.makedirs(os.path.join(p, "materials")); os.makedirs(os.path.join(p, "models"))
bg.write_tex(png, os.path.join(p, "materials", "abc.tex"))
json.dump({"clampuvs": True, "format": "rgba8888", "nomip": True, "nonpoweroftwo": True}, open(os.path.join(p, "materials", "abc.tex-json"), "w"))
json.dump({"passes": [{"blending": "translucent", "cullmode": "nocull", "depthtest": "disabled", "depthwrite": "disabled",
                       "shader": "genericimage4", "textures": ["abc"]}]}, open(os.path.join(p, "materials", "abc.json"), "w"), indent=1)
json.dump({"autosize": True, "material": "materials/abc.json"}, open(os.path.join(p, "models", "abc.json"), "w"), indent=1)
scene = {"camera": {"center": "0 0 -1", "eye": "0 0 0", "up": "0 1 0"},
         "general": {"clearcolor": "0.15 0.15 0.15", "ambientcolor": "0.3 0.3 0.3", "skylightcolor": "0.3 0.3 0.3",
                     "orthogonalprojection": {"width": 1920, "height": 1080}},
         "objects": [{"id": 10, "name": "abc", "image": "models/abc.json", "origin": "960 540 0", "angles": "0 0 0",
                      "scale": "1 1 1", "size": "512 256", "visible": True}]}
json.dump(scene, open(os.path.join(p, "scene.json"), "w"), indent=1)
json.dump({"file": "scene.json", "title": name, "type": "scene", "general": {"properties": {}}}, open(os.path.join(p, "project.json"), "w"), indent=1)
print(p)
