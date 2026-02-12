#!/bin/bash
# 测试公网 IPv6 连接和 iTerm2 窗口裁切

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== 1. 检查网络环境 ==="
echo "公网 IPv4: $(curl -4 -s --max-time 5 ifconfig.co || echo 'N/A')"
echo "公网 IPv6: $(curl -6 -s --max-time 5 ifconfig.co || echo 'N/A')"
echo "本地 IP: $(ifconfig | rg 'inet ' | rg -v '127.0.0.1' | head -1 | awk '{print $2}')"

echo ""
echo "=== 2. 启动 host_daemon (监听所有接口) ==="
bash "$REPO_ROOT/scripts/stop_host_and_client.sh" 2>/dev/null || true

DAEMON_LOG="/tmp/itermremote_daemon_test.log"
DAEMON_APP="$REPO_ROOT/apps/host_daemon/build/macos/Build/Products/Release/itermremote.app"

if [ ! -d "$DAEMON_APP" ]; then
    echo "构建 host_daemon..."
    cd "$REPO_ROOT/apps/host_daemon"
    flutter build macos --release 2>&1 | tee "$DAEMON_LOG"
fi

DAEMON_BIN="$DAEMON_APP/Contents/MacOS/itermremote"
nohup env ITERMREMOTE_HEADLESS=1 ITERMREMOTE_WS_PORT=8766 "$DAEMON_BIN" >> "$DAEMON_LOG" 2>&1 &
DAEMON_PID=$!
echo "Daemon PID: $DAEMON_PID"

sleep 5
if ! lsof -nP -iTCP:8766 -sTCP:LISTEN >/dev/null 2>&1; then
    echo "ERROR: Daemon 未启动"
    exit 1
fi
echo "Daemon 已启动，监听 [::]:8766"

echo ""
echo "=== 3. 测试 iTerm2 窗口裁切 ==="
python3 - << 'PYEOF'
import asyncio
import json
import websockets

async def test_crop():
    uri = "ws://127.0.0.1:8766"
    print(f"连接 {uri}")
    
    async with websockets.connect(uri) as ws:
        # 获取 iTerm2 sessions
        req_id = "test-1"
        await ws.send(json.dumps({
            "version": 1, "type": "cmd", "id": req_id,
            "target": "iterm2", "action": "getSessions"
        }))
        resp = json.loads(await ws.recv())
        sessions = resp.get("data", {}).get("sessions", [])
        print(f"找到 {len(sessions)} 个 iTerm2 session")
        
        if not sessions:
            print("没有 iTerm2 session，跳过裁切测试")
            return
        
        # 选择第一个有 cgWindowId 的 session
        picked = None
        for s in sessions:
            if s.get("cgWindowId"):
                picked = s
                break
        if not picked:
            picked = sessions[0]
        
        session_id = picked.get("id")
        print(f"选择 session: {session_id}")
        
        # 激活 session 并获取 cropRect
        req_id = "test-2"
        await ws.send(json.dumps({
            "version": 1, "type": "cmd", "id": req_id,
            "target": "iterm2", "action": "activateSession",
            "payload": {"sessionId": session_id}
        }))
        resp = json.loads(await ws.recv())
        meta = resp.get("data", {}).get("meta", {})
        
        # 计算归一化 cropRect
        lf = meta.get("layoutFrame", {})
        lwf = meta.get("layoutWindowFrame", {})
        if lwf.get("w") and lwf.get("h"):
            crop = {
                "x": lf.get("x", 0) / lwf["w"],
                "y": lf.get("y", 0) / lwf["h"],
                "w": lf.get("w", 0) / lwf["w"],
                "h": lf.get("h", 0) / lwf["h"],
            }
            print(f"Crop rect (normalized): {crop}")
            
            # 启动 WebRTC loopback with crop
            cg_window_id = meta.get("cgWindowId") or picked.get("cgWindowId")
            print(f"启动 WebRTC loopback (cgWindowId={cg_window_id})")
            
            req_id = "test-3"
            await ws.send(json.dumps({
                "version": 1, "type": "cmd", "id": req_id,
                "target": "webrtc", "action": "startLoopback",
                "payload": {
                    "sourceType": "window",
                    "sourceId": str(cg_window_id),
                    "cropRect": crop,
                    "fps": 30,
                    "bitrateKbps": 2000,
                }
            }))
            resp = json.loads(await ws.recv())
            print(f"startLoopback success={resp.get('success')}")
            
            # 等待并检查状态
            await asyncio.sleep(3)
            req_id = "test-4"
            await ws.send(json.dumps({
                "version": 1, "type": "cmd", "id": req_id,
                "target": "webrtc", "action": "getLoopbackStats"
            }))
            resp = json.loads(await ws.recv())
            stats = resp.get("data", {}).get("stats", {})
            print(f"Loopback stats: {json.dumps(stats, indent=2)}")
            
            if stats.get("actualFps", 0) > 0:
                print("✓ iTerm2 窗口裁切测试通过")
            else:
                print("⚠ 未检测到帧率")
        else:
            print("无法计算 cropRect")

asyncio.run(test_crop())
PYEOF

echo ""
echo "=== 4. 清理 ==="
kill $DAEMON_PID 2>/dev/null || true
echo "测试完成"
