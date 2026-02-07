

## iTerm2 Panel Switching Test

**功能**：自动遍历所有 iTerm2 panels，对每个 panel 进行以下测试：
- 激活 panel
- 计算裁切坐标
- 启动 WebRTC loopback 捕获
- 等待 5 秒（可配置）以稳定编码
- 捕获 preview 截图
- 采集 WebRTC stats
- 生成证据包（preview PNG + stats + crop meta）

**用法**：
```bash
cd examples/host_test_app
flutter run -d macos --release lib/verify/iterm2_panel_switching_test.dart
```

**环境变量**：
- `FPS_LIST`: FPS 列表（逗号分隔），默认 `30`
- `BITRATE_KBPS_LIST`: 码率列表（kbps，逗号分隔），默认 `1000`
- `PANEL_SWITCH_SECONDS`: 每个 panel 停留时间（秒），默认 `5`
- `ITERMREMOTE_SWITCHING_OUT_DIR`: 输出目录，默认 `build/verify_switching`

**输出**：
- `switching_summary.json`: 所有 panel 的测试结果汇总
- `switch_{title}_fps{fps}_bps{bitrate}.png`: 每个 panel 的 preview 截图
- `switch_window_overlay.png`: 带红框的窗口捕获（验证裁切）


