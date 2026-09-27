"""Cursor capture request (docs/test-risks.md FX1): WE scene projects for x-ray, cursor ripple and
the fluid simulation with the cursor at known points, plus shots.json listing every capture.

Usage (on the Windows machine, like the effect gallery's build_gallery.py):
    python build_cursor_request.py --we "C:\\Program Files (x86)\\Steam\\steamapps\\common\\wallpaper_engine"
        [--out <WE>\\projects\\myprojects]
The same command on the Mac (with --out anywhere) regenerates the projects for our side.

Every project has one layer, gradient_1024.png (the effect gallery's hue gradient, 1024 px), over a
0.15 grey clear colour, bloom off (so the sprite's edge isn't smeared), and the effect at its
defaults ({"file": "effects/<name>/effect.json"}, no values). x-ray at its defaults draws its sprite
(particle/halo_6, 0.2 of the layer) in white wherever the pointer maps into the layer, so each still
shows where WE maps the cursor. Coordinates below are pixels on the captured 1920x1080 display, from
its top-left.
"""
import argparse, json, os, shutil, struct
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))

PARALLAX = {"cameraparallax": True, "cameraparallaxamount": 1.0, "cameraparallaxdelay": 0.1,
            "cameraparallaxmouseinfluence": 1.0}

# name: (effect, layer origin (scene units, y up), layer scale, angles (radians), general extras,
#        scene size, stills [(x, y) display px], sweep)
PROJECTS = {
    # The control: no effect.
    "curs_none": dict(effect=None, origin=(960, 540), scale=(0.85, 0.85), angle=0.0,
                      stills=[(960, 540)]),
    # The layer centred and scaled as in the gallery.
    "curs_xray_plain": dict(effect="xray", origin=(960, 540), scale=(0.85, 0.85), angle=0.0,
                            stills=[(960, 540), (700, 350), (1250, 760), (560, 540), (960, 180)]),
    # Moved, scaled unevenly and turned 30 degrees counter-clockwise.
    "curs_xray_moved": dict(effect="xray", origin=(1250, 620), scale=(0.6, 0.9), angle=0.5236,
                            stills=[(1250, 460), (1100, 340), (1400, 600), (1000, 520)]),
    # The orthographic camera zoomed in 1.5x (general.zoom).
    "curs_xray_zoom": dict(effect="xray", origin=(960, 540), scale=(0.85, 0.85), angle=0.0,
                           general={"zoom": 1.5}, stills=[(960, 540), (1200, 700), (700, 380)]),
    # A 4:3 scene (1920x1440) on the 16:9 display: WE covers it, cropping 180 px top and bottom.
    # Tells whether the pointer is normalised to the window or to the scene.
    "curs_xray_crop": dict(effect="xray", origin=(960, 720), scale=(0.85, 0.85), angle=0.0,
                           scene=(1920, 1440), stills=[(960, 540), (1200, 800), (700, 250)]),
    # Camera parallax on (amount 1, delay 0.1, mouse influence 1), the layer at depth 1. The layer
    # moves with the cursor, so its control is the same scene without the effect at the same points.
    "curs_xray_parallax": dict(effect="xray", origin=(960, 540), scale=(0.85, 0.85), angle=0.0,
                               general=PARALLAX, stills=[(960, 540), (1100, 620), (840, 460)],
                               control="curs_parallax_none"),
    "curs_parallax_none": dict(effect=None, origin=(960, 540), scale=(0.85, 0.85), angle=0.0,
                               general=PARALLAX, stills=[(960, 540), (1100, 620), (840, 460)]),
    # A horizontal sweep through the layer's centre: the ripple and the fluid's pointer force.
    "curs_ripple_sweep": dict(effect="cursorripple", origin=(960, 540), scale=(0.85, 0.85), angle=0.0,
                              stills=[], sweep=dict(start=(560, 540), end=(1360, 540), seconds=1.0)),
    "curs_fluid_sweep": dict(effect="fluidsimulation", origin=(960, 540), scale=(0.85, 0.85), angle=0.0,
                             stills=[], sweep=dict(start=(560, 540), end=(1360, 540), seconds=1.0)),
}


