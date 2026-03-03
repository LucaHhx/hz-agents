---
name: create-docs
description: "Manage structured project documentation throughout the full lifecycle. Use when the user wants to: (1) Initialize project docs (triggers: '初始化项目文档', '创建文档结构', 'init docs'), (2) Create a new requirement (triggers: '新建需求', '创建需求', 'new req'), (3) Create a role directory (triggers: '创建角色', 'new role'), (4) Update task status, record decisions, log changes, or manage docs/ structure."
---

# Project Docs (三层架构)

Manage `docs/` directory for project documentation and plan tracking via `scripts/docs.py` CLI.

## Important: Scope Boundary

**This skill handles business/product documentation ONLY.**

- **PM (产品经理)** uses this skill to manage L1 (项目级) + L2 (需求级)
- **Developer** uses this skill to manage L3 (角色级): 技术设计 + 技术任务
- **Technical decisions** (tech stack, architecture, database schema, API design) are NOT part of L1/L2 — they belong in L3

### What Goes Where

| 层级 | 内容 | 负责人 |
|------|------|--------|
| L1 项目级 | 项目概览、核心价值、目标用户、成功指标、需求列表 | PM |
| L2 需求级 | 需求说明、用户场景、验收标准、功能任务、时间线日志 | PM |
| L3 角色级 | 技术选型、架构设计、Schema、API 设计、技术任务 | Dev/QA |

## 三层目录结构

```
docs/
├── project.md              # L1: 项目概览（业务信息）
├── tasks.md                # L1: 需求列表（每行 = 一个需求模块）
├── CHANGELOG.md            # L1: 项目级变更日志
│
├── fixes/                  # 修复记录目录
│   ├── log.md              # 修复索引（表格汇总）
│   ├── 1-<slug>.md         # 单条修复记录（自动编号）
│   └── 2-<slug>.md
│
├── 1-<req-name>/           # L2: 需求目录 (自动编号 + kebab-case)
│   ├── plan.md             # 需求说明、目标、范围、用户场景、验收清单
│   ├── tasks.md            # 需求级任务（功能粒度）
│   ├── log.md              # 时间线日志（决策/变更/测试）
│   │
│   ├── <role-name>/        # L3: 角色目录 (如 backend, frontend, qa)
│   │   ├── design.md       # 技术选型、架构设计、关键决策
│   │   └── tasks.md        # 角色级技术任务
│   │
│   └── <role-name>/        # L3: 可有多个角色
│       ├── design.md
│       └── tasks.md
```

> **编号规则**: `docs.py req` 创建需求时自动递增编号 (1-, 2-, 3-...)，保证文件夹排列顺序。后续命令支持短名称 (`user-system`) 或全名 (`1-user-system`) 引用。

### 每层文件规范

**L1 项目级 (`docs/`)**

| 文件 | 用途 | 格式要点 |
|------|------|----------|
| `project.md` | 项目概览 | 表格式基本信息 + 列表式价值/用户/指标 |
| `tasks.md` | 需求列表 | 表格: `\| # \| 需求 \| 状态 \| 负责人 \| 备注 \|` |
| `CHANGELOG.md` | 变更日志 | Keep a Changelog 格式 (新增/变更/修复/移除) |

**L2 需求级 (`docs/<req-name>/`)**

| 文件 | 用途 | 格式要点 |
|------|------|----------|
| `plan.md` | 需求说明 | 目标/范围/用户场景/时间线/验收清单 |
| `tasks.md` | 功能任务 | 表格: `\| # \| 任务 \| 状态 \| 开始日期 \| 完成日期 \| 备注 \|` |
| `log.md` | 时间线日志 | 按日期分组, `- [类型] 内容`, 最新在前 |

**L3 角色级 (`docs/<req-name>/<role-name>/`)**

| 文件 | 用途 | 格式要点 |
|------|------|----------|
| `design.md` | 技术设计 | 技术选型/架构设计/关键决策 |
| `tasks.md` | 技术任务 | 表格: `\| # \| 任务 \| 状态 \| 开始日期 \| 完成日期 \| 备注 \|` |

## CLI Commands

```bash
SCRIPT=".claude/skills/create-docs/scripts/docs.py"

# L1: 初始化项目
python3 $SCRIPT init <project-root>

# L2: 创建需求 (自动编号: 1-user-system, 2-ledger, ...)
python3 $SCRIPT req <req-name> [--root <project-root>]

# L3: 创建角色
python3 $SCRIPT role <req-name> <role-name> [--root <project-root>]

# 任务管理 (L2 需求级) — req-name 支持短名或全名
python3 $SCRIPT task <req> <description>          # 添加功能任务
python3 $SCRIPT start <req> <task-number>          # 开始任务 (自动写log)
python3 $SCRIPT done <req> <task-number> [--note]  # 完成任务 (自动写log)

# 任务管理 (L3 角色级)
python3 $SCRIPT task <req> <description> --role <role>    # 添加技术任务
python3 $SCRIPT start <req> <task-number> --role <role>   # 开始技术任务
python3 $SCRIPT done <req> <task-number> --role <role>    # 完成技术任务

# 日志
python3 $SCRIPT log <req> <type> <message>
# type: 决策 / 变更 / 修复 / 新增 / 测试 / 备注

# 修复记录
python3 $SCRIPT fix <title> [--severity P0|P1|P2]    # 创建修复记录
python3 $SCRIPT fix-list                               # 查看修复列表

# 状态总览 (三层展示)
python3 $SCRIPT status [req-name]
```

> **名称解析**: 所有命令中的 `<req>` 参数支持短名称 (`user-system`) 和全名 (`1-user-system`)。

## Workflows

### Initialize Docs (L1)

1. Run `docs.py init <project-root>`
2. Fill `project.md` with **business information only**
3. Add initial CHANGELOG entry
4. `docs/tasks.md` 自动创建为空需求列表

### Create Requirement (L2)

1. Ask requirement name (kebab-case) if not provided
2. Run `docs.py req <name>`
3. Fill `plan.md`: 目标 / 范围 / 用户场景 / 时间线 / 验收清单
4. Fill `tasks.md`: 功能级任务拆解
5. Add initial log entries via `docs.py log <name> 决策 <msg>`

### Create Role (L3)

1. Requirement directory must exist first
2. Run `docs.py role <req-name> <role-name>`
3. Fill `design.md`: 技术选型 / 架构设计 / 关键决策
4. Fill `tasks.md`: 技术级任务拆解

### Update Operations

Use CLI commands for standard operations (task/start/done/log). Read `references/update-guide.md` for manual edit guidelines and cross-file consistency rules.

## Conventions

- Req dirs: 自动编号 + kebab-case (e.g., `1-user-system`, `2-ledger`)
- Names: kebab-case (e.g., `user-system`, `ledger`)
- Dates: YYYY-MM-DD
- Task status: 待办 / 进行中 / 已完成 / 已取消
- Log types: 决策 / 变更 / 修复 / 新增 / 测试 / 备注 / 完成
- L2 tasks: 功能/业务级 (e.g., "用户可以注册和登录")
- L3 tasks: 技术实现级 (e.g., "设计用户表 Schema")
- Common role names: `backend`, `frontend`, `qa`, `ui`, `infra`, `mobile`
