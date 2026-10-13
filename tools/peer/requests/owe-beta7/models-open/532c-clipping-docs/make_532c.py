"""532c: circle_rect.png (purple circle left, red rectangle right, transparent between) and project p532c (image layer at 960,540)."""
import json, os, shutil, sys
from PIL import Image, ImageDraw
H = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, r"K:\DeepWorkspace\wem-images2\tools\peer\effect_gallery")
import build_gallery as bg
png = os.path.join(H, "circle_rect.png")
im = Image.new("RGBA", (512, 256), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
d.ellipse((40, 58, 180, 198), fill=(150, 60, 220, 255)); d.rectangle((300, 70, 470, 186), fill=(230, 30, 30, 255))
im.save(png)
WE = r"C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine\projects\myprojects"
name = sys.argv[1] if len(sys.argv) > 1 else "p532c"
p = os.path.join(WE, name)
if os.path.exists(p): shutil.rmtree(p)
os.makedirs(os.path.join(p, "materials")); os.makedirs(os.path.join(p, "models"))
bg.write_tex(png, os.path.join(p, "materials", "circle_rect.tex"))
json.dump({"clampuvs": True, "format": "rgba8888", "nomip": True, "nonpoweroftwo": True}, open(os.path.join(p, "materials", "circle_rect.tex-json"), "w"))
json.dump({"passes": [{"blending": "translucent", "cullmode": "nocull", "depthtest": "disabled", "depthwrite": "disabled",
                       "shader": "genericimage2", "textures": ["circle_rect"]}]}, open(os.path.join(p, "materials", "circle_rect.json"), "w"), indent=1)
json.dump({"autosize": True, "material": "materials/circle_rect.json"}, open(os.path.join(p, "models", "circle_rect.json"), "w"), indent=1)
scene = {"camera": {"center": "0 0 -1", "eye": "0 0 0", "up": "0 1 0"},
         "general": {"clearcolor": "0.15 0.15 0.15", "ambientcolor": "0.3 0.3 0.3", "skylightcolor": "0.3 0.3 0.3",
                     "orthogonalprojection": {"width": 1920, "height": 1080}},
         "objects": [{"id": 10, "name": "shapes", "image": "models/circle_rect.json", "origin": "960 540 0", "angles": "0 0 0",
                      "scale": "1 1 1", "size": "512 256", "visible": True}]}
json.dump(scene, open(os.path.join(p, "scene.json"), "w"), indent=1)
json.dump({"file": "scene.json", "title": name, "type": "scene", "general": {"properties": {}}}, open(os.path.join(p, "project.json"), "w"), indent=1)
print(p)
