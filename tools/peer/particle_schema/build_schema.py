"""Merge editor-observed panels (UI Automation) with the file inventory into particle_fields.json."""
import json, os

D = os.path.dirname(os.path.abspath(__file__))
E = os.path.join(D, "editor_observed")
IDS = {  # editor display name -> component id (wallpaperui.exe / scene.json 'name')
    "Sprite": "sprite", "Sprite trail": "spritetrail", "Rope": "rope", "Rope trail": "ropetrail",
    "Sphere random": "sphererandom", "Box random": "boxrandom", "Layer image": "layerimage",
    "Lifetime random": "lifetimerandom", "Size random": "sizerandom", "Color random": "colorrandom",
    "HSV color random": "hsvcolorrandom", "Color list": "colorlist", "Alpha random": "alpharandom",
    "Velocity random": "velocityrandom", "Inherit control point velocity": "inheritcontrolpointvelocity",
    "Turbulent velocity random": "turbulentvelocityrandom", "Rotation random": "rotationrandom",
    "Position offset random": "positionoffsetrandom", "Angular velocity random": "angularvelocityrandom",
    "Position around control point": "mapsequencearoundcontrolpoint",
    "Position between control points": "mapsequencebetweencontrolpoints",
    "Remap initial value": "remapinitialvalue", "Inherit initial value from event": "inheritinitialvaluefromevent",
    "Movement": "movement", "Angular movement": "angularmovement", "Alpha fade": "alphafade",
    "Size change": "sizechange", "Color change": "colorchange", "Alpha change": "alphachange",
    "Oscillate position": "oscillateposition", "Oscillate alpha": "oscillatealpha", "Oscillate size": "oscillatesize",
    "Control point force": "controlpointattract", "Maintain distance to control point": "maintaindistancetocontrolpoint",
    "Maintain distance between control points": "maintaindistancebetweencontrolpoints",
    "Reduce movement near control point": "reducemovementnearcontrolpoint", "Turbulence": "turbulence",
    "Vortex": "vortex_v2", "Boids": "boids", "Cap velocity": "capvelocity", "Remap value": "remapvalue",
    "Inherit value from event": "inheritvaluefromevent", "Collision plane": "collisionplane",
    "Collision sphere": "collisionsphere", "Collision bounds": "collisionbounds",
    "Collision rectangle": "collisionquad", "Collision model": "collisionmodel",
}
SECT = {"renderers": "renderer", "emitters": "emitter", "initializers": "initializer", "operators": "operator"}
inv = json.load(open(os.path.join(D, "particle_fields_observed.json")))


def fields(rows):
    out, last = [], None
    rows = [rows] if isinstance(rows, dict) else (rows or [])
    for r in rows:
        r = dict(r)
        if "control" not in r: continue
        f = {"label": r.get("label"), "type": {"Spinner": "number", "Slider": "number", "CheckBox": "bool",
                                               "Combo": "combo"}.get(r["control"], r["control"])}
        if r["control"] in ("Slider", "Spinner"):
            if r["control"] == "Slider":  # slider carries the range; the following spinner carries the typed value
                f.update(slider_min=r.get("min"), slider_max=r.get("max"), add_default=r.get("value"))
                last = f; out.append(f); continue
            if last is not None and last["label"] == f["label"] and "slider_min" in last and "spinner" not in last:
                last["spinner"] = "typed value box has no range (UIA min=max=0) -> not clamped by the box"
                continue
            f.update(add_default=r.get("value"), slider="none (number box only)")
        elif r["control"] == "CheckBox":
            f["add_default"] = r.get("value")
        elif r["control"] == "Combo":
            f.update(add_default=r.get("value"), options=r.get("options") or [])
        last = f; out.append(f)
    # vec components: label X/Y/Z follow the field label that precedes them
    for i, f in enumerate(out):
        if f["label"] in ("X", "Y", "Z") and i:
            j = i - 1
            while j >= 0 and out[j]["label"] in ("X", "Y", "Z"): j -= 1
            if j >= 0: f["label"] = "%s.%s" % (out[j]["label"], f["label"].lower()) if out[j]["type"] != "number" else f["label"]
    return out


schema = {"_meta": {
    "source": "WE 2.8.0.42 particle editor, read via Windows UI Automation from the embedded Chromium page; "
              "each component added to an otherwise-empty category of a Basic particle system, its panel read, then removed.",
    "add_default": "value shown in the panel immediately after ADD (the editor's add-default)",
    "slider_min/max": "UIA RangeValue of the slider; step is not exposed (SmallChange=0)",
    "json_fields_seen": "field keys observed for this component id across 410 particle JSONs (particle_fields_observed.json)",
}}
for fn, sec in SECT.items():
    data = json.load(open(os.path.join(E, fn + ".json")))
    for disp, rows in data.items():
        cid = IDS.get(disp, disp)
        key = "%s:%s" % (sec, cid)
        schema[key] = {"display_name": disp, "fields": fields(rows),
                       "json_fields_seen": sorted(inv.get(key, {}).get("fields", {}).keys())}
gp = json.load(open(os.path.join(E, "general_panels.json")))
for k, rows in gp.items():
    schema["_panel:" + k] = {"fields": fields(rows)}
json.dump(schema, open(os.path.join(D, "particle_fields.json"), "w"), indent=1)
print(len(schema) - 1, "entries")
for k, v in schema.items():
    if k.startswith("_meta"): continue
    print("%-48s %2d fields  %s" % (k, len(v["fields"]), ", ".join("%s=%s" % (f["label"], f.get("add_default")) for f in v["fields"])[:150]))


