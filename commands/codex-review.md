---
description: "调度 Codex 执行只读审查任务（代码、文档、架构等）"
argument-hint: "任务描述或审查指令"
---

# Codex Reviewer — 调度 Codex 执行只读审查

接收用户输入，通过 codex-app-server bridge 调度 OpenAI Codex 执行审查或分析任务。始终以只读模式运行，不修改代码。

## 执行流程

### 1. 模型选择

AskUserQuestion:
- question: "选择 Codex 使用的模型"
- options:
  - label: "o4-mini（推荐）"
    description: "速度快、成本低，适合常规审查"
  - label: "o3"
    description: "推理能力更强，适合复杂架构分析"
  - label: "codex-mini"
    description: "Codex 专用轻量模型"
  - label: "自己指定"
    description: "输入模型名称"

记录用户选择的模型，后续调用 bridge 时通过 `--model <model>` 传入。

### 2. 定位 Bridge 脚本

使用 Glob 搜索 `**/codex_bridge.py`，获取脚本绝对路径。如果找不到，报错并停止。

### 3. 校验输入

读取 `$ARGUMENTS`，若为空则提示用户提供审查指令并停止：
> 请提供审查指令，例如：`/codex-review 审查代码`、`/codex-review 审查这个需求文档`

### 4. 调用 Codex

根据 `$ARGUMENTS` 判断任务类型，直接调用 bridge：

**review 模式判定规则**（按优先级从高到低，命中即停）：

| 优先级 | 关键词（支持中英文混用） | target |
|--------|--------------------------|--------|
| 1 | `review commit`、`审查 commit` + SHA | `commit --commit-sha <sha>` |
| 2 | `review PR`、`审查 PR`、`base branch` | `baseBranch` |
| 3 | `审查代码`、`review code`、`代码审查`、`review changes` | `uncommittedChanges` |
| 4 | 其他所有内容 | task 模式 |

**匹配前预处理**：将输入统一转小写后匹配。

**快速校验**（匹配后、执行前）：
- **commit 模式**：若未提供 SHA，提示用户补充并停止
- **PR 模式**：运行 `git rev-parse --abbrev-ref @{upstream}` 检查 base branch，失败则提示
- **uncommittedChanges 模式**：运行 `git status --porcelain`，若无变更则提示并停止

**调用命令：**

review 模式（不支持 `--effort`）：
```bash
python3 <bridge-path> --review --cwd "$(pwd)" --model <model> --target <target>
```

task 模式：
```bash
python3 <bridge-path> --cwd "$(pwd)" --model <model> --sandbox read-only --effort high "$ARGUMENTS"
```

注意：始终使用 `--sandbox read-only`，不使用 `danger-full-access`。

### 5. 整理并呈现结果

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

**Review Type:** [类型]  **Scope:** [范围]  **Model:** [模型]

### Summary
审查完成，未发现显著问题。

### Overall Assessment
[Codex 的整体评价]
```

### 6. 补充 Claude 自己的分析（可选）

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
- **空参数**：提示提供审查指令（见步骤 3）
- **commit 模式缺少 SHA**：提示补充 commit SHA
- **工作区无改动**：提示无未提交变更，建议改用 commit 或 PR 模式
- **base branch 不可解析**：提示用户指定 base branch

**Codex/Bridge 错误**：
- **超时/无响应**：报告错误，建议缩小审查范围重试
- **ContextWindowExceeded**：缩小范围（更少文件、特定函数），重试
- **UsageLimitExceeded / Rate Limit**：报告限额信息，建议稍后重试
- **认证失败**：提示用户运行 `codex login` 检查登录状态
- **非零退出码**：显示 bridge 返回的错误信息，建议用户检查 Codex 日志
