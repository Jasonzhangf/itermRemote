#!/usr/bin/env python3
import subprocess
import sys


def capture_window_by_title(title_contains: str, out_path: str) -> None:
    # NOTE: macOS Accessibility permission is required for System Events.
    script = f'''
    tell application "System Events"
        tell process "iTerm2"
            set w to first window whose name contains "{title_contains}"
            set wid to id of w
            return wid
        end tell
    end tell
    '''
    proc = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"osascript failed: {proc.stderr.strip()}")

    wid = proc.stdout.strip()
    if not wid:
        raise RuntimeError("no window id returned")

    subprocess.run(["/usr/sbin/screencapture", "-l", wid, "-x", out_path], check=True)
    print(f"Saved: {out_path}")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: tools/capture_window_by_title.py <title_contains> <out.png>")
        raise SystemExit(1)
    capture_window_by_title(sys.argv[1], sys.argv[2])
