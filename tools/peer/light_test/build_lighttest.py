"""2D light matrix: image LIGHTING combo x light castshadow x general.lightconfig, to see what actually lights an image."""
import json, os, shutil, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "effect_gallery"))
import build_gallery as bg

OUT = bg.OUT
CHECKER = bg.IMGS["checkerboard"]
VARIANTS = [  # name, image LIGHTING combo, light castshadow, lightconfig (None = omit), add light?
    ("control_nolight_lit1", 1, None, None, False),
    ("lit1_cs0_cfgP1", 1, False, {"point": 1}, True),
    ("lit1_cs1_cfgP1S1", 1, True, {"point": 1, "pointshadow": 1}, True),
    ("lit1_cs1_cfgP1", 1, True, {"point": 1}, True),
    ("lit1_cs0_nocfg", 1, False, None, True),
    ("lit1_cs1_nocfg", 1, True, None, True),
    ("lit0_cs0_cfgP1", 0, False, {"point": 1}, True),
    ("lit0_cs1_cfgP1S1", 0, True, {"point": 1, "pointshadow": 1}, True),
]

for name, lit, cs, cfg, has_light in VARIANTS:
    d = os.path.join(OUT, "lt_" + name)
    if os.path.exists(d):
        shutil.rmtree(d)
    os.makedirs(os.path.join(d, "materials"))
    os.makedirs(os.path.join(d, "models"))
    bg.write_tex(CHECKER, os.path.join(d, "materials", "checker.tex"))
    json.dump({"clampuvs": True, "format": "rgba8888", "nomip": True, "nonpoweroftwo": True},
              open(os.path.join(d, "materials", "checker.tex-json"), "w"))
    json.dump({"passes": [{"blending": "translucent", "cullmode": "nocull", "depthtest": "disabled",
                           "depthwrite": "disabled", "shader": "genericimage4", "combos": {"LIGHTING": lit},
                           "textures": ["checker"]}]},
              open(os.path.join(d, "materials", "checker.json"), "w"), indent=1)
    json.dump({"autosize": True, "material": "materials/checker.json"}, open(os.path.join(d, "models", "checker.json"), "w"))
    objs = [{"id": 10, "name": "checker", "image": "models/checker.json", "origin": "960 540 0", "angles": "0 0 0",
             "scale": "1 1 1", "size": "1024 1024", "visible": True}]
    if has_light:
        objs.append({"id": 20, "name": "point", "light": "lpoint", "origin": "700 700 200", "angles": "0 0 0",
                     "color": "1 0.3 0.3", "intensity": 5.0, "radius": 600.0, "exponent": 2.0, "density": 2.0,
                     "volumetricsexponent": 1.0, "castshadow": cs, "visible": True})
    general = {"clearcolor": "0.15 0.15 0.15", "ambientcolor": "0.3 0.3 0.3", "skylightcolor": "0.3 0.3 0.3",
               "orthogonalprojection": {"width": 1920, "height": 1080}}
    if cfg is not None:
        general["lightconfig"] = cfg
    json.dump({"camera": {"center": "0 0 -1", "eye": "0 0 0", "up": "0 1 0"}, "general": general, "objects": objs},
              open(os.path.join(d, "scene.json"), "w"), indent=1)
    json.dump({"file": "scene.json", "title": "lt_" + name, "type": "scene", "general": {"properties": {}}},
              open(os.path.join(d, "project.json"), "w"), indent=1)
    print("lt_" + name)
