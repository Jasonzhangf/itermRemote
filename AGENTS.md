# AGENTS.md

本文件定义本仓库的强制规则与开发流程，所有自动化与人工提交必须遵守。

## 任务管理（强制）

- 本仓库使用 Beads CLI（`bd`）管理具体任务；`AGENTS.md` 只保留通用强制规则。
- 使用 stealth 模式在本地管理任务，不把 beads 数据提交到仓库：`bd init --stealth`。
- 常用命令：
  - `bd ready`：列出无 blocker 的任务
  - `bd create "Title" -p 0`：创建 P0 任务
  - `bd dep add <child> <parent>`：建立依赖（blocked/blocks 关系）
  - `bd show <id>`：查看任务细节/审计

### bd 搜索/过滤（常用）

#### 1) `bd search`：全文检索（标题/描述/ID）

- 基础：
  - `bd search "关键词"`
  - `bd search "authentication bug"`
  - `bd search "itermremote-"`（支持部分 ID）
  - `bd search --query "performance"`

- 常用过滤：
  - `bd search "bug" --status open`
  - `bd search "database" --label backend --limit 10`
  - `bd search "refactor" --assignee alice`
  - `bd search "security" --priority-min 0 --priority-max 2`

- 时间范围：
  - `bd search "bug" --created-after 2025-01-01`
  - `bd search "refactor" --updated-after 2025-01-01`
  - `bd search "cleanup" --closed-before 2025-12-31`

- 排序与展示：
  - `bd search "bug" --sort priority`
  - `bd search "task" --sort created --reverse`
  - `bd search "design" --long`

- `--sort` 支持字段：
  - `priority, created, updated, closed, status, id, title, type, assignee`

#### 2) `bd list`：字段级精确过滤（缩小范围）

- 按状态/优先级/类型：
  - `bd list --status open --priority 1`
  - `bd list --type bug`

- 按标签：
  - `bd list --label bug,critical`（AND：必须同时拥有）
  - `bd list --label-any frontend,backend`（OR：任意一个即可）

- 按字段包含（子串匹配）：
  - `bd list --title-contains "auth"`
  - `bd list --desc-contains "implement"`
  - `bd list --notes-contains "TODO"`

- 按日期范围：
  - `bd list --created-after 2024-01-01`
  - `bd list --updated-before 2024-12-31`
  - `bd list --closed-after 2024-01-01`

- 空字段筛选：
  - `bd list --empty-description`
  - `bd list --no-assignee`
  - `bd list --no-labels`

- 优先级范围：
  - `bd list --priority-min 0 --priority-max 1`
  - `bd list --priority-min 2`

- 组合过滤：
  - `bd list --status open --priority 1 --label-any urgent,critical --no-assignee`

## 核心原则

1. **从小开始构建**：每个模块先实现基础版本，通过功能测试后才能提交。
2. **测试先行**：新增任何功能必须有完整单元测试；可做 E2E 的最终必须做一次端到端测试。
3. **持续可用**：每次提交必须能构建、能通过测试、能通过 CI。
4. **测试后人工确认**：每次跑完测试（单测/E2E/回环截图验证等）必须人工检查输出（日志/截图/视频/指标）是否符合预期；禁止只看“测试通过”就判定完成。

## Build Gate（强制）

1. **未跟踪文件阻断构建**：
   - 在 `packages/` 或 `apps/` 下发现未被 git 跟踪的文件时，构建必须失败。
   - 允许的临时文件必须放在 `.gitignore` 忽略目录（如 `build/`、`.dart_tool/`）。

2. **README 必须最新**：
   - 每个模块的 `README.md` 必须由脚本生成（包含 MANUAL + AUTO-GEN 两部分）。
   - 构建前会重新生成 README，若与提交内容不一致则构建失败。

## README 规范（强制）

每个模块目录必须包含：

- `README.md`（自动生成 + 人工说明两部分；禁止直接手工改写 AUTO-GEN 部分）
- `README_MANUAL.md`（人工编写，可选：用于补充模块说明；由脚本合并进 README.md）
- `DEBUG_NOTES.md`（可选，建议维护）
- `ERROR_LOG.md`（可选，建议维护）
- `UPDATE_HISTORY.md`（可选，建议维护）

README.md 结构（强制）：

1. **MANUAL 部分**（顶部，人工编写）：
   - 模块功能与作用
   - 设计决策与约束
   - 使用说明
   - 依赖关系

2. **AUTO-GEN 部分**（底部，由脚本生成）：
   - 模块架构说明
   - 每个文件的说明（优先读取头部 `///` 注释）
   - 调试经验与错误记录
   - 更新历史

分隔符（强制）：

MANUAL 部分与 AUTO-GEN 部分之间必须有明确的分隔线：

```markdown
---
## AUTO-GEN (以下内容由脚本生成，禁止手工修改)
---
```

生成规则（强制）：

- 构建前会重新生成 README.md（合并 README_MANUAL.md + 自动生成内容）
- 若与提交内容不一致则构建失败
- 手工修改只允许在 README_MANUAL.md 中进行

## 文档索引（强制）

1. 顶层文档索引：根目录 `INDEX.md`
   - 只列出路径（不需要写详细内容）
   - 包含：各模块 README 路径 + AGENTS.md 路径

2. 模块 README 位置（强制）：
   - 每个模块的 README.md 放在模块代码根目录

## CI / CD 规则（强制）

1. CI 必须包含：
   - build gate（未跟踪文件检查）
   - README freshness 检查
   - 各模块单元测试
   - E2E 测试（条件具备时）

2. 只有 CI 全绿的 commit 才允许合并。

## 运行时监控规则（强制）

1. 内存监控必须作为系统级常驻服务运行（launchd）。禁止依赖 wrapper 脚本来启动监控。
2. 监控服务配置模板：`scripts/itermremote.memory-monitor.plist`。
3. 默认监控脚本：`scripts/monitor_memory.py`，默认目标进程名：`host_test_app`。
4. 日志/状态文件必须写入可写目录（推荐 `/tmp/itermremote-memory-monitor` 或通过 `--state-dir` 指定）。

## 交付阶段（通过 bd 管理）

- 交付阶段与里程碑拆分到 bd 中管理（epic/task/sub-task）。
- 本文件仅保留门禁与流程规则；不要在此维护阶段任务清单。

## 提交策略

1. **每次提交必须可用**：
   - 通过所有测试
   - 可构建

2. **功能拆分提交**：
   - 每个功能在独立提交中完成（避免混合变更）

3. **测试与功能绑定**：
   - 功能实现与测试必须在同一提交中出现
