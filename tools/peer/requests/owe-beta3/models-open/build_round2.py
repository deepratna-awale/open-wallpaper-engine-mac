"""Second batch of models-plan §5 probes (510, 511, 515, 518 translucent, 519b, 520, 522, 531b) as mo2_* projects."""
import copy, json, os, shutil

M = r"C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine\projects\myprojects"
P = r"K:\DeepWorkspace\wem-images2\tools\peer"
BOX = P + r"\models_gt\mg4\we_import_project"
ORTHO = P + r"\requests\cursor-effects\projects\curs_none"
ROPE = P + r"\requests\bone-physics\response\A\project"
LC = r"C:\Users\kskam\AppData\Local\Temp\claude\K--DeepWorkspace\b607b3e2-a426-4795-9cf0-764846af90dd\scratchpad\lc_orig\scene.json"
MAT = "materials/models/rootmotion_box/red.json"

def make(name, base, edit):
    d = os.path.join(M, name)
    if os.path.exists(d): shutil.rmtree(d)
    shutil.copytree(base, d, ignore=shutil.ignore_patterns("shaders", "*.fbx"))
    s = json.load(open(os.path.join(d, "scene.json"), encoding="utf-8"))
    edit(s, d)
    json.dump(s, open(os.path.join(d, "scene.json"), "w", encoding="utf-8"), indent=1)
    p = json.load(open(os.path.join(d, "project.json"), encoding="utf-8-sig")); p["title"] = name
    json.dump(p, open(os.path.join(d, "project.json"), "w", encoding="utf-8"), indent=1)
    print(name)

def box_setup(s):
    s["camera"] = {"center": "0 0.5 0", "eye": "3 2 3", "up": "0 1 0"}
    s["general"]["bloom"] = False
    m = [o for o in s["objects"] if o.get("model")][0]; m["scale"] = "0.01 0.01 0.01"; m.pop("animationlayers", None)
    return m

def edit_mat(d, fn):
    p = os.path.join(d, MAT); j = json.load(open(p)); fn(j["passes"][0]); json.dump(j, open(p, "w"), indent=1)

def key(f, v): return {"back": {"enabled": True, "x": -1, "y": 0}, "frame": f, "front": {"enabled": True, "x": 1, "y": 0}, "lockangle": True, "locklength": True, "value": v}
def track(pairs): return [key(f, v) for f, v in pairs]
def path(eye_x, cen_x, length=150, visible=True, mode="loop"):
    const = lambda v: track([(0, v), (length, v)])
    return {"paths": [{"center": {"c0": track(cen_x), "c1": const(0), "c2": const(-1)},
                       "eye": {"c0": track(eye_x), "c1": const(0), "c2": const(0)},
                       "up": {"c0": const(0), "c1": const(1), "c2": const(0)},
                       "fov": const(50), "id": 900, "name": "probe", "visible": visible, "zoom": None,
                       "options": {"cameramode": "fly", "events": None, "fps": 30.0, "length": length, "mode": mode, "wraploop": True}}]}

def cam_obj(d, pth, oid=950, extra=None):
    os.makedirs(os.path.join(d, "scripts"), exist_ok=True)
    fn = "scripts/camera_paths_%d.json" % oid
    json.dump(pth, open(os.path.join(d, fn), "w"), indent=1)
    o = {"camera": "default", "id": oid, "name": "Probe Cam", "origin": "0 0 0", "path": fn, "queuemode": "random", "solid": True, "visible": True, "zoom": 1.0}
    o.update(extra or {}); return o

# 518: translucent material, static object alpha
for a in ("1", "0.5", "0.1", "0.01", "0.001", "0"):
    def e(s, d, a=a):
        m = box_setup(s); m["alpha"] = float(a)
        edit_mat(d, lambda p: p.update(blending="translucent"))
    make("mo2_518_alpha_" + a.replace(".", "p"), BOX, e)

# 518b: translucent material, material Alpha constant
for a in ("0.5", "0.1", "0.01", "0.001", "0"):
    def e(s, d, a=a):
        box_setup(s)
        edit_mat(d, lambda p: (p.update(blending="translucent"), p.setdefault("constantshadervalues", {}).update(Alpha=float(a))))
    make("mo2_518m_matalpha_" + a.replace(".", "p"), BOX, e)

# 511: custom shader reading vertex colour + 2nd UV the mesh lacks
SH_V = """attribute vec3 a_Position;
attribute vec4 a_Color;
attribute vec2 a_TexCoordC1;
uniform mat4 g_ModelViewProjectionMatrix;
varying vec4 v_Color;
varying vec2 v_UV1;
void main() {
	gl_Position = mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix);
	v_Color = a_Color;
	v_UV1 = a_TexCoordC1;
}
"""
SH_F = """varying vec4 v_Color;
varying vec2 v_UV1;
void main() {
	gl_FragColor = vec4(v_Color.rgb + vec3(v_UV1, 0.0), 1.0);
}
"""
def e511(s, d):
    box_setup(s)
    os.makedirs(os.path.join(d, "shaders"), exist_ok=True)
    open(os.path.join(d, "shaders", "probe_missing.vert"), "w").write(SH_V)
    open(os.path.join(d, "shaders", "probe_missing.frag"), "w").write(SH_F)
    edit_mat(d, lambda p: (p.update(shader="probe_missing"), p.pop("constantshadervalues", None)))
