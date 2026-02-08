#!/usr/bin/env python3

"""WS-level WebRTC loopback smoke test.

Requirements:
  - python3
  - pip install websockets (only if not already available)

This talks to host_daemon over WS and tries:
  - system.listBlocks
  - webrtc.startLoopback
  - webrtc.stopLoopback

It writes all responses to an output dir under /tmp.
"""

from __future__ import annotations

import asyncio
import json
import os
import time
from pathlib import Path


def _now_ts() -> str:
    return str(int(time.time()))


async def _ws_roundtrip(ws, msg: dict) -> dict:
    await ws.send(json.dumps(msg))
    raw = await ws.recv()
    try:
        return json.loads(raw)
    except Exception:
        return {"_raw": raw}


async def main() -> int:
    host = "127.0.0.1"
    port = int(os.environ.get("ITERMREMOTE_WS_PORT", "8766"))
    url = f"ws://{host}:{port}"

    out_dir = Path(f"/tmp/itermremote-webrtc-test-{_now_ts()}")
    out_dir.mkdir(parents=True, exist_ok=True)
    print(f"[test_webrtc] url={url}")
    print(f"[test_webrtc] out_dir={out_dir}")

    try:
        import websockets  # type: ignore
    except Exception as e:
        (out_dir / "error.txt").write_text(
            "Missing dependency: websockets\n"
            "Install: python3 -m pip install websockets\n\n"
            f"Import error: {e}\n"
        )
        print("[test_webrtc] ERROR: python websockets not installed")
        return 2

    # Wait for daemon
    deadline = time.time() + 20
    last_err = None
    while time.time() < deadline:
        try:
            async with websockets.connect(url) as ws:
                await ws.close()
                break
        except Exception as e:
            last_err = e
            await asyncio.sleep(0.5)
    else:
        (out_dir / "connect_error.txt").write_text(str(last_err))
        print(f"[test_webrtc] ERROR: daemon not reachable: {last_err}")
        return 1

    async with websockets.connect(url) as ws:
        blocks = await _ws_roundtrip(
            ws,
            {
                "version": 1,
                "type": "cmd",
                "id": "test-1",
                "target": "system",
                "action": "listBlocks",
            },
        )
        (out_dir / "blocks_list.json").write_text(json.dumps(blocks, indent=2))
        blocks_list = blocks.get("data", {}).get("blocks", [])
        print(f"[test_webrtc] blocks={blocks_list}")

        start = await _ws_roundtrip(
            ws,
            {
                "version": 1,
                "type": "cmd",
                "id": "test-2",
                "target": "webrtc",
                "action": "startLoopback",
                "payload": {"sourceId": "iTerm2"},
            },
        )
        (out_dir / "start_response.json").write_text(json.dumps(start, indent=2))
        print(f"[test_webrtc] start.success={start.get('success')}")

        await asyncio.sleep(3)

        stop = await _ws_roundtrip(
            ws,
            {
                "version": 1,
                "type": "cmd",
                "id": "test-3",
                "target": "webrtc",
                "action": "stopLoopback",
            },
        )
        (out_dir / "stop_response.json").write_text(json.dumps(stop, indent=2))
        print(f"[test_webrtc] stop.success={stop.get('success')}")

    print("[test_webrtc] done")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
