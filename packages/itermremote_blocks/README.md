# itermremote_blocks

## 功能与作用

定义系统级功能模块（Blocks）的统一接口与注册机制。

每个 block 是一个独立的功能单元，例如：
- ITerm2Block：iTerm2 panel 切换与裁切元数据
- CaptureBlock：ScreenCaptureKit 捕获与裁切应用
- WebRTCBlock：loopback / remote WebRTC 流
- VerifyBlock：截图验证、证据采集
- ObservabilityBlock：日志与快照

## 设计决策与约束

- Block 必须无 UI 逻辑
- Block 必须提供：
  - init() / dispose()
  - onCommand(cmd) -> ack
  - eventStream（broadcast）
- Block 通过统一 WS server 注册端点，所有控制指令走 WS
- Block 必须可单元测试

## 使用说明

- host_daemon 启动时创建 BlockRegistry
- 每个 block 注册自己的 name
- WS server 将 cmd 按 target 路由到对应 block
- block 通过 eventStream 广播状态变化

## 依赖关系

- 依赖 itermremote_protocol（消息结构）
- 依赖 itermremote_observability（日志/快照）

---
## AUTO-GEN (以下内容由脚本生成，禁止手工修改)
---

### Module Path
`packages/itermremote_blocks`

### pubspec.yaml
`pubspec.yaml`

### Files

```
analysis_options.yaml
lib/itermremote_blocks.dart
pubspec.lock
pubspec.yaml
test/block_registry_test.dart
```
