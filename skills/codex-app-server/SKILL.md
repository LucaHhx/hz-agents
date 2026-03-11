---
name: codex-app-server
description: |
  通过 codex app-server 的 JSON-RPC stdio 协议程序化控制 OpenAI Codex CLI agent。
  用于：(1) 给 Codex 分配编码任务并获取结果, (2) 创建多轮对话让 Codex 分析/修改代码,
  (3) 在 Claude Code 中调度 Codex 作为子 agent 执行工作, (4) 批量任务编排。
  触发词: codex, codex app-server, 调度codex, codex任务, codex bridge,
  控制codex, openai codex, codex agent, 用codex做
---

# Codex App-Server 使用指南

## Claude 调用方式（首选）

使用此 skill 目录下的 bridge 脚本与 Codex 交互。

**定位脚本路径**：使用 Glob 工具搜索 `**/codex_bridge.py` 获取脚本绝对路径，然后用绝对路径调用。

```bash
# 示例（请替换为实际绝对路径）
python3 /path/to/skills/codex-app-server/scripts/codex_bridge.py --cwd "$(pwd)" "任务描述"

# 指定模型和 effort
python3 /path/to/skills/codex-app-server/scripts/codex_bridge.py --cwd "$(pwd)" --model gpt-5.4 --effort high "任务描述"

# 调试模式（查看原始 JSON 消息）
python3 /path/to/skills/codex-app-server/scripts/codex_bridge.py --debug --cwd "$(pwd)" "任务描述"
```

## 前置条件

```bash
# 确认 codex 已安装
which codex && codex --version
```

需要有效的 OpenAI API key 或 Codex 登录态。

## 核心流程

### 1. 启动与初始化握手（必须）

每次连接必须完成 `initialize` + `initialized` 两步，否则所有请求返回 "Not initialized"。

```
→ {"method":"initialize","id":0,"params":{"clientInfo":{"name":"my_client","title":"My Client","version":"0.1.0"}}}
← {"id":0,"result":{"userAgent":"my_client/0.114.0 ..."}}
→ {"method":"initialized"}    ← 这是通知，没有 id，不会有响应
```

### 2. 创建 Thread（对话线程）

```
→ {"method":"thread/start","id":10,"params":{
    "model":"gpt-5.4",
    "cwd":"/path/to/project",
    "approvalPolicy":"never",
    "sandbox":"danger-full-access"
  }}
← {"id":10,"result":{"thread":{"id":"019cdc34-..."}}}
```

### 3. 发送任务 (Turn)

```
→ {"method":"turn/start","id":20,"params":{
    "threadId":"<thread-id>",
    "input":[{"type":"text","text":"你的任务描述"}],
    "cwd":"/path/to/project",
    "model":"gpt-5.4",
    "effort":"medium"
  }}
```

### 4. 收集事件流直到完成

监听 stdout 的 JSONL 行，直到收到 `turn/completed` 或 `codex/event/task_complete`。

## 避坑指南（实战总结）

### 坑1: sandbox 值必须用 kebab-case

```
✗ "sandbox": "dangerFullAccess"              → 报错 unknown variant
✓ "sandbox": "danger-full-access"            → 正确
✓ "sandbox": "read-only"                     → 正确
✓ "sandbox": "workspace-write"               → 正确
```

### 坑2: 事件名称与官方文档不一致

实际收到的事件名 vs 文档描述的名称：

| 实际事件 | 文档事件 | 用途 |
|----------|----------|------|
| `codex/event/agent_message_content_delta` | `item/agentMessage/delta` | agent 文本流式输出 |
| `codex/event/agent_message` | `item/completed` (agentMessage) | agent 完整消息 |
| `codex/event/exec_command_begin` | `item/started` (commandExecution) | 命令开始执行 |
| `codex/event/exec_command_end` | `item/completed` (commandExecution) | 命令执行结束 |
| `codex/event/task_complete` | `turn/completed` | 整个 turn 完成 |

**两套命名都可能出现**，代码中应同时处理。完整事件列表见 [references/api-reference.md](references/api-reference.md)。

### 坑3: thread/start 首次可能较慢

首次创建 thread 时服务端需要初始化模型连接，wait timeout 建议设 15-20 秒。

### 坑4: stdio 双向通信需要正确的管道处理

