"""Inventory of particle component fields from every particle JSON WE ships plus the user's downloaded wallpapers.
For each component (and the system level) records each field's JSON type, observed values/ranges and source counts.
This is the data-observed half of the schema; slider ranges / add-defaults come from the editor or the binary."""
import json, os, re, sys, struct
from collections import defaultdict

WE = r"C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine"
WS = r"C:\Program Files (x86)\Steam\steamapps\workshop\content\431960"
OUT = os.path.dirname(os.path.abspath(__file__))
SECTIONS = ("emitter", "initializer", "operator", "renderer", "controlpoint", "children")


def lenient(txt):
    txt = re.sub(r",(\s*[}\]])", r"\1", txt)
    return json.loads(txt, strict=False)


def pkg_files(path):
    b = open(path, "rb").read()
    p = 0
    def i32():
        nonlocal p
        v = struct.unpack_from("<i", b, p)[0]; p += 4; return v
    def s():
        nonlocal p
        n = i32(); v = b[p:p + n].decode("utf-8", "replace"); p += n; return v
    s(); n = i32(); ents = [(s(), i32(), i32()) for _ in range(n)]
    base = p
    for name, off, ln in ents:
        if name.startswith("particles/") and name.endswith(".json"):
            yield name, b[base + off:base + off + ln].decode("utf-8", "replace")


def sources():
    for root, _, files in os.walk(os.path.join(WE, "assets")):
        for f in files:
            if f.endswith(".json") and ("particles" in root.replace("\\", "/").split("/")):
                p = os.path.join(root, f)
                yield os.path.relpath(p, WE), open(p, encoding="utf-8", errors="replace").read()
    for root, _, files in os.walk(WS):
        for f in files:
            if f == "scene.pkg":
                try:
                    for name, txt in pkg_files(os.path.join(root, f)):
                        yield "workshop/%s/%s" % (os.path.basename(root), name), txt
                except Exception:
                    pass


def kind(v):
    if isinstance(v, bool): return "bool"
    if isinstance(v, int): return "int"
    if isinstance(v, float): return "float"
    if isinstance(v, str):
        parts = v.split()
        if len(parts) in (2, 3, 4) and all(re.fullmatch(r"-?[\d.e+-]+", t) for t in parts):
            return "vec%d" % len(parts)
        return "string"
    if isinstance(v, dict): return "object(user/script-bound)" if ("user" in v or "script" in v) else "object"
    if isinstance(v, list): return "list"
    return type(v).__name__


inv = defaultdict(lambda: defaultdict(lambda: {"types": set(), "values": [], "count": 0}))
comp_files = defaultdict(set)
nfiles = 0
for src, txt in sources():
    try:
        j = lenient(txt)
    except Exception:
        continue
    if not isinstance(j, dict) or not any(k in j for k in SECTIONS + ("maxcount", "material")):
        continue
    nfiles += 1
    for k, v in j.items():
        if k not in SECTIONS:
            e = inv["_system"][k]; e["types"].add(kind(v)); e["count"] += 1
            if not isinstance(v, (dict, list)): e["values"].append(v)
    for sec in SECTIONS:
        for c in j.get(sec, []) or []:
            if not isinstance(c, dict):
                continue
            name = "%s:%s" % (sec, c.get("name", "(unnamed)")) if sec not in ("controlpoint", "children") else sec
            comp_files[name].add(src)
            for k, v in c.items():
                if k in ("name", "id"):
                    continue
                e = inv[name][k]; e["types"].add(kind(v)); e["count"] += 1
                if isinstance(v, dict) and "value" in v: v = v["value"]
                if not isinstance(v, (dict, list)): e["values"].append(v)


def summarize(vals):
    nums = [v for v in vals if isinstance(v, (int, float)) and not isinstance(v, bool)]
    out = {}
    if nums:
        out["observed_min"] = min(nums); out["observed_max"] = max(nums)
    distinct = sorted({json.dumps(v) for v in vals})
    out["distinct_values"] = [json.loads(v) for v in distinct[:25]]
    if len(distinct) > 25: out["distinct_values_truncated"] = len(distinct)
    return out


table = {}
for comp in sorted(inv):
    table[comp] = {"_files": len(comp_files.get(comp, [])) if comp != "_system" else nfiles, "fields": {}}
    for f in sorted(inv[comp]):
        e = inv[comp][f]
        table[comp]["fields"][f] = dict(types=sorted(e["types"]), occurrences=e["count"], **summarize(e["values"]))
json.dump(table, open(os.path.join(OUT, "particle_fields_observed.json"), "w"), indent=1)
print(nfiles, "particle files;", len(table) - 1, "components")
for c in sorted(table):
    print("%-45s files=%-4s fields=%s" % (c, table[c]["_files"], ", ".join(table[c]["fields"])))
