---
description: 对已完成的需求启动 QA 验收测试（QA 驱动 + 团队协作修复闭环）
argument-hint: [req-name]
---

# QA 验收测试 — 团队协作模式

启动以 QA 为主导的测试团队。QA 执行完整验收测试，发现问题后反馈给 PM 和技术主管，技术主管分析根因并安排修复，修复后 QA 回归测试，循环直到验收通过。

## Usage

```bash
# 测试指定需求
/qa-test 1-login-sync

# 不指定需求（自动扫描可测试需求）
/qa-test
```

## 流程概览

```
┌───────────────────────────────────┐
│        QA 执行验收测试              │
│    (API 测试 + 浏览器 E2E 测试)     │
└───────────────┬───────────────────┘
                │
        ┌───────┴───────┐
        │   全部通过?    │
        └───────┬───────┘
     YES ↙           ↘ NO
┌──────────┐   ┌────────────────────────┐
│  ✅ 完成  │   │  QA 输出 Bug 报告       │
│  清理团队 │   │  反馈 PM + Tech Lead    │
└──────────┘   └──────────┬─────────────┘
                          │
             ┌────────────┴────────────┐
             │                         │
    ┌────────┴────────┐   ┌───────────┴───────────┐
    │  PM 审查文档     │   │  Tech Lead 分析根因    │
    │  更新需求/记录   │   │  创建修复任务          │
    └─────────────────┘   │  分配给 FE / BE        │
                          └───────────┬───────────┘
                                      │
                         ┌────────────┴────────────┐
                         │                         │
                ┌────────┴────────┐   ┌───────────┴──────────┐
                │  Backend 修复   │   │  Frontend 修复        │
                └────────┬────────┘   └───────────┬──────────┘
                         └────────────┬────────────┘
                                      │
                             ┌────────┴────────┐
                             │  QA 回归测试     │
                             └────────┬────────┘
                                      │
                             回到 "全部通过?" 判断
```

## Implementation Steps

### Step 1: 确定目标需求

If `$ARGUMENTS` 不为空:
- 检查 `docs/$ARGUMENTS/` 目录是否存在
- If 不存在 → 列出 `docs/` 下可用需求目录，报错停止

If `$ARGUMENTS` 为空:
- 扫描 `docs/` 下所有需求目录
- 读取每个需求的 `qa/tasks.md`，找出有待完成测试任务的需求
- 列出可测试需求，让用户选择
- If 没有待测试需求 → 报告所有测试已完成，停止

将确定的需求名称记为 `REQ_NAME`。

### Step 2: 前置检查

检查以下文件是否存在:
- `docs/$REQ_NAME/plan.md` — 需求验收标准
- `docs/$REQ_NAME/backend/design.md` — 后端 API 定义
- `docs/$REQ_NAME/frontend/design.md` — 前端设计
- `docs/$REQ_NAME/qa/design.md` — 测试方案
- `docs/$REQ_NAME/qa/tasks.md` — 测试任务

If 任何文件缺失 → 报错并提示先完善文档，停止执行。

### Step 3: 创建测试团队

```
TeamCreate:
  team_name: "qa-REQ_NAME"
  description: "QA 验收测试: REQ_NAME — QA 驱动 + 团队协作修复闭环"
```

创建主任务:
```
TaskCreate:
  subject: "QA 完整验收测试: REQ_NAME"
  description: "对 REQ_NAME 执行 API + 浏览器 E2E 完整验收测试，记录结果到 log.md"
  activeForm: "执行 QA 验收测试"
```

设置轮次计数器 `ROUND = 1`。

### Step 4: 启动 QA Agent

```
Task tool:
  subagent_type: "hz-qa"
  team_name: "qa-REQ_NAME"
  name: "qa-tester"
  prompt: |
    你是 QA 工程师，对需求 REQ_NAME 执行完整验收测试。
    这是第 ROUND 轮测试。

    先读取 .claude/skills/create-docs/SKILL.md 了解文档规范和 CLI 用法。

    按照你的标准工作流程执行:
    1. 阅读 docs/REQ_NAME/ 下的 plan.md, backend/design.md, frontend/design.md, qa/design.md, qa/tasks.md
    2. 执行后端 API 测试 (使用 pm-mcp 启动服务 + curl 测试)
    3. 执行浏览器 E2E 测试 (使用 pm-mcp + agent-browser --headed)
    4. 将完整测试结果写入 docs/REQ_NAME/log.md
    5. 使用 docs.py CLI 更新 qa/tasks.md 任务状态

    完成后输出结构化测试报告，格式:
    ---
    ## 测试报告
    **状态**: PASS 或 FAIL
    **API 测试**: N/M 通过
    **E2E 测试**: N/M 通过

    ### Bug 清单 (仅 FAIL 时)
    | Bug ID | 严重程度 | 描述 | 复现步骤 | 相关文件 | 建议修复角色 |
    |--------|----------|------|----------|----------|-------------|
    | BUG-XXX | P0/P1/P2 | ... | 1. 2. 3. | file:line | backend/frontend |
    ---

    测试结束后清理: 关闭浏览器, 停止服务, 清理进程。
```

