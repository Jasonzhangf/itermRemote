# iTerm Remote 任务清单

## 阶段 1: 本地后台启动 App

### 1.1 Host 端启动
- [ ] `apps/host_daemon` 可以后台启动（无窗口）
- [ ] 监听 WebSocket 端口（默认 8766）
- [ ] 启动脚本：`scripts/start_host_daemon.sh`
- [ ] 支持环境变量：`ITERMREMOTE_HEADLESS=1`
- [ ] 输出日志到 `/tmp/itermremote_host.log`

### 1.2 Client 端启动
- [ ] `apps/android_client` 可以后台启动
- [ ] 自动连接本地 `ws://localhost:8766`
- [ ] 启动脚本：`scripts/start_android_client.sh`
- [ ] 输出日志到 `/tmp/itermremote_client.log`

### 1.3 启动验证
- [ ] 检查进程是否运行
- [ ] 检查 WebSocket 连接状态
- [ ] 检查日志无错误

---

## 阶段 2: App 层面控制

### 2.1 CLI 控制接口
- [ ] Host CLI：`apps/host_daemon/bin/daemon_cli.dart`
  - [ ] `status` - 查看当前状态
  - [ ] `list-panels` - 列出 iTerm2 panels
  - [ ] `list-windows` - 列出窗口
  - [ ] `activate-panel <id>` - 激活 panel
  - [ ] `switch-window <id>` - 切换窗口

- [ ] Client CLI：`apps/android_client/bin/client_cli.dart`
  - [ ] `status` - 查看连接状态
  - [ ] `connect <host>` - 连接到 host
  - [ ] `disconnect` - 断开连接
  - [ ] `send-key <keycode>` - 发送按键

### 2.2 WebSocket API
- [ ] Host 暴露 WebSocket 服务（8766）
- [ ] Client 暴露 WebSocket 服务（8767）
- [ ] 定义 JSON-RPC 协议
- [ ] 实现双向消息通信

---

## 阶段 3: Host 端实际功能

### 3.1 窗口切换
- [ ] 使用 `ITerm2Block` 获取窗口列表
- [ ] 实现窗口激活
- [ ] 测试：`scripts/test/test_window_switch.dart`

### 3.2 Panel 切割
- [ ] 使用 `ITerm2Block` 获取 Panel 列表
- [ ] 实现 Panel 激活
- [ ] 支持多 Panel 并排显示
- [ ] 测试：`scripts/test/iterm2_panel_switching_test.dart`

### 3.3 视频编码
- [ ] 使用 `WebRTCBlock` 进行屏幕捕获
- [ ] 实现 H.264/VP8 编码
- [ ] 支持动态码率调整
- [ ] 测试：`scripts/test/test_video_encoding.dart`

### 3.4 数据传输
- [ ] 使用 WebRTC DataChannel 传输控制指令
- [ ] 使用 WebRTC 媒体流传输视频
- [ ] 实现网络拥塞控制
- [ ] 测试：`scripts/test/test_data_channel.dart`

---

## 阶段 4: Client 端实际功能

### 4.1 连接管理
- [ ] 实现 WebSocket 连接到 Host
- [ ] 自动重连机制
- [ ] 连接状态显示
- [ ] 测试：`test/connection_test.dart`

### 4.2 视频串流
- [ ] 使用 `flutter_webrtc` 接收视频流
- [ ] 实现视频渲染
- [ ] 支持全屏/窗口模式
- [ ] 测试：`test/streaming_test.dart`

### 4.3 输入控制
- [ ] 实现键盘输入发送
- [ ] 实现鼠标/触摸事件转换
- [ ] 快捷键系统集成
- [ ] 测试：`test/input_test.dart`

### 4.4 Panel/Window 切换
- [ ] 显示远程 Panel 列表
- [ ] 实现快捷切换
- [ ] 收藏常用目标
- [ ] 测试：`test/shortcuts_test.dart`

---

## 阶段 5: 回环测试