def write_tex(png, path):
    """Uncompressed RGBA8888 .tex, as the effect gallery's build_gallery.py writes it."""
    im = Image.open(png).convert("RGBA")
    w, h = im.size
    data = im.tobytes()
    with open(path, "wb") as f:
        f.write(b"TEXV0005\0TEXI0001\0")
        f.write(struct.pack("<7i", 0, 2, w, h, w, h, 0))
        f.write(b"TEXB0001\0")
        f.write(struct.pack("<4i", 1, 1, w, h))
        f.write(struct.pack("<i", len(data)))
        f.write(data)


def build(name, spec, effects_dir, out):
    d = os.path.join(out, name)
    if os.path.exists(d):
        shutil.rmtree(d)
    os.makedirs(os.path.join(d, "materials"))
    os.makedirs(os.path.join(d, "models"))
    write_tex(os.path.join(HERE, "gradient_1024.png"), os.path.join(d, "materials", "gradient.tex"))
    json.dump({"clampuvs": True, "format": "rgba8888", "nomip": True, "nonpoweroftwo": True},
              open(os.path.join(d, "materials", "gradient.tex-json"), "w"))
    json.dump({"passes": [{"blending": "translucent", "cullmode": "nocull", "depthtest": "disabled",
                           "depthwrite": "disabled", "shader": "genericimage2", "textures": ["gradient"]}]},
              open(os.path.join(d, "materials", "gradient.json"), "w"), indent=1)
    json.dump({"autosize": True, "material": "materials/gradient.json"},
              open(os.path.join(d, "models", "gradient.json"), "w"), indent=1)
    effect = spec["effect"]
    layer = {"id": 10, "name": "gradient", "image": "models/gradient.json",
             "origin": "%g %g 0" % spec["origin"], "angles": "0 0 %g" % spec["angle"],
             "scale": "%g %g 1" % spec["scale"], "size": "1024 1024", "visible": True,
             "parallaxDepth": "1 1",
             "effects": [{"file": "effects/%s/effect.json" % effect}] if effect else []}
    if effect:
        src = os.path.join(effects_dir, effect)
        os.makedirs(os.path.join(d, "effects", effect))
        shutil.copy(os.path.join(src, "effect.json"), os.path.join(d, "effects", effect))
        for sub in os.listdir(src):
            p = os.path.join(src, sub)
            if os.path.isdir(p) and sub != "preview":
                shutil.copytree(p, os.path.join(d, sub), dirs_exist_ok=True)
    width, height = spec.get("scene", (1920, 1080))
    general = {"clearcolor": "0.15 0.15 0.15", "ambientcolor": "0.3 0.3 0.3", "skylightcolor": "0.3 0.3 0.3",
               "bloom": False, "orthogonalprojection": {"width": width, "height": height}}
    general.update(spec.get("general", {}))
    scene = {"camera": {"center": "0 0 -1", "eye": "0 0 0", "up": "0 1 0"}, "general": general, "objects": [layer]}
    json.dump(scene, open(os.path.join(d, "scene.json"), "w"), indent=1)
    json.dump({"file": "scene.json", "title": name, "type": "scene", "general": {"properties": {}}},
              open(os.path.join(d, "project.json"), "w"), indent=1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--we", required=True, help="the wallpaper_engine install folder")
    parser.add_argument("--out", help="where the projects go (default <we>/projects/myprojects)")
    args = parser.parse_args()
    out = args.out or os.path.join(args.we, "projects", "myprojects")
    os.makedirs(out, exist_ok=True)
    for name, spec in PROJECTS.items():
        build(name, spec, os.path.join(args.we, "assets", "effects"), out)
        print(name)
    shots = [{"project": name, "stills": [list(p) for p in spec["stills"]], "sweep": spec.get("sweep"),
              "control": spec.get("control")}
             for name, spec in PROJECTS.items()]
    json.dump(shots, open(os.path.join(HERE, "shots.json"), "w"), indent=1)


if __name__ == "__main__":
    main()