### Step 5: 分析 QA 结果

等待 QA agent 完成并返回结果。

**如果全部通过 (PASS)** → 跳到 Step 9 (完成)

**如果有 Bug (FAIL)** → 从 QA 报告中提取 Bug 清单，继续 Step 6

### Step 6: 启动 PM + Tech Lead 处理 Bug（如有视觉 Bug 则加入 UI 设计师）

**并行启动** agent（PM + Tech Lead 必启，UI 设计师按需启动）:

PM Agent:
```
Task tool:
  subagent_type: "hz-pm"
  team_name: "qa-REQ_NAME"
  name: "pm"
  prompt: |
    QA 第 ROUND 轮验收测试发现以下 Bug:

    [粘贴 QA 报告中的 Bug 清单表格]

    请执行:
    1. 读取 docs/REQ_NAME/plan.md 审查验收标准
    2. 判断 Bug 是否涉及需求理解偏差或验收标准缺失
    3. 如需更新:
       - 补充或修正 plan.md 中的验收标准
       - 使用 docs.py log 在 log.md 记录变更原因
    4. 如不需要更新:
       - 确认 Bug 属于实现问题，不涉及需求变更

    输出你的审查结论: 是否需要更新文档，以及更新了什么。
```

Tech Lead Agent:
```
Task tool:
  subagent_type: "hz-tech-lead"
  team_name: "qa-REQ_NAME"
  name: "tech-lead"
  prompt: |
    QA 第 ROUND 轮验收测试发现以下 Bug:

    [粘贴 QA 报告中的 Bug 清单表格]

    请执行:
    1. 阅读每个 Bug 的描述和复现步骤
    2. 阅读相关 design.md 和源代码，分析每个 Bug 的根因
    3. 确定每个 Bug 应由哪个角色修复 (backend / frontend)
    4. 在对应角色的 tasks.md 中创建修复任务:
       python3 .claude/skills/create-docs/scripts/docs.py task REQ_NAME "修复 BUG-XXX: 简要描述" --role backend
       python3 .claude/skills/create-docs/scripts/docs.py task REQ_NAME "修复 BUG-XXX: 简要描述" --role frontend
    5. 使用 docs.py log 在 log.md 中记录分析结论和分配决策
    6. 如果 design.md 需要更新（如接口约定有误），同步更新

    输出:
    - 每个 Bug 的根因分析
    - 修复任务分配: { backend: [...], frontend: [...] }
    - 是否更新了 design.md
    - 是否有视觉相关 Bug（需要 UI 设计师参与审查）
```

如果 Bug 中包含视觉/布局/样式问题，启动 UI 设计师:
```
Task tool:
  subagent_type: "hz-ui"
  team_name: "qa-REQ_NAME"
  name: "ui-reviewer"
  prompt: |
    QA 测试发现以下视觉相关 Bug:

    [粘贴视觉相关的 Bug 清单]

    请执行:
    1. 对照 docs/REQ_NAME/ui/ 下的设计稿，确认这些 Bug 是否属于视觉还原问题
    2. 如果是设计稿本身的问题，更新设计稿和 design.md
    3. 如果是前端还原问题，提供具体的修复指导（Tailwind class、间距、颜色值等）
    4. 输出每个视觉 Bug 的分析和修复建议
```

### Step 7: 执行修复

根据 Tech Lead 的输出，**按需启动**修复 agent:

如果有后端 Bug:
```
Task tool:
  subagent_type: "hz-backend"
  team_name: "qa-REQ_NAME"
  name: "backend-dev"
  prompt: |
    Tech Lead 分析发现以下后端 Bug 需要修复:

    [粘贴 Tech Lead 分配的后端修复任务]

    请执行:
    1. 读取 docs/REQ_NAME/backend/tasks.md 中新增的修复任务
    2. 阅读 Bug 描述、根因分析和相关源代码
    3. 修复代码，确保改动最小化
    4. 使用 docs.py done 更新任务状态为已完成
    5. 使用 docs.py log 在 log.md 中记录修复内容

    输出: 修复了什么，改动了哪些文件，关键代码变更说明。
```

