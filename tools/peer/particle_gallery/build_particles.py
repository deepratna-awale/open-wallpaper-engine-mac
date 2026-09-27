"""One WE project per built-in preset variant (assets/presets/*/preset.json), at defaults, emitter at screen centre,
over a measurement background: near-black or 50% grey with a 100 px numbered grid + centre crosshair,
or a 32 px high-contrast pattern for refractive variants."""
import json, os, re, shutil, struct, sys
from PIL import Image, ImageDraw, ImageFont

WE = r"C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine"
PRESETS = os.path.join(WE, "assets", "presets")
OUT = os.path.join(WE, "projects", "myprojects")
HERE = os.path.dirname(os.path.abspath(__file__))
W, H, CX, CY = 1920, 1080, 960, 540
GREY_FOR = ("smoke", "fog")


def lenient(path):
    s = open(path, encoding="utf-8").read()
    s = re.sub(r",(\s*[}\]])", r"\1", s)
    return json.loads(s, strict=False)  # raw newlines inside embedded scripts


def make_backgrounds():
    os.makedirs(os.path.join(HERE, "assets"), exist_ok=True)
    font = ImageFont.truetype("arial.ttf", 14)
    for name, bg, line, txt in (("bg_black", 12, 45, 110), ("bg_grey", 128, 150, 200)):
        im = Image.new("RGB", (W, H), (bg,) * 3)
        d = ImageDraw.Draw(im)
        for x in range(0, W, 100):
            d.line([(x, 0), (x, H)], fill=(line,) * 3)
            d.text((x + 3, 3), str(x), fill=(txt,) * 3, font=font)
        for y in range(0, H, 100):
            d.line([(0, y), (W, y)], fill=(line,) * 3)
            d.text((3, y + 3), str(y), fill=(txt,) * 3, font=font)
        d.line([(CX - 30, CY), (CX + 30, CY)], fill=(255, 60, 60), width=2)
        d.line([(CX, CY - 30), (CX, CY + 30)], fill=(255, 60, 60), width=2)
        d.ellipse([CX - 6, CY - 6, CX + 6, CY + 6], outline=(255, 60, 60), width=2)
        im.save(os.path.join(HERE, "assets", name + ".png"))
    im = Image.new("RGB", (W, H))
    px = im.load()
    for y in range(H):
        for x in range(W):
            px[x, y] = (235, 235, 235) if ((x // 32) + (y // 32)) % 2 else (20, 20, 20)
    d = ImageDraw.Draw(im)
    d.polygon([(CX, CY - 200), (CX - 60, CY - 90), (CX + 60, CY - 90)], fill=(230, 30, 30))
    d.line([(CX - 30, CY), (CX + 30, CY)], fill=(255, 60, 60), width=3)
    d.line([(CX, CY - 30), (CX, CY + 30)], fill=(255, 60, 60), width=3)
    im.save(os.path.join(HERE, "assets", "bg_pattern.png"))


def write_tex(png, path):
    im = Image.open(png).convert("RGBA")
    w, h = im.size
    data = im.tobytes()
    with open(path, "wb") as f:
        f.write(b"TEXV0005\0TEXI0001\0")
        f.write(struct.pack("<7i", 0, 2, w, h, w, h, 0))
        f.write(b"TEXB0001\0")
        f.write(struct.pack("<5i", 1, 1, w, h, len(data)))
        f.write(data)


def offset(v, dx, dy):
    try:
        x, y, z = [float(t) for t in str(v).split()]
    except ValueError:
        return v
    return "%.3f %.3f %.3f" % (x + dx, y + dy, z)


def build(preset, idx, variant, bgname):
    name = "ptcl_%s_%d" % (preset, idx)
    d = os.path.join(OUT, name)
    if os.path.exists(d):
        shutil.rmtree(d)
    src = os.path.join(PRESETS, preset)
    shutil.copytree(src, d, ignore=shutil.ignore_patterns("preview*", "preset.json"))
    os.makedirs(os.path.join(d, "materials"), exist_ok=True)
    os.makedirs(os.path.join(d, "models"), exist_ok=True)
    write_tex(os.path.join(HERE, "assets", bgname + ".png"), os.path.join(d, "materials", "bg.tex"))
    json.dump({"clampuvs": True, "format": "rgba8888", "nomip": True, "nonpoweroftwo": True},
              open(os.path.join(d, "materials", "bg.tex-json"), "w"))
    json.dump({"passes": [{"blending": "translucent", "cullmode": "nocull", "depthtest": "disabled",
                           "depthwrite": "disabled", "shader": "genericimage2", "textures": ["bg"]}]},
              open(os.path.join(d, "materials", "bg.json"), "w"))
    json.dump({"autosize": True, "material": "materials/bg.json"}, open(os.path.join(d, "models", "bg.json"), "w"))
    objs = [{"id": 1, "name": "background", "image": "models/bg.json", "origin": "%d %d 0" % (CX, CY),
             "angles": "0 0 0", "scale": "1 1 1", "size": "%d %d" % (W, H), "visible": True}]
    for i, o in enumerate(variant.get("objects", [])):
        o = dict(o)
        o["id"] = 10 + i
        o["origin"] = offset(o.get("origin", "0 0 0"), CX, CY)  # editor drops presets at screen centre
        o.setdefault("visible", True)
        objs.append(o)
    scene = {"camera": {"center": "0 0 -1", "eye": "0 0 0", "up": "0 1 0"},
             "general": {"clearcolor": "0 0 0", "ambientcolor": "0.3 0.3 0.3", "skylightcolor": "0.3 0.3 0.3",
                         "orthogonalprojection": {"width": W, "height": H}},
             "objects": objs}
    json.dump(scene, open(os.path.join(d, "scene.json"), "w"), indent=1)
    json.dump({"file": "scene.json", "title": name, "type": "scene", "general": {"properties": {}}},
              open(os.path.join(d, "project.json"), "w"), indent=1)
    return name, bgname, [o.get("name", "") for o in variant.get("objects", [])]


if __name__ == "__main__":
    if not os.path.exists(os.path.join(HERE, "assets", "bg_black.png")):
        make_backgrounds()
    index = []
    for preset in sorted(os.listdir(PRESETS)):
        pj = lenient(os.path.join(PRESETS, preset, "preset.json"))
        for i, v in enumerate(pj.get("variants", [])):
            names = " ".join(o.get("name", "") for o in v.get("objects", [])).lower()
            bg = "bg_pattern" if "refract" in names else "bg_grey" if preset in GREY_FOR else "bg_black"
            index.append(build(preset, i, v, bg))
    json.dump(index, open(os.path.join(HERE, "index.json"), "w"), indent=1)
    print(len(index), "projects")

