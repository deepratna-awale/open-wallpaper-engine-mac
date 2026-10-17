"""537 text variants from the editor-saved p537_text text layer (editor_scene.json): letter spacing 0/5/20 without background,
and opaque background colour 0.2 0.4 0.8 at padding 0/20 and layer alpha 1/0.5. The bars image layer is dropped."""
import json, os, shutil, copy
M = r"C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine\projects\myprojects"
H = os.path.dirname(os.path.abspath(__file__))
base = json.load(open(os.path.join(H, "editor_scene.json"), encoding="utf-8"))
V = {"sp0": {"spacing": "0 0"}, "sp5": {"spacing": "5 5"}, "sp20": {"spacing": "20 20"}}
for pad in (0, 20):
    for a in (1.0, 0.5):
        V["bg_pad%d_a%s" % (pad, str(a).replace(".", ""))] = {"opaquebackground": True, "backgroundcolor": "0.2 0.4 0.8",
                                                              "padding": "%d %d" % (pad, pad), "spacing": "0 0", "alpha": a}
for name, ch in V.items():
    d = os.path.join(M, "p537_" + name)
    if os.path.exists(d): shutil.rmtree(d)
    shutil.copytree(os.path.join(M, "p537_text"), d, ignore=shutil.ignore_patterns("shaders"))
    s = copy.deepcopy(base)
    s["objects"] = [o for o in s["objects"] if "text" in o]
    t = s["objects"][0]; t["opaquebackground"] = False; t.update(ch)
    json.dump(s, open(os.path.join(d, "scene.json"), "w", encoding="utf-8"), indent=1)
    json.dump(s, open(os.path.join(H, "scene_%s.json" % name), "w", encoding="utf-8"), indent=1)
    p = json.load(open(os.path.join(d, "project.json"), encoding="utf-8")); p["title"] = "p537_" + name
    json.dump(p, open(os.path.join(d, "project.json"), "w", encoding="utf-8"), indent=1)
    print(name, json.dumps(ch))
