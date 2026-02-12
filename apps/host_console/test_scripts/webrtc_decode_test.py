#!/usr/bin/env python3

"""WebRTC decode test using aiortc.

Requirements:
  - python3
  - pip install aiortc av pillow websockets

This script:
  1) connects to host_daemon WS
  2) starts loopback
  3) gets offer
  4) answers with aiortc
  5) receives video frames and saves first frame
"""

from __future__ import annotations

import asyncio
import json
import os
import time
from pathlib import Path

async def run() -> int:
    try:
        import websockets  # type: ignore
        from aiortc import RTCPeerConnection, RTCSessionDescription  # type: ignore
        from aiortc.mediastreams import MediaStreamError  # type: ignore
        from av import VideoFrame  # type: ignore
    except Exception as e:
        print(f"Missing dependencies: {e}")
        print("Install: python3 -m pip install aiortc av pillow websockets")
        return 2

    ws_url = os.environ.get("ITERMREMOTE_WS_URL", "ws://127.0.0.1:8766")
    out_dir = Path(f"/tmp/itermremote-webrtc-decode-{int(time.time())}")
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"[decode] ws={ws_url}")
    print(f"[decode] out_dir={out_dir}")

    async with websockets.connect(ws_url) as ws:
        async def send_cmd(target: str, action: str, payload: dict | None = None) -> dict:
            cmd_id = f"cmd-{int(time.time()*1000)}-{target}-{action}"
            msg = {
                "version": 1,
                "type": "cmd",
                "id": cmd_id,
                "target": target,
                "action": action,
            }
            if payload is not None:
                msg["payload"] = payload
            await ws.send(json.dumps(msg))
            while True:
                raw = await ws.recv()
                if not isinstance(raw, str):
                    continue
                data = json.loads(raw)
                if data.get("type") == "ack" and data.get("id") == cmd_id:
                    return data

        # Start loopback
        start_ack = await send_cmd("webrtc", "startLoopback", {
            "sourceType": "screen",
            "fps": 30,
            "bitrateKbps": 1500,
        })
        print(f"[decode] startLoopback success={start_ack.get('success')}")
        if not start_ack.get("success"):
            (out_dir / "start_error.json").write_text(json.dumps(start_ack, indent=2))
            return 1

        # Offer
        offer_ack = await send_cmd("webrtc", "createOffer")
        print(f"[decode] createOffer success={offer_ack.get('success')}")
        if not offer_ack.get("success"):
            (out_dir / "offer_error.json").write_text(json.dumps(offer_ack, indent=2))
            return 1

        offer = offer_ack.get("data", {})
        sdp = offer.get("sdp")
        if not sdp:
            print("[decode] no SDP in offer")
            return 1

        pc = RTCPeerConnection()
        frame_count = 0
        first_frame_path = out_dir / "first_frame.png"

        @pc.on("track")
        async def on_track(track):
            nonlocal frame_count
            if track.kind != "video":
                return
            print("[decode] video track received")
            while frame_count < 30:
                try:
                    frame = await track.recv()
                except MediaStreamError:
                    break
                if isinstance(frame, VideoFrame):
                    frame_count += 1
                    # Save first frame and log every 10 frames
                    if frame_count == 1 or frame_count % 10 == 0:
                        img = frame.to_image()
                        img.save(first_frame_path)
                        print(f"[decode] saved frame {frame_count} to {first_frame_path}")

        @pc.on("icecandidate")
        async def on_ice(candidate):
            if candidate is None:
                return
            await send_cmd("webrtc", "addIceCandidate", {
                "candidate": candidate.candidate,
                "sdpMid": candidate.sdpMid,
                "sdpMLineIndex": candidate.sdpMLineIndex,
            })

        await pc.setRemoteDescription(RTCSessionDescription(sdp, "offer"))
        answer = await pc.createAnswer()
        await pc.setLocalDescription(answer)

        answer_ack = await send_cmd("webrtc", "setRemoteDescription", {
            "type": "answer",
            "sdp": pc.localDescription.sdp,
        })
        print(f"[decode] setRemoteDescription success={answer_ack.get('success')}")

        deadline = time.time() + 15
        while time.time() < deadline and frame_count < 30:
            await asyncio.sleep(0.2)

        print(f"[decode] frames_received={frame_count}")
        if frame_count == 0:
            print("[decode] No frames received")
            return 1

        stop_ack = await send_cmd("webrtc", "stopLoopback")
        print(f"[decode] stopLoopback success={stop_ack.get('success')}")

        await pc.close()

    return 0

if __name__ == "__main__":
    raise SystemExit(asyncio.run(run()))
