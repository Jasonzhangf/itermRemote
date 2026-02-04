# observability

## 功能与作用

系统级可观测性模块：统一提供日志（log）与快照（PNG）落盘能力。

主要目标：
- 让每次回环验证/运行时问题可复现
- 让 CI 或人工排查时有明确的证据包（log + screenshot）

## 设计决策与约束

- 必须是系统级模块：daemon / blocks / apps 都可复用
- 输出目录必须可写（默认 `/tmp/itermremote_logs`）
- 每次运行必须生成独立 run-id 目录

## 使用说明

- RunLogger：
  - writeLine(): 写入 run.log
  - writeJson(): 写入结构化 JSON
  - writePng(): 写入 PNG 快照

## 依赖关系

- 纯 Dart/Flutter，无外部服务依赖

---
## AUTO-GEN (以下内容由脚本生成，禁止手工修改)
---

### Module Path
`src/modules/observability`

### pubspec.yaml
`pubspec.yaml`

### Files

```
lib/observability.dart
lib/run_logger.dart
pubspec.lock
pubspec.yaml
test/run_logger_test.dart
```
