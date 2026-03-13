---
name: hz-agent-common
description: 所有 hz-* agent 共享的公共规范和模板。包含文档体系概述、进程管理规则、链接浏览规范、brainstorming 探索规范、CRUD 框架知识引用、输出质量标准等。通过 skills 字段预加载到各 agent 中。
---

# Hz Agent 公共规范

本 skill 包含所有 hz-* agent 共享的规范和模板，避免在各 agent 中重复定义。

## 文档体系概述 — create-docs Skill

**在开始任何文档操作前，必须先读取 `create-docs` skill 获取规范:**

1. 读取 `.claude/skills/create-docs/SKILL.md` — 三层架构、目录结构、CLI 命令、约定
2. 读取 `.claude/skills/create-docs/references/update-guide.md` — 角色权限、编辑规则、跨文件一致性

**严格遵循 skill 中定义的:**
- 目录结构 (自动编号: `1-req-name`, `2-req-name`)
- CLI 命令 (`python3 .claude/skills/create-docs/scripts/docs.py`)
- 文件格式 (表格、日期、状态值)
- 层级权限 (各角色按自身权限操作)

## 进程管理 — 硬性规则

**禁止直接运行 `go run`、`npm run`、`npm start` 等命令启动服务。所有服务必须通过 process-manager 启动和停止。**

```bash
PM=.claude/skills/process-manager/scripts

# 启动前必须检查已有进程
$PM/list.sh

# 启动后端（HAB 项目必须传 HAB_CONFIG）
$PM/start.sh backend "go run ." --cwd ./server --env "HAB_CONFIG=config.local.yaml"
sleep 3
$PM/search.sh backend "listening on|server run success"

# 启动前端
$PM/start.sh frontend "npm run serve" --cwd ./web
sleep 3
$PM/search.sh frontend "ready in|Local:|compiled"
```

**完成后必须清理：**
```bash
$PM/stop.sh --all
$PM/clean.sh
```

**为什么必须遵守：**
- 直接启动的进程不受管理，端口占用导致后续启动失败
- 其他 Agent 无法通过 `list.sh` 感知服务状态
- 未清理的进程会持续占用系统资源

## 链接浏览规范

当用户在指令中提供了 URL 链接，**必须使用 `agent-browser` 浏览这些链接**，提取关键信息：

```
agent-browser open <用户提供的URL>
agent-browser snapshot -i
agent-browser get text @e1  # 提取关键内容
agent-browser close
```

如需截图留档：
```
agent-browser screenshot docs/<req>/<role>/references/<描述>.png
```

## Brainstorming 探索规范

在需求不清晰、方案有多种选择、或设计方向不明确时，**使用 `brainstorming` skill** 与用户协作探索：
- 逐个提问澄清目标、场景、约束
- 提出 2-3 种方案并分析利弊、给出推荐
- 获得用户确认后再写入文档或开始实现

## CRUD 框架知识引用

**在处理涉及数据管理的需求时，必须先判断是否为标准 CRUD 模块。**
详见 `.claude/skills/hab-temp/references/crud-workflow.md`

## 角色边界 — 通用规则

- **不修改** 非本角色管辖的文档（各角色有明确的 Read-Only / Read-Write 范围）
- **不创建** 其他角色目录（除非是 Tech Lead 使用 `docs.py role` 命令）
- **不做** 超出本角色职责的工作（PM 不做技术选型，Frontend 不做后端开发等）

## 输出质量标准

- 所有文档使用中文
- 使用 `docs.py` CLI 进行结构操作和任务状态管理
- 遵循 docs/ 约定 (日期: YYYY-MM-DD, 状态: 待办/进行中/已完成/已取消)
- 决策和变更记录到 log.md
