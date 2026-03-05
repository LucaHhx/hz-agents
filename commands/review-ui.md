---
description: "[单角色] UI 设计师产出/更新设计稿和设计系统"
argument-hint: [需求名称或ID] [设计指令]
---

# UI 设计产出

启动 UI 设计师 agent 为指定需求产出 merge.html 响应式效果图和设计系统文档。支持附带设计指令（设计建议、修改要求等）。

## Implementation Steps

### 1. 参数解析 → 确定 REQ_NAME + USER_INSTRUCTIONS

读取 `$ARGUMENTS`，拆分为**需求标识**和**用户指令**两部分：

**拆分规则**: 取第一个 token（空格分隔）作为需求标识，剩余部分作为 `USER_INSTRUCTIONS`。

示例:
- `/review-ui 7 按钮改成圆角风格` → 需求标识=`7`, USER_INSTRUCTIONS=`按钮改成圆角风格`
- `/review-ui 7-user-management` → 需求标识=`7-user-management`, USER_INSTRUCTIONS=空
- `/review-ui` → 需求标识=空, USER_INSTRUCTIONS=空

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

如有不满足项 → 列出缺失项 + 对应前置命令，**停止执行**。

### 3. 启动 Agent

使用 Agent tool 启动 hz-ui agent:

```
Agent tool:
  subagent_type: "hz-ui"
  prompt: |
    先读取 create-docs skill 的 SKILL.md (.claude/skills/create-docs/SKILL.md) 了解文档规范和 CLI 用法。

    为需求 {REQ_NAME} 产出 UI 设计:
    1. 阅读 docs/{REQ_NAME}/plan.md 了解用户场景和验收标准
    2. 使用 ui-ux-pro-max skill 生成设计系统
    3. 制作 merge.html 响应式效果图
    4. 编写 design.md 设计系统文档
    5. 编写 Introduction.md 前端设计说明
    6. 交付 Resources/ 资源（SVG 图标、CSS 变量、Tailwind 配置）
    7. 对照 10 项交付检查清单逐项自检

    {如果 USER_INSTRUCTIONS 非空，追加以下段落}
    ## 用户设计指令（优先级最高）
    {USER_INSTRUCTIONS}
    请根据以上指令调整设计方案。如果是设计修改，需在现有设计基础上迭代更新（merge.html、design.md 等）。

    按照你的 agent 职责完成所有工作。完成后输出执行摘要。
```

### 4. 完成报告

输出 Agent 的执行摘要。

### 5. Git 提交

1. 运行 `git status` + `git diff --stat` 展示变更概要
2. 使用 AskUserQuestion 询问用户是否提交 git:
   - 选项: 提交 / 不提交 / 修改后再提交
3. 用户批准后提交:
   - commit message: `docs({REQ_NAME}): review-ui 产出 UI 设计稿`
4. **绝不自动提交**，必须等待用户明确批准
