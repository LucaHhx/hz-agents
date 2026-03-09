---
name: process-manager
description: >
  进程管理工具，用于管理长期运行的后台服务进程。
  内置 scripts/ 脚本直接管理进程，不依赖外部工具。
  触发场景：(1) 启动服务/进程 (triggers: 'start server', 'run service', '启动服务', '运行进程'),
  (2) 管理多个服务的生命周期 (triggers: 'manage services', '管理服务', 'service lifecycle'),
  (3) 查看/搜索进程日志 (triggers: 'check logs', '查看日志', 'debug service'),
  (4) 编排前后端启动顺序 (triggers: 'start all services', '启动所有服务', 'orchestrate services')
---

# 进程管理工具

## 脚本路径

所有脚本位于本 skill 目录下 `scripts/`。使用时用相对于项目根目录的完整路径：

```
PM=.claude/skills/process-manager/scripts
```

以下示例均使用 `$PM` 代替完整路径。

## 脚本一览

| 脚本 | 用途 | 用法 |
|------|------|------|
| `start.sh` | 启动后台进程 | `$PM/start.sh <name> "<cmd>" [--cwd <dir>]` |
| `stop.sh` | 终止进程 | `$PM/stop.sh <name>` 或 `$PM/stop.sh --all` |
| `list.sh` | 列出所有进程 | `$PM/list.sh` |
| `logs.sh` | 查看日志 | `$PM/logs.sh <name> [--lines N] [--head] [--follow]` |
| `search.sh` | 搜索日志 | `$PM/search.sh <name> "<pattern>"` |
| `restart.sh` | 重启进程 | `$PM/restart.sh <name>` |
| `clean.sh` | 清理记录 | `$PM/clean.sh` 或 `$PM/clean.sh --all` |

## 核心工作流

### 1. 启动单个服务

```bash
PM=.claude/skills/process-manager/scripts
$PM/list.sh
$PM/start.sh backend "go run ./cmd/server" --cwd ./server
$PM/logs.sh backend --lines 20
```

启动前**必须**先 `list.sh` 检查重复（脚本内也会自动检查）。

### 2. 启动前后端服务

后端先启动，前端后启动：

```bash
PM=.claude/skills/process-manager/scripts
$PM/list.sh
$PM/start.sh backend "go run ./cmd/server" --cwd ./server
$PM/search.sh backend "listening on|started"
$PM/start.sh frontend "npm run dev" --cwd ./web
$PM/search.sh frontend "ready in|Local:"
```

就绪标志：
- Go/Node HTTP：`listening on`, `started on port`
- Vite/Webpack：`ready in`, `compiled successfully`, `Local:`

### 3. 日志诊断

```bash
$PM/logs.sh backend                              # 最新 30 行
$PM/logs.sh backend --lines 50                   # 最新 50 行
$PM/logs.sh backend --head                       # 从头查看
$PM/logs.sh backend --follow                     # 实时跟踪
$PM/search.sh backend "error|Error|panic|fatal"  # 搜索错误
```

### 4. 生命周期管理

```bash
$PM/list.sh              # 查看状态
$PM/restart.sh backend   # 重启
$PM/stop.sh frontend     # 停止单个
$PM/stop.sh --all        # 停止所有
$PM/clean.sh             # 清理已停止的记录
$PM/clean.sh --all       # 清理所有记录
```

## 常见问题

| 问题 | 处理 |
|------|------|
| 端口占用 | `search.sh <name> "EADDRINUSE"` → `stop.sh` → `start.sh` |
| 进程立即退出 | `logs.sh <name> --head` 查看启动日志 |
| 服务无响应 | `search.sh <name> "error\|panic"` |
| 查找占用端口 | `lsof -i :<port>` |

## 编排模式

更多模式见 [references/patterns.md](references/patterns.md)。
