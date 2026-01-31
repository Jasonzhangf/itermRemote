# iTerm2 Remote Streaming Service - Task Tracking

> **项目目标**: 创建独立的 WebRTC 串流服务，支持 iTerm2 深度集成，提供视频串流和纯聊天两种模式。
> **开发原则**: 从小开始构建，每个模块基础版本通过测试后才提交，CI 门禁阻止未跟踪文件和过时 README。

---


- **当前阶段**: Phase 4 - End-to-End Testing (COMPLETED)
- **总体进度**: 5/5 (100%)
- **CI 状态**: ✅ 通过
- **上次更新**: 2026-01-31

---


| 阶段 | 名称 | 状态 | 提交数 |
|------|------|------|--------|
| Phase 0 | Infrastructure & Skeleton | ✅ 已完成 | 1 |
| Phase 1 | Core Module | ✅ 已完成 | 1 |
| Phase 2 | Host Module | ✅ 已完成 | 1 |
| Phase 3 | Android Client Module | ✅ 已完成 | 1 |
| Phase 4 | End-to-End Testing | ✅ 已完成 | 1 |

---


### 目标
建立项目骨架、CI 配置、构建门禁和 README 生成系统。

### 检查清单

- [ ] 创建目录结构
  - [ ] `packages/cloudplayplus_core/lib/{entities,services,utils}`
  - [ ] `packages/iterm2_host/lib/{iterm2,streaming,config}`
  - [ ] `apps/android_client/lib/{pages,widgets,services}`
  - [ ] `scripts/{ci,test,python}`
  - [ ] `test/{unit,integration,e2e}`
  - [ ] `docs`

- [ ] 创建 CI 配置
  - [ ] `.github/workflows/ci.yml`
    - [ ] build-gate job
    - [ ] test-core job
    - [ ] test-host job
    - [ ] test-android job
    - [ ] e2e-test job

- [ ] 创建构建门禁脚本
  - [ ] `scripts/ci/check_untracked.sh`
  - [ ] `scripts/ci/check_readme_fresh.sh`

- [ ] 创建 README 生成脚本
  - [ ] `scripts/gen_readme.sh` (bash wrapper)
  - [ ] `scripts/gen_readme.dart` (Dart implementation)

- [ ] 创建骨架脚本
  - [ ] `scripts/setup_skeleton.sh`
  - [ ] `scripts/test/setup_iterm2_mock.sh`
  - [ ] `scripts/test/run_e2e.sh`

- [ ] 创建占位文件
  - [ ] `packages/cloudplayplus_core/lib/cloudplayplus_core.dart`
  - [ ] `packages/iterm2_host/lib/main.dart`
  - [ ] `apps/android_client/lib/main.dart`

- [ ] 创建 pubspec.yaml 文件
  - [ ] `packages/cloudplayplus_core/pubspec.yaml`
  - [ ] `packages/iterm2_host/pubspec.yaml`
  - [ ] `apps/android_client/pubspec.yaml`

- [ ] 创建测试占位
  - [ ] `packages/cloudplayplus_core/test/core_test.dart`
  - [ ] `packages/iterm2_host/test/host_test.dart`
  - [ ] `apps/android_client/test/client_test.dart`

- [ ] 创建 .gitignore

- [ ] 生成初始 README 文件
  - [ ] `packages/cloudplayplus_core/README.md`
  - [ ] `packages/iterm2_host/README.md`
  - [ ] `apps/android_client/README.md`

- [ ] 运行测试并验证 CI
  - [ ] `bash scripts/test/run_e2e.sh`
  - [ ] 推送到 GitHub 并等待 CI 通过

### 验收标准
- [ ] 所有脚本可执行
- [ ] CI 配置正确，能检测未跟踪文件
- [ ] README 生成后与提交版本一致
- [ ] 所有占位文件存在且能通过基础检查

### 完成时间估算
2-3 小时

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
