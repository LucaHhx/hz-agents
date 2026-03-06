---
description: "[单角色] QA 执行 API + E2E 验收测试"
argument-hint: [需求名称或ID] [测试指令]
---

# QA 验收测试

启动 QA agent 对指定需求执行 API 接口测试和浏览器 E2E 验收测试。支持附带测试指令（重点场景、回归要求等）。

## Implementation Steps

### 1. 参数解析 → 确定 REQ_NAME + USER_INSTRUCTIONS

读取 `$ARGUMENTS`，拆分为**需求标识**和**用户指令**两部分：

**拆分规则**: 取第一个 token（空格分隔）作为需求标识，剩余部分作为 `USER_INSTRUCTIONS`。

示例:
- `/review-qa 7 重点测试并发场景` → 需求标识=`7`, USER_INSTRUCTIONS=`重点测试并发场景`
- `/review-qa 7` → 需求标识=`7`, USER_INSTRUCTIONS=空

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
| qa/design.md | `docs/{REQ_NAME}/qa/design.md` 存在且非空 | "请先运行 `/review-tech {REQ_NAME}` 创建测试方案" |
| 开发任务完成 | `docs/{REQ_NAME}/frontend/tasks.md` 或 `docs/{REQ_NAME}/backend/tasks.md` 中有已完成任务 | "请先运行 `/dev-frontend` 或 `/dev-backend` 完成开发任务" |

如有不满足项 → 列出缺失项 + 对应前置命令，**停止执行**。

### 3. 启动 Agent

使用 Agent tool 启动 hz-qa agent:

```
Agent tool:
  subagent_type: "hz-qa"
  prompt: |
    先读取 create-docs skill 的 SKILL.md (.claude/skills/create-docs/SKILL.md) 了解文档规范和 CLI 用法。

    对需求 {REQ_NAME} 执行验收测试:
    1. 读取 docs/{REQ_NAME}/plan.md 获取验收标准
    2. 读取 docs/{REQ_NAME}/qa/design.md 获取测试方案
    3. 读取 docs/{REQ_NAME}/backend/design.md 获取 API 接口定义

    ## 阶段 A: 后端 API 测试
    - 逐个测试 API 端点，记录请求/响应

    ## 阶段 B: 浏览器 E2E 测试
    - 使用 pm-mcp 启动前后端服务
    - 使用 agent-browser --headed 模拟用户操作
    - 按用户场景逐步验证

    {如果 USER_INSTRUCTIONS 非空，追加以下段落}
    ## 用户测试指令（优先级最高）
    {USER_INSTRUCTIONS}
    请根据以上指令调整测试重点或范围。

    ## 链接浏览
    如果用户指令中包含 URL 链接（测试环境、线上地址、Bug 报告等），使用 agent-browser 浏览这些链接，获取测试上下文和复现信息。

    ## 测试探索
    如果测试策略或重点不明确，使用 brainstorming skill 与用户确认测试优先级和重点场景后再开始测试。

    记录所有测试结果到 docs/{REQ_NAME}/log.md。
    按照你的 agent 职责完成所有工作。完成后输出执行摘要。
```

### 4. 完成报告

输出 Agent 的执行摘要。

### 5. Git 提交

1. 运行 `git status` + `git diff --stat` 展示变更概要
2. 使用 AskUserQuestion 询问用户是否提交 git:
   - 选项: 提交 / 不提交 / 修改后再提交
3. 用户批准后提交:
   - commit message: `test({REQ_NAME}): review-qa 执行验收测试`
4. **绝不自动提交**，必须等待用户明确批准