如果有前端 Bug:
```
Task tool:
  subagent_type: "hz-frontend"
  team_name: "qa-REQ_NAME"
  name: "frontend-dev"
  prompt: |
    Tech Lead 分析发现以下前端 Bug 需要修复:

    [粘贴 Tech Lead 分配的前端修复任务]

    请执行:
    1. 读取 docs/REQ_NAME/frontend/tasks.md 中新增的修复任务
    2. 阅读 Bug 描述、根因分析和相关源代码
    3. 修复代码，确保改动最小化
    4. 使用 docs.py done 更新任务状态为已完成
    5. 使用 docs.py log 在 log.md 中记录修复内容

    输出: 修复了什么，改动了哪些文件，关键代码变更说明。
```

**如果前后端都有 Bug，并行启动两个 agent。**

### Step 8: QA 回归测试

修复完成后，`ROUND += 1`，重新启动 QA Agent:

```
Task tool:
  subagent_type: "hz-qa"
  team_name: "qa-REQ_NAME"
  name: "qa-retest-ROUND"
  prompt: |
    上一轮 QA 测试发现以下 Bug，已经修复:

    [粘贴 Bug 清单 + 每个 Bug 的修复内容摘要]

    请执行回归测试 (第 ROUND 轮):
    1. 阅读 docs/REQ_NAME/log.md 中最新的修复记录
    2. 针对每个已修复 Bug 重点回归:
       - 验证原问题已修复
       - 验证修复未引入新问题 (回归)
    3. 执行完整验收测试:
       - API 测试 (修复相关接口 + 核心流程回归)
       - 浏览器 E2E 测试 (修复相关场景 + 核心流程回归)
    4. 将回归测试结果写入 docs/REQ_NAME/log.md (标注 "第 ROUND 轮回归测试")
    5. 更新 qa/tasks.md 任务状态

    输出格式与首轮测试相同 (状态 + Bug 清单表格)。

    测试结束后清理: 关闭浏览器, 停止服务, 清理进程。
```

**回到 Step 5**: 分析回归测试结果。如果仍有 Bug 则重复 Step 6-8。

**循环上限**: 如果超过 3 轮回归测试仍未通过，暂停循环，汇总所有问题，请求用户介入决策。

### Step 9: 完成

全部测试通过后:

1. **向所有活跃 teammate 发送 shutdown_request**，等待确认退出

2. **TeamDelete** 清理团队资源

3. **输出最终报告**:

```
## QA 验收报告: REQ_NAME ✅

**状态**: PASS
**测试轮次**: ROUND 轮 (首轮 + N 次回归)

### 测试概况
- API 测试: X/X 通过
- 浏览器 E2E 测试: X/X 通过

### Bug 修复记录 (如有)
| Bug | 严重程度 | 描述 | 修复角色 | 修复内容 |
|-----|----------|------|----------|----------|
| BUG-XXX | P1 | ... | frontend | ... |

### 团队协作记录
- PM: [文档审查/更新情况]
- Tech Lead: [分析/分配情况]
- Backend: [修复情况]
- Frontend: [修复情况]

### 详细结果
见 docs/REQ_NAME/log.md
```

## Error Handling

If 后端服务启动失败:
- 检查 pm-mcp 日志: `mcp__pm-mcp__get_logs(id, fromTop=true)`
- 搜索错误: `mcp__pm-mcp__grep_logs(id, pattern="error|panic|fatal")`
- 将启动失败作为 Bug 记录，通知 Tech Lead 分析

If 前端服务启动失败:
- 检查端口占用: `grep_logs` 搜索 `EADDRINUSE`
- 尝试终止旧进程后重启
- 将启动失败作为 Bug 记录，通知 Tech Lead 分析

If 浏览器打开失败:
- 确认前端服务正在运行且端口正确
- 尝试 `agent-browser --headed open http://localhost:5173`
- 将打开失败作为 Bug 记录

If 修复引入更多 Bug (回归轮次 > 3):
- 暂停循环
- 汇总所有历史 Bug 和修复记录
- AskUserQuestion 请求用户介入决策

## 重要规则

- **QA 只测试不修复** — QA 只记录和报告 Bug，修复由 Frontend/Backend 负责
- **Tech Lead 主导修复分配** — 不直接让 QA 指挥开发，Tech Lead 分析根因后分配
- **PM 只管文档和需求** — PM 不参与技术修复，只审查需求文档是否需要更新
- **每轮测试必须有完整证据** — API 请求/响应 + 浏览器截图，全部记录到 log.md
- **必须使用 --headed 模式** — agent-browser 有头浏览器测试
- **不跳过 E2E 测试** — 仅 API 测试不够，必须模拟真实用户操作
- **循环上限 3 轮** — 超过 3 轮回归未通过则暂停，请求用户介入
