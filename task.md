# iTermRemote - Task Tracking

> **项目目标**: 把 Host 能力重构为可常驻的系统服务（daemon），通过 WebSocket 控制与状态广播驱动各功能 block；UI 只做呈现与操作。
> **开发原则**: 从小开始构建；新增功能必须有单测；可做 E2E 的必须做一次端到端；CI 门禁阻止未跟踪文件与过时 README。

---


- **当前阶段**: Phase D - Host Daemon + Blocks + WS (IN PROGRESS)
- **CI 状态**: ✅ 通过（以当前 main 分支为准）
- **上次更新**: 2026-02-02

---


| 阶段 | 名称 | 状态 |
|------|------|------|
| Phase A | Protocol + Blocks 基础设施 | 🔄 进行中 |
| Phase B | host_daemon 骨架 + WS server + headless 模式 | 🔄 进行中 |
| Phase C | Core Blocks 迁移（iTerm2/Capture/WebRTC/Verify） | ⏳ 待开始 |
| Phase D | host_console 变薄（WS client + 呈现） | ⏳ 待开始 |

---

## 当前迭代目标（Daemon + Blocks + WS）

### Phase A - Protocol + Blocks
- [ ] 新建 `packages/itermremote_protocol`（Cmd/Ack/Evt + version=1 + 单测）
- [ ] 新建 `packages/itermremote_blocks`（Block 接口 + Registry + EventBus + 单测）

### Phase B - host_daemon 骨架
- [ ] 新建 `apps/host_daemon`（Flutter macOS runner）
- [ ] headless 模式（`ITERMREMOTE_HEADLESS=1` 隐藏窗口，不抢焦点）
- [ ] WS server 单端口（默认 `127.0.0.1:8765`）
- [ ] 提供 orchestrator 基础命令：`subscribe/getState`

### Phase C - 业务 blocks 迁移（验收点：裁切宽度正确）
- [ ] ITerm2Block：panel list + activate + crop meta
- [ ] CaptureBlock：window/source 选择 + crop 应用
- [ ] WebRTCBlock：loopback
- [ ] VerifyBlock：截图证据采集 + 裁切验证

### Phase D - host_console 变薄
- [ ] host_console 变为 WS client
- [ ] UI 展示两种模式：连接 headless daemon / UI daemon


## 验收标准（本轮重构）
- [ ] `packages/itermremote_protocol` / `packages/itermremote_blocks` 单测全绿
- [ ] `apps/host_daemon` headless 模式运行时无 UI 干扰，WS 可控
- [ ] E2E：切换 iTerm2 panel -> loopback -> crop -> 截图验证通过

---


### 目标
实现共享核心库，包含数据模型和流设置，确保 100% 测试覆盖率。

### 检查清单

- [ ] 枚举类型
  - [ ] `lib/entities/stream_mode.dart`
    - [ ] `StreamMode` enum (video, chat)
    - [ ] `StreamModeExtension` with toJson/fromJson
    - [ ] `test/entities/stream_mode_test.dart`
    - [ ] 覆盖率: 100%

  - [ ] `lib/entities/capture_target.dart`
    - [ ] `CaptureTargetType` enum (screen, window, iterm2Panel)
    - [ ] `CaptureTargetTypeExtension` with toJson/fromJson
    - [ ] `test/entities/capture_target_test.dart`
    - [ ] 覆盖率: 100%

- [ ] 数据模型
  - [ ] `lib/entities/iterm2_session.dart`
    - [ ] `ITerm2SessionInfo` class
    - [ ] fromJson/toJson methods
    - [ ] _parseRect helper
    - [ ] `test/entities/iterm2_session_test.dart`
    - [ ] 覆盖率: 100%

  - [ ] `lib/entities/stream_settings.dart`
    - [ ] `StreamSettings` class with all fields
    - [ ] fromJson/toJson methods
    - [ ] copyWith method
    - [ ] _parseRect helper
    - [ ] `test/entities/stream_settings_test.dart`
    - [ ] 覆盖率: 100%

- [ ] 库入口
  - [ ] 更新 `lib/cloudplayplus_core.dart` 导出所有实体

- [ ] 测试验证
  - [ ] `dart test` 全部通过
  - [ ] `dart test --coverage` 覆盖率 >= 90%
  - [ ] `dart analyze` 无警告

- [ ] 更新 README
  - [ ] 运行 `bash scripts/gen_readme.sh`
  - [ ] 提交更新后的 README

### 验收标准
- [ ] 所有实体类完整实现
- [ ] 单元测试覆盖率 >= 90%
- [ ] 所有测试通过
- [ ] README 自动生成且通过 CI 检查

### 完成时间估算
3-4 小时

---


### 目标
实现 macOS 主机服务，包含 iTerm2 Python API 桥接和基础流控制，使用 Mock 脚本进行测试。

### 检查清单

