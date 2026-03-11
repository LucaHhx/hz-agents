# Codex App-Server API 参考

## 传输协议

- **stdio**（默认）：`codex app-server --listen stdio://`，消息格式为 JSONL（每行一个 JSON）
- **WebSocket**（实验性）：`codex app-server --listen ws://IP:PORT`，每帧一个 JSON 消息

WebSocket 模式下还提供健康检查端点：
- `GET /readyz` — 监听器就绪后返回 200
- `GET /healthz` — 始终返回 200

## 消息格式

基于 JSON-RPC 2.0（省略 `"jsonrpc":"2.0"` 头）。

**请求**（有 id，期望响应）：
```json
{"method": "thread/start", "id": 10, "params": {...}}
```

**通知**（无 id，无响应）：
```json
{"method": "initialized"}
```

**响应**：
```json
{"id": 10, "result": {...}}
```
或
```json
{"id": 10, "error": {"code": -32600, "message": "..."}}
```

## 生命周期

```
客户端                          服务端
  │                              │
  ├─ initialize ────────────────►│
  │◄──────────────── result ─────┤
  ├─ initialized (通知) ────────►│
  │                              │
  ├─ thread/start ──────────────►│
  │◄──────────────── result ─────┤
  │                              │
  ├─ turn/start ────────────────►│
  │◄───── 事件流(多条) ──────────┤
  │◄───── turn/completed ────────┤
  │                              │
```

## 全部方法列表

### 初始化

| 方法 | 类型 | 说明 |
|------|------|------|
| `initialize` | 请求 | 握手，传入 clientInfo |
| `initialized` | 通知 | 告知服务端客户端已就绪 |

### Thread 操作

| 方法 | 说明 |
|------|------|
| `thread/start` | 创建新对话线程 |
| `thread/resume` | 重新打开已有线程 |
| `thread/fork` | 从现有线程分支 |
| `thread/read` | 读取线程数据（不恢复） |
| `thread/list` | 分页列出线程 |
| `thread/loaded/list` | 列出内存中的线程 |
| `thread/archive` | 归档线程 |
| `thread/unarchive` | 取消归档 |
| `thread/unsubscribe` | 取消事件订阅 |
| `thread/compact/start` | 触发历史压缩 |
| `thread/rollback` | 回滚最近 N 个 turn |

### Turn 操作

| 方法 | 说明 |
|------|------|
| `turn/start` | 发送任务，开始新的 turn |
| `turn/steer` | 向正在执行的 turn 追加输入 |
| `turn/interrupt` | 中断当前 turn |

### 其他操作

| 方法 | 说明 |
|------|------|
| `model/list` | 列出可用模型 |
| `command/exec` | 直接执行命令（无需 thread） |
| `review/start` | 启动代码审查 |
| `skills/list` | 列出可用 skill |
| `app/list` | 列出可用 app |
| `config/read` | 读取配置 |
| `config/value/write` | 写入配置 |
| `feedback/upload` | 提交反馈 |

## thread/start 参数详解

```json
{
  "model": "gpt-5.4",
  "cwd": "/path/to/project",
  "approvalPolicy": "never",
  "sandbox": "danger-full-access"
}
```

- **model**: 模型 ID，通过 `model/list` 获取
- **cwd**: 工作目录
- **approvalPolicy**: `"never"` | `"onRequest"` | `"unlessTrusted"`
- **sandbox**: `"danger-full-access"` | `"read-only"` | `"workspace-write"`（必须 kebab-case）

## turn/start 参数详解

```json
{
  "threadId": "UUID",
  "input": [{"type": "text", "text": "任务描述"}],
  "cwd": "/path/to/project",
  "model": "gpt-5.4",
  "effort": "medium"
}
```

- **input 类型**:
  - `{"type": "text", "text": "..."}` — 文本输入
  - `{"type": "image", "url": "https://..."}` — 远程图片
  - `{"type": "localImage", "path": "/tmp/..."}` — 本地图片
  - `{"type": "skill", "name": "...", "path": "..."}` — 调用 skill
  - `{"type": "mention", "name": "...", "path": "app://..."}` — 调用 app

- **effort**: `"low"` | `"medium"` | `"high"` | `"xhigh"`

## review/start 参数

```json
{
  "threadId": "UUID",
  "delivery": "inline",
  "target": {"type": "uncommittedChanges"}
}
```

- **delivery**: `"inline"`（当前线程）| `"detached"`（新线程）
- **target 类型**: `"uncommittedChanges"` | `"baseBranch"` | `{"type":"commit","sha":"..."}` | `"custom"`

## command/exec 参数

```json
{
  "command": ["ls", "-la"],
  "cwd": "/path/to/project",
  "sandboxPolicy": {"type": "workspace-write"},
  "timeoutMs": 10000
}
```

返回: `{"exitCode": 0, "stdout": "...", "stderr": ""}`

## 事件名称映射表

实际事件与文档事件名的对应关系（两套都可能出现）：

| 实际事件 | 文档事件 | 说明 |
|----------|----------|------|
| `codex/event/task_started` | - | 任务开始 |
| `codex/event/agent_message_content_delta` | `item/agentMessage/delta` | 文本流 |
| `codex/event/agent_message_delta` | - | delta 元信息 |
| `codex/event/agent_message` | - | 完整消息 |
| `codex/event/exec_command_begin` | `item/started` | 命令开始 |
| `codex/event/exec_command_end` | `item/completed` | 命令结束 |
| `codex/event/exec_command_output` | - | 命令输出流 |
| `codex/event/item_started` | `item/started` | 通用 item |
| `codex/event/item_completed` | `item/completed` | 通用 item |
| `codex/event/user_message` | - | 用户消息回显 |
| `codex/event/token_count` | - | token 计数 |
| `codex/event/task_complete` | `turn/completed` | 任务完成 |
| `turn/started` | `turn/started` | turn 开始 |
| `turn/completed` | `turn/completed` | turn 完成 |
| `thread/status/changed` | `thread/status/changed` | 线程状态变化 |
| `thread/tokenUsage/updated` | `thread/tokenUsage/updated` | 用量更新 |
| `account/rateLimits/updated` | `account/rateLimits/updated` | 限额更新 |

## 错误码

| 错误码 | 含义 |
|--------|------|
| `-32001` | 服务过载，客户端应指数退避重试 |
| `-32600` | 无效请求（参数错误等） |
| `-32601` | 方法不存在 |

## 常见错误类型（turn 失败时）

- `ContextWindowExceeded` — 上下文超限
- `UsageLimitExceeded` — 使用配额耗尽
- `HttpConnectionFailed` — 网络连接失败
- `ResponseStreamConnectionFailed` — 流式连接断开
- `SandboxError` — 沙箱执行错误
- `Unauthorized` — 认证失败
