# iTerm2 Remote - 文档索引

> **项目目标**: 把 Host 能力重构为可常驻的系统服务（daemon），通过 WebSocket 控制与状态广播驱动各功能 block；UI 只做呈现与操作。
> **开发原则**: 从小开始构建；新增功能必须有单测；可做 E2E 的必须做一次端到端；CI 门禁阻止未跟踪文件与过时 README。

---

## 快速导航

- [项目规则](#项目规则) - AGENTS.md
- [架构规划](#架构规划) - PLAN.md
- [任务跟踪](#任务跟踪) - task.md

---

## 模块文档

### 应用层 (apps/)

- **[host_daemon](apps/host_daemon/README.md)** - 系统服务守护进程（WebSocket Server + Blocks 编排）
- **[host_console](apps/host_console/README.md)** - Flutter UI 客户端（通过 WS 连接 daemon）
- **[android_client](apps/android_client/README.md)** - Android 客户端

### 核心包 (packages/)

- **[cloudplayplus_core](packages/cloudplayplus_core/README.md)** - 共享核心库（实体、网络、iTerm2 裁切）
- **[iterm2_host](packages/iterm2_host/README.md)** - Host 端核心逻辑（iTerm2 Bridge、Stream Host）
- **[itermremote_protocol](packages/itermremote_protocol/README.md)** - WebSocket 通信协议（Cmd/Ack/Evt）
- **[itermremote_blocks](packages/itermremote_blocks/README.md)** - 功能块抽象与注册（Block 接口、Registry）

### 插件 (plugins/)

- **[flutter-webrtc](plugins/flutter-webrtc/README.md)** - flutter_webrtc 插件（本地修改版，禁用 eager thumbnail）

### 系统模块 (src/modules/)

- **[observability](src/modules/observability/README.md)** - 可观测性模块（RunLogger：日志 + 快照）

### 示例 (examples/)

- **[host_test_app](examples/host_test_app/README.md)** - 回环验证测试应用

---

## 规则文档

- **[AGENTS.md](AGENTS.md)** - 项目强制规则与开发流程
  - 任务管理（bd cli）
  - 核心原则（从小开始、测试先行、持续可用）
  - Build Gate（未跟踪文件、README freshness）
  - README 规范（自动生成 + 人工说明）
  - CI/CD 规则
  - 运行时监控规则

- **[PLAN.md](PLAN.md)** - 架构重构规划（Daemon + Blocks + WS）

- **[task.md](task.md)** - 任务跟踪文档

---

## 开发文档 (docs/)

- **[架构设计](docs/architecture.md)** - 系统架构说明
- **[API 文档](docs/api.md)** - API 接口文档
- **[测试指南](docs/testing.md)** - 测试规范与 E2E 流程
- **[调试笔记](docs/debug/iterm2_crop_coordinates.md)** - iTerm2 裁切坐标调试记录

---

## 脚本 (scripts/)

- **[gen_readme.sh](scripts/gen_readme.sh)** - README 自动生成脚本
- **[test/run_e2e.sh](scripts/test/run_e2e.sh)** - E2E 测试入口

---

## 技术栈

- **语言**: Dart (Flutter), Python (iTerm2 API)
- **通信**: WebSocket (JSON 协议)
- **音视频**: WebRTC (flutter_webrtc), ScreenCaptureKit (macOS)
- **测试**: dart test, Playwright (E2E)

---

## 参考项目

- [cloudplayplus_stone](https://github.com/Jasonzhangf/cloudplayplus_stone) - 参考实现
- [iTerm2 Python API](https://iterm2.com/python-api/) - iTerm2 API 文档
- [flutter-webrtc](https://github.com/flutter-webrtc/flutter-webrtc) - WebRTC Flutter 插件
