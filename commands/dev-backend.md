---
description: "[单角色] 后端开发实现后端代码"
argument-hint: [需求名称或ID] [用户指令]
---

# 后端开发

启动后端开发 agent 按照技术方案实现后端功能。支持附带用户指令（实现优先级、特定要求等）。

## Implementation Steps

### 1. 参数解析 → 确定 REQ_NAME + USER_INSTRUCTIONS

读取 `$ARGUMENTS`，拆分为**需求标识**和**用户指令**两部分：

**拆分规则**: 取第一个 token（空格分隔）作为需求标识，剩余部分作为 `USER_INSTRUCTIONS`。

示例:
- `/dev-backend 7 只做用户API` → 需求标识=`7`, USER_INSTRUCTIONS=`只做用户API`
- `/dev-backend 7` → 需求标识=`7`, USER_INSTRUCTIONS=空

**需求匹配**（用需求标识部分）：

- **需求标识为空** → 扫描 `docs/` 下所有需求目录（排除 project.md, tasks.md, CHANGELOG.md, fixes/），使用 AskUserQuestion 列出需求列表让用户选择
- **需求标识非空** → 按顺序尝试:
  1. 精确匹配: `docs/{需求标识}/` 存在？
  2. ID 匹配: `docs/{需求标识}-*/` 存在？
  3. 短名匹配: `docs/*-{需求标识}/` 存在？
  4. 全部失败 → 报错，列出可用需求目录，**停止执行**
- **匹配到多个** → 使用 AskUserQuestion 列出候选让用户选择

将确定的需求名称记为 `REQ_NAME`。

### 2. 前置检查

逐项检查以下条件，**任一不满足 → 严格拒绝执行**:

| 检查项 | 条件 | 不满足时提示 |
|--------|------|-------------|
| backend/design.md | `docs/{REQ_NAME}/backend/design.md` 存在且非空 | "请先运行 `/review-tech {REQ_NAME}` 创建技术方案" |
| backend/tasks.md | `docs/{REQ_NAME}/backend/tasks.md` 存在且有待办任务 | "请先运行 `/review-tech {REQ_NAME}` 创建技术任务" |

如有不满足项 → 列出缺失项 + 对应前置命令，**停止执行**。

### 3. 启动 Agent

使用 Agent tool 启动 hz-backend agent:

```
Agent tool:
  subagent_type: "hz-backend"
  prompt: |
    先读取 create-docs skill 的 SKILL.md (.claude/skills/create-docs/SKILL.md) 了解文档规范和 CLI 用法。

    实现需求 {REQ_NAME} 的后端功能:
    1. 读取 docs/{REQ_NAME}/backend/design.md 了解技术方案
    2. 读取 docs/{REQ_NAME}/backend/tasks.md 获取任务列表
    3. 按任务列表逐项实现后端代码
    4. 每完成一个任务，使用 docs.py CLI 更新 tasks.md 状态

    {如果 USER_INSTRUCTIONS 非空，追加以下段落}
    ## 用户指令（优先级最高）
    {USER_INSTRUCTIONS}
    请根据以上用户指令调整实现顺序或方式。

    按照你的 agent 职责完成所有工作。完成后输出执行摘要。
```

### 4. 完成报告

输出 Agent 的执行摘要。

### 5. Git 提交

1. 运行 `git status` + `git diff --stat` 展示变更概要
2. 使用 AskUserQuestion 询问用户是否提交 git:
   - 选项: 提交 / 不提交 / 修改后再提交
3. 用户批准后提交:
   - commit message: `feat({REQ_NAME}): dev-backend 实现后端功能`
4. **绝不自动提交**，必须等待用户明确批准
