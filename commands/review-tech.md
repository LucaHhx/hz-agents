---
description: "[单角色] Tech Lead 创建/更新技术方案和技术任务"
argument-hint: [需求名称或ID] [用户指令]
---

# Tech Lead 技术评审

启动 Tech Lead agent 为指定需求创建角色目录、编写 design.md 技术方案、拆解技术任务。支持附带用户指令（需求修改、追加功能等）。

## Implementation Steps

### 1. 参数解析 → 确定 REQ_NAME + USER_INSTRUCTIONS

读取 `$ARGUMENTS`，拆分为**需求标识**和**用户指令**两部分：

**拆分规则**: 取第一个 token（空格分隔）作为需求标识，剩余部分作为 `USER_INSTRUCTIONS`。

示例:
- `/review-tech 7 追加登录日志功能` → 需求标识=`7`, USER_INSTRUCTIONS=`追加登录日志功能`
- `/review-tech 7-user-management` → 需求标识=`7-user-management`, USER_INSTRUCTIONS=空
- `/review-tech` → 需求标识=空, USER_INSTRUCTIONS=空

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
| plan.md | `docs/{REQ_NAME}/plan.md` 存在且非空 | "请先运行 `/review-pm {REQ_NAME}` 完善业务文档" |
| tasks.md | `docs/{REQ_NAME}/tasks.md` 存在且非空 | "请先运行 `/review-pm {REQ_NAME}` 创建功能任务" |

如有不满足项 → 列出缺失项 + 对应前置命令，**停止执行**。

### 3. 启动 Agent

使用 Agent tool 启动 hz-tech-lead agent:

```
Agent tool:
  subagent_type: "hz-tech-lead"
  prompt: |
    先读取 create-docs skill 的 SKILL.md (.claude/skills/create-docs/SKILL.md) 了解文档规范。
    再读取 references/update-guide.md (.claude/skills/create-docs/references/update-guide.md) 了解更新规则。
    再读取 references/tech-stack.md (.claude/skills/create-docs/references/tech-stack.md) 了解项目技术栈。

    为需求 {REQ_NAME} 执行技术评审:
    1. 读取 docs/{REQ_NAME}/plan.md 和 tasks.md 理解业务需求
    2. 创建角色目录（backend, frontend, qa, ui）
    3. 编写各角色 design.md 技术方案
    4. 拆解技术任务到各角色 tasks.md
    5. 在 log.md 记录技术决策

    {如果 USER_INSTRUCTIONS 非空，追加以下段落}
    ## 用户指令（优先级最高）
    {USER_INSTRUCTIONS}
    请根据以上用户指令调整技术方案和任务拆解。如果是需求修改或追加，需同步更新相关的 design.md 和 tasks.md。

    ## 链接浏览
    如果用户指令中包含 URL 链接（技术文档、API 参考、架构图等），使用 agent-browser 浏览这些链接，提取技术细节融入设计方案。

    ## 技术探索
    如果技术选型或架构设计有多种可行方案，使用 brainstorming skill 与用户协作探讨，确认后再写入 design.md。

    按照你的 agent 职责完成所有工作。完成后输出执行摘要。
```

### 4. 完成报告

输出 Agent 的执行摘要。

### 5. Git 提交

1. 运行 `git status` + `git diff --stat` 展示变更概要
2. 使用 AskUserQuestion 询问用户是否提交 git:
   - 选项: 提交 / 不提交 / 修改后再提交
3. 用户批准后提交:
   - commit message: `docs({REQ_NAME}): review-tech 完善技术文档`
4. **绝不自动提交**，必须等待用户明确批准
