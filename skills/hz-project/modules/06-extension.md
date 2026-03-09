# 模块 06 — 扩展指南

## 概述

hz-agents 支持三种扩展方式：添加 Skill、Command、Agent。

## 添加新 Skill

Skill 是知识库，当用户问题匹配时自动触发。

**使用方法：**
1. 触发 `create-skill` skill
2. 或参照现有 skill 结构手动创建

**目录结构：**
```
skills/<skill-name>/
├── SKILL.md           # 主文件（必须）
├── modules/           # 模块化内容（可选，大型 skill 推荐）
├── references/        # 参考资料（可选）
├── scripts/           # 辅助脚本（可选）
└── examples/          # 示例文件（可选）
```

**最佳实践：**
- SKILL.md 保持轻量（<200行），用索引指向模块文件
- 大型知识库拆分为多个模块文件（如 hz-project 的做法）
- 脚本放在 scripts/ 目录，保持 SKILL.md 纯文档

## 添加新 Command

Command 是用户通过 `/command-name` 触发的可执行流程。

**使用方法：**
1. 触发 `create-command` skill
2. 或参照现有 command 手动创建

**文件格式：**
```markdown
---
description: "一句话描述"
argument-hint: [可选参数说明]
---

# 命令标题

## Implementation Steps

### 1. 步骤一
...
### 2. 步骤二
...

## Important Notes
...
```

**位置：** `commands/<command-name>.md`

## 添加新 Agent

Agent 是具有特定角色和能力的专业代理。

**使用方法：**
1. 触发 `create-agent` skill
2. 或参照现有 agent 手动创建

**文件格式：**
```markdown
---
name: hz-<role>
description: |
  描述和触发示例
model: opus
color: <color>
permissionMode: bypassPermissions
skills:
  - skill1
  - skill2
---

系统提示词内容...
```

**位置：** `agents/<agent-name>.md`

## 链接到项目

所有扩展通过 `.claude/link.sh` 的符号链接自动可用：

```bash
# .claude/link.sh 内容
HZ_AGENTS="/Users/luca/work/hz-agents"
ln -sf "$HZ_AGENTS/skills"/* .claude/skills/
ln -sf "$HZ_AGENTS/commands"/* .claude/commands/
ln -sf "$HZ_AGENTS/agents"/* .claude/agents/
```

新增的 skill/command/agent 在下次运行 `link.sh` 后自动生效。
