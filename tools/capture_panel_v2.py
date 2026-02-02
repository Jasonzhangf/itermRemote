#!/usr/bin/env python3
"""Capture and crop iTerm2 panel from a full-screen screenshot (v2).

Key difference from v1:
- Do NOT trust rawWindowFrame.x/y for locating the window inside the PNG.
- Instead, locate the iTerm2 window rect in the screenshot via template matching:
  1) Take full screenshot.
  2) Crop a tight patch from the screenshot using the rawWindowFrame-derived rect
     (best-effort initial guess).
  3) Search that patch back in the full screenshot with normalized cross correlation
     to recover the exact window rect in PNG coordinates.
  4) Map panel frame from windowFrame coords into that recovered rect.

This avoids coordinate space mismatch between Cocoa window coords and screencapture PNG.

Requires: Pillow, numpy
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Optional

import numpy as np
from PIL import Image


def activate_panel(repo_root: Path, session_id: str) -> dict:
    proc = subprocess.run(
        [sys.executable, str(repo_root / "scripts/python/iterm2_activate_and_crop.py"), session_id],
        capture_output=True,
        text=True,
        check=True,
    )
    out = proc.stdout.strip()
    meta = json.loads(out) if out else {}
    if "error" in meta:
        raise RuntimeError(f"activate failed: {meta['error']}")
    for k in ("frame", "windowFrame", "rawWindowFrame"):
        if k not in meta:
            raise RuntimeError(f"activate missing key: {k} (got keys={list(meta.keys())})")
    return meta


def screencapture_full(out_path: Path) -> None:
    subprocess.run(["/usr/sbin/screencapture", "-x", str(out_path)], check=True)


def to_gray_np(img: Image.Image) -> np.ndarray:
    return np.asarray(img.convert("L"), dtype=np.float32)


def norm_xcorr2d(search: np.ndarray, templ: np.ndarray) -> tuple[int, int, float]:
    """Very small NCC matcher.

    Returns (best_y, best_x, best_score).

    Notes:
    - This is CPU heavy but fine for a constrained search area.
    - search and templ are grayscale float32.
    """
    sh, sw = search.shape
    th, tw = templ.shape
    if th <= 0 or tw <= 0 or th > sh or tw > sw:
        raise ValueError("invalid template/search sizes")

    t = templ
    t_mean = float(t.mean())
    t0 = t - t_mean
    t_norm = float(np.sqrt((t0 * t0).sum()))
    if t_norm == 0:
        raise ValueError("template has zero variance")

    best = (-1e9, 0, 0)
    # Step by 2 pixels for speed; refine around best later.
    step = 2
    for y in range(0, sh - th + 1, step):
        patch_rows = search[y : y + th]
        for x in range(0, sw - tw + 1, step):
            p = patch_rows[:, x : x + tw]
            p_mean = float(p.mean())
            p0 = p - p_mean
            p_norm = float(np.sqrt((p0 * p0).sum()))
            if p_norm == 0:
                continue
            score = float((p0 * t0).sum()) / (p_norm * t_norm)
            if score > best[0]:
                best = (score, y, x)

    # Local refine in a 10px radius with step=1.
    _, by, bx = best
    ry0 = max(0, by - 10)
    rx0 = max(0, bx - 10)
    ry1 = min(sh - th, by + 10)
    rx1 = min(sw - tw, bx + 10)
    best2 = best
    for y in range(ry0, ry1 + 1):
        patch_rows = search[y : y + th]
        for x in range(rx0, rx1 + 1):
            p = patch_rows[:, x : x + tw]
            p_mean = float(p.mean())
            p0 = p - p_mean
            p_norm = float(np.sqrt((p0 * p0).sum()))
            if p_norm == 0:
                continue
            score = float((p0 * t0).sum()) / (p_norm * t_norm)
            if score > best2[0]:
                best2 = (score, y, x)

    score, y, x = best2
    return y, x, score


def clamp_rect(x: int, y: int, w: int, h: int, W: int, H: int) -> tuple[int, int, int, int]:
    x = max(0, min(x, W - 1))
    y = max(0, min(y, H - 1))
    w = max(1, min(w, W - x))
    h = max(1, min(h, H - y))
    return x, y, w, h


def locate_window_rect(full_img: Image.Image, meta: dict, debug_dir: Optional[Path]) -> tuple[int, int, int, int]:
    """Return (x,y,w,h) of iTerm2 window in full screenshot pixel coords."""
    W, H = full_img.size

    rwf = meta["rawWindowFrame"]
    # Initial guess rect from rawWindowFrame; may be off due to coord system mismatch.
    gx = int(float(rwf.get("x", 0.0)))
    gy = int(float(rwf.get("y", 0.0)))
    gw = int(float(rwf.get("w", W)))
    gh = int(float(rwf.get("h", H)))

    # If guess looks insane, fall back to center-ish crop.
    if gw <= 0 or gh <= 0 or gw > W * 2 or gh > H * 2:
        gx, gy, gw, gh = 0, 0, W, H

    # Build a template patch from the screenshot itself:
    # Use a band near the top-left of the guessed window (includes title bar / tabs).
    # This patch tends to be stable and unique.
    gx, gy, gw, gh = clamp_rect(gx, gy, gw, gh, W, H)

    # Use a 400x120 patch (scaled down if window smaller).
    tw = min(400, gw)
    th = min(120, gh)
    templ_box = (gx, gy, gx + tw, gy + th)
    templ = full_img.crop(templ_box)

    # Search within a padded region around the guess.
    pad = 300
    sx0 = max(0, gx - pad)
    sy0 = max(0, gy - pad)
    sx1 = min(W, gx + gw + pad)
    sy1 = min(H, gy + gh + pad)
    search_box = (sx0, sy0, sx1, sy1)
    search = full_img.crop(search_box)

    if debug_dir:
        debug_dir.mkdir(parents=True, exist_ok=True)
        templ.save(debug_dir / "templ.png")
        search.save(debug_dir / "search.png")

    y, x, score = norm_xcorr2d(to_gray_np(search), to_gray_np(templ))

    # Recovered top-left of template within full image.
    rx = sx0 + x
    ry = sy0 + y

    # Window rect is recovered template origin plus original offsets inside the window guess.
    # Since template starts at (gx,gy), recovered window origin should align to (rx,ry).
    win_x = rx
    win_y = ry
    win_w = gw
    win_h = gh

    if debug_dir:
        (debug_dir / "match.txt").write_text(
            f"score={score}\n"
            f"guess=({gx},{gy},{gw},{gh})\n"
            f"search_box=({sx0},{sy0},{sx1},{sy1})\n"
            f"templ_box=({templ_box[0]},{templ_box[1]},{templ_box[2]},{templ_box[3]})\n"
            f"match_tl=({rx},{ry})\n"
            f"win=({win_x},{win_y},{win_w},{win_h})\n"
        )

    return clamp_rect(win_x, win_y, win_w, win_h, W, H)


def crop_panel(full_img: Image.Image, meta: dict, win_rect: tuple[int, int, int, int]) -> Image.Image:
    wf = meta["windowFrame"]
    pf = meta["frame"]

    win_x, win_y, win_w, win_h = win_rect
    window_img = full_img.crop((win_x, win_y, win_x + win_w, win_y + win_h))

    wfw = float(wf["w"])
    wfh = float(wf["h"])
    if wfw <= 0 or wfh <= 0:
        raise RuntimeError(f"invalid windowFrame: {wf}")

    scale_x = win_w / wfw
    scale_y = win_h / wfh

    px = int(float(pf["x"]) * scale_x)
    py = int(float(pf["y"]) * scale_y)
    pw = int(float(pf["w"]) * scale_x)
    ph = int(float(pf["h"]) * scale_y)

    # Clamp.
    px = max(0, min(px, win_w - 1))
    py = max(0, min(py, win_h - 1))
    pw = max(1, min(pw, win_w - px))
    ph = max(1, min(ph, win_h - py))

    return window_img.crop((px, py, px + pw, py + ph))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("session_id")
    ap.add_argument("--out", required=True)
    ap.add_argument("--debug-dir", default=None)
    args = ap.parse_args()

    repo_root = Path(__file__).parent.parent
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    debug_dir = Path(args.debug_dir) if args.debug_dir else None

    meta = activate_panel(repo_root, args.session_id)
    time.sleep(0.25)

    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
        tmp_path = Path(tmp.name)

    try:
        screencapture_full(tmp_path)
        full_img = Image.open(tmp_path)

        win_rect = locate_window_rect(full_img, meta, debug_dir)
        panel = crop_panel(full_img, meta, win_rect)
        panel.save(out_path)

        # Emit metadata for inspection.
        meta_out = {
            "sessionId": meta.get("sessionId"),
            "frame": meta.get("frame"),
            "windowFrame": meta.get("windowFrame"),
            "rawWindowFrame": meta.get("rawWindowFrame"),
            "winRect": {"x": win_rect[0], "y": win_rect[1], "w": win_rect[2], "h": win_rect[3]},
        }
        (out_path.parent / (out_path.stem + ".meta.json")).write_text(json.dumps(meta_out, indent=2))

        print(f"Saved: {out_path}")
        return 0
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass


if __name__ == "__main__":
    raise SystemExit(main())
