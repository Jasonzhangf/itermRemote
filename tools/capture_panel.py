#!/usr/bin/env python3
"""
Capture iTerm2 panel screenshot:
- Activate panel via python bridge
- Take full screenshot with screencapture
- Crop according to panel frame (relative to window)
"""

import argparse
import subprocess
import sys
import tempfile
import os
from pathlib import Path

try:
    from PIL import Image, ImageFilter
except ImportError:
    print("PIL not found: pip3 install Pillow", file=sys.stderr)
    sys.exit(1)

def activate_panel(session_id):
    """Run iterm2_activate_and_crop.py and return JSON."""
    repo_root = Path(__file__).parent.parent
    proc = subprocess.run(
        [sys.executable, str(repo_root / "scripts/python/iterm2_activate_and_crop.py"), session_id],
        capture_output=True, text=True, check=True
    )
    import json
    return json.loads(proc.stdout)

def capture_full_screen(out_path):
    """Capture full screen using screencapture."""
    subprocess.run(["/usr/sbin/screencapture", "-x", out_path], check=True)
    return Image.open(out_path)

def crop_panel_from_full(full_img, meta):
    """
    Crop full image to get the panel.
    meta contains:
      - windowFrame: window bounds (in window coords)
      - frame: panel bounds (in window coords)
      - rawWindowFrame: actual window screen bounds
    """
    wf = meta["windowFrame"]
    pf = meta["frame"]
    rwf = meta["rawWindowFrame"]

    # Normalize coordinates to full image space.
    # rawWindowFrame is in screen coordinates (top-left origin, y offset by menu bar).
    # windowFrame and frame are in window coordinates (bottom-left origin).
    # The Python bridge already converts frame to windowFrame coordinates (top-left).
    # So we can use rawWindowFrame to locate the window in the full image,
    # then crop the panel relative to that window.

    wx = int(rwf["x"])
    wy = int(rwf["y"])
    ww = int(rwf["w"])
    wh = int(rwf["h"])

    # Extract window from full image.
    # Note: full image may be larger (multi-monitor). We'll assume window is within.
    window_img = full_img.crop((wx, wy, wx + ww, wy + wh))

    # Now crop panel from window image using windowFrame (normalized to window size).
    # windowFrame is the layout bounds of the window content (may be slightly smaller than raw).
    # But the panel frame is already relative to windowFrame coordinates.
    # So we need to scale panel frame to window_img size.

    # windowFrame is the layout bounds; rawWindowFrame is the actual window bounds.
    # The ratio between them:
    wfx = wf["x"]
    wfy = wf["y"]
    wfw = wf["w"]
    wfh = wf["h"]

    # panel frame is in windowFrame coordinates.
    pfx = pf["x"]
    pfy = pf["y"]
    pfw = pf["w"]
    pfh = pf["h"]

    # Scale to window_img size.
    scale_x = ww / wfw
    scale_y = wh / wfh

    px = int(pfx * scale_x)
    py = int(pfy * scale_y)
    pw = int(pfw * scale_x)
    ph = int(pfh * scale_y)

    # Invert y (windowFrame is top-left, but panel frame might be bottom-left in some versions).
    # The Python bridge should normalize to top-left. We'll trust it.
    # However, the rawWindowFrame y is screen coordinates (top-left).
    # We'll assume panel frame is already top-left relative to windowFrame.

    # Clip to image bounds.
    px = max(0, min(px, ww - 1))
    py = max(0, min(py, wh - 1))
    pw = max(1, min(pw, ww - px))
    ph = max(1, min(ph, wh - py))

    return window_img.crop((px, py, px + pw, py + ph))

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("session_id", help="iTerm2 session ID")
    parser.add_argument("--out", default="/tmp/panel.png", help="Output path")
    args = parser.parse_args()

    meta = activate_panel(args.session_id)
    # Wait a moment for UI to update.
    import time
    time.sleep(0.2)

    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
        tmp_path = tmp.name

    try:
        out_path = Path(args.out)
        out_path.parent.mkdir(parents=True, exist_ok=True)

        full_img = capture_full_screen(tmp_path)
        panel_img = crop_panel_from_full(full_img, meta)
        panel_img.save(str(out_path))
        print(f"Saved: {args.out}")
        print(f"Window frame: {meta['windowFrame']}")
        print(f"Panel frame: {meta['frame']}")
        print(f"Raw window frame: {meta['rawWindowFrame']}")
    finally:
        os.unlink(tmp_path)

if __name__ == "__main__":
    main()
