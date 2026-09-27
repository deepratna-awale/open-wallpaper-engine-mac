"""Capture config: fps 60 and every playback rule 'run'. Edits WE's config.json in place (WE must be stopped)."""
import json, re, sys

C = r"C:\Program Files (x86)\Steam\steamapps\common\wallpaper_engine\config.json"
t = open(C, encoding="utf-8").read()
assert len(t) > 5000
t = re.sub(r'"fps"\s*:\s*\d+', '"fps" : %s' % (sys.argv[1] if len(sys.argv) > 1 else "60"), t)
for k in ("playbackfocus", "playbackfullscreen", "playbackmaximized", "playbackaudio"):
    t = re.sub(r'"%s"\s*:\s*"\w+"' % k, '"%s" : "run"' % k, t)
json.loads(t)
open(C, "w", encoding="utf-8").write(t)
print("config set", len(t))
