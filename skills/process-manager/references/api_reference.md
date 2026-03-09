# 脚本参考

所有脚本位于 `.claude/skills/process-manager/scripts/`（下文用 `$PM` 代替），共享公共函数 `_common.sh`。

进程数据存储在 `/tmp/claude-pm/`，每个进程 4 个文件：
- `<name>.pid` — 进程 PID
- `<name>.log` — 合并日志（stdout + stderr）
- `<name>.cmd` — 启动命令（用于重启）
- `<name>.cwd` — 工作目录（用于重启）

---

## start.sh

启动一个后台进程。自动检查同名进程是否已在运行。

```
用法: start.sh <name> "<command>" [--cwd <dir>]

参数:
  name      进程名称（如 backend, frontend）
  command   要执行的命令（需引号包裹）
  --cwd     工作目录（默认当前目录）
```

示例：
```bash
$PM/start.sh backend "go run ./cmd/server" --cwd ./server
$PM/start.sh frontend "npm run dev" --cwd ./web
```

---

## stop.sh

终止进程。先发 SIGTERM，5 秒未退出则 SIGKILL。

```
用法: stop.sh <name>       终止指定进程
      stop.sh --all         终止所有进程
```

---

## list.sh

列出所有管理中的进程，显示名称、状态、PID、命令和工作目录。

```
用法: list.sh
```

---

## logs.sh

查看进程日志。

```
用法: logs.sh <name> [--lines N] [--head] [--follow]

选项:
  --lines N, -n N    显示行数（默认 30）
  --head             从开头显示（默认从末尾）
  --follow, -f       实时跟踪日志
```

示例：
```bash
$PM/logs.sh backend --lines 50
$PM/logs.sh backend --head
$PM/logs.sh frontend --follow
```

---

## search.sh

用正则表达式搜索进程日志，带行号输出。

```
用法: search.sh <name> "<pattern>"
```

常用 pattern：
- `"error|Error|ERROR|panic|fatal"` — 搜索错误
- `"(GET|POST|PUT|DELETE) /api"` — 搜索 HTTP 请求
- `"listening on|started on port"` — 搜索端口监听
- `"ECONNREFUSED|connection refused|timeout"` — 搜索连接问题

---

## restart.sh

重启进程（自动使用之前保存的命令和工作目录）。

```
用法: restart.sh <name>
```

---

## clean.sh

清理进程记录。

```
用法: clean.sh           清理已停止的进程记录
      clean.sh --all      清理所有记录（含运行中的）
```
