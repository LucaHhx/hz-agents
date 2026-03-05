---
description: "[单角色] 前端开发实现前端代码"
argument-hint: [需求名称或ID] [用户指令]
---

# 前端开发

启动前端开发 agent 按照技术方案和 UI 设计稿实现前端功能。支持附带用户指令（实现优先级、特定要求等）。

## Implementation Steps

### 1. 参数解析 → 确定 REQ_NAME + USER_INSTRUCTIONS

读取 `$ARGUMENTS`，拆分为**需求标识**和**用户指令**两部分：

**拆分规则**: 取第一个 token（空格分隔）作为需求标识，剩余部分作为 `USER_INSTRUCTIONS`。

示例:
- `/dev-frontend 7 先实现登录页` → 需求标识=`7`, USER_INSTRUCTIONS=`先实现登录页`
- `/dev-frontend 7` → 需求标识=`7`, USER_INSTRUCTIONS=空

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
| frontend/design.md | `docs/{REQ_NAME}/frontend/design.md` 存在且非空 | "请先运行 `/review-tech {REQ_NAME}` 创建技术方案" |
| frontend/tasks.md | `docs/{REQ_NAME}/frontend/tasks.md` 存在且有待办任务 | "请先运行 `/review-tech {REQ_NAME}` 创建技术任务" |
| ui/merge.html | `docs/{REQ_NAME}/ui/merge.html` 存在 | "请先运行 `/review-ui {REQ_NAME}` 产出 UI 设计稿" |

如有不满足项 → 列出缺失项 + 对应前置命令，**停止执行**。

### 3. 启动 Agent

使用 Agent tool 启动 hz-frontend agent:

```
Agent tool:
  subagent_type: "hz-frontend"
  prompt: |
    先读取 create-docs skill 的 SKILL.md (.claude/skills/create-docs/SKILL.md) 了解文档规范和 CLI 用法。

    实现需求 {REQ_NAME} 的前端功能:
    1. 读取 docs/{REQ_NAME}/frontend/design.md 了解技术方案
    2. 读取 docs/{REQ_NAME}/frontend/tasks.md 获取任务列表
    3. 读取 docs/{REQ_NAME}/ui/ 下的设计稿作为视觉参考:
       - ui/merge.html — 响应式效果图
       - ui/Introduction.md — UI 设计说明
       - ui/design.md — 设计系统
       - ui/Resources/ — 可复用资源
    4. 检查 ui/Resources/ 中的可用资源，优先使用本地资源
    5. 按任务列表逐项实现前端代码
    6. 每完成一个任务，使用 docs.py CLI 更新 tasks.md 状态

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
   - commit message: `feat({REQ_NAME}): dev-frontend 实现前端功能`
4. **绝不自动提交**，必须等待用户明确批准
