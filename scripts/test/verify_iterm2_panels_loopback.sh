#!/bin/bash
# iTerm2 panel loopback verification (API-based, no window-id guessing)
#
# Verifies panel switch + crop correctness by:
# - Resolving sessionIds for panels by title (e.g. 1.1.1 and 1.1.8)
# - Activating A -> B -> A via iTerm2 Python API
# - Taking iTerm2 app screenshot via `screencapture -c -x iTerm2`
# - Saving clipboard PNG to disk (AppKit NSPasteboard)
# - Cropping panel region using verified coordinate transform:
#     top = img_h - (y + h) - window_y
#
# Output: build/verify_loopback/<TS>/
#   - A1.window.png / B1.window.png / A2.window.png
#   - A1.panel.png  / B1.panel.png  / A2.panel.png
#   - A1.meta.json  / B1.meta.json  / A2.meta.json
#
# Requirements:
# - iTerm2 running (do NOT close the only window)
# - iTerm2 Python API enabled and `python3 -c 'import iterm2'` works
# - macOS Screen Recording permission granted to terminal (screencapture)
# - python3 has AppKit (pyobjc) available
# - python3 has Pillow installed (pip3 install Pillow)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT_BASE="$REPO_ROOT/build/verify_loopback"
TS="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$OUT_BASE/$TS"
mkdir -p "$OUT_DIR"

TITLE_A="1.1.1"
TITLE_B="1.1.8"

log() {
  echo "[verify_iterm2_panels_loopback] $*"
}

die() {
  echo "[verify_iterm2_panels_loopback][ERROR] $*" >&2
  exit 2
}

command -v python3 >/dev/null 2>&1 || die "python3 not found"
command -v /usr/sbin/screencapture >/dev/null 2>&1 || die "screencapture not found"

log "Resolve iTerm2 sessionIds for titles: $TITLE_A and $TITLE_B"
python3 - <<PY > "$OUT_DIR/sessions.json"
import json
import subprocess
import sys

p = subprocess.run([sys.executable, "scripts/python/iterm2_sources.py"], capture_output=True, text=True)
if p.returncode != 0:
    raise SystemExit(f"iterm2_sources.py failed: {p.stderr}")
print(p.stdout)
PY

SESSION_A=$(python3 - <<PY
import json
from pathlib import Path
p = json.loads(Path("$OUT_DIR/sessions.json").read_text())
for s in p.get("panels", []):
    if s.get("title") == "$TITLE_A":
        print(s.get("id", ""))
        raise SystemExit(0)
print("")
PY
)

SESSION_B=$(python3 - <<PY
import json
from pathlib import Path
p = json.loads(Path("$OUT_DIR/sessions.json").read_text())
for s in p.get("panels", []):
    if s.get("title") == "$TITLE_B":
        print(s.get("id", ""))
        raise SystemExit(0)
print("")
PY
)

[[ -n "$SESSION_A" ]] || die "Could not find session for title=$TITLE_A"
[[ -n "$SESSION_B" ]] || die "Could not find session for title=$TITLE_B"

log "A=$TITLE_A sessionId=$SESSION_A"
log "B=$TITLE_B sessionId=$SESSION_B"

activate_and_capture() {
  local label="$1"
  local sid="$2"

  # Activate session and get metadata (including cgWindowId).
  log "Activate $label sessionId=$sid"
  python3 "$REPO_ROOT/scripts/python/iterm2_activate_and_crop.py" "$sid" > "$OUT_DIR/$label.meta.json" || die "activate failed for $label"

  # Allow UI to settle.
  sleep 0.25

  log "Screenshot iTerm2 app to clipboard"

  # Extract cgWindowId from metadata for direct window capture.
  local cgwid=$(python3 - <<PY
import json
from pathlib import Path
meta = json.loads(Path("$OUT_DIR/$label.meta.json").read_text())
print(meta.get("cgWindowId", ""))
PY
)
  [[ -n "$cgwid" ]] || die "Could not extract cgWindowId from metadata for $label"
  log "Using cgWindowId=$cgwid for window capture"

  log "Screenshot iTerm2 window to clipboard via cgWindowId"
  /usr/sbin/screencapture -c -x -l "$cgwid" || die "screencapture failed (check Screen Recording permission)"

  log "Save clipboard PNG -> $OUT_DIR/$label.window.png"
  python3 - <<PY
from AppKit import NSPasteboard
import os
pb = NSPasteboard.generalPasteboard()
data = pb.dataForType_("public.png")
if not data:
    raise SystemExit("No PNG in clipboard")
os.makedirs("$OUT_DIR", exist_ok=True)
data.writeToFile_atomically_("$OUT_DIR/$label.window.png", False)
print("Saved: $OUT_DIR/$label.window.png")
PY

  [[ -s "$OUT_DIR/$label.window.png" ]] || die "window screenshot not created for $label"

  log "Crop panel -> $OUT_DIR/$label.panel.png"
  python3 - <<PY
import json
from PIL import Image

meta = json.load(open("$OUT_DIR/$label.meta.json"))
img = Image.open("$OUT_DIR/$label.window.png")
img_w, img_h = img.size

# This script uses iterm2_activate_and_crop.py output.
# - frame: panel rect in iTerm2 coordinates
# - rawWindowFrame.y: menu bar offset used by iTerm2 window.frame
f = meta.get("frame") or {}
wf = meta.get("rawWindowFrame") or {}

x = int(float(f.get("x", 0)))
y = int(float(f.get("y", 0)))
w = int(float(f.get("w", 0)))
h = int(float(f.get("h", 0)))
window_y = int(float(wf.get("y", 0)))

if w <= 0 or h <= 0:
    raise SystemExit(f"Invalid frame: {f}")

left = x
# Convert from bottom-left-ish to top-left screenshot coords.
top = img_h - (y + h) - window_y
right = left + w
bottom = top + h

# Clamp.
left = max(0, min(img_w, left))
right = max(0, min(img_w, right))
top = max(0, min(img_h, top))
bottom = max(0, min(img_h, bottom))

img.crop((left, top, right, bottom)).save("$OUT_DIR/$label.panel.png")
print("Saved:", "$OUT_DIR/$label.panel.png")
print("Box:", (left, top, right, bottom), "Image:", img.size, "window_y:", window_y)
PY

  [[ -s "$OUT_DIR/$label.panel.png" ]] || die "panel crop not created for $label"
}

activate_and_capture "A1" "$SESSION_A"
activate_and_capture "B1" "$SESSION_B"
activate_and_capture "A2" "$SESSION_A"

log "Done. Outputs: $OUT_DIR"
ls -lh "$OUT_DIR"/*.panel.png "$OUT_DIR"/*.window.png "$OUT_DIR"/*.meta.json "$OUT_DIR"/sessions.json