- [ ] Mock Python 脚本
  - [ ] `scripts/python/iterm2_sources.py`
    - [ ] 返回模拟 session 列表
    - [ ] 支持 JSON 输出
  - [ ] `scripts/python/iterm2_activate_and_crop.py`
    - [ ] 返回模拟 frame 信息
    - [ ] 支持 session_id 参数
  - [ ] `scripts/python/iterm2_send_text.py`
    - [ ] 模拟文本发送
    - [ ] 返回成功状态
  - [ ] `scripts/python/iterm2_session_reader.py`
    - [ ] 返回模拟缓冲区内容
    - [ ] 支持 base64 编码

- [ ] iTerm2 Bridge
  - [ ] `lib/iterm2/iterm2_bridge.dart`
    - [ ] `ITerm2Bridge` class
    - [ ] `getSessions()` method
    - [ ] `activateSession()` method
    - [ ] `sendText()` method
    - [ ] `readSessionBuffer()` method
    - [ ] `_runPythonScript()` helper
    - [ ] `ITerm2Exception` class
  - [ ] `test/iterm2/iterm2_bridge_test.dart`
    - [ ] 测试 getSessions
    - [ ] 测试 activateSession
    - [ ] 测试 sendText
    - [ ] 测试 readSessionBuffer
    - [ ] 测试异常处理
    - [ ] 覆盖率: >= 85%

- [ ] 基础流控制（占位）
  - [ ] `lib/streaming/stream_host.dart`
    - [ ] `StreamHost` class skeleton
    - [ ] 基础状态管理
    - [ ] 占位方法
  - [ ] `test/streaming/stream_host_test.dart`
    - [ ] 基础初始化测试

- [ ] 测试脚本
  - [ ] 更新 `scripts/test/setup_iterm2_mock.sh`
    - [ ] 确保所有 mock 脚本存在

- [ ] 测试验证
  - [ ] `dart test` 全部通过
  - [ ] `dart test --coverage` 覆盖率 >= 85%
  - [ ] Mock 脚本可独立运行

- [ ] 更新 README
  - [ ] 运行 `bash scripts/gen_readme.sh`
  - [ ] 提交更新后的 README

### 验收标准
- [ ] 所有 Mock 脚本可执行
- [ ] ITerm2Bridge 完整实现
- [ ] 单元测试覆盖率 >= 85%
- [ ] README 自动生成且通过 CI 检查

### 完成时间估算
4-5 小时

---


### 目标
实现 Android Flutter 客户端基础结构，确保应用可构建和运行。

### 检查清单

- [ ] 应用入口
  - [ ] `lib/main.dart`
    - [ ] `ITerm2RemoteApp` widget
    - [ ] `HomePage` widget
    - [ ] Material Design 主题

- [ ] 基础页面（占位）
  - [ ] `lib/pages/connect_page.dart`
    - [ ] 设备发现 UI
  - [ ] `lib/pages/streaming_page.dart`
    - [ ] 视频渲染占位
    - [ ] 模式切换占位
  - [ ] `lib/pages/chat_page.dart`
    - [ ] 聊天界面占位

- [ ] 基础 Widget（占位）
  - [ ] `lib/widgets/streaming/video_renderer.dart`
  - [ ] `lib/widgets/streaming/panel_switcher.dart`
  - [ ] `lib/widgets/chat/chat_input_field.dart`
  - [ ] `lib/widgets/chat/chat_history_view.dart`

- [ ] 测试
  - [ ] `test/app_test.dart`
    - [ ] 应用构建测试
    - [ ] Widget 基础测试
  - [ ] `test/pages/connect_page_test.dart`
  - [ ] `test/pages/streaming_page_test.dart`

- [ ] Android 配置
  - [ ] `android/app/build.gradle`
    - [ ] minSdkVersion: 21
    - [ ] targetSdkVersion: 34
  - [ ] `android/app/src/main/AndroidManifest.xml`
    - [ ] 必要权限

- [ ] 测试验证
  - [ ] `flutter test` 全部通过
  - [ ] `flutter build apk` 成功
  - [ ] `flutter analyze` 无警告

- [ ] 更新 README
  - [ ] 运行 `bash scripts/gen_readme.sh`
  - [ ] 提交更新后的 README

### 验收标准
- [ ] 应用可构建
- [ ] 基础页面可渲染
- [ ] Widget 测试通过
- [ ] README 自动生成且通过 CI 检查

### 完成时间估算
3-4 小时

---


### 目标
建立端到端测试流程，验证所有模块集成。

### 检查清单

- [ ] E2E 测试脚本
  - [ ] 更新 `scripts/test/run_e2e.sh`
    - [ ] 模拟环境设置
    - [ ] Core 模块测试
    - [ ] Host 模块测试
    - [ ] Android 客户端测试
    - [ ] 集成验证

- [ ] 集成测试
  - [ ] `test/integration/bridge_integration_test.dart`
    - [ ] 测试 Python 脚本调用
    - [ ] 测试数据流转
  - [ ] `test/integration/settings_integration_test.dart`
    - [ ] 测试设置序列化
    - [ ] 测试跨模块兼容性

