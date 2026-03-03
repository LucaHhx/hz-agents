---
name: pm-mcp-guide
description: >
  pm-mcp (Process Manager MCP) 使用指南，用于管理长期运行的后台服务进程。
  当需要启动前后端开发服务器等长期运行进程时使用此 skill。
  触发场景：(1) 启动服务/进程 (triggers: 'start server', 'run service', '启动服务', '运行进程'),
  (2) 管理多个服务的生命周期 (triggers: 'manage services', '管理服务', 'service lifecycle'),
  (3) 查看/搜索进程日志 (triggers: 'check logs', '查看日志', 'debug service'),
  (4) 编排前后端启动顺序 (triggers: 'start all services', '启动所有服务', 'orchestrate services')
---

# pm-mcp 进程管理指南

## 核心概念

pm-mcp 提供 8 个工具管理长期运行的后台进程。所有进程由 MCP 服务器统一管理，支持日志查看、输入发送和生命周期控制。

## 快速参考

| 工具 | 用途 |
|------|------|
| `start_process` | 启动进程（name + command 必填） |
| `list_processes` | 列出所有进程及状态 |
| `get_logs` | 读取进程日志（支持分页） |
| `grep_logs` | 正则搜索日志 |
| `send_input` | 向进程发送输入 |
| `terminate_process` | 终止指定进程 |
| `terminate_all_processes` | 终止所有进程 |
| `clear_finished` | 清理已结束进程 |

详细参数说明见 [references/api_reference.md](references/api_reference.md)。

## 核心工作流

### 1. 启动单个服务

```
步骤：
1. list_processes → 检查是否已有同名进程运行，避免重复启动
2. start_process(name, command, cwd?, description?) → 启动进程
3. get_logs(id, lines=20) → 确认启动成功
```

**关键规则**：启动前**必须**先 `list_processes` 检查重复。

### 2. 启动前后端服务

典型启动顺序：**后端先启动，前端后启动**（前端通常依赖后端 API）。

编排步骤：
1. `list_processes` → 检查已运行的服务
2. 启动后端，用 `grep_logs` 确认就绪
3. 后端就绪后启动前端

**就绪判断** — 用 `grep_logs` 搜索就绪标志：
- Go/Node HTTP 服务：`listening on`, `started on port`
- Vite/Webpack 前端：`ready in`, `compiled successfully`, `Local:`

### 3. 日志诊断

```
快速查看最新日志：  get_logs(id, lines=30)
从头查看启动日志：  get_logs(id, lines=30, fromTop=true)
搜索错误：         grep_logs(id, pattern="error|Error|ERROR|panic|fatal")
搜索特定请求：     grep_logs(id, pattern="POST /api/users")
分页查看：         get_logs(id, lines=50, skip=100)
```

### 4. 服务生命周期管理

```
检查状态：list_processes         → 查看 running/terminated/failed
重启服务：terminate_process(id)  → start_process(同参数)
全部停止：terminate_all_processes
清理记录：clear_finished         → 移除已终止进程记录和日志
```

### 5. 交互式进程

部分进程需要输入交互（如确认提示、REPL）：

```
send_input(id, input="yes\n")   // 注意：需要 \n 换行符表示回车
```

## 常见问题处理

| 问题 | 处理方式 |
|------|---------|
| 端口被占用 | `grep_logs` 搜索 `EADDRINUSE`，终止旧进程后重启 |
| 进程立即退出 | `get_logs(id, fromTop=true)` 查看完整启动日志 |
| 服务无响应 | `grep_logs` 搜索 error/panic，检查依赖服务状态 |

## 常见编排模式

更多编排模式和实际场景示例见 [references/patterns.md](references/patterns.md)。
