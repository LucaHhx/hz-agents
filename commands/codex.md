---
description: 启动 Codex 交互会话 — 选择模型后直接与 Codex 对话
argument-hint: [初始任务描述]
---

# Codex 交互会话

启动 codex app-server，让用户选择模型，然后进入透传对话模式 — 用户的所有消息直接转发给 Codex，不做任何处理。

## 实现步骤

### 1. 定位 Bridge 脚本

使用 Glob 工具搜索 `**/codex-app-server/scripts/codex_bridge.py`，获取脚本绝对路径。

如果找不到脚本，报错并退出：
- "未找到 codex_bridge.py，请确认 codex-app-server skill 已安装"

### 2. 验证 Codex 已安装

```bash
which codex && codex --version
```

如果未安装，报错：
- "未找到 codex 命令。请先安装: npm install -g @openai/codex"

### 3. 获取可用模型列表

运行 bridge 脚本获取模型列表：

```bash
python3 <bridge路径> --json --cwd "$(pwd)" --list-models 2>/dev/null
```

如果 `--list-models` 不可用，使用以下默认模型列表。

### 4. 让用户选择模型

使用 AskUserQuestion 工具让用户选择模型：

**问题**: "选择 Codex 使用的模型？"
**选项**:
- `gpt-5.4` — 最新旗舰 agentic 模型（Recommended）
- `gpt-5.3-codex` — Codex 优化的 agentic 模型
- `gpt-5.2-codex` — 前代 Codex 优化模型
- `gpt-5.1-codex-max` — 深度推理 Codex 模型

同时询问 effort 级别：

**问题**: "选择推理深度？"
**选项**:
- `medium` — 平衡速度与质量（Recommended）
- `high` — 深度推理
- `low` — 快速响应
- `xhigh` — 最大深度推理

记录用户选择的模型和 effort。

### 5. 启动 Codex 并处理初始任务

如果用户在调用 `/codex` 时提供了参数（即 `$ARGUMENTS` 非空），将其作为第一个任务发送给 Codex：

```bash
python3 <bridge路径> --cwd "$(pwd)" --model <用户选择的模型> --effort <用户选择的effort> --sandbox danger-full-access "<用户提供的参数>"
```

将 Codex 的完整输出原样展示给用户，**不做任何摘要、修改或处理**。

### 6. 进入透传对话循环

初始任务完成后（或无初始任务时），告知用户：

> Codex 会话已就绪。请直接输入你想让 Codex 处理的任务。输入 `exit` 或 `quit` 结束会话。

然后进入循环：

1. 等待用户输入下一条消息
2. 收到用户消息后，**不做任何处理**，直接通过 bridge 脚本转发给 Codex：
   ```bash
   python3 <bridge路径> --cwd "$(pwd)" --model <模型> --effort <effort> --sandbox danger-full-access "<用户的原始消息>"
   ```
3. 将 Codex 的完整输出**原样**展示给用户
4. 回到步骤 1

**关键原则**：你是一个透明代理。**绝对不要**对用户的输入做解读、修改、补充或过滤。**绝对不要**对 Codex 的输出做摘要、评论或修改。只做转发。

### 7. 结束会话

当用户输入 `exit`、`quit` 或 `q` 时，结束 Codex 会话并告知用户会话已关闭。

## 重要规则

- **纯透传**：不要对用户消息做任何处理，直接转发给 Codex
- **不要摘要**：Codex 的输出原样展示，不添加评论或总结
- **不要干预**：不要在 Codex 执行过程中插入自己的判断
- **保持上下文**：每次调用 bridge 脚本是独立的 turn，但用户的对话上下文由你维护
- **错误透传**：如果 Codex 返回错误，也原样展示给用户

## 错误处理

- Bridge 脚本执行失败：显示完整错误信息，询问用户是否重试
- Codex 超时：告知用户任务超时，询问是否重试或调整 effort
- 进程异常退出：显示 stderr 输出，帮助用户诊断问题
