# Update Guide

## 三层角色权限

| 层级 | 内容 | 谁负责 | 时机 |
|------|------|--------|------|
| L1 | 产品信息 / 核心价值 / 成功指标 | PM | 初始化时 |
| L1 | 需求列表 (`docs/tasks.md`) | PM | 创建需求时 (目录自动编号: `1-xxx`, `2-xxx`) |
| L2 | 需求目标 / 范围 / 用户场景 | PM | 创建需求时 |
| L2 | 功能级任务拆解 / 验收标准 | PM | 创建需求时 |
| L3 | 技术选型 / 框架选择 | Developer | 开发启动时 |
| L3 | 架构设计 / Schema / API | Developer | 开发过程中 |
| L3 | 技术任务拆解 | Developer | 认领需求后 |

## CLI vs Manual Edit

| 操作 | 方法 | 命令 |
|------|------|------|
| 创建需求目录 | CLI | `docs.py req <name>` |
| 创建角色目录 | CLI | `docs.py role <req> <role>` |
| 添加功能任务 | CLI | `docs.py task <req> <desc>` |
| 添加技术任务 | CLI | `docs.py task <req> <desc> --role <role>` |
| 开始任务 | CLI | `docs.py start <req> <num> [--role <role>]` |
| 完成任务 | CLI | `docs.py done <req> <num> [--note] [--role <role>]` |
| 添加日志 | CLI | `docs.py log <req> <type> <msg>` |
| 修改任务描述 | 手动编辑 tasks.md | |
| 取消任务 | 手动编辑 tasks.md，状态改为 已取消 | |
| 修改需求目标/范围 | 手动编辑 plan.md，同时 log 一条 [变更] | |
| 更新项目信息 | 手动编辑 project.md | |
| 更新技术设计 | 手动编辑 design.md | |

## Manual Edit Rules

### tasks.md (L2 功能任务)

- 表格格式: `| # | 任务 | 状态 | 开始日期 | 完成日期 | 备注 |`
- 任务编号递增，不复用已删除编号
- 合法状态: 待办 / 进行中 / 已完成 / 已取消
- 任务描述应为功能级别（"用户可以..."），而非技术级别

### tasks.md (L3 技术任务)

- 同样的表格格式
- 任务描述为技术实现级别（"设计 Schema"、"实现 API"）
- 与 L2 功能任务对应，可在备注中标注关联的 L2 任务编号

### design.md (L3 技术设计)

- 包含: 技术选型、架构设计、关键决策
- 由开发团队在开发启动时填写
- 变更时应在需求 log.md 中记录 [决策] 类型日志

### log.md

- 按日期分组，最新日期在前
- 格式: `- [类型] 内容`
- L3 角色任务操作自动加前缀: `[backend]`, `[frontend]` 等
- 只追加不修改 (append-only)

### plan.md

- 创建后视为基本不可变
- 范围变更时，同时执行: `docs.py log <req> 变更 "范围调整: ..."`

## Cross-File Consistency

- `done` / `start` 命令自动写 log.md（包括 `--role` 操作）
- 范围变更 → 手动 `docs.py log <req> 变更 <msg>`
- 项目级重要变更 → 同时更新根 `docs/CHANGELOG.md`
- 新需求创建 → 同时在 `docs/tasks.md` 中添加一行
- 需求目录使用自动编号 (`1-user-system`, `2-ledger`)，CLI 命令支持短名称和全名引用
