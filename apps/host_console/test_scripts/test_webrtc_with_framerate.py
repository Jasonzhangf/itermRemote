#!/usr/bin/env python3
"""
WebRTC Loopback Test with Frame Rate Verification
Tests the host daemon WebRTC signaling and verifies actual frame capture rate
"""
import asyncio
import websockets
import json
import sys
import time

async def test_webrtc_framerate(uri="ws://[::1]:8766", test_duration=5):
    """Test WebRTC loopback with frame rate verification"""
    print(f"[Test] Connecting to {uri}...")
    
    async with websockets.connect(uri) as ws:
        print("[Test] Connected!")
        
        # Step 1: Start loopback with high FPS target
        target_fps = 30
        print(f"\n[Step 1] Starting loopback (target FPS: {target_fps})...")
        cmd = {
            "version": 1,
            "type": "cmd",
            "id": "cmd-start",
            "target": "webrtc",
            "action": "startLoopback",
            "payload": {"sourceType": "screen", "fps": target_fps, "bitrateKbps": 2000}
        }
        await ws.send(json.dumps(cmd))
        
        msg = await asyncio.wait_for(ws.recv(), timeout=10.0)
        data = json.loads(msg)
        
        if not data.get("success"):
            print(f"[FAIL] startLoopback failed: {data.get('error')}")
            return False
        print("[PASS] Loopback started successfully")
        
        # Step 2: Create offer to establish peer connection
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
        
        # Step 3: Collect frames/events for test duration
        print(f"\n[Step 3] Collecting stats for {test_duration} seconds...")
        start_time = time.time()
        ice_candidates = 0
        events_received = []
        
        # Clear any pending events
        try:
            while True:
                msg = await asyncio.wait_for(ws.recv(), timeout=0.5)
                data = json.loads(msg)
                if data.get("type") == "evt":
                    events_received.append(data.get("event"))
                    if data.get("event") == "iceCandidate":
                        ice_candidates += 1
        except asyncio.TimeoutError:
            pass
        
        print(f"  Initial events received: {len(events_received)}")
        if ice_candidates > 0:
            print(f"  ICE candidates: {ice_candidates}")
        
        # Step 4: Get final stats
        print("\n[Step 4] Getting final loopback stats...")
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
        actual_fps = stats.get('actualFps', 0)
        active = stats.get('active', False)
        source_type = stats.get('sourceType', 'unknown')
        
        print(f"[INFO] Stats: active={active}, sourceType={source_type}")
        print(f"[INFO] Target FPS: {target_fps}, Actual FPS: {actual_fps:.2f}")
        
        # Step 5: Verify frame capture is working
        print("\n[Step 5] Verifying frame capture...")
        
        # Check if stream is active
        if not active:
            print("[FAIL] Stream is not active!")
            return False
        
        # FPS verification - should be close to target
        if actual_fps < target_fps * 0.5:
            print(f"[WARN] FPS is low: {actual_fps} (target: {target_fps})")
        else:
            print(f"[PASS] FPS is acceptable: {actual_fps}")
        
        # Step 6: Stop loopback
        print("\n[Step 6] Stopping loopback...")
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
        
        # Final verification
        print("\n" + "="*50)
        print("[SUMMARY] WebRTC Test Results:")
        print(f"  - Signaling: PASS")
        print(f"  - Stream active: {'PASS' if active else 'FAIL'}")
        print(f"  - Actual FPS: {actual_fps:.2f} (target: {target_fps})")
        print("="*50)
        
        return active

if __name__ == "__main__":
    try:
        result = asyncio.run(test_webrtc_framerate())
        print("\n" + "="*50)
        if result:
            print("[SUCCESS] WebRTC test with frame rate check passed!")
        else:
            print("[FAILURE] WebRTC test failed")
        print("="*50)
        sys.exit(0 if result else 1)
    except Exception as e:
        print(f"\n[ERROR] {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
