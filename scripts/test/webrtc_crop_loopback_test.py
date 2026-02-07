#!/usr/bin/env python3
"""
WebRTC Loopback + Crop E2E Test

This script tests the complete video pipeline:
1. Connect to host_daemon via WebSocket
2. Get iTerm2 panel list (sorted spatially)
3. For each panel:
   - Activate session
   - Start WebRTC loopback with crop rectangle
   - Wait 5 seconds
   - Capture evidence (screenshot + crop)
   - Stop loopback
4. Generate summary report
"""

import argparse
import asyncio
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
    def key(p):
        f = p.get("layoutFrame") or p.get("frame") or {}
        y = float(f.get("y", 0))
        x = float(f.get("x", 0))
        y_bucket = round(y / 5.0) * 5.0
        return (y_bucket, x)
    return sorted(panels, key=key)

def calculate_crop_rect(session, windowFrame, rawWindowFrame):
    """
    Calculate normalized crop rectangle for WebRTC.
    
    Args:
        session: Panel session data with frame/layoutFrame
        windowFrame: iTerm2 window frame
        rawWindowFrame: OS-level window frame (for coordinate conversion)
    
    Returns:
        dict with x, y, width, height (normalized 0-1)
    """
    # Use layoutFrame if available (more stable), else frame
    frame = session.get("layoutFrame") or session.get("frame") or {}
    
    fx = frame.get("x", 0)
    fy = frame.get("y", 0)
    fw = frame.get("w", 0)
    fh = frame.get("h", 0)
    
    ww = windowFrame.get("w", 1)
    wh = windowFrame.get("h", 1)
    
    # Calculate normalized coordinates
    x = fx / ww
    y = fy / wh
    w = fw / ww
    h = fh / wh
    
    # Clamp to 0-1
    x = max(0, min(1, x))
    y = max(0, min(1, y))
    w = max(0, min(1-x, w))
    h = max(0, min(1-y, h))
    
    return {"x": x, "y": y, "width": w, "height": h}

async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ws-url", default="ws://127.0.0.1:8766")
    parser.add_argument("--output-dir", default=f"/tmp/itermremote-webrtc-loopback/{int(time.time())}")
    parser.add_argument("--duration", type=int, default=5)
    parser.add_argument("--fps", type=int, default=30)
    parser.add_argument("--bitrate-kbps", type=int, default=2000)
    args = parser.parse_args()

    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    results = []

    async with websockets.connect(args.ws_url) as ws:
        print(f"Connected to {args.ws_url}")
        
        # Step 1: Get sessions
        print("\n[1/2] Getting iTerm2 sessions...")
        list_ack = await ws_cmd(ws, "iterm2", "getSessions", {})
        if not list_ack.get("success"):
            raise RuntimeError(f"getSessions failed: {list_ack}")
        sessions = list_ack["data"]["sessions"]
        panels = sort_panels_spatial(sessions)
        print(f"Found {len(panels)} panels")
        
        # Step 2: Test each panel
        print(f"\n[2/2] Testing WebRTC loopback for each panel ({args.duration}s each)...")
        
        for idx, p in enumerate(panels, start=1):
            sid = p.get("id")
            title = p.get("title", "")
            print(f"\n[{idx}/{len(panels)}] Testing panel: {title}")
            
            entry = {
                "order": idx,
                "title": title,
                "sessionId": sid,
                "status": "pending",
                "ts": int(time.time() * 1000),
            }
            
            try:
                # Activate session
                print(f"  - Activating session...")
                act = await ws_cmd(ws, "iterm2", "activateSession", {"sessionId": sid})
                if not act.get("success"):
                    raise RuntimeError(f"activate failed: {act}")
                meta = act["data"]["meta"]
                
                # Calculate crop rectangle
                windowFrame = meta.get("windowFrame", {})
                rawWindowFrame = meta.get("rawWindowFrame", {})
                cropRect = calculate_crop_rect(p, windowFrame, rawWindowFrame)
                
                print(f"  - Crop rect (normalized): x={cropRect['x']:.3f}, y={cropRect['y']:.3f}, "
                      f"w={cropRect['width']:.3f}, h={cropRect['height']:.3f}")
                
                # Start WebRTC loopback
                print(f"  - Starting WebRTC loopback (fps={args.fps}, bitrate={args.bitrate_kbps}kbps)...")
                loopback_ack = await ws_cmd(ws, "webrtc", "startLoopback", {
                    "sourceType": "desktop",
                    "sourceId": meta.get("cgWindowId"),
                    "cropRect": cropRect,
                    "fps": args.fps,
                    "bitrateKbps": args.bitrate_kbps,
                })
                
                if not loopback_ack.get("success"):
                    print(f"  - WARNING: startLoopback failed: {loopback_ack.get('error')}")
                    entry["loopbackError"] = loopback_ack.get("error")
                    results.append(entry)
                    continue
                
                entry["loopbackState"] = loopback_ack.get("data", {})
                
                # Wait for video to stabilize
                await asyncio.sleep(2)
                
                # Capture evidence
                print(f"  - Capturing evidence...")
                cap = await ws_cmd(ws, "verify", "captureEvidence", {
                    "evidenceDir": str(out_dir),
                    "sessionId": sid,
                    "cropMeta": meta,
                })
                
                if cap.get("success"):
                    entry.update({
                        "screenshotPng": cap["data"].get("screenshotPng"),
                        "croppedPng": cap["data"].get("croppedPng"),
                        "overlayPng": cap["data"].get("overlayPng"),
                    })
                    print(f"  - Evidence saved: {entry.get('overlayPng')}")
                
                # Get loopback stats
                stats_ack = await ws_cmd(ws, "webrtc", "getLoopbackStats", {})
                if stats_ack.get("success"):
                    entry["loopbackStats"] = stats_ack.get("data", {}).get("stats", {})
                    print(f"  - Stats: {entry.get('loopbackStats')}")
                
                # Wait for remaining duration
                remaining = max(0, args.duration - 2)
                if remaining > 0:
                    await asyncio.sleep(remaining)
                
                # Stop loopback
                print(f"  - Stopping loopback...")
                stop_ack = await ws_cmd(ws, "webrtc", "stopLoopback", {})
                if not stop_ack.get("success"):
                    print(f"  - WARNING: stopLoopback failed: {stop_ack.get('error')}")
                
                entry["status"] = "success"
                
            except Exception as e:
                entry["status"] = "error"
                entry["error"] = str(e)
                print(f"  - ERROR: {e}")
                
                # Try to stop loopback on error
                try:
                    await ws_cmd(ws, "webrtc", "stopLoopback", {})
                except:
                    pass
            
            results.append(entry)
    
    # Generate summary
    summary = {
        "ts": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "wsUrl": args.ws_url,
        "durationSec": args.duration,
        "fps": args.fps,
        "bitrateKbps": args.bitrate_kbps,
        "total": len(results),
        "success": len([r for r in results if r["status"] == "success"]),
        "failed": len([r for r in results if r["status"] != "success"]),
        "results": results,
    }
    
    summary_path = out_dir / "webrtc_loopback_summary.json"
    with open(summary_path, "w") as f:
        json.dump(summary, f, indent=2)
    
    print(f"\n{'='*60}")
    print(f"Test complete!")
    print(f"Summary: {summary['success']}/{summary['total']} panels passed")
    print(f"Output: {summary_path}")
    print(f"{'='*60}")

if __name__ == "__main__":
    asyncio.run(main())
