#!/usr/bin/env python3
import argparse
import json
import sys
import time
from pathlib import Path

try:
    import websockets
except ImportError:
    print("Missing dependency: websockets. Install via: pip3 install websockets", file=sys.stderr)
    sys.exit(2)


async def ws_cmd(ws, target, action, payload):
    req_id = f"{target}.{action}.{int(time.time()*1000)}"
    msg = {
        "type": "cmd",
        "version": 1,
        "id": req_id,
        "target": target,
        "action": action,
        "payload": payload,
    }
    await ws.send(json.dumps(msg))
    while True:
        raw = await ws.recv()
        data = json.loads(raw)
        if data.get("id") == req_id:
            return data


def sort_panels_spatial(panels):
    # row-major: top-to-bottom, left-to-right
    # Prefer layoutFrame (stable window coords). Fallback to frame if missing.
    # Observed layoutFrame uses y that increases downward, so row order is y ASC.
    def key(p):
        f = p.get("layoutFrame") or p.get("frame") or {}
        y = float(f.get("y", 0))
        x = float(f.get("x", 0))
        # Normalize y to row buckets to reduce tiny jitter
        y_bucket = round(y / 5.0) * 5.0
        return (y_bucket, x)

    return sorted(panels, key=key)


def _load_json(path: Path):
    return json.loads(Path(path).read_text())


def _save_json(path: Path, obj):
    path.write_text(json.dumps(obj, indent=2))


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ws-url", default="ws://127.0.0.1:8766")
    parser.add_argument("--output-dir", default=f"/tmp/itermremote-panel-switching/{int(time.time())}")
    parser.add_argument("--duration", type=int, default=5)
    args = parser.parse_args()

    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    results = []

    async with websockets.connect(args.ws_url) as ws:
        list_ack = await ws_cmd(ws, "iterm2", "getSessions", {})
        if not list_ack.get("success"):
            raise RuntimeError(f"getSessions failed: {list_ack}")
        sessions = list_ack["data"]["sessions"]
        panels = sort_panels_spatial(sessions)

        # Use the first panel to fetch cropMeta (cgWindowId + window frames) and capture 1 base screenshot.
        first_sid = panels[0].get("id")
        first_title = panels[0].get("title", "")
        print(f"[0/{len(panels)}] capture base window screenshot via first panel: {first_title} {first_sid}")

        base_act = await ws_cmd(ws, "iterm2", "activateSession", {"sessionId": first_sid})
        if not base_act.get("success"):
            raise RuntimeError(f"activate failed: {base_act}")
        base_meta = base_act["data"]["meta"]
        time.sleep(0.25)

        base_cap = await ws_cmd(
            ws,
            "verify",
            "captureEvidence",
            {
                "evidenceDir": str(out_dir),
                "sessionId": first_sid,
                "cropMeta": base_meta,
            },
        )
        if not base_cap.get("success"):
            raise RuntimeError(f"captureEvidence failed: {base_cap}")

        base_data = base_cap["data"]
        base_screenshot = base_data.get("screenshotPng")
        base_crop_meta = base_meta

        # Write a multi-box overlay image (one screenshot, multiple red boxes + order labels)
        overlay_multi_path = out_dir / "window_multi_overlay.png"
        overlay_multi_json = out_dir / "window_multi_overlay.json"

        overlay_payload = {
            "evidenceDir": str(out_dir),
            "screenshotPng": base_screenshot,
            "windowMeta": {
                "rawWindowFrame": base_crop_meta.get("rawWindowFrame"),
            },
            "panels": [
                {
                    "order": i + 1,
                    "title": p.get("title", ""),
                    "sessionId": p.get("id"),
                    # Use layoutFrame if present (more stable), else frame
                    "frame": p.get("layoutFrame") or p.get("frame"),
                }
                for i, p in enumerate(panels)
            ],
            "outputPng": str(overlay_multi_path),
            "outputJson": str(overlay_multi_json),
        }

        # Ask verify block to render overlay. If not supported, we still proceed per-panel.
        multi_ack = await ws_cmd(ws, "verify", "renderMultiPanelOverlay", overlay_payload)
        if not multi_ack.get("success"):
            print(f"WARN: renderMultiPanelOverlay not available: {multi_ack.get('error')}")
        else:
            print(f"Wrote multi overlay: {overlay_multi_path}")

        # Per-panel switching + evidence
        for idx, p in enumerate(panels, start=1):
            sid = p.get("id")
            title = p.get("title", "")
            print(f"[{idx}/{len(panels)}] activate {title} {sid}")
            entry = {
                "order": idx,
                "title": title,
                "sessionId": sid,
                "status": "pending",
                "ts": int(time.time() * 1000),
            }
            try:
                act = await ws_cmd(ws, "iterm2", "activateSession", {"sessionId": sid})
                if not act.get("success"):
                    raise RuntimeError(f"activate failed: {act}")
                meta = act["data"]["meta"]

                time.sleep(0.25)

                cap = await ws_cmd(
                    ws,
                    "verify",
                    "captureEvidence",
                    {
                        "evidenceDir": str(out_dir),
                        "sessionId": sid,
                        "cropMeta": meta,
                    },
                )
                if not cap.get("success"):
                    raise RuntimeError(f"capture failed: {cap}")

                data = cap["data"]
                entry.update(
                    {
                        "status": "success",
                        "screenshotPng": data.get("screenshotPng"),
                        "croppedPng": data.get("croppedPng"),
                        "overlayPng": data.get("overlayPng"),
                        "metaJson": data.get("metaJson"),
                    }
                )
                print(f"  overlay={entry.get('overlayPng')}")

                time.sleep(args.duration)
            except Exception as e:
                entry["status"] = "error"
                entry["error"] = str(e)
                print(f"  ERROR: {e}")

            results.append(entry)

    summary = {
        "ts": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "wsUrl": args.ws_url,
        "order": "row-major (top-to-bottom, left-to-right) using layoutFrame.y asc then layoutFrame.x asc",
        "durationSec": args.duration,
        "total": len(results),
        "success": len([r for r in results if r["status"] == "success"]),
        "failed": len([r for r in results if r["status"] != "success"]),
        "results": results,
    }

    with open(out_dir / "summary.json", "w") as f:
        json.dump(summary, f, indent=2)

    print(f"Wrote summary: {out_dir / 'summary.json'}")


if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