### 5.1 本地回环
- [ ] Host 和 Client 同时启动
- [ ] Client 连接本地 Host
- [ ] 验证完整流程
- [ ] 脚本：`scripts/test/run_loopback_e2e.sh`

### 5.2 E2E 验证
- [ ] 测试 Panel 切换
- [ ] 测试键盘输入
- [ ] 测试视频流质量
- [ ] 截图对比验证
- [ ] 脚本：`scripts/test/full_e2e_validation.py`

### 5.3 性能测试
- [ ] 测试延迟（RTT）
- [ ] 测试帧率（FPS）
- [ ] 测试码率稳定性
- [ ] 输出性能报告

---

## 阶段 6: 日志与调试

### 6.1 日志模块
- [ ] Host 日志：结构化 JSON 格式
- [ ] Client 日志：结构化 JSON 格式
- [ ] 统一日志级别：DEBUG/INFO/WARN/ERROR
- [ ] 日志存储：`/tmp/itermremote_{host|client}.log`

### 6.2 日志对比工具
- [ ] 脚本：`scripts/debug/compare_logs.py`
- [ ] 时间戳对齐
- [ ] 事件关联（request/response）
- [ ] 差异高亮

### 6.3 调试面板
- [ ] Host Console 显示实时日志
- [ ] Android Client 显示连接日志
- [ ] 支持日志导出

---

## 阶段 7: 网络状态管理与编码策略

参考 `cloudplayplus_stone`：

### 7.1 网络状态检测
- [ ] 实现 RTT 探测
- [ ] 丢包率检测
- [ ] 带宽估算
- [ ] 参考：`cloudplayplus_stone/lib/services/network_monitor.dart`

### 7.2 自适应码率
- [ ] 根据网络状况调整码率
- [ ] 实现码率阶梯（360p/480p/720p/1080p）
- [ ] 平滑切换策略
- [ ] 参考：`cloudplayplus_stone/lib/core/adaptive_bitrate.dart`

### 7.3 编码策略
- [ ] H.264 硬编码优先
- [ ] VP8 软编码降级
- [ ] 关键帧间隔优化
- [ ] 参考：`cloudplayplus_stone/lib/core/encoder_config.dart`

### 7.4 拥塞控制
- [ ] 实现 GCC（Google Congestion Control）
- [ ] 动态调整发送速率
- [ ] 缓冲区管理
- [ ] 参考：`cloudplayplus_stone/lib/core/congestion_control.dart`

---

## 验收标准

### Host 端
- ✅ 可以后台运行，无 UI
- ✅ 可以通过 CLI 控制
- ✅ 可以切换 iTerm2 Panel
- ✅ 可以切换窗口
- ✅ 视频编码稳定，FPS ≥ 30
- ✅ RTT ≤ 50ms（本地回环）

### Client 端
- ✅ 可以连接本地 Host
- ✅ 可以显示远程视频流
- ✅ 可以发送键盘/鼠标事件
- ✅ 可以切换 Panel/Window
- ✅ 收藏功能正常

### 回环测试
- ✅ 完整流程通过
- ✅ 截图验证一致
- ✅ 日志无错误
- ✅ 性能指标达标

### 网络管理
- ✅ 网络状态实时更新
- ✅ 自适应码率生效
- ✅ 弱网环境可用（丢包 5% 下可用）

---

## 当前进度

- [x] Android Client UI 完成
- [x] Host Console UI 完成
- [x] Desktop Simulator 完成
- [x] 测试脚本框架完成
- [ ] Host 后台启动
- [ ] Client 连接功能
- [ ] WebRTC 集成
- [ ] 回环测试

## 下一步

**优先级 P0（立即执行）：**
1. 实现 Host 后台启动脚本
2. 实现 Client 连接功能
3. 集成 WebRTC 视频流
4. 完成本地回环测试

**优先级 P1（本周）：**
5. 实现日志模块
6. 实现网络状态检测
7. 实现自适应码率

**优先级 P2（下周）：**
8. 性能优化
9. 完整 E2E 测试
10. 文档完善
