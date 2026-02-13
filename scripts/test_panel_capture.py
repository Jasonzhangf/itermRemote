#!/usr/bin/env python3
"""
Test WebRTC loopback via WebSocket.
Tests: startLoopback with screen capture.
"""
import websocket
import json
import subprocess
import sys
import time

def test_loopback():
    ws = websocket.create_connection("ws://127.0.0.1:8766/ws")

    # 1. Start loopback with screen capture
    print("=== 1. Start Loopback ===")
    start_cmd = {
        "version": 1,
        "type": "cmd",
        "id": "test-start",
        "target": "webrtc",
        "action": "startLoopback",
        "payload": {
            "sourceType": "screen",
            "fps": 30,
            "bitrateKbps": 3000
        }
    }
    print(f"Sending command: {json.dumps(start_cmd, indent=2)}")

    # Record time before sending
    time.sleep(0.5)  # Brief pause to separate logs
    ws.send(json.dumps(start_cmd))
    resp = ws.recv()
    data = json.loads(resp)
    print(f"Start response: success={data.get('success')}")
    state = data.get("data", {})
    print(f"  loopbackActive: {state.get('loopbackActive')}")
    print(f"  loopbackSourceType: {state.get('loopbackSourceType')}")
    print(f"  loopbackSourceId: {state.get('loopbackSourceId')}")
    print(f"  Error: {data.get('code')}: {data.get('message')}")
    if not data.get('success'):
        print(f"  Full response: {json.dumps(data, indent=2)}")

    ws.close()

    # Show recent host daemon logs for debugging
    time.sleep(1)  # Wait a moment for logs to flush
    print("\n=== 2. Host Daemon Logs (last 15s) ===")
    result = subprocess.run(
        ["log", "show", "--style", "compact", "--last", "15s",
         "--predicate", 'process == "itermremote"'],
        capture_output=True,
        text=True
    )
    relevant_lines = []
    for line in result.stdout.split('\n'):
        # Filter for WebRTC, display media, loopback, errors, or print output
        line_lower = line.lower()
        if any(kw in line_lower for kw in ['webrtc', 'getdisplay', 'loopback', 'error', 'fail', 'start', 'params', 'stream']):
            relevant_lines.append(line)
    if relevant_lines:
        for line in relevant_lines[-30:]:  # Last 30 relevant lines
            print(f"  {line}")
    else:
        print("  (no relevant logs found)")
        print(f"  Total output lines: {len(result.stdout.split(chr(10)))}")

    if data.get('success') and state.get('loopbackActive'):
        print("\n✅ Loopback test PASSED!")
        return True
    else:
        print(f"\n❌ Loopback test FAILED!")
        print(f"   Code: {data.get('code')}")
        print(f"   Message: {data.get('message')}")
        print(f"   Details: {data.get('details')}")
        return False

if __name__ == "__main__":
    success = test_loopback()
    sys.exit(0 if success else 1)
