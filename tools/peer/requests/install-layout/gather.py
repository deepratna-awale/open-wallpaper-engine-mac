"""A1-A4 of the install-layout request: tree listing, default projects, redacted config.json shape, redacted acf sample."""
import json, os, re

WE = r"C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine"
ACF = r"C:\Program Files (x86)\Steam\steamapps\workshop\appworkshop_431960.acf"
OUT = os.path.dirname(os.path.abspath(__file__))

# A1: top two levels (relative paths only), skipping crash dumps and logs
lines = []
for top in sorted(os.listdir(WE)):
    lines.append(top + ("/" if os.path.isdir(os.path.join(WE, top)) else ""))
    if os.path.isdir(os.path.join(WE, top)):
        for sub in sorted(os.listdir(os.path.join(WE, top))):
            if re.search(r"\.(mdmp|log)$|log\.txt$", sub): continue
            lines.append(top + "/" + sub + ("/" if os.path.isdir(os.path.join(WE, top, sub)) else ""))
open(os.path.join(OUT, "tree_2_levels.txt"), "w").write("\n".join(lines) + "\n")

dp = []
for p in sorted(os.listdir(os.path.join(WE, "projects", "defaultprojects"))):
    f = os.path.join(WE, "projects", "defaultprojects", p, "project.json")
    if not os.path.exists(f): continue
    d = json.load(open(f, encoding="utf-8-sig"))
    dp.append({"folder": p, **{k: d.get(k, "<absent>") for k in ("type", "file", "contentrating")}})
json.dump(dp, open(os.path.join(OUT, "defaultprojects.json"), "w"), indent=1)

# A3: config.json shape. Strings -> "<str>", numbers kept only for small enums, paths/usernames redacted.
cfg = json.load(open(os.path.join(WE, "config.json"), encoding="utf-8-sig"))
def shape(v, depth=0):
    if isinstance(v, dict):
        out = {}
        for i, (k, x) in enumerate(v.items()):
            key = "<username>" if depth == 0 and k not in ("?installdirectory", "steamuser") and isinstance(x, dict) and "general" in x else k
            if re.search(r"[A-Za-z]:[\\/]|/", k): key = "<path-key-%d>" % i
            out[key] = shape(x, depth + 1)
        return out
    if isinstance(v, list): return [shape(v[0], depth + 1), "... %d items" % len(v)] if v else []
    if isinstance(v, bool): return v
    if isinstance(v, (int, float)): return "<number>"
    return "<str>"
json.dump(shape(cfg), open(os.path.join(OUT, "config_shape_redacted.json"), "w"), indent=1)

# A4: acf, 3 items, subscriber ids redacted
t = open(ACF, encoding="utf-8").read()
t = re.sub(r'("subscribedby"\s*)"\d+"', r'\1"<steamid>"', t)
def keep3(block_name, text):
    m = re.search(r'("%s"\s*\{)(.*?\n\t\})' % block_name, text, re.S)
    if not m: return text
    items = re.findall(r'\n\t\t"\d+"\s*\{.*?\n\t\t\}', m.group(2), re.S)
    return text.replace(m.group(2), "".join(items[:3]) + "\n\t}")
for b in ("WorkshopItemsInstalled", "WorkshopItemDetails"): t = keep3(b, t)
open(os.path.join(OUT, "appworkshop_431960_redacted.acf"), "w").write(t)
print("ok", len(lines), len(dp))
