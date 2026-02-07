#!/usr/bin/env python3
"""
Simple WebRTC loopback test using cgWindowId from iTerm2 API.
"""
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

async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ws-url", default="ws://127.0.0.1:8766")
    parser.add_argument("--output-dir", default=f"/tmp/itermremote-webrtc-simple/{int(time.time())}")
    parser.add_argument("--fps", type=int, default=30)
    parser.add_argument("--bitrate", type=int, default=2000)
    args = parser.parse_args()

    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    results = []

    async with websockets.connect(args.ws_url) as ws:
        # Get sessions
        list_ack = await ws_cmd(ws, "iterm2", "getSessions", {})
        if not list_ack.get("success"):
            raise RuntimeError(f"getSessions failed: {list_ack}")
        sessions = list_ack["data"]["sessions"]
        
        # Sort by layoutFrame (row-major: y asc, x asc)
        def key(p):
            f = p.get("layoutFrame") or p.get("frame") or {}
            y = float(f.get("y", 0))
            x = float(f.get("x", 0))
            y_bucket = round(y / 5.0) * 5.0
            return (y_bucket, x)
        
        panels = sorted(sessions, key=key)
        
        # Test only first panel for simplicity
        panel = panels[0]
        sid = panel.get("id")
        title = panel.get("title", "")
        
        print(f"Testing panel: {title} ({sid})")
        
        # Activate and get crop metadata
        act_ack = await ws_cmd(ws, "iterm2", "activateSession", {"sessionId": sid})
        if not act_ack.get("success"):
            print(f"ERROR: activateSession failed: {act_ack}")
            return
        
        meta = act_ack["data"]["meta"]
        cg_window_id = meta.get("cgWindowId")
        
        if not cg_window_id:
            print(f"ERROR: No cgWindowId in metadata")
            return
        
        # Calculate normalized crop rect
        lf = panel.get("layoutFrame") or panel.get("frame") or {}
        lwf = panel.get("layoutWindowFrame") or {}
        
        fx = float(lf.get("x", 0))
        fy = float(lf.get("y", 0))
        fw = float(lf.get("w", 0))
        fh = float(lf.get("h", 0))
        lww = float(lwf.get("w", 0))
        lwh = float(lwf.get("h", 0))
        
        crop_rect = {
            "x": fx / lww if lww > 0 else 0,
            "y": fy / lwh if lwh > 0 else 0,
            "w": fw / lww if lww > 0 else 0,
            "h": fh / lwh if lwh > 0 else 0,
        }
        
        print(f"  Crop rect (normalized): x={crop_rect['x']:.3f}, y={crop_rect['y']:.3f}, w={crop_rect['w']:.3f}, h={crop_rect['h']:.3f}")
        print(f"  cgWindowId: {cg_window_id}")
        
        # Start WebRTC loopback
        start_ack = await ws_cmd(ws, "webrtc", "startLoopback", {
            "sourceType": "window",
            "sourceId": str(cg_window_id),
            "cropRect": crop_rect,
            "fps": args.fps,
            "bitrateKbps": args.bitrate,
        })
        
        if not start_ack.get("success"):
            print(f"ERROR: startLoopback failed: {start_ack}")
            return
        
        print(f"  ✓ Loopback started (fps={args.fps}, bitrate={args.bitrate}kbps)")
        
        # Wait for a few seconds
        time.sleep(3)
        
        # Get stats
        stats_ack = await ws_cmd(ws, "webrtc", "getLoopbackStats", {})
        if not stats_ack.get("success"):
            print(f"WARNING: getLoopbackStats failed: {stats_ack}")
        else:
            stats = stats_ack["data"].get("stats", {})
            print(f"  Stats: {json.dumps(stats, indent=2)}")
        
        # Stop loopback
        stop_ack = await ws_cmd(ws, "webrtc", "stopLoopback", {})
        if not stop_ack.get("success"):
            print(f"WARNING: stopLoopback failed: {stop_ack}")
        else:
            print(f"  ✓ Loopback stopped")
        
        results.append({
            "title": title,
            "sessionId": sid,
            "cgWindowId": cg_window_id,
            "cropRect": crop_rect,
            "fps": args.fps,
            "bitrate": args.bitrate,
            "status": "success",
        })
    
    summary = {
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "total": len(results),
        "results": results,
    }
    
    summary_file = out_dir / "summary.json"
    summary_file.write_text(json.dumps(summary, indent=2))
    print(f"\nSummary written to: {summary_file}")

if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
