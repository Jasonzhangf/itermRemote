#!/usr/bin/env python3
"""
WebRTC Loopback Test Script - Tests the host daemon WebRTC signaling
Usage: python3 test_webrtc_loopback_final.py
"""
import asyncio
import websockets
import json
import sys

async def test_webrtc_loopback(uri="ws://127.0.0.1:8766"):
    """Test WebRTC loopback functionality"""
    print(f"[Test] Connecting to {uri}...")
    
    async with websockets.connect(uri) as ws:
        print("[Test] Connected!")
        
        # Step 1: Start loopback
        print("\n[Step 1] Starting loopback...")
        cmd = {
            "version": 1,
            "type": "cmd",
            "id": "cmd-start",
            "target": "webrtc",
            "action": "startLoopback",
            "payload": {"sourceType": "screen", "fps": 30, "bitrateKbps": 2000}
        }
        await ws.send(json.dumps(cmd))
        
        msg = await asyncio.wait_for(ws.recv(), timeout=10.0)
        data = json.loads(msg)
        
        if not data.get("success"):
            print(f"[FAIL] startLoopback failed: {data.get('error')}")
            return False
        print("[PASS] Loopback started successfully")
        
        # Step 2: Create offer
        print("\n[Step 2] Creating offer...")
        cmd = {
            "version": 1,
            "type": "cmd",
            "id": "cmd-offer",
            "target": "webrtc",
            "action": "createOffer",
            "payload": {}
        }
        await ws.send(json.dumps(cmd))
        
        msg = await asyncio.wait_for(ws.recv(), timeout=5.0)
        data = json.loads(msg)
        
        if not data.get("success"):
            print(f"[FAIL] createOffer failed: {data.get('error')}")
            return False
        
        offer = data.get("data", {})
        sdp = offer.get("sdp", "")
        print(f"[PASS] Offer created: {len(sdp)} chars")
        
        # Step 3: Get stats
        print("\n[Step 3] Getting loopback stats...")
        cmd = {
            "version": 1,
            "type": "cmd",
            "id": "cmd-stats",
            "target": "webrtc",
            "action": "getLoopbackStats",
            "payload": {}
        }
        await ws.send(json.dumps(cmd))
        
        msg = await asyncio.wait_for(ws.recv(), timeout=5.0)
        data = json.loads(msg)
        
        if not data.get("success"):
            print(f"[FAIL] getLoopbackStats failed: {data.get('error')}")
            return False
        
        stats = data.get("data", {}).get("stats", {})
        print(f"[PASS] Stats: active={stats.get('active')}, sourceType={stats.get('sourceType')}")
        
        # Step 4: Stop loopback
        print("\n[Step 4] Stopping loopback...")
        cmd = {
            "version": 1,
            "type": "cmd",
            "id": "cmd-stop",
            "target": "webrtc",
            "action": "stopLoopback",
            "payload": {}
        }
        await ws.send(json.dumps(cmd))
        
        msg = await asyncio.wait_for(ws.recv(), timeout=5.0)
        data = json.loads(msg)
        
        if not data.get("success"):
            print(f"[FAIL] stopLoopback failed: {data.get('error')}")
            return False
        print("[PASS] Loopback stopped successfully")
        
        return True

if __name__ == "__main__":
    try:
        result = asyncio.run(test_webrtc_loopback())
        print("\n" + "="*50)
        if result:
            print("[SUCCESS] WebRTC signaling test passed!")
        else:
            print("[FAILURE] Some tests failed")
        print("="*50)
        sys.exit(0 if result else 1)
    except Exception as e:
        print(f"\n[ERROR] {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