- 不能用简单的 `echo | codex app-server`，因为 stdin 关闭后服务端也退出
- 推荐使用 Python subprocess 保持 stdin 打开
- 每条消息必须以 `\n` 结尾（JSONL 格式）

### 坑5: initialized 是通知不是请求

`initialized` 消息**不能包含 `id` 字段**，它是 notification，加了 id 会导致协议混乱。

### 坑6: threadId 必须是 UUID 格式

thread/start 返回的 id 是 UUID（如 `019cdc34-cba7-7662-...`），不能自己编造。

## Bridge 脚本用法

以下示例假设已 `cd` 到此 skill 目录，或将路径替换为绝对路径：

```bash
# 基本用法 - 发送单个任务
python3 codex_bridge.py "分析项目结构"

# 指定工作目录
python3 codex_bridge.py --cwd /path/to/project "实现登录功能"

# 指定模型和 effort
python3 codex_bridge.py --model gpt-5.3-codex --effort high "重构这个模块"

# 代码审查（使用原生 review/start API）
python3 codex_bridge.py --review --cwd /path/to/project
python3 codex_bridge.py --review --target baseBranch --cwd /path/to/project
python3 codex_bridge.py --review --target commit --commit-sha abc123

# JSON 结构化输出（适合程序化调用）
python3 codex_bridge.py --json "分析项目结构"
python3 codex_bridge.py --json --review --cwd /path/to/project

# 调试模式
python3 codex_bridge.py --debug "查看原始通信"

# 多轮对话模式
python3 codex_bridge.py --interactive
```

## 场景→API 映射表

| 使用场景 | Bridge 模式 | 底层 API | 默认 sandbox | 复用 thread |
|----------|-------------|----------|-------------|-------------|
| 编码任务 | `"任务描述"` | `turn/start` | danger-full-access | 否 |
| 未提交代码审查 | `--review` | `review/start` | read-only | 否 |
| PR/base branch 审查 | `--review --target baseBranch` | `review/start` | read-only | 否 |
| 指定 commit 审查 | `--review --target commit --commit-sha <sha>` | `review/start` | read-only | 否 |
| 文档/架构评审 | `"审查 prompt"` + `--sandbox read-only` | `turn/start` | 按参数 | 否 |
| 多轮对话/追问 | `--interactive` | `turn/start`（同 thread） | 按参数 | 是 |
| 直接执行命令 | API only | `command/exec` | 按参数 | 否 |

> **注意**：Bridge 脚本目前封装了 `initialize`、`thread/start`、`turn/start`、`turn/interrupt`、`review/start`、`model/list`。
> 协议还支持 `thread/resume`、`thread/fork`、`thread/read`、`turn/steer` 等高级方法，可通过 `CodexBridge.send()` 直接调用。详见 [references/api-reference.md](references/api-reference.md)。

## 可用模型

| 模型 | 说明 |
|------|------|
| gpt-5.4 | 最新旗舰 agentic 模型（默认） |
| gpt-5.3-codex | Codex 优化的 agentic 模型 |
| gpt-5.2-codex | 前代 Codex 优化模型 |
| gpt-5.1-codex-max | 深度推理 Codex 模型 |

effort 选项: `low`（快速）、`medium`（平衡）、`high`（深度）、`xhigh`（最大深度）

## 高级用法

### 多轮对话（同一 thread 追加 turn）

在同一个 thread 中发送多个 turn，Codex 会保留上下文：

```
→ {"method":"turn/start","id":30,"params":{
    "threadId":"<同一个-thread-id>",
    "input":[{"type":"text","text":"基于上面的分析，帮我重构 utils.py"}],
    ...
  }}
```

### 中途打断正在执行的 turn

```
→ {"method":"turn/interrupt","id":99,"params":{"threadId":"<thread-id>"}}
```

### 代码审查

```
→ {"method":"review/start","id":40,"params":{
    "threadId":"<thread-id>",
    "delivery":"inline",
    "target":{"type":"uncommittedChanges"}
  }}
```

### 直接执行命令（无需 thread）

```
→ {"method":"command/exec","id":50,"params":{
    "command":["ls","-la"],
    "cwd":"/path/to/project",
    "timeoutMs":10000
  }}
```

更多 API 细节见 [references/api-reference.md](references/api-reference.md)。
