# 模块 02 — 项目管理

## 概述

使用 docs 三层架构管理项目全生命周期的文档和任务。

## 三层架构

### L1 — 项目级

```
docs/
├── project.md       # 项目概览（名称、描述、技术栈、团队）
```

由 PM 初始化，所有人只读。

### L2 — 需求级

```
docs/
├── 1-user-system/
│   ├── plan.md      # 业务需求、用户场景、验收标准
│   ├── tasks.md     # 功能级任务列表
│   └── log.md       # 变更记录
├── 2-order-module/
│   ├── plan.md
│   ├── tasks.md
│   └── log.md
```

由 PM 创建和维护，Tech Lead 只读。

### L3 — 角色级

```
docs/1-user-system/
├── backend/
│   ├── design.md    # 后端技术方案
│   └── tasks.md     # 后端技术任务
├── frontend/
│   ├── design.md    # 前端技术方案
│   └── tasks.md     # 前端技术任务
├── qa/
│   ├── design.md    # 测试策略
│   └── tasks.md     # 测试任务
└── ui/
    ├── design.md    # 设计系统
    ├── merge.html   # 响应式设计稿
    └── Introduction.md  # 设计说明
```

由 Tech Lead 创建目录结构，各角色填充内容。

## 角色分工

| 角色 | Agent | 职责 | 读写范围 |
|------|-------|------|---------|
| PM | hz-pm | 业务需求、验收标准 | L1+L2 读写，L3 只读 |
| Tech Lead | hz-tech-lead | 技术选型、架构设计、任务拆解 | L2 只读，L3 读写 |
| UI 设计师 | hz-ui | 视觉设计、设计系统 | L2 只读，ui/ 读写 |
| 前端开发 | hz-frontend | 页面实现、交互逻辑 | L2 只读，frontend/ 读写 |
| 后端开发 | hz-backend | API 实现、数据模型 | L2 只读，backend/ 读写 |
| QA | hz-qa | 测试用例、验收测试 | L2 只读，qa/ 读写 |

## docs.py CLI 速查

```bash
# 初始化 docs 目录
python3 .claude/skills/create-docs/scripts/docs.py init

# 创建需求
python3 .claude/skills/create-docs/scripts/docs.py req <name>

# 创建角色目录
python3 .claude/skills/create-docs/scripts/docs.py role <req> backend
python3 .claude/skills/create-docs/scripts/docs.py role <req> frontend
python3 .claude/skills/create-docs/scripts/docs.py role <req> qa
python3 .claude/skills/create-docs/scripts/docs.py role <req> ui

# 任务管理
python3 .claude/skills/create-docs/scripts/docs.py status <req>
python3 .claude/skills/create-docs/scripts/docs.py status <req> --role frontend
python3 .claude/skills/create-docs/scripts/docs.py start <req> <task-id> --role frontend
python3 .claude/skills/create-docs/scripts/docs.py done <req> <task-id> --role frontend

# 记录日志
python3 .claude/skills/create-docs/scripts/docs.py log <req> 决策 "选择 JWT，理由: ..."
```

## 文件格式约定

- 日期格式：`YYYY-MM-DD`
- 任务状态：`待办` / `进行中` / `已完成` / `已取消`
- 需求目录自动编号：`1-req-name`、`2-req-name`
- 所有文档使用中文
