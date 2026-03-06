---
description: "[单角色] PM 评审/完善需求业务文档，或新建需求"
argument-hint: [需求名称或ID] [用户指令] | [新建需求：描述]
---

# PM 文档评审 / 新建需求

启动 PM agent 评审指定需求的 L1+L2 业务文档，或新建一个需求。支持附带用户指令（需求修改、补充说明等）。

## Implementation Steps

### 1. 参数解析 → 确定模式、REQ_NAME、USER_INSTRUCTIONS

读取 `$ARGUMENTS`：

#### 模式 A: 新建需求

如果 `$ARGUMENTS` 包含以下关键词之一，则进入**新建需求模式**：
- 关键词: `新建需求`、`增加需求`、`新需求`、`创建需求`、`添加需求`、`new req`

**解析流程**:
1. 从 `$ARGUMENTS` 中提取需求描述（关键词之后的部分，去掉冒号等分隔符）
2. 将描述转换为 kebab-case 短名作为 `REQ_SHORT_NAME`（如 "用户积分系统" → `user-points`）
3. 使用 AskUserQuestion 确认需求短名:
   - 显示: "将创建需求目录 `docs/<N>-{REQ_SHORT_NAME}/`，是否确认？"
   - 选项: 确认 / 修改名称
4. 运行 `python3 .claude/skills/create-docs/scripts/docs.py req {REQ_SHORT_NAME}` 创建目录
5. 将创建的完整目录名记为 `REQ_NAME`（含编号前缀，如 `8-user-points`）
6. 跳到 **步骤 3-B (新建 Agent)**

#### 模式 B: 评审已有需求

**拆分规则**: 取第一个 token（空格分隔）作为需求标识，剩余部分作为 `USER_INSTRUCTIONS`。

示例:
- `/review-pm 7 补充验收标准` → 需求标识=`7`, USER_INSTRUCTIONS=`补充验收标准`
- `/review-pm 7` → 需求标识=`7`, USER_INSTRUCTIONS=空

**需求匹配**（用需求标识部分）：

- **需求标识为空** → 扫描 `docs/` 下所有需求目录（排除 project.md, tasks.md, CHANGELOG.md, fixes/），使用 AskUserQuestion 列出需求列表让用户选择
- **需求标识非空**（且不含新建关键词）→ 按顺序尝试:
  1. 精确匹配: `docs/{需求标识}/` 存在？
  2. ID 匹配: `docs/{需求标识}-*/` 存在？
  3. 短名匹配: `docs/*-{需求标识}/` 存在？
  4. 全部失败 → 使用 AskUserQuestion 询问用户:
     - "未找到匹配的需求目录。请选择操作："
     - 选项: 以此名称新建需求 / 查看已有需求列表 / 取消
     - 如选"新建" → 按**模式 A 步骤 4** 执行
- **匹配到多个** → 使用 AskUserQuestion 列出候选让用户选择

将确定的需求名称记为 `REQ_NAME`。

### 2. 前置检查

无前置条件。

### 3. 启动 Agent

#### 3-A. 评审模式

使用 Agent tool 启动 hz-pm agent:

```
Agent tool:
  subagent_type: "hz-pm"
  prompt: |
    先读取 create-docs skill 的 SKILL.md (.claude/skills/create-docs/SKILL.md) 了解文档规范。
    再读取 references/update-guide.md (.claude/skills/create-docs/references/update-guide.md) 了解更新规则。

    评审需求 {REQ_NAME} 的 L1 + L2 业务文档:
    - docs/project.md — 项目概览业务信息完整性
    - docs/{REQ_NAME}/plan.md — 目标、用户场景、验收标准
    - docs/{REQ_NAME}/tasks.md — 功能任务清晰度和完整性
    - docs/{REQ_NAME}/log.md — 变更记录

    {如果 USER_INSTRUCTIONS 非空，追加以下段落}
    ## 用户指令（优先级最高）
    {USER_INSTRUCTIONS}
    请根据以上用户指令重点调整相关文档。

    ## 链接浏览
    如果用户指令中包含 URL 链接，使用 agent-browser 浏览这些链接，提取关键信息融入需求文档。

    ## 需求探索
    如果评审中发现需求不够清晰或有歧义，使用 brainstorming skill 与用户逐步澄清后再修改文档。

    发现问题直接修复。完成后输出评审摘要。
```

#### 3-B. 新建模式

使用 Agent tool 启动 hz-pm agent:

```
Agent tool:
  subagent_type: "hz-pm"
  prompt: |
    先读取 create-docs skill 的 SKILL.md (.claude/skills/create-docs/SKILL.md) 了解文档规范。
    再读取 references/update-guide.md (.claude/skills/create-docs/references/update-guide.md) 了解更新规则。

    为新需求 {REQ_NAME} 编写完整的 L1 + L2 业务文档。

    需求描述: {用户提供的原始描述}

    ## 链接浏览
    如果需求描述中包含 URL 链接（PRD、竞品、参考文档等），先使用 agent-browser 浏览这些链接，提取关键信息作为需求输入。

    ## 需求探索
    使用 brainstorming skill 与用户协作探索需求细节：逐个提问澄清业务目标、用户场景、验收标准，提出 2-3 种方案，获得确认后再写入文档。

    任务:
    1. 更新 docs/project.md — 确保项目概览包含此需求
    2. 更新 docs/tasks.md — 在需求列表中添加此需求条目
    3. 编写 docs/{REQ_NAME}/plan.md — 目标、范围、用户场景、验收标准
    4. 编写 docs/{REQ_NAME}/tasks.md — 功能级任务拆解
    5. 初始化 docs/{REQ_NAME}/log.md — 添加创建记录

    完成后输出需求摘要。
```

### 4. 完成报告

输出 Agent 的评审摘要。

### 5. Git 提交

1. 运行 `git status` + `git diff --stat` 展示变更概要
2. 使用 AskUserQuestion 询问用户是否提交 git:
   - 选项: 提交 / 不提交 / 修改后再提交
3. 用户批准后提交:
   - commit message: `docs({REQ_NAME}): review-pm 完善业务文档`
4. **绝不自动提交**，必须等待用户明确批准
