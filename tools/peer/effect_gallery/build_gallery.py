"""Build one WE scene project per built-in effect: checkerboard (left) + gradient (right),
each layer carrying the effect with NO values, so WE falls back to shader defaults."""
import json, os, shutil, struct, sys
from PIL import Image

WE = r"C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine"
ASSETS = os.path.join(WE, "assets", "effects")
OUT = os.path.join(WE, "projects", "myprojects")
IMGS = {"checkerboard": r"K:\DeepWorkspace\effect-gallery-assets\checkerboard_1024.png",
        "gradient": r"K:\DeepWorkspace\effect-gallery-assets\gradient_1024.png"}


def write_tex(png, path):
    """Uncompressed RGBA8888 .tex, same layout as assets/effects/*/preview/materials/effectpreview.tex."""
    im = Image.open(png).convert("RGBA")
    w, h = im.size
    data = im.tobytes()
    with open(path, "wb") as f:
        f.write(b"TEXV0005\0TEXI0001\0")
        f.write(struct.pack("<7i", 0, 2, w, h, w, h, 0))  # format, flags, tex w/h, image w/h, unk
        f.write(b"TEXB0001\0")
        f.write(struct.pack("<4i", 1, 1, w, h))  # image count, mip count, mip w/h
        f.write(struct.pack("<i", len(data)))
        f.write(data)


def build(effect):
    name = "fxgal_" + effect.lstrip("_")
    d = os.path.join(OUT, name)
    if os.path.exists(d):
        shutil.rmtree(d)
    os.makedirs(os.path.join(d, "materials"))
    os.makedirs(os.path.join(d, "models"))
    objs = []
    for i, (key, png) in enumerate(IMGS.items()):
        write_tex(png, os.path.join(d, "materials", key + ".tex"))
        json.dump({"clampuvs": True, "format": "rgba8888", "nomip": True, "nonpoweroftwo": True},
                  open(os.path.join(d, "materials", key + ".tex-json"), "w"))
        json.dump({"passes": [{"blending": "translucent", "cullmode": "nocull", "depthtest": "disabled",
                               "depthwrite": "disabled", "shader": "genericimage2", "textures": [key]}]},
                  open(os.path.join(d, "materials", key + ".json"), "w"), indent=1)
        json.dump({"autosize": True, "material": "materials/%s.json" % key},
                  open(os.path.join(d, "models", key + ".json"), "w"), indent=1)
        fx = [] if effect == "_none" else [{"file": "effects/%s/effect.json" % effect}]
        objs.append({"id": 10 + i, "name": key, "image": "models/%s.json" % key,
                     "origin": "%d 540 0" % (480 + 960 * i), "angles": "0 0 0",
                     "scale": "0.85 0.85 1", "size": "1024 1024", "visible": True, "effects": fx})
    if effect != "_none":
        src = os.path.join(ASSETS, effect)
        os.makedirs(os.path.join(d, "effects", effect))
        shutil.copy(os.path.join(src, "effect.json"), os.path.join(d, "effects", effect))
        for sub in os.listdir(src):
            p = os.path.join(src, sub)
            if os.path.isdir(p) and sub != "preview":
                shutil.copytree(p, os.path.join(d, sub), dirs_exist_ok=True)
    scene = {"camera": {"center": "0 0 -1", "eye": "0 0 0", "up": "0 1 0"},
             "general": {"clearcolor": "0.15 0.15 0.15", "ambientcolor": "0.3 0.3 0.3",
                         "skylightcolor": "0.3 0.3 0.3",
                         "orthogonalprojection": {"width": 1920, "height": 1080}},
             "objects": objs}
    json.dump(scene, open(os.path.join(d, "scene.json"), "w"), indent=1)
    json.dump({"file": "scene.json", "title": name, "type": "scene", "general": {"properties": {}}},
              open(os.path.join(d, "project.json"), "w"), indent=1)
    return name


BLANK = os.path.join(OUT, "effecttest-blank")  # user's editor-made base: black solid + both images at scale 1


def build_from_blank(effect):
    """Copy the user's EffectTest-Blank and add the bare effect to both image layers."""
    name = "fxgal_" + effect.lstrip("_")
    d = os.path.join(OUT, name)
    if os.path.exists(d):
        shutil.rmtree(d)
    shutil.copytree(BLANK, d, ignore=shutil.ignore_patterns("effects", "preview.*"))
    scene = json.load(open(os.path.join(d, "scene.json")))
    for o in scene["objects"]:
        if o.get("image", "").startswith("models/util/"):
            continue
        o["effects"] = [] if effect == "_none" else [{"file": "effects/%s/effect.json" % effect}]
    json.dump(scene, open(os.path.join(d, "scene.json"), "w"), indent=1)
    if effect != "_none":
        src = os.path.join(ASSETS, effect)
        os.makedirs(os.path.join(d, "effects", effect), exist_ok=True)
        shutil.copy(os.path.join(src, "effect.json"), os.path.join(d, "effects", effect))
        for sub in os.listdir(src):
            p = os.path.join(src, sub)
            if os.path.isdir(p) and sub != "preview":
                shutil.copytree(p, os.path.join(d, sub), dirs_exist_ok=True)
    proj = json.load(open(os.path.join(d, "project.json")))
    proj["title"] = name
    json.dump(proj, open(os.path.join(d, "project.json"), "w"), indent=1)
    return name


def restore_tex(projects_dir, assets_dir):
    """The committed projects omit the 4 MB .tex files; regenerate them from assets/*.png."""
    for p in sorted(os.listdir(projects_dir)):
        if p.startswith("fxgal_"):
            for key in IMGS:
                write_tex(os.path.join(assets_dir, key + "_1024.png"),
                          os.path.join(projects_dir, p, "materials", key + ".tex"))


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "--restore-tex":  # build_gallery.py --restore-tex <projects> <assets>
        restore_tex(sys.argv[2], sys.argv[3])
        sys.exit()
    effects = ["_none"] + sorted(e for e in os.listdir(ASSETS) if e != "_empty")
    for e in effects:
        print(build(e))  # generated layout (scale 0.85, gap between images); build_from_blank kept as an alternative
