---
name: process-manager
description: >
  进程管理工具，用于管理长期运行的后台服务进程。
  内置 scripts/ 脚本直接管理进程，不依赖外部工具。
  触发场景：
  (1) 启动服务/进程 (triggers: 'start server', 'run service', '启动服务', '运行进程',
      '启动项目', '运行项目', '跑起来', '把服务跑起来', '启动后端', '启动前端',
      'go run', 'npm run dev', 'npm run serve', 'npm start',
      '运行后端', '运行前端', '启动开发环境', 'run backend', 'run frontend'),
  (2) 管理多个服务的生命周期 (triggers: 'manage services', '管理服务', 'service lifecycle',
      '重启服务', 'restart', '停止服务', 'stop service'),
  (3) 查看/搜索进程日志 (triggers: 'check logs', '查看日志', 'debug service', '看看日志'),
  (4) 编排前后端启动顺序 (triggers: 'start all services', '启动所有服务', 'orchestrate services',
      '同时启动前后端', '启动前后端')
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
| `start.sh` | 启动后台进程 | `$PM/start.sh <name> "<cmd>" [--cwd <dir>] [--env "K=V"]` |
| `stop.sh` | 终止进程 | `$PM/stop.sh <name>` 或 `$PM/stop.sh --all` |
| `list.sh` | 列出所有进程 | `$PM/list.sh` |
| `logs.sh` | 查看日志 | `$PM/logs.sh <name> [--lines N] [--head] [--follow]` |
| `search.sh` | 搜索日志 | `$PM/search.sh <name> "<pattern>"` |
| `restart.sh` | 重启进程 | `$PM/restart.sh <name>` |
| `clean.sh` | 清理记录 | `$PM/clean.sh` 或 `$PM/clean.sh --all` |

## HAB 项目启动（最常用）

HAB/GVA 项目标准启动方式：

```bash
PM=.claude/skills/process-manager/scripts

# 1. 检查已有进程
$PM/list.sh

# 2. 启动后端（需要 HAB_CONFIG 指向 config.local.yaml）
$PM/start.sh backend "go run ." --cwd ./server --env "HAB_CONFIG=config.local.yaml"
sleep 3
$PM/search.sh backend "listening on|server run success"

# 3. 启动前端
$PM/start.sh frontend "npm run serve" --cwd ./web
sleep 3
$PM/search.sh frontend "ready in|Local:|compiled"
```

> **关键**：后端必须通过 `--env "HAB_CONFIG=config.local.yaml"` 传入配置文件路径，否则会使用默认的 `config.yaml`（可能不存在或缺少数据库密码等敏感配置）。

## 核心工作流

### 启动单个服务

```bash
PM=.claude/skills/process-manager/scripts
$PM/list.sh
$PM/start.sh backend "go run ." --cwd ./server
$PM/logs.sh backend --lines 20
```

### 带环境变量启动

```bash
$PM/start.sh backend "go run ." --cwd ./server --env "HAB_CONFIG=config.local.yaml GIN_MODE=release"
```

### 日志诊断

```bash
$PM/logs.sh backend                              # 最新 30 行
$PM/logs.sh backend --lines 50                   # 最新 50 行
$PM/logs.sh backend --head                       # 从头查看
$PM/search.sh backend "error|Error|panic|fatal"  # 搜索错误
```

### 生命周期管理

```bash
$PM/list.sh              # 查看状态
$PM/restart.sh backend   # 重启
$PM/stop.sh frontend     # 停止单个
$PM/stop.sh --all        # 停止所有
$PM/clean.sh             # 清理已停止的记录
```

## 常见问题

| 问题 | 处理 |
|------|------|
| 端口占用 | `lsof -i :<port>` 找到进程 → `stop.sh` → `start.sh` |
| 进程立即退出 | `logs.sh <name> --head` 查看启动日志 |
| 服务无响应 | `search.sh <name> "error\|panic"` |

## 编排模式

更多模式见 [references/patterns.md](references/patterns.md)。