make("mo2_511_missing_attr", BOX, e511)

# 510: text in a perspective scene behind the box, depthtest enabled vs disabled
lc = json.load(open(LC, encoding="utf-8"))
txt = copy.deepcopy([o for o in lc["objects"] if o.get("name") == "Clock 12"][0])
for k in list(txt):
    if isinstance(txt[k], dict) and "script" in txt[k]: txt[k] = txt[k].get("value", "")
for dt in ("enabled", "disabled"):
    def e(s, d, dt=dt):
        box_setup(s)
        t = copy.deepcopy(txt); t.update(id=500, name="probe text", text="DEPTH TEST", origin="-1.5 0.6 -1.5", angles="0 45 0",
                                         scale="0.004 0.004 0.004", parent=None, depthtest=dt, depthwrite="disabled", visible=True)
        t.pop("parent", None); s["objects"].append(t)
    make("mo2_510_text_depth_" + dt, BOX, e)

# 515: attachment chain on the rope puppet's tail bone
GRAD = json.load(open(os.path.join(ORTHO, "scene.json")))["objects"][0]
def e515(s, d):
    for f in os.listdir(os.path.join(ORTHO, "materials")): shutil.copy(os.path.join(ORTHO, "materials", f), os.path.join(d, "materials"))
    shutil.copy(os.path.join(ORTHO, "models", "gradient.json"), os.path.join(d, "models"))
    rope = [o for o in s["objects"] if o.get("name") == "rope"][0]
    if isinstance(rope.get("origin"), dict): rope["origin"] = rope["origin"]["value"]
    prev = rope["id"]
    for depth in range(1, 5):
        g = copy.deepcopy(GRAD); g.update(id=600 + depth, name="att depth %d" % depth, parent=prev, origin="1100 0 0" if depth > 1 else "0 0 0", scale="0.06 0.06 1" if depth == 1 else "1 1 1", angles="0 0 0")
        g.pop("parallaxDepth", None)
        if depth == 1: g["attachment"] = "tail"
        s["objects"].append(g); prev = g["id"]
make("mo2_515_attach_chain", ROPE, e515)

# 531b: puppet whose origin is script-written (x += 200 over 4 s) running as wallpaper
MOVE = """'use strict';
let t=0; export function update(value){ t+=engine.frametime; value.x = 760 + Math.min(t,4)*100; return value; }"""
def e531(s, d):
    rope = [o for o in s["objects"] if o.get("name") == "rope"][0]
    v = rope["origin"]["value"] if isinstance(rope.get("origin"), dict) else rope["origin"]
    rope["origin"] = {"script": MOVE, "scriptproperties": {}, "value": v}
make("mo2_531b_puppet_origin_script", ROPE, e531)

# 519b: ortho scene with a camera path panning eye/center x 0 -> 600 over 5 s
def e519(s, d):
    s["general"]["cameraparallax"] = False
    s["objects"].append(cam_obj(d, path([(0, 0), (150, 600)], [(0, 0), (150, 600)])))
make("mo2_519b_ortho_campath", ORTHO, e519)

# 520: camera layer with path + origin script writing x every frame
SCRIPT_X = """'use strict';
let t=0; export function update(value){ t+=engine.frametime; value.x = -400 * Math.min(t/5,1); return value; }"""
def e520(s, d):
    s["general"]["cameraparallax"] = False
    s["objects"].append(cam_obj(d, path([(0, 0), (150, 600)], [(0, 0), (150, 600)]),
                                extra={"origin": {"script": SCRIPT_X, "scriptproperties": {}, "value": "0 0 0"}}))
make("mo2_520_writeback_vs_script", ORTHO, e520)

# 522: two keys at the same frame; and a path with visible false
def e522a(s, d):
    s["general"]["cameraparallax"] = False
    s["objects"].append(cam_obj(d, path([(0, 0), (0, 500), (150, 0)], [(0, 0), (0, 500), (150, 0)])))
make("mo2_522_samekey", ORTHO, e522a)
def e522b(s, d):
    s["general"]["cameraparallax"] = False
    s["objects"].append(cam_obj(d, path([(0, 0), (150, 600)], [(0, 0), (150, 600)], visible=False)))
make("mo2_522_path_hidden", ORTHO, e522b)

# control for 519b/520/522: same camera-object format in the perspective box scene (eye x 3 -> -3)
def ectl(s, d):
    box_setup(s)
    p = path([(0, 3), (150, -3)], [(0, 0), (150, 0)])
    for k, v in (("c1", 2), ("c2", 3)):
        p["paths"][0]["eye"][k] = track([(0, v), (150, v)])
    p["paths"][0]["center"]["c1"] = track([(0, 0.5), (150, 0.5)]); p["paths"][0]["center"]["c2"] = track([(0, 0), (150, 0)])
    s["objects"].append(cam_obj(d, p))
make("mo2_ctl_persp_campath", BOX, ectl)
