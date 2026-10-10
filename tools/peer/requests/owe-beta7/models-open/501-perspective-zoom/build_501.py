"""Writes the 501 projects: a perspective scene with three unit cubes at different depths on a floor grid,
seen through a camera layer whose static zoom, or whose path's zoom or fov, varies.

    python build_501.py [--out DIR]      # default: ./projects next to this script

Plain Python 3, no packages. The models are static MDLV0013 meshes (position, normal, uv), the same layout
as models-gt's gt_red_cube.mdl, which WE 2.8.0.42 loaded (MG6). Every material is generic4 unlit
(LIGHTING 0, FOG 0) on util/white, so each object is one flat colour. It also prints where each cube's
centre lands on a 1920x1080 frame, at zoom 1 and as an FOV-like 2x zoom would put it.
"""
import argparse, copy, json, math, os, struct

HERE = os.path.dirname(os.path.abspath(__file__))
W, H = 1920, 1080
EYE = (0.0, 1.0, 10.0)          # the camera layer's origin; it looks down -Z, angles 0
SCENE_EYE = (0.0, 1.0, 14.0)    # the scene's camera block: 4 units further back, so a frame that
                                # ignores the layer is visibly smaller
CUBES = [('red', '1 0 0', (-2.0, 0.5, 0.0)), ('green', '0 0.8 0', (0.0, 0.5, -5.0)), ('blue', '0 0 1', (2.0, 0.5, -15.0))]
FOV_FOR_ZOOM2 = 2 * math.degrees(math.atan(math.tan(math.radians(25)) / 2))   # 26.2505


# ---------------------------------------------------------------- .mdl
def cstr(s): return s.encode() + b'\0'
def blob(b): return struct.pack('<I', len(b)) + b


def mesh_bytes(material, quads):
    """quads: lists of 4 corners (x, y, z) with a normal; two triangles each."""
    verts, idx = bytearray(), []
    for corners, n in quads:
        base = len(verts) // 32
        for (x, y, z), (u, v) in zip(corners, ((0, 0), (1, 0), (1, 1), (0, 1))):
            verts += struct.pack('<8f', x, y, z, *n, u, v)
        idx += [base, base + 1, base + 2, base, base + 2, base + 3]
    return cstr(material) + struct.pack('<I', 0) + blob(bytes(verts)) + blob(struct.pack('<%dH' % len(idx), *idx))


def mdl(meshes):
    """MDLV0013, legacy format 0xb (position, normal, uv; stride 32), one material per mesh, no sections."""
    out = cstr('MDLV0013') + struct.pack('<III', 0xb, 1, len(meshes))
    for material, quads in meshes:
        out += mesh_bytes(material, quads)
    return out + b'\0'                       # the empty tag that ends the section loop


def cube_quads(h=0.5):
    q = []
    for axis in range(3):
        for sign in (-1, 1):
            n = [0, 0, 0]; n[axis] = sign
            a, b = [k for k in range(3) if k != axis]
            corners = []
            for da, db in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                p = [0.0, 0.0, 0.0]; p[axis] = sign * h; p[a] = da * h; p[b] = db * h
                corners.append(tuple(p))
            q.append((corners, tuple(n)))
    return q


def grid_quads(major):
    """Floor lines on y = 0: x = -10..10 and z = -30..5 every unit; major = every 5th (the axes included)."""
    q, w, up = [], 0.02 if not major else 0.04, (0, 1, 0)
    for x in range(-10, 11):
        if (x % 5 == 0) == major:
            q.append(([(x - w, 0, 5), (x + w, 0, 5), (x + w, 0, -30), (x - w, 0, -30)], up))
    for z in range(-30, 6):
        if (z % 5 == 0) == major:
            q.append(([(-10, 0, z + w), (10, 0, z + w), (10, 0, z - w), (-10, 0, z - w)], up))
    return q


def material(color):
    return {"passes": [{"shader": "generic4", "combos": {"LIGHTING": 0, "FOG": 0}, "cullmode": "nocull",
                        "depthtest": "enabled", "depthwrite": "enabled",
                        "constantshadervalues": {"color": color}, "textures": ["util/white"]}]}


# ---------------------------------------------------------------- scene
def vec(v): return '%.5f %.5f %.5f' % v


def general():
    return {"ambientcolor": "0.30000 0.30000 0.30000", "bloom": False, "camerafade": False, "cameraparallax": False,
            "camerashake": False, "clearcolor": "0.85000 0.85000 0.85000", "clearenabled": True, "farz": 10000.0,
            "fov": 50.0, "hdr": False, "nearz": 0.1, "orthogonalprojection": None,
            "skylightcolor": "0.30000 0.30000 0.30000", "transparentsorting": False, "zoom": 1.0}


def objects():
    objs = [{"id": 10, "name": "grid", "model": "models/p501_grid.mdl", "origin": "0 0 0", "scale": "1 1 1", "solid": True}]
    for i, (name, _, pos) in enumerate(CUBES):
        objs.append({"id": 11 + i, "name": name + " cube", "model": "models/p501_%s.mdl" % name, "origin": vec(pos),
                     "scale": "1 1 1", "solid": True})
    return objs


