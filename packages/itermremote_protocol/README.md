# itermremote_protocol

## 功能与作用

定义 WebSocket 通信协议，用于 host_daemon 与 host_console 之间的消息交换。

## 设计决策与约束

- 使用 JSON 格式，易于调试和扩展
- 支持三种消息类型：Cmd（命令）、Ack（响应）、Evt（事件）
- 每个消息必须有唯一 ID（UUID）
- 版本号机制（version=1）用于协议升级

## 使用说明

### 消息类型

1. **Cmd（命令）**: Client -> Server
   - type: "cmd"
   - id: UUID
   - target: block 名称
   - action: 动作名称
   - payload: 参数对象

2. **Ack（响应）**: Server -> Client
   - type: "ack"
   - id: 对应的 cmd ID
   - success: true/false
   - data: 返回数据或错误信息

3. **Evt（事件）**: Server -> Client（广播）
   - type: "evt"
   - source: block 名称
   - event: 事件类型
   - payload: 事件数据

### 示例

```json
// Cmd: 激活 iTerm2 panel
{
  "type": "cmd",
  "id": "uuid-123",
  "target": "iterm2",
  "action": "activate",
  "payload": { "sessionId": "..." }
}

// Ack: 成功响应
{
  "type": "ack",
  "id": "uuid-123",
  "success": true,
  "data": { "frame": {...} }
}
```

## 依赖关系

- 无外部依赖（纯 Dart）
- 将被 itertermremote_blocks 和 host_daemon 使用

---
## AUTO-GEN (以下内容由脚本生成，禁止手工修改)
---

### Module Path
`packages/itermremote_protocol`

### pubspec.yaml
`pubspec.yaml`

### Files

```
README_MANUAL.md
analysis_options.yaml
lib/itermremote_protocol.dart
pubspec.lock
pubspec.yaml
test/envelope_test.dart
```
