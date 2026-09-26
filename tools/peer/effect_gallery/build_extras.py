"""Generate the remaining 'editor items' as WE projects without the editor.
Each project reuses the gallery layout (checkerboard left, gradient right, 1920x1080) from build_gallery.py."""
import copy, json, os, shutil
import build_gallery as bg

WE, OUT = bg.WE, bg.OUT
ASSETS = os.path.join(WE, "assets")


def base(name):
    """Start from the generated control project and return (dir, scene)."""
    src = os.path.join(OUT, "fxgal_none")
    d = os.path.join(OUT, "fxx_" + name)
    if os.path.exists(d):
        shutil.rmtree(d)
    shutil.copytree(src, d)
    scene = json.load(open(os.path.join(d, "scene.json")))
    return d, scene


def save(d, scene, name):
    json.dump(scene, open(os.path.join(d, "scene.json"), "w"), indent=1)
    json.dump({"file": "scene.json", "title": "fxx_" + name, "type": "scene", "general": {"properties": {}}},
              open(os.path.join(d, "project.json"), "w"), indent=1)


def copy_effect(d, effect):
    src = os.path.join(ASSETS, "effects", effect)
    os.makedirs(os.path.join(d, "effects", effect), exist_ok=True)
    shutil.copy(os.path.join(src, "effect.json"), os.path.join(d, "effects", effect))
    for sub in os.listdir(src):
        if os.path.isdir(os.path.join(src, sub)) and sub != "preview":
            shutil.copytree(os.path.join(src, sub), os.path.join(d, sub), dirs_exist_ok=True)


def composite():
    """Item 2: blur is the only effect with the COMPOSITE combo (Normal/Blend/Under/Cutout)."""
    variants = [("normal", 0, None), ("blend_a0.5", 1, 0.5), ("blend_a1.5", 1, 1.5), ("under", 2, None), ("cutout", 3, None)]
    for tag, combo, alpha in variants:
        d, scene = base("composite_" + tag)
        copy_effect(d, "blur")
        for o in scene["objects"]:
            p = {"combos": {"COMPOSITE": combo}}
            if alpha is not None:
                p["constantshadervalues"] = {"compositealpha": alpha}
            o["effects"] = [{"file": "effects/blur/effect.json", "passes": [{}, {}, {}, p]}]  # COMPOSITE lives in pass 4 (blur_combine)
        save(d, scene, "composite_" + tag)


BLENDS = {0: "normal", 2: "multiply", 7: "screen", 9: "lineardodge", 11: "overlay", 18: "difference", 31: "add_native"}


def solid_blends():
    """Item 3: a coloured solid band (on top) across both images, one project per colorBlendMode."""
    for mode, tag in BLENDS.items():
        d, scene = base("solidblend_%02d_%s" % (mode, tag))
        scene["objects"].append({"id": 50, "name": "solid band", "image": "models/util/solidlayer.json",
                                 "origin": "960 540 0", "size": "1920 300", "color": "0.2 0.6 1.0",
                                 "colorBlendMode": mode, "alpha": 1.0, "visible": True})
        save(d, scene, "solidblend_%02d_%s" % (mode, tag))


def key(frame, value, back=(-1, 0), front=(1, 0)):
    return {"frame": frame, "value": value, "lockangle": True, "locklength": True,
            "back": {"enabled": True, "x": back[0], "y": back[1]},
            "front": {"enabled": True, "x": front[0], "y": front[1]}}


def timeline():
    """Item 4: animate the checkerboard's origin X (c0) +300 px over 60 frames at 30 fps.
    Variants: loop / mirror / single; plus a steep custom Bezier on loop."""
    variants = {
        "loop": ("loop", None),
        "mirror": ("mirror", None),
        "single": ("single", None),
        "loop_bezier": ("loop", ((-20, 0), (20, 250))),
    }
    for tag, (mode, handles) in variants.items():
        d, scene = base("timeline_" + tag)
        chk = scene["objects"][0]
        x, y, z = [float(v) for v in chk["origin"].split()]
        f = handles[1] if handles else (1, 0)
        b = handles[0] if handles else (-1, 0)
        anim = {"c0": [key(0, x, b, f), key(60, x + 300, b, f)],
                "c1": [key(0, y), key(60, y)], "c2": [key(0, z), key(60, z)],
                "options": {"fps": 30, "length": 60, "mode": mode, "wraploop": None}}
        chk["origin"] = {"value": chk["origin"], "animation": anim}
        save(d, scene, "timeline_" + tag)


def text_effects():
    """Item 8: same text with each font effect (field names from wallpaper64.exe strings)."""
    font_src = os.path.join(ASSETS, "fonts", "NotoSans-Regular.ttf")
    variants = {
        "plain_msdf": {"msdf": True},
        "plain_nomsdf": {"msdf": False},
        "outline": {"outline": True, "outlinethickness": 4, "outlinecolor": "0 0 0"},
        "blur": {"blur": True, "blursize": 1},
        "dropshadow": {"dropshadow": True, "dropshadowsize": 6, "dropshadowopacity": 1,
                       "dropshadowoffset": "4 4", "dropshadowcolor": "0 0 0"},
        "defaults_only": {"outline": True, "blur": True, "dropshadow": True},  # values left to WE defaults
    }
    for tag, extra in variants.items():
        d, scene = base("text_" + tag)
        os.makedirs(os.path.join(d, "fonts"), exist_ok=True)
        shutil.copy(font_src, os.path.join(d, "fonts"))
        t = {"id": 60, "name": "text", "text": {"value": "WE Text 123"}, "font": "fonts/NotoSans-Regular.ttf",
             "pointsize": 64, "color": "1 0.85 0.2", "origin": "960 540 0", "size": "1400 300",
             "horizontalalign": "center", "verticalalign": "center", "anchor": "center",
             "padding": 32, "visible": True}
        t.update(extra)
        scene["objects"].append(t)
        save(d, scene, "text_" + tag)


def refraction():
    """Item 10a: a few large, slow refractive drops over the checkerboard (rain refractive preset, enlarged)."""
    d, scene = base("refraction_bigdrops")
    pr = os.path.join(ASSETS, "presets", "rain")
    for sub in ("materials", "particles"):
        shutil.copytree(os.path.join(pr, sub), os.path.join(d, sub), dirs_exist_ok=True)
    p = json.load(open(os.path.join(d, "particles", "presets", "rainrefractive.json")))
    p["emitter"] = [{"id": 7, "name": "boxrandom", "origin": "0 0 0", "distancemax": "700 350 0",
                     "directions": "1 1 0", "rate": 2}]
    p["initializer"] = [{"id": 2, "name": "lifetimerandom", "min": 30, "max": 30},
                        {"id": 3, "name": "sizerandom", "min": 220, "max": 220},
                        {"id": 5, "name": "colorrandom", "min": "255 255 255"},
                        {"id": 6, "name": "alpharandom", "min": 1, "max": 1}]
    p["operator"] = []
    p["renderer"] = [{"id": 1, "name": "sprite"}]
    p["maxcount"] = 8
    json.dump(p, open(os.path.join(d, "particles", "presets", "bigdrops.json"), "w"), indent=1)
    scene["objects"].append({"id": 70, "name": "big drops", "particle": "particles/presets/bigdrops.json",
                             "origin": "960 540 0", "angles": "0 0 0", "scale": "1 1 1", "visible": True})
    save(d, scene, "refraction_bigdrops")


if __name__ == "__main__":
    for fn in (composite, solid_blends, timeline, text_effects, refraction):
        fn()
    print("\n".join(sorted(p for p in os.listdir(OUT) if p.startswith("fxx_"))))