def camera_layer(zoom=1.0, fov=50.0, path=None):
    o = {"angles": "0.00000 0.00000 0.00000", "camera": "default", "disablepropagation": False, "fov": fov, "id": 950,
         "name": "Probe Cam", "origin": vec(EYE), "queuemode": "random", "solid": True, "zoom": zoom,
         "visible": {"value": True}}
    if path:
        o["path"] = path
    return o


def key(frame, value):
    """An editor-written key, as in 519b's editor-made path (magic handles)."""
    return {"back": {"enabled": True, "magic": True, "x": -1, "y": -0.0}, "frame": frame,
            "front": {"enabled": True, "magic": True, "x": 1, "y": 0}, "lockangle": True, "locklength": True, "value": value}


def channel(values):
    return {"c%d" % i: [key(f, v) for f in (0, 30, 60)] for i, v in enumerate(values)}


def path_file(zoom=None, fov=None):
    """One path, 60 frames at 30 fps, mode single, the layout of 519b's editor-made camera_paths_950.json.
    Eye and centre hold the layer's view (centre = eye - 5 * forward); zoom or fov goes 1 -> 2 -> 1 / 50 -> 26.25 -> 50."""
    p = {"center": channel((0, 1, 5)), "eye": channel(EYE), "id": 24, "name": "",
         "options": {"cameramode": "fly", "events": None, "fps": 30.0, "length": 60, "mode": "single", "wraploop": False},
         "visible": True, "fov": None, "zoom": None}
    if zoom:
        p["zoom"] = [key(f, v) for f, v in zip((0, 30, 60), zoom)]
    if fov:
        p["fov"] = [key(f, v) for f, v in zip((0, 30, 60), fov)]
    return {"paths": [p]}


VARIANTS = {
    # name: (layer kwargs, path file or None)
    "p501_layer_zoom1": (dict(zoom=1.0), None),
    "p501_layer_zoom2": (dict(zoom=2.0), None),
    "p501_layer_fov26": (dict(fov=round(FOV_FOR_ZOOM2, 4)), None),
    "p501_path_zoom": (dict(), path_file(zoom=(1.0, 2.0, 1.0))),
    "p501_path_fov": (dict(), path_file(fov=(50.0, round(FOV_FOR_ZOOM2, 4), 50.0))),
}


def write(out):
    files = {"models/p501_grid.mdl": mdl([("materials/p501_minor.json", grid_quads(False)),
                                          ("materials/p501_major.json", grid_quads(True))]),
             "materials/p501_minor.json": material("0.55 0.55 0.55"), "materials/p501_major.json": material("0.1 0.1 0.1")}
    for name, color, _ in CUBES:
        files["models/p501_%s.mdl" % name] = mdl([("materials/p501_%s.json" % name, cube_quads())])
        files["materials/p501_%s.json" % name] = material(color)
    for name, (layer, path) in VARIANTS.items():
        d = os.path.join(out, name)
        for rel, data in files.items():
            os.makedirs(os.path.dirname(os.path.join(d, rel)), exist_ok=True)
            with open(os.path.join(d, rel), 'wb') as f:
                f.write(data if isinstance(data, bytes) else json.dumps(data, indent=1).encode())
        if path:
            layer = dict(layer, path="scripts/camera_paths_950.json")
            os.makedirs(os.path.join(d, "scripts"), exist_ok=True)
            json.dump(path, open(os.path.join(d, "scripts", "camera_paths_950.json"), "w"), indent=1)
        scene = {"camera": {"center": "0.00000 1.00000 0.00000", "eye": vec(SCENE_EYE), "up": "0.00000 1.00000 0.00000"},
                 "general": general(), "objects": objects() + [camera_layer(**layer)], "version": 5}
        json.dump(scene, open(os.path.join(d, "scene.json"), "w"), indent=1)
        json.dump({"file": "scene.json", "general": {"properties": {"schemecolor": {"order": 0, "text": "ui_browse_properties_scheme_color",
                   "type": "color", "value": "0 0 0"}}}, "title": name, "type": "scene", "version": 0},
                  open(os.path.join(d, "project.json"), "w"), indent=1)
        print(name)


def project(p, eye, fov=50.0, zoom=1.0):
    t = math.tan(math.radians(fov) / 2) / zoom
    d = eye[2] - p[2]
    return (W / 2 + (p[0] - eye[0]) / d / (t * W / H) * W / 2, H / 2 - (p[1] - eye[1]) / d / t * H / 2)


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default=os.path.join(HERE, 'projects'))
    write(ap.parse_args().out)
    for name, _, pos in CUBES:
        print('%-5s layer eye zoom 1 (%.0f, %.0f)  FOV-like zoom 2 (%.0f, %.0f)  scene camera block (%.0f, %.0f)' % (
            (name,) + project(pos, EYE) + project(pos, EYE, zoom=2) + project(pos, SCENE_EYE)))
