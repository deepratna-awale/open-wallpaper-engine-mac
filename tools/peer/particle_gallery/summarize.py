"""Contact sheets + metrics for the particle preset and component-preview captures."""
import os, subprocess, numpy as np
from PIL import Image, ImageDraw, ImageFont

G = os.path.dirname(os.path.abspath(__file__))
font = ImageFont.truetype("arialbd.ttf", 22)


def run(folder, bg_for):
    C = os.path.join(G, folder)
    names = sorted(f[:-4] for f in os.listdir(C) if f.endswith(".png"))
    rows = []
    for n in names:
        a = np.asarray(Image.open(os.path.join(C, n + ".png")).convert("RGB"))[:1030].astype(np.float32)
        bg = bg_for(n)
        cover = (np.abs(a - bg).max(axis=2) > 40).mean() * 100 if bg is not None else float("nan")
        raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", os.path.join(C, n + ".mp4"), "-vf",
                              "fps=5,scale=480:270,format=gray", "-f", "rawvideo", "-"], capture_output=True).stdout
        f = np.frombuffer(raw, np.uint8).reshape(-1, 270, 480).astype(np.float32)[:, :257]
        motion = np.abs(f[1:] - f[:-1]).mean() if len(f) > 1 else 0
        rows.append((n, cover, motion))
    with open(os.path.join(G, folder + "_metrics.tsv"), "w") as fh:
        fh.write("name\tcoverage_pct_vs_background\tmean_frame_motion\n")
        for r in rows:
            fh.write("%s\t%.2f\t%.2f\n" % r)
    tw, th, cols = 480, 258, 5
    for k in range(0, len(names), 25):
        chunk = names[k:k + 25]
        sheet = Image.new("RGB", (cols * tw, ((len(chunk) + cols - 1) // cols) * (th + 30)), (20, 20, 20))
        for i, n in enumerate(chunk):
            im = Image.open(os.path.join(C, n + ".png")).convert("RGB").crop((0, 0, 1920, 1030)).resize((tw, th))
            x, y = (i % cols) * tw, (i // cols) * (th + 30)
            sheet.paste(im, (x, y + 30))
            ImageDraw.Draw(sheet).text((x + 6, y + 3), n, fill=(255, 220, 80), font=font)
        sheet.save(os.path.join(G, "contact_%s_%d.png" % (folder, k // 25 + 1)))
    return rows


bgs = {k: np.asarray(Image.open(os.path.join(G, "assets", k + ".png")).convert("RGB"))[:1030].astype(np.float32)
       for k in ("bg_black", "bg_grey", "bg_pattern")}
import json
idx = {e[0].replace("ptcl_", ""): e[1] for e in json.load(open(os.path.join(G, "index.json")))}
p = run("captures", lambda n: bgs.get(idx.get(n, "bg_black")))
e = run("elements", lambda n: None)
for r in p + e:
    print("%-40s cover=%6.2f%% motion=%5.2f" % r)
