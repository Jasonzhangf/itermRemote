#!/bin/bash
set -euo pipefail

# Simple static window screenshot tool for macOS.
#
# Usage:
#   tools/window_screenshot.sh --list
#   tools/window_screenshot.sh --window-id 123 --out /tmp/w.png
#
# Notes:
# - Uses /usr/sbin/screencapture, which requires Screen Recording permission.

out="/tmp/window.png"
win_id=""
list=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)
      out="$2"; shift 2;;
    --window-id)
      win_id="$2"; shift 2;;
    --list)
      list=1; shift;;
    *)
      echo "Unknown arg: $1" >&2
      exit 2;;
  esac
done

if [[ $list -eq 1 ]]; then
  # CGWindow window numbers are not easily queryable without APIs; show user-facing list.
  echo "screencapture does not provide a window list; use the on-screen picker:"
  echo "  screencapture -i -W /tmp/picked.png"
  exit 0
fi

if [[ -z "$win_id" ]]; then
  echo "--window-id is required (or use --list for picker instructions)" >&2
  exit 2
fi

mkdir -p "$(dirname "$out")"
/usr/sbin/screencapture -l "$win_id" -x "$out"
echo "Saved: $out"
