"""Contact sheets + per-effect metrics: difference vs the no-effect control, and motion across the 3 s clip."""
import os, subprocess, numpy as np
from PIL import Image, ImageDraw, ImageFont

G = os.path.dirname(os.path.abspath(__file__))
C = os.path.join(G, "captures")
names = sorted(f[:-4] for f in os.listdir(C) if f.endswith(".png"))
H = 1030  # drop the taskbar
load = lambda n: np.asarray(Image.open(os.path.join(C, n + ".png")).convert("RGB"))[:H].astype(np.float32)
ctrl = load("none")

rows = []
for n in names:
    a = load(n)
    diff = np.abs(a - ctrl).mean()
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", os.path.join(C, n + ".mp4"), "-vf",
                          "fps=5,scale=480:270,format=gray", "-f", "rawvideo", "-"], capture_output=True).stdout
    f = np.frombuffer(raw, np.uint8).reshape(-1, 270, 480).astype(np.float32)[:, :257]
    motion = np.abs(f[1:] - f[:-1]).mean() if len(f) > 1 else 0
    rows.append((n, diff, motion))

with open(os.path.join(G, "metrics.tsv"), "w") as fh:
    fh.write("effect\tmean_abs_diff_vs_control\tmean_frame_motion\n")
    for n, d, m in rows:
        fh.write("%s\t%.2f\t%.2f\n" % (n, d, m))

font = ImageFont.truetype("arialbd.ttf", 22)
tw, th, cols = 480, 258, 5
for k in range(0, len(names), 25):
    chunk = names[k:k + 25]
    sheet = Image.new("RGB", (cols * tw, ((len(chunk) + cols - 1) // cols) * (th + 30)), (20, 20, 20))
    for i, n in enumerate(chunk):
        im = Image.open(os.path.join(C, n + ".png")).convert("RGB").crop((0, 0, 1920, H)).resize((tw, th))
        x, y = (i % cols) * tw, (i // cols) * (th + 30)
        sheet.paste(im, (x, y + 30))
        ImageDraw.Draw(sheet).text((x + 6, y + 3), n, fill=(255, 220, 80), font=font)
    sheet.save(os.path.join(G, "contact_%d.png" % (k // 25 + 1)))
for n, d, m in rows:
    print("%-20s diff=%6.2f motion=%5.2f" % (n, d, m))
