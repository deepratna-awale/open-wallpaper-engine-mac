"""534: arm.png (one 452x40 orange bar, dark ticks at the joints) and project p534_ik (image layer at 960,540)."""
import json, os, shutil, sys
from PIL import Image, ImageDraw
H = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, r"K:\DeepWorkspace\wem-images2\tools\peer\effect_gallery")
import build_gallery as bg
png = os.path.join(H, "arm.png")
im = Image.new("RGBA", (512, 256), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
d.rectangle((30, 108, 482, 148), fill=(240, 170, 40, 255))
for x in (143, 256, 369): d.rectangle((x - 2, 108, x + 2, 148), fill=(90, 50, 10, 255))
im.save(png)
WE = r"C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine\projects\myprojects"
name = sys.argv[1] if len(sys.argv) > 1 else "p534_ik"
p = os.path.join(WE, name)
if os.path.exists(p): shutil.rmtree(p)
os.makedirs(os.path.join(p, "materials")); os.makedirs(os.path.join(p, "models"))
bg.write_tex(png, os.path.join(p, "materials", "arm.tex"))
json.dump({"clampuvs": True, "format": "rgba8888", "nomip": True, "nonpoweroftwo": True}, open(os.path.join(p, "materials", "arm.tex-json"), "w"))
json.dump({"passes": [{"blending": "translucent", "cullmode": "nocull", "depthtest": "disabled", "depthwrite": "disabled",
                       "shader": "genericimage2", "textures": ["arm"]}]}, open(os.path.join(p, "materials", "arm.json"), "w"), indent=1)
json.dump({"autosize": True, "material": "materials/arm.json"}, open(os.path.join(p, "models", "arm.json"), "w"), indent=1)
scene = {"camera": {"center": "0 0 -1", "eye": "0 0 0", "up": "0 1 0"},
         "general": {"clearcolor": "0.15 0.15 0.15", "ambientcolor": "0.3 0.3 0.3", "skylightcolor": "0.3 0.3 0.3",
                     "orthogonalprojection": {"width": 1920, "height": 1080}},
         "objects": [{"id": 10, "name": "arm", "image": "models/arm.json", "origin": "960 540 0", "angles": "0 0 0",
                      "scale": "1 1 1", "size": "512 256", "visible": True}]}
json.dump(scene, open(os.path.join(p, "scene.json"), "w"), indent=1)
json.dump({"file": "scene.json", "title": name, "type": "scene", "general": {"properties": {}}}, open(os.path.join(p, "project.json"), "w"), indent=1)
print(p)
