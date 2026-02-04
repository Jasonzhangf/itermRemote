#!/usr/bin/env python3
"""Draw a red crop rectangle on a window screenshot.

Inputs:
  1) window_png_path
  2) meta_json_path (output of iterm2_activate_and_crop.py)
  3) out_png_path

This is used as evidence for crop correctness.

Coordinate model:
  - meta.frame is in iTerm2 coordinates (origin bottom-left)
  - meta.rawWindowFrame.y is used to convert to screenshot top-left coords
  - screenshot is from `screencapture -l <cgWindowId>`
"""

import json
import sys


def die(msg):
    print(f"[overlay_crop_box][ERROR] {msg}", file=sys.stderr)
    raise SystemExit(2)


def main():
    if len(sys.argv) < 4:
        die("usage: overlay_crop_box.py <window.png> <meta.json> <out.png>")

    window_png = sys.argv[1]
    meta_json = sys.argv[2]
    out_png = sys.argv[3]

    try:
        from PIL import Image, ImageDraw
    except Exception as e:
        die(f"Pillow required: {e}")

    meta = json.load(open(meta_json))
    f = meta.get("frame") or {}
    wf = meta.get("rawWindowFrame") or {}

    x = float(f.get("x", 0))
    y = float(f.get("y", 0))
    w = float(f.get("w", 0))
    h = float(f.get("h", 0))
    window_y = float(wf.get("y", 0))

    if w <= 0 or h <= 0:
        die(f"invalid frame: {f}")

    img = Image.open(window_png)
    img_w, img_h = img.size

    left = int(x)
    top = int(img_h - (y + h) - window_y)
    right = int(left + w)
    bottom = int(top + h)

    # Clamp to image bounds
    left = max(0, min(img_w, left))
    right = max(0, min(img_w, right))
    top = max(0, min(img_h, top))
    bottom = max(0, min(img_h, bottom))

    draw = ImageDraw.Draw(img)
    # Thicker red border
    for i in range(3):
        draw.rectangle([left - i, top - i, right + i, bottom + i], outline=(255, 0, 0))

    img.save(out_png)
    print(json.dumps({
        "out": out_png,
        "box": {"left": left, "top": top, "right": right, "bottom": bottom},
        "img": {"w": img_w, "h": img_h},
    }))


if __name__ == "__main__":
    main()

