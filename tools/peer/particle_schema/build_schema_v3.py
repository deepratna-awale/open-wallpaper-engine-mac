"""particle_fields.json from the structure-aware harvest (editor_observed_v3): section / field / type / add_default /
slider range / combo options per component, keyed by component id; plus json keys seen in real files."""
import json, os
from build_schema import IDS, SECT  # display name -> id map

D = os.path.dirname(os.path.abspath(__file__))
E = os.path.join(D, "editor_observed_v3")
inv = json.load(open(os.path.join(D, "particle_fields_observed.json")))
load = lambda f: json.load(open(os.path.join(E, f), encoding="utf-8-sig"))
norm = lambda rows: [rows] if isinstance(rows, dict) else (rows or [])


def clean(rows):
    out = []
    for r in norm(rows):
        f = {k: r[k] for k in ("section", "field", "type", "add_default", "slider_min", "slider_max", "options") if k in r and r[k] not in ("", None, [])}
        if f.get("type") == "number" and "slider_min" not in f:
            f["range"] = "none (unranged number box; editor does not clamp)"
        out.append(f)
    return out


schema = {"_meta": {
    "we_version": "2.8.0.42",
    "method": "UI Automation over the editor's embedded Chromium page. Each add-dialog component was added to a Basic "
              "particle system, selected, read, and removed; nothing saved. Panel structure: Group(label) + controls; "
              "vectors as label + X/Y/Z (or Width/Depth) boxes; checkboxes are icon glyphs U+F0C8 (off) / U+F14A (on); "
              "combos = Button(current) + List(options); a label with no control = section title.",
    "add_default": "value in the panel right after ADD",
    "hidden_fields": "fields only shown under a condition (e.g. periodic-emission sub-fields) are absent here",
}}
for fn, sec in SECT.items():
    for disp, rows in load(fn + ".json").items():
        cid = IDS.get(disp, disp); key = "%s:%s" % (sec, cid)
        schema[key] = {"display_name": disp, "fields": clean(rows),
                       "json_fields_seen": sorted(inv.get(key, {}).get("fields", {}).keys())}
for k, rows in load("general.json").items():
    schema["panel:" + k] = {"fields": clean(rows)}
json.dump(schema, open(os.path.join(D, "particle_fields.json"), "w"), indent=1)
F = [f for k, v in schema.items() if k != "_meta" for f in v["fields"]]
print(len(schema) - 1, "panels,", len(F), "fields:", sum(f["type"] == "bool" for f in F), "checkboxes,",
      sum(f["type"] == "combo" for f in F), "combos,", sum("slider_min" in f for f in F), "sliders,",
      sum(bool(f.get("section")) for f in F), "in sections")
