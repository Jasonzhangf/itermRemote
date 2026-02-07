# Android Client Architecture

## 层次结构

```
┌─────────────────────────────────────────┐
│  UI Layer (Flutter Widgets)             │
│  - pages/                                │
│  - widgets/                              │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│  App Layer (Orchestration)              │
│  - CLI interface                         │
│  - WebSocket control                     │
│  - State machine                         │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│  Block Layer (功能模块)                  │
│  - iterm2_block                          │
│  - webrtc_block                          │
│  - input_block                           │
│  - verify_block                          │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│  State Manager (全局状态)                │
│  - Redux/Provider                        │
│  - Session lifecycle                     │
│  - Connection state                      │
└─────────────────────────────────────────┘
```

## 核心原则

1. **UI 与 Logic 分离**
   - UI 只负责渲染和用户交互
   - 业务逻辑在 App 层编排

2. **Block 是独立功能单元**
   - 每个 Block 实现一个完整功能
   - Block 之间通过状态机协调

3. **状态机管理全局状态**
   - 单一数据源
   - 状态变更可追踪

4. **CLI 接口**
   - App 可以通过 CLI 控制
   - WebSocket 暴露状态和控制接口

## 目录结构

```
apps/android_client/
├── lib/
│   ├── main.dart                    # 入口
│   ├── pages/                       # UI 页面
│   │   ├── streaming_page.dart      # 远程控制主页
│   │   ├── connect_page.dart        # 设备列表
│   │   └── settings_page.dart       # 设置
│   ├── widgets/                     # UI 组件
│   │   ├── floating_shortcut_button.dart  # 悬浮快捷键按钮
│   │   ├── shortcut_toolbar.dart    # 快捷键工具栏
│   │   └── system_keyboard_panel.dart # 系统键盘面板
│   ├── app/                         # App 层
│   │   ├── orchestrator.dart        # 编排器
│   │   ├── cli_server.dart          # CLI WebSocket 服务
│   │   └── state_machine.dart       # 状态机
│   ├── blocks/                      # Block 层（复用 packages）
│   │   └── ... (link to packages/itermremote_blocks)
│   └── state/                       # 状态管理
│       ├── app_state.dart
│       └── app_store.dart
└── cli/                             # CLI 工具
    └── client_cli.dart              # 命令行控制工具
```

## 快捷键系统

### 悬浮按钮

- 位置：右下角固定
- 点击：展开快捷键工具栏
- 不占用底部导航

### 快捷键工具栏

- 顶部：流控制（模式/目标切换）
- 中间：方向键（左/右/上/下）
- 底部：自定义快捷键（横向滚动）
- 设置：快捷键配置/IME策略

### 系统输入法

- **完全手动控制**
- 不自动显示/隐藏
- 用户点击键盘按钮触发
- 与快捷键工具栏分离

## 状态流转

```
[User Action] 
    ↓
[UI Widget]
    ↓
[State Dispatch]
    ↓
[App Orchestrator] → [Block Execution]
    ↓                       ↓
[State Update] ←────────────┘
    ↓
[UI Re-render]
```

## WebSocket API

App 层启动 WebSocket 服务器，接受外部控制：

```dart
// 查询状态
ws://localhost:8765/state

// 控制指令
ws://localhost:8765/control
  - connect {deviceId}
  - disconnect
  - switch_panel {index}
  - send_key {keyCode}
```
