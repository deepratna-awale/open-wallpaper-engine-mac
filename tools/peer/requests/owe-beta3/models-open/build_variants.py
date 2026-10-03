"""Builds the scene.json-only test projects for models-plan §5 open points (prefix mo_) into WE's myprojects."""
import copy, json, os, shutil

M = r"C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine\projects\myprojects"
ORTHO, BOX, ROPE = os.path.join(M, "curs_none"), os.path.join(M, "owe_zoombox1"), os.path.join(M, "bp_rope_A")

def make(name, base, edit):
    d = os.path.join(M, name)
    if os.path.exists(d): shutil.rmtree(d)
    shutil.copytree(base, d, ignore=shutil.ignore_patterns("shaders"))
    s = json.load(open(os.path.join(d, "scene.json"), encoding="utf-8"))
    edit(s, d)
    json.dump(s, open(os.path.join(d, "scene.json"), "w", encoding="utf-8"), indent=1)
    p = json.load(open(os.path.join(d, "project.json"), encoding="utf-8")); p["title"] = name
    json.dump(p, open(os.path.join(d, "project.json"), "w", encoding="utf-8"), indent=1)
    print(name)

def img(s): return s["objects"][0]
def model(s): return [o for o in s["objects"] if o.get("model")][0]
def rope(s): return [o for o in s["objects"] if o.get("name") == "rope"][0]

# 5.13 root image without origin
make("mo_513_noorigin", ORTHO, lambda s, d: img(s).pop("origin"))
make("mo_513_control", ORTHO, lambda s, d: None)
# 5.14 two-number scale
make("mo_514_img_scale2", ORTHO, lambda s, d: img(s).update(scale="0.5 0.5"))
make("mo_514_img_scale3", ORTHO, lambda s, d: img(s).update(scale="0.5 0.5 1"))
make("mo_514_box_scale2", BOX, lambda s, d: model(s).update(scale="0.02 0.02"))
make("mo_514_box_scale3", BOX, lambda s, d: model(s).update(scale="0.02 0.02 0.02"))
make("mo_514_box_scale3z0", BOX, lambda s, d: model(s).update(scale="0.02 0.02 0"))
make("mo_514_box_scale3z1", BOX, lambda s, d: model(s).update(scale="0.02 0.02 1"))
# 5.19 ortho zoom 2
make("mo_519_orthozoom2", ORTHO, lambda s, d: s["general"].update(zoom=2.0))
# 5.18 model alpha fade
for a in ("0.5", "0.05", "0.01", "0.004", "0"):
    make("mo_518_alpha_" + a.replace(".", "p"), BOX, lambda s, d, a=a: model(s).update(alpha=float(a)))
# 5.17 puppet cull winding (rope puppet, script removed, material cull normal)
def cull(flip):
    def e(s, d):
        r = rope(s); r["origin"] = "960 540 0"; r["scale"] = ("-1 1 1" if flip else "1 1 1")
        mp = os.path.join(d, "materials", "rope.json"); mat = json.load(open(mp))
        mat["passes"][0]["cullmode"] = "normal"; json.dump(mat, open(mp, "w"), indent=1)
    return e
make("mo_517_cull_normal", ROPE, cull(False))
make("mo_517_cull_normal_flipx", ROPE, cull(True))
# 5.16 nested tilt in ortho: parent tilted x 30, child with its own tilt and origin z
def tilt(s, d):
    p = img(s); p["angles"] = "30 0 0"; p["origin"] = "700 540 0"
    c = copy.deepcopy(p); c["id"] = 11; c["name"] = "child"; c["parent"] = 10
    c["origin"] = "500 0 200"; c["angles"] = "0 30 0"; c["scale"] = "0.5 0.5 1"
    s["objects"].append(c)
make("mo_516_nested_tilt", ORTHO, tilt)
def tilt_flat(s, d):
    p = img(s); p["origin"] = "700 540 0"
    c = copy.deepcopy(p); c["id"] = 11; c["name"] = "child"; c["parent"] = 10
    c["origin"] = "500 0 0"; c["scale"] = "0.5 0.5 1"; s["objects"].append(c)
make("mo_516_nested_flat", ORTHO, tilt_flat)
