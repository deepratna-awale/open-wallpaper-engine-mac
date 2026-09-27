"""Render tests for the audit session:
 D) child flags 0 vs 2 under an instance colour override (colorn red) + a periodic child emitter;
 E) remapvalue lifetimefraction->size, input 0-0.5 -> 0-1 (multiply), flags absent vs 1 (clamp input)."""
import json, os, shutil

WE = r"C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine"
OUT = os.path.join(WE, "projects", "myprojects")
HALO = os.path.join(WE, "assets", "scenes", "particleelementpreviews", "alphachange", "materials", "particle", "halo_1.json")


def project(name, systems, override=None):
    d = os.path.join(OUT, name)
    if os.path.exists(d): shutil.rmtree(d)
    os.makedirs(os.path.join(d, "particles")); os.makedirs(os.path.join(d, "materials", "particle"))
    shutil.copy(HALO, os.path.join(d, "materials", "particle", "halo_1.json"))
    for fn, js in systems.items():
        json.dump(js, open(os.path.join(d, "particles", fn), "w"), indent=1)
    obj = {"id": 10, "name": "ps", "particle": "particles/" + list(systems)[0], "origin": "960 540 0",
           "angles": "0 0 0", "scale": "1 1 1", "visible": True}
    if override: obj["instanceoverride"] = override
    scene = {"camera": {"center": "0 0 -1", "eye": "0 0 0", "up": "0 1 0"},
             "general": {"clearcolor": "0.05 0.05 0.05", "ambientcolor": "0.3 0.3 0.3", "skylightcolor": "0.3 0.3 0.3",
                         "orthogonalprojection": {"width": 1920, "height": 1080}}, "objects": [obj]}
    json.dump(scene, open(os.path.join(d, "scene.json"), "w"), indent=1)
    json.dump({"file": "scene.json", "title": name, "type": "scene", "general": {"properties": {}}},
              open(os.path.join(d, "project.json"), "w"), indent=1)
    print(name)


def system(emitter, size, extra_ops=(), children=None, origin="0 0 0", maxcount=500, lifetime=3):
    s = {"material": "materials/particle/halo_1.json", "maxcount": maxcount, "starttime": 0,
         "emitter": [dict(emitter, id=1, origin=origin)],
         "initializer": [{"id": 2, "name": "lifetimerandom", "min": lifetime, "max": lifetime},
                         {"id": 3, "name": "sizerandom", "min": size, "max": size},
                         {"id": 4, "name": "colorrandom", "min": "255 255 255", "max": "255 255 255"}],
         "operator": [{"id": 5, "name": "movement"}] + list(extra_ops),
         "renderer": [{"id": 6, "name": "sprite"}]}
    if children: s["children"] = children
    return s


# D) child flags
for flags in (0, 2):
    parent = system({"name": "sphererandom", "rate": 20, "distancemin": 0, "distancemax": 150}, 40, origin="-400 0 0",
                    children=[{"id": 20, "name": "particles/child.json", "type": "static", "flags": flags,
                               "origin": "800 0 0", "maxcount": 10, "probability": 1}])
    child = system({"name": "sphererandom", "rate": 60, "distancemin": 0, "distancemax": 150, "flags": 4,
                    "minperiodicduration": 0.5, "maxperiodicduration": 0.5, "minperiodicdelay": 1.0, "maxperiodicdelay": 1.0},
                   40, lifetime=0.6)
    project("pf_childflags_%d" % flags, {"parent.json": parent, "child.json": child}, override={"colorn": "1 0 0"})

# E) remap clamp
for tag, flags in (("absent", None), ("1", 1)):
    op = {"id": 7, "name": "remapvalue", "input": "lifetimefraction", "output": "size", "operation": "multiply",
          "inputrangemin": 0, "inputrangemax": 0.5, "outputrangemin": 0, "outputrangemax": 1}
    if flags is not None: op["flags"] = flags
    ps = system({"name": "boxrandom", "rate": 100, "distancemax": "900 480 0", "speedmin": 0, "speedmax": 0}, 60,
                extra_ops=[op], maxcount=300, lifetime=4)
    project("pf_remapclamp_%s" % tag, {"ps.json": ps})

# E2) sanity: does the remap operator act at all? none vs x5 output
for tag, op in (("none", None), ("x5", {"id": 7, "name": "remapvalue", "input": "lifetimefraction", "output": "size",
                                         "operation": "multiply", "inputrangemin": 0, "inputrangemax": 1,
                                         "outputrangemin": 1, "outputrangemax": 5})):
    ps = system({"name": "boxrandom", "rate": 100, "distancemax": "900 480 0", "speedmin": 0, "speedmax": 0}, 60,
                extra_ops=[op] if op else [], maxcount=300, lifetime=4)
    project("pf_remapsanity_%s" % tag, {"ps.json": ps})

# E3) explicit flags 0 (and 2) to see whether clamping can be switched off
for f in (0, 2):
    op = {"id": 7, "name": "remapvalue", "input": "lifetimefraction", "output": "size", "operation": "multiply",
          "inputrangemin": 0, "inputrangemax": 0.5, "outputrangemin": 0, "outputrangemax": 1, "flags": f}
    ps = system({"name": "boxrandom", "rate": 100, "distancemax": "900 480 0", "speedmin": 0, "speedmax": 0}, 60,
                extra_ops=[op], maxcount=300, lifetime=4)
    project("pf_remapclamp_f%d" % f, {"ps.json": ps})
