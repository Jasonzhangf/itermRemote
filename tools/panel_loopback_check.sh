#!/bin/bash
set -euo pipefail

# Loopback check for iTerm2 panel switching:
# - Uses python bridge to resolve iTerm2 window frame/windowNumber
# - Uses screencapture to take a static screenshot of the iTerm2 window
# - Stores images for manual verification
#
# This script does NOT crop the image; it captures the whole iTerm2 window.
# Crop verification is done visually by comparing the app's in-app thumbnail/crop.

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
out_dir="${OUT_DIR:-$repo_root/build/panel_loopback}"

mkdir -p "$out_dir"

python_bin="$(/usr/bin/which python3 || true)"
if [[ -z "$python_bin" ]]; then
  echo "python3 not found" >&2
  exit 2
fi

sessions_json="$($python_bin "$repo_root/scripts/python/iterm2_sources.py" 2>/dev/null || true)"
if [[ -z "$sessions_json" ]]; then
  echo "Failed to run scripts/python/iterm2_sources.py" >&2
  echo "- Is iTerm2 running?" >&2
  echo "- Is iTerm2 Python API enabled?" >&2
  echo "- Can python3 import iterm2?" >&2
  exit 3
fi

echo "$sessions_json" > "$out_dir/sessions.json"

echo "Saved sessions list: $out_dir/sessions.json"
echo "Pick TWO sessionIds from sessions.json for loopback (A -> B -> A)."

cat <<EOF

Commands (replace <A> and <B>):

  $python_bin "$repo_root/scripts/python/iterm2_activate_and_crop.py" <A>
  $python_bin "$repo_root/scripts/python/iterm2_activate_and_crop.py" <B>
  $python_bin "$repo_root/scripts/python/iterm2_activate_and_crop.py" <A>

Each call returns JSON with windowId. Use it to take static screenshots:

  /usr/sbin/screencapture -l <windowId> -x "$out_dir/A1.png"
  /usr/sbin/screencapture -l <windowId> -x "$out_dir/B1.png"
  /usr/sbin/screencapture -l <windowId> -x "$out_dir/A2.png"

EOF
