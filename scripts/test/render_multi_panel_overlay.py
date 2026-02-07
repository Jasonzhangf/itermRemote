#!/usr/bin/env python3
# Render a single window screenshot with multiple panel boxes + numeric labels.
#
# Output:
#   <out_dir>/window.png
#   <out_dir>/window_multi_overlay.png
#   <out_dir>/window_multi_overlay.json
#
# Uses iTerm2 Python API via scripts/python/iterm2_sources.py to get panels + frames.

import json
import subprocess
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    raise SystemExit("Missing Pillow. Install: pip3 install Pillow")

REPO_ROOT = Path(__file__).resolve().parents[2]

out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else REPO_ROOT / "build/verify_panel_switching/manual_overlay"
out_dir.mkdir(parents=True, exist_ok=True)

raw = subprocess.check_output([sys.executable, str(REPO_ROOT / "scripts/python/iterm2_sources.py")])
data = json.loads(raw)

panels = data.get("panels", [])
if not panels:
    raise SystemExit("No panels found")

# Sort spatial: row-major (top-to-bottom, left-to-right)
# In our derived layoutFrame, y increases downward, so row order is y asc.

def key(p):
    f = p.get("layoutFrame") or p.get("frame") or {}
    y = float(f.get("y", 0))
    x = float(f.get("x", 0))
    yb = round(y / 5.0) * 5.0
    return (yb, x)

panels_sorted = sorted(panels, key=key)

first_sid = panels_sorted[0].get("id")
if not first_sid:
    raise SystemExit("sessionId missing")

# Activate first panel to get cgWindowId (iterm2_sources may not include it)
meta_raw = subprocess.check_output(
    [sys.executable, str(REPO_ROOT / "scripts/python/iterm2_activate_and_crop.py"), str(first_sid)]
)
meta = json.loads(meta_raw)
cg = meta.get("cgWindowId")
if not cg:
    raise SystemExit("cgWindowId missing (activate_and_crop)")

screenshot_path = out_dir / "window.png"
subprocess.check_call(["/usr/sbin/screencapture", "-x", "-l", str(cg), str(screenshot_path)])

img = Image.open(screenshot_path).convert("RGBA")
draw = ImageDraw.Draw(img)

# Load font
try:
    font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 24)
except Exception:
    font = ImageFont.load_default()

# window origin offset
wf = meta.get("rawWindowFrame") or {}
wx = float(wf.get("x", 0))
wy = float(wf.get("y", 0))

W, H = img.size

boxes = []

for idx, p in enumerate(panels_sorted, start=1):
    f = p.get("layoutFrame") or p.get("frame") or {}
    fx = float(f.get("x", 0))
    fy = float(f.get("y", 0))
    fw = float(f.get("w", 0))
    fh = float(f.get("h", 0))
    if fw <= 0 or fh <= 0:
        continue

    left = int(wx + fx)
    top = int(H - (wy + fy + fh))
    right = int(left + fw)
    bottom = int(top + fh)

    # clamp
    left = max(0, min(W, left))
    right = max(0, min(W, right))
    top = max(0, min(H, top))
    bottom = max(0, min(H, bottom))

    # draw rect
    for t in range(3):
        draw.rectangle([left - t, top - t, right + t, bottom + t], outline=(255, 0, 0, 255), width=1)

    # label
    draw.text((left + 6, top + 6), str(idx), fill=(255, 0, 0, 255), font=font)

    boxes.append({
        "order": idx,
        "title": p.get("title"),
        "sessionId": p.get("id"),
        "box": {"left": left, "top": top, "right": right, "bottom": bottom},
        "frame": f,
    })

out_path = out_dir / "window_multi_overlay.png"
img.save(out_path)
(out_dir / "window_multi_overlay.json").write_text(
    json.dumps(
        {
            "screenshot": str(screenshot_path),
            "overlay": str(out_path),
            "rawWindowFrame": wf,
            "count": len(boxes),
            "boxes": boxes,
        },
        indent=2,
    )
)

print("Wrote:", out_path)
