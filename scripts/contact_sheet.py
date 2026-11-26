#!/usr/bin/env python3
"""Contact sheet: each frame's light and dark side by side, labelled, in frame order."""
import sys, pathlib
from PIL import Image, ImageDraw, ImageFont

src = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "screenshots-review")
out = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else src / "contact-sheet.png")
shots = sorted(p for p in src.glob("*.png") if p.name != out.name and not p.name.startswith("contact"))
frames = sorted({p.stem.rsplit("-", 1)[0] if p.stem.endswith(("-light", "-dark")) else p.stem for p in shots})
W, cols, pad, label = 220, 6, 12, 28
thumbs = []
for f in frames:
    for variant in ("light", "dark"):
        p = src / f"{f}-{variant}.png"
        if p.exists(): thumbs.append((f"{f} · {variant}", p))
for p in shots:
    if "accessibility" in p.name: thumbs.append((p.stem.replace("-accessibility-extra-large", " · AX3"), p))
seen, uniq = set(), []
for t in thumbs:
    if t[1] not in seen: seen.add(t[1]); uniq.append(t)
H = int(W * 2.17)
rows = (len(uniq) + cols - 1) // cols
sheet = Image.new("RGB", (cols * (W + pad) + pad, rows * (H + label + pad) + pad), (245, 245, 245))
draw = ImageDraw.Draw(sheet)
try: font = ImageFont.truetype("DejaVuSans.ttf", 13)
except Exception: font = ImageFont.load_default()
for i, (name, p) in enumerate(uniq):
    im = Image.open(p).convert("RGB")
    im.thumbnail((W, H))
    x = pad + (i % cols) * (W + pad); y = pad + (i // cols) * (H + label + pad)
    sheet.paste(im, (x, y + label))
    draw.text((x, y + 6), name, fill=(20, 20, 20), font=font)
sheet.save(out)
print(f"{len(uniq)} shots -> {out} ({sheet.size[0]}x{sheet.size[1]})")