- [ ] 端到端场景
  - [ ] [E1] Core 序列化/反序列化完整流程
  - [ ] [E2] Host 获取 session 列表
  - [ ] [E3] Host 发送文本到 session
  - [ ] [E4] Host 读取 session 缓冲区
  - [ ] [E5] Android 客户端构建和启动

- [ ] 测试验证
  - [ ] `bash scripts/test/run_e2e.sh` 全部通过
  - [ ] CI E2E job 通过
  - [ ] 覆盖率报告生成

- [ ] 文档
  - [ ] 更新 `docs/architecture.md`
  - [ ] 更新 `docs/api.md`
  - [ ] 更新 `docs/testing.md`

- [ ] 更新 README
  - [ ] 运行 `bash scripts/gen_readme.sh`
  - [ ] 提交更新后的 README

### 验收标准
- [ ] 所有 E2E 测试通过
- [ ] CI 完整流程通过
- [ ] 覆盖率报告生成
- [ ] 文档完整

### 完成时间估算
2-3 小时

---


| 里程碑 | 描述 | 状态 | 目标日期 |
|--------|------|------|----------|
| M1 | 基础设施就绪 | ✅ | Phase 0 完成 |
| M2 | Core 模块完成 | ✅ | Phase 1 完成 |
| M3 | Host 模块完成 | ✅ | Phase 2 完成 |
| M4 | Android 客户端完成 | ✅ | Phase 3 完成 |
| M5 | E2E 测试通过 | ✅ | Phase 4 完成 |

---


| 日期 | 模块 | 问题描述 | 解决方案 | 状态 |
|------|------|----------|----------|------|
| - | - | - | - | - |

---


### 常见问题

1. **CI 构建失败：未跟踪文件**
   - 症状：check_untracked.sh 报错
   - 解决：运行 `git add` 添加文件，或添加到 .gitignore

2. **README 不一致**
   - 症状：check_readme_fresh.sh 报错
   - 解决：运行 `bash scripts/gen_readme.sh` 并提交

3. **Python 脚本权限**
   - 症状：Permission denied
   - 解决：运行 `chmod +x scripts/python/*.py`

---


### [0.4.0] - 2026-01-31
- Phase 4 完成：集成测试 + 文档（architecture/api/testing）
- E2E 脚本跑通全链路（unit + integration）
- 所有测试通过（24/24）

### [0.5.0] - 2026-01-31
- WebRTC 实时编码策略模块完成（多 Profile 支持）
- 三种预设策略：textLatency（文字优先低延迟）/balanced（平衡）/textQuality（文字清晰优先）
- 动态参数调整：maxBitrate/maxFramerate/scaleResolutionDownBy/degradationPreference/scalabilityMode
- 独立可更新子模块：packages/iterm2_host/lib/webrtc/encoding_policy/
- 单元测试覆盖：EncodingPolicyEngine 状态机与 Profile 决策
- 目标：维持 15-30fps，黑底白字场景优化（contentHint=text）

### [0.3.0] - 2026-01-31
- Phase 3 完成：Android 客户端基础结构（三个页面 + 四个 Widget）
- Android 配置完成：minSdk 21, targetSdk 34, 网络权限
- APK 构建成功，所有测试通过（4/4）

### [0.2.0] - 2026-01-31
- Phase 0-2 基础闭环完成（CI/README/Build Gate/Core/Host）
- Host 模块完成 StreamHost 骨架与可测试初始化
- E2E 脚本跑通全链路基础测试

### [0.1.0] - 2026-01-31
- 初始任务跟踪文档
- 定义 4 个开发阶段
- 建立 CI 门禁要求
- 定义测试覆盖率目标

---



---


- [cloudplayplus_stone](https://github.com/Jasonzhangf/cloudplayplus_stone) - 参考项目
- [iTerm2 Python API](https://iterm2.com/python-api/) - iTerm2 API 文档
- [flutter_webrtc](https://github.com/flutter-webrtc/flutter-webrtc) - WebRTC Flutter 插件
- [GitHub Actions](https://docs.github.com/en/actions) - CI/CD 文档

---

## 当前执行：保活 + 崩溃原因抓取

### 已完成
- [x] 确认 main.dart 中已有 crashLog、heartbeat、runZonedGuarded、FlutterError.onError
- [x] 确认 WsServer 中已有端口冲突自动清理逻辑
- [x] 创建 launchd plist 配置文件

### 发现的问题
1. **日志文件未更新**：/tmp/itermremote-host-daemon/stdout.log 和 stderr.log 显示的是旧进程（16:15）的日志
2. **heartbeat 文件缺失**：说明 runZonedGuarded 内的 Timer.periodic 没有执行
3. **WS 端口未监听**：8766 端口一直显示为 not in use，说明 wsServer.start() 未被执行或失败
4. **crash 文件缺失**：说明没有异常被捕获，可能是进程被系统直接杀掉

### 下一步
- [x] 创建 launchd plist 配置
- [ ] 加载 launchd 服务
- [ ] 验证服务启动并查看日志
- [ ] 如果仍然失败，添加更详细的日志输出
