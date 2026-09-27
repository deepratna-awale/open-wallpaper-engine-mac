"""Per-second L/R RMS for the spatialization captures, aligned on the step changes, relative to project 4."""
import wave, os, numpy as np, json

D = os.path.dirname(os.path.abspath(__file__))
def load(name):
    w = wave.open(os.path.join(D, name + ".wav"))
    a = np.frombuffer(w.readframes(w.getnframes()), "<i2").reshape(-1, 2).astype(np.float64) / 32767
    return a, w.getframerate()

def rms_env(a, sr, win=0.05):
    n = int(sr * win); k = len(a) // n
    return np.sqrt((a[:k * n].reshape(k, n, 2) ** 2).mean(axis=1)), n

def steps(name, onset=None):
    a, sr = load(name)
    env, n = rms_env(a, sr)
    tot = env.sum(axis=1)
    start = onset if onset is not None else int(np.argmax(tot > 0.01)) * n   # tone onset = wallpaper load (engine.runtime ~ 0)
    out = []
    for s in range(24):
        a0 = start + int((s + 0.2) * sr); a1 = start + int((s + 0.8) * sr)
        if a1 > len(a): break
        seg = a[a0:a1]
        out.append(np.sqrt((seg ** 2).mean(axis=0)))
    return np.array(out), start / sr

res = {}
ref, t_ref = steps("4-plain-mono")
refL, refR = np.median(ref[:, 0]), np.median(ref[:, 1])
res["reference_plain_mono_rms"] = [round(refL, 5), round(refR, 5)]
print("project 4 (plain mono) onset %.2fs  RMS L/R %.5f %.5f (flat: %.4f..%.4f)" % (t_ref, refL, refR, ref.min(), ref.max()))
exp_pan = [(1.0579, .3314), (.9904, .3886), (.9174, .4528), (.8400, .5234), (.7598, .5993), (.6788, .6788),
           (.5993, .7598), (.5234, .8400), (.4528, .9174), (.3886, .9904), (.3314, 1.0579)]
exp_depth = [1.0, .6788, .6788, .4849, .3085, .2263, .1786, .1476, .1257, .1095, .0970]
for name, exp in (("1-spatial-mono-pan", exp_pan), ("2-spatial-mono-depth", exp_depth), ("3-spatial-stereo-pan", None)):
    st, t0 = steps(name)
    rel = st / np.array([refL, refR])
    print("\n%s  onset %.2fs  (seconds counted from onset; step = second %% 11)" % (name, t0))
    rows = []
    for s, (l, r) in enumerate(rel):
        k = s % 11
        e = exp[k] if exp else None
        es = ("%.4f / %.4f" % e) if isinstance(e, tuple) else ("%.4f / %.4f" % (e, e) if e is not None else "-")
        print("  t=%2d step %2d  L/R rel %.4f / %.4f   expected %s" % (s, k, l, r, es))
        rows.append({"second": s, "step": k, "rms": [round(st[s][0], 5), round(st[s][1], 5)], "rel": [round(l, 4), round(r, 4)], "expected": es})
    res[name] = {"onset_s": round(t0, 3), "rows": rows}
json.dump(res, open(os.path.join(D, "results.json"), "w"), indent=1)
