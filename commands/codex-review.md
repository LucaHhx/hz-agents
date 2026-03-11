---
description: "调度 Codex 执行只读审查任务（代码、文档、架构等）"
argument-hint: "任务描述或审查指令"
---

# Codex Reviewer — 调度 Codex 执行只读审查

接收用户输入，通过 codex-app-server bridge 调度 OpenAI Codex 执行代码审查、文档审查、架构评估或分析任务。本命令始终以只读模式运行，不会修改代码。

## 执行流程

### 1. 定位 Bridge 脚本

使用 Glob 搜索 `**/codex_bridge.py`，获取脚本绝对路径。如果找不到，报错并停止。

### 2. 校验输入

读取 `$ARGUMENTS`，若为空则提示用户提供审查指令并停止：
> 请提供审查指令，例如：`/codex-review 审查代码`、`/codex-review 审查这个需求文档`

### 3. 解析用户意图

判断任务类型，规则按优先级从高到低匹配（命中即停）：

| 优先级 | 关键词（支持中英文混用） | 模式 | 说明 |
|--------|--------------------------|------|------|
| 1 | `review commit`、`审查 commit` + SHA | `--review --target commit --commit-sha <sha>` | 指定提交审查 |
| 2 | `review PR`、`审查 PR`、`base branch` | `--review --target baseBranch` | PR 级别审查 |
| 3 | `审查代码`、`review code`、`代码审查`、`review changes`、`审查未提交`、`review` + `代码/代码变更` | `--review --target uncommittedChanges` | 未提交变更审查 |
| 4 | 其他所有内容 | task 模式 | 作为只读分析任务发送 |

**匹配前预处理**：将输入统一转小写后匹配，支持"帮我 review 一下代码"等混合表达。

**校验规则**（匹配后、执行前）：
- **commit 模式**：若未提供 SHA，提示用户补充并停止
- **PR 模式**：运行 `git rev-parse --abbrev-ref @{upstream}` 检查 base branch，失败则提示用户指定 base branch
- **uncommittedChanges 模式**：运行 `git status --porcelain`，若无变更则提示"工作区无未提交改动"并停止

**示例**：
- `/codex-review 审查代码` → `--review --target uncommittedChanges`
- `/codex-review review commit abc1234` → `--review --target commit --commit-sha abc1234`
- `/codex-review review PR` → `--review --target baseBranch`
- `/codex-review 帮我看看这个需求文档写得怎么样` → task 模式
- `/codex-review 分析项目架构给出改进建议` → task 模式
- `/codex-review 审查 docs/plan.md 的业务逻辑是否完整` → task 模式，读取文件后构建 prompt

### 4. 收集上下文（task 模式）

如果是 task 模式且涉及特定文件/文档：
1. 使用 Read/Grep/Glob 读取相关文件内容
2. 将文件内容嵌入 prompt（Codex 在独立上下文中运行，无法直接访问你读过的文件）
3. **内容限制**：单文件超过 500 行时，只嵌入关键片段（首尾 + 相关函数/段落），注明已截断
4. 构建结构化 prompt，包含：审查类型、审查范围、文件内容、关注重点、期望输出格式

### 5. 调用 Codex

**review 模式**（使用原生 review/start API，不支持 `--effort`）：
```bash
python3 <bridge-path> --review --cwd "$(pwd)" --target <target>
```

**task 模式**（通用分析任务）：
```bash
python3 <bridge-path> --cwd "$(pwd)" --sandbox read-only --effort high "<构建的prompt>"
```

注意：本命令始终使用 `--sandbox read-only`，不使用 `danger-full-access`。

### 6. 整理并呈现结果

将 Codex 返回的结果整理为以下格式：

```
## Codex Review Report

**Review Type:** [Code/Document/Architecture/Task]
**Scope:** [审查范围]
**Model:** [使用的模型]

### Summary
[1-2 句概述]

### Findings

#### Critical
- **[file:line]** [问题标题] — [证据和建议]

#### Warnings
- **[file:line]** [问题标题] — [证据和建议]

#### Suggestions
- **[file:line]** [改进建议] — [理由]

### Overall Assessment
[Codex 的整体评价和关键要点]
```

如果 Codex 未发现问题，使用简化格式：

```
## Codex Review Report

**Review Type:** [类型]  **Scope:** [范围]

### Summary
审查完成，未发现显著问题。

### Overall Assessment
[Codex 的整体评价]
```

### 7. 补充 Claude 自己的分析（可选）

如果在审查过程中发现 Codex 遗漏的问题，在报告末尾补充：

```
### Claude's Notes
- [补充发现]
```

## 错误处理

**环境错误**：
- **python3 不存在 / bridge 启动失败**：报告错误，提示检查 Python 环境
- **Codex 未安装**：提示用户执行 `npm install -g @openai/codex`
- **Bridge 脚本未找到**：提示检查 skills/codex-app-server 是否存在

**输入错误**：
- **空参数**：提示提供审查指令（见步骤 2）
- **commit 模式缺少 SHA**：提示补充 commit SHA
- **工作区无改动**：提示无未提交变更，建议改用 commit 或 PR 模式
- **base branch 不可解析**：提示用户指定 base branch

**Codex/Bridge 错误**：
- **超时/无响应**：报告错误，建议缩小审查范围重试
- **ContextWindowExceeded**：缩小范围（更少文件、特定函数），重试
- **UsageLimitExceeded / Rate Limit**：报告限额信息，建议稍后重试
- **认证失败**：提示用户运行 `codex login` 检查登录状态
- **非零退出码**：显示 bridge 返回的错误信息，建议用户检查 Codex 日志
