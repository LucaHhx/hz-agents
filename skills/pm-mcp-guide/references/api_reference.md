# pm-mcp API 参考

## 目录

1. [start_process](#start_process)
2. [list_processes](#list_processes)
3. [get_logs](#get_logs)
4. [grep_logs](#grep_logs)
5. [send_input](#send_input)
6. [terminate_process](#terminate_process)
7. [terminate_all_processes](#terminate_all_processes)
8. [clear_finished](#clear_finished)

---

## start_process

启动一个长期运行的后台进程。

**参数：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `name` | string | 是 | 进程名称，用于标识（建议语义化，如 `backend-api`, `redis`） |
| `command` | string | 是 | 要执行的 bash 命令 |
| `cwd` | string | 否 | 工作目录（默认当前目录） |
| `description` | string | 否 | 进程描述 |

**返回**：进程 ID 和状态信息。

**示例：**

```
start_process(
  name: "backend-api",
  command: "go run ./cmd/server",
  cwd: "/project/server",
  description: "Go 后端 API 服务"
)
```

**注意事项：**
- 启动前必须先 `list_processes` 检查同名进程是否已在运行
- `name` 用于人类识别，可以重复但不建议
- 进程在后台运行，不会阻塞当前会话

---

## list_processes

列出所有进程（运行中和已终止）及其信息。

**参数：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | string | 否 | 指定进程 ID，仅返回该进程信息 |

**返回**：进程列表，包含 id、name、status、command 等字段。

**状态值：**
- `running` — 进程运行中
- `terminated` — 正常终止
- `failed` — 异常退出

---

## get_logs

获取指定进程的日志输出（stdout 和 stderr 合并）。

**参数：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | string | 是 | 进程 ID |
| `lines` | number | 否 | 返回行数（默认全部） |
| `skip` | number | 否 | 跳过的行数（从末尾或开头计算） |
| `fromTop` | boolean | 否 | 从文件开头读取（默认 false，从末尾读取） |

**分页用法：**
- 最新 50 行：`get_logs(id, lines=50)`
- 开头 50 行：`get_logs(id, lines=50, fromTop=true)`
- 跳过末尾 100 行取 50 行：`get_logs(id, lines=50, skip=100)`

---

## grep_logs

使用正则表达式搜索进程日志。

**参数：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | string | 是 | 进程 ID |
| `pattern` | string | 是 | 正则表达式模式 |

**常用 pattern：**
- 搜索错误：`"error|Error|ERROR|panic|fatal|FATAL"`
- 搜索 HTTP 请求：`"(GET|POST|PUT|DELETE) /api"`
- 搜索端口监听：`"listening on|started on port"`
- 搜索连接问题：`"ECONNREFUSED|connection refused|timeout"`

---

## send_input

向运行中的进程发送输入文本（模拟键盘输入）。

**参数：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | string | 是 | 进程 ID |
| `input` | string | 是 | 要发送的文本 |

**注意**：发送后需要 `\n` 表示回车。例如 `send_input(id, input="y\n")`。

---

## terminate_process

终止指定进程。

**参数：**

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | string | 是 | 进程 ID |

---

## terminate_all_processes

终止所有由 pm-mcp 管理的进程。无参数。

---

## clear_finished

清理所有已结束（terminated/failed）的进程记录并删除其日志文件。无参数。

用于保持进程列表整洁，移除不再需要的历史记录。
