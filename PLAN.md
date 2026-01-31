# iTerm2 Remote Streaming Service - Plan

本仓库目标是把 iTerm2 panel 相关能力从参考项目中拆出来，形成一个**独立可运行的 WebRTC 串流服务**（macOS Host）与 Android Flutter 客户端。

核心能力：

1) **视频串流模式**：把 iTerm2 的窗口/Panel（session）作为输出，通过 WebRTC 推送到移动端，接收��户输入交互。
2) **纯聊天模式**：把 iTerm2 session 的 buffer 以压缩/分片方式传输到客户端，客户端解压显示；并提供“预输入 -> 一次性注入 iTerm2”的聊天输入方式。

---

## 关键约束

- 从小开始：每个模块先实现基础版本，通过功能测试后才能提交。
- 每次新增功能必须有完整单元测试；可做 E2E 的最终都必须做一次 E2E。
- CI 门禁：
  - 在指定目录（`packages/`、`apps/`）发现**未被 git 跟踪的文件**即阻断构建。
  - 每个模块 README 必须自动生成，CI 会校验 README 是否为最新产物。

---

## Repository Layout

目标结构（先占位，后逐步填充功能）：

```
itermRemote/
├── packages/
│   ├── cloudplayplus_core/           # 共享核心库：协议/模型/工具（抽取自参考项目）
│   └── iterm2_host/                 # macOS host：iTerm2 Python bridge + WebRTC host
├── apps/
│   └── android_client/              # Flutter Android 客户端
├── scripts/
│   ├── ci/                          # build gate / readme gate
│   ├── python/                      # iTerm2 python scripts（先 mock，后接真 API）
│   └── test/                        # e2e/run scripts
├── test/
│   ├── unit/
│   ├── integration/
│   └── e2e/
├── docs/
├── task.md                          # 项目任务跟踪（强制）
└── PLAN.md                          # 计划落盘（本文件）
```

---

## Phase Plan

### Phase 0 - Infrastructure & Skeleton

目标：建立 CI、门禁、README 自动生成、项目骨架。

必须产物：

- `.github/workflows/ci.yml`
- `scripts/ci/check_untracked.sh`
- `scripts/ci/check_readme_fresh.sh`
- `scripts/gen_readme.sh`
- `scripts/gen_readme.dart`
- `scripts/test/setup_iterm2_mock.sh`
- `scripts/test/run_e2e.sh`
- `.gitignore`

验收：

- push 后 CI 可以跑通（即使功能空壳，也必须全绿）。
- `packages/`、`apps/` 下出现任何未跟踪文件会让 CI fail。
- README 生成后若产生 diff，CI fail。

---

### Phase 1 - Core Module (cloudplayplus_core)

目标：把“协议/模型”做成可复用的 Dart 包，稳定、100% 单测。

范围（先实现最小闭环）：

- `StreamMode`（video/chat）
- `CaptureTargetType`（screen/window/iterm2Panel）
- `ITerm2SessionInfo` 数据结构
- `StreamSettings`（包含 turn 配置字段）
- Core package 入口 `cloudplayplus_core.dart`

验收：

- `dart test` 通过。
- `dart test --coverage` 通过且覆盖率达到 task.md 要求（基础阶段目标 >= 90%，逐步收敛到 100%）。
- README 自动生成且 CI 通过。

---

### Phase 2 - Host Module (iterm2_host)

目标：macOS host 可运行，具备 iTerm2 的 panel list、activate+crop meta、send text、read buffer 的可测试桥接层。

实现策略：

1) 先用 `scripts/python/*` mock 脚本实现所有接口，并且用单测覆盖。
2) 再把 mock 替换为真实 iTerm2 Python API（逐步切换，但每次都要可测）。

必须接口：

- `ITerm2Bridge.getSessions()`
- `ITerm2Bridge.activateSession(sessionId)`
- `ITerm2Bridge.sendText(sessionId, text)`
- `ITerm2Bridge.readSessionBuffer(sessionId, maxBytes)`

验收：

- 单元测试覆盖 mock 与异常分支。
- readme/ci 全绿。

---

### Phase 3 - Android Client Module

目标：客户端可构建、可测试，先落基础 UI 骨架。

范围：

- `HomePage`
- 连接页/串流页/聊天页（占位）
- 基础 widget tests

验收：

- `flutter test` 通过。
- CI 全绿。

---

### Phase 4 - End-to-End Testing

目标：形成一键 E2E 流程（先 mock），最后再替换成真实 iTerm2 环境。

范围：

- `scripts/test/run_e2e.sh` 串联 core/host/android 的测试。
- `test/integration/*` 做跨模块数据流转验证。

验收：

- CI 的 e2e job 全绿。

---

## README Generation Contract (Hard Requirement)

每个模块目录必须存在：

- `README.md`（自动生成，不允许手写）
- `DEBUG_NOTES.md`（可选，但推荐存在；generator 会收集）
- `ERROR_LOG.md`（可选；generator 会收集）
- `UPDATE_HISTORY.md`（可选；generator 会收集）

生成内容至少包含：

- 每个文件的说明（优先读取头部 `///` doc comment）
- 模块架构描述（基于目录结构 + 可选的 `docs/architecture.md`）
- 调试经验、错误记录、更新历史

CI 必须在 build 前生成 README，并校验 `git diff` 是否为空。

---

## Build Gate Contract (Hard Requirement)

- 门禁检查范围：`packages/`、`apps/`
- 任意未跟踪文件（`git ls-files --others --exclude-standard`）匹配上述前缀即 fail。
- 允许的临时/缓存输出必须位于 `.gitignore` 中，且应落在 repo 根部的 `build/`、`.dart_tool/` 等目录。

---

## Implementation Notes (来自参考项目)

- iTerm2 panel list / activate / crop / sendText 在参考项目中通过 Python 脚本实现（可复用思路）。
- WebRTC 部分优先复用参考项目协议与逻辑，但要逐步抽取到 `cloudplayplus_core` 并保持最小依赖。

