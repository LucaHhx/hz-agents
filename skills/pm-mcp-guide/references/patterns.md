# pm-mcp 常见编排模式

## 目录

1. [前后端开发环境](#前后端开发环境)
2. [微服务编排](#微服务编排)
3. [开发工具链](#开发工具链)
4. [服务健康检查](#服务健康检查)
5. [优雅关闭](#优雅关闭)

---

## 前后端开发环境

典型 Go + React/Tauri 项目启动：

```
# 检查已有进程
list_processes

# 先启动后端
start_process(name: "backend", command: "go run ./cmd/server", cwd: "/project/server", description: "Go API 服务")
grep_logs(id: backend_id, pattern: "listening on|started")

# 后端就绪后启动前端
start_process(name: "frontend", command: "npm run dev", cwd: "/project/web", description: "Vite 开发服务器")
grep_logs(id: frontend_id, pattern: "ready in|Local:")
```

## 微服务编排

多个独立服务，部分有依赖关系：

```
# 网关依赖 auth 和 user 服务
# auth 和 user 可并行启动

# 并行启动无依赖服务
start_process(name: "auth-svc", command: "go run ./cmd/auth", cwd: "/project")
start_process(name: "user-svc", command: "go run ./cmd/user", cwd: "/project")

# 确认都就绪
grep_logs(id: auth_id, pattern: "listening on")
grep_logs(id: user_id, pattern: "listening on")

# 启动依赖服务
start_process(name: "gateway", command: "go run ./cmd/gateway", cwd: "/project")
```

## 开发工具链

同时运行多个前端开发辅助工具：

```
start_process(name: "tailwind", command: "npx tailwindcss -i ./src/input.css -o ./dist/output.css --watch", cwd: "/project/web")
start_process(name: "typecheck", command: "npx tsc --watch --noEmit", cwd: "/project/web")
start_process(name: "test-watch", command: "npx vitest --watch", cwd: "/project/web")
```

## 服务健康检查

按需检查所有服务状态：

```
# 列出所有进程状态
list_processes

# 对每个运行中的服务检查最新日志
get_logs(id: service_id, lines=10)

# 批量搜索错误
grep_logs(id: service_id, pattern: "error|panic|fatal|FATAL")
```

**异常处理流程：**

```
发现异常 → get_logs 查看详情 → terminate_process → start_process 重启
```

## 优雅关闭

按依赖的反向顺序关闭：

```
# 关闭顺序：前端 → 后端（与启动相反）
terminate_process(id: frontend_id)
terminate_process(id: backend_id)

# 清理记录
clear_finished
```

或一键关闭所有服务：

```
terminate_all_processes
clear_finished
```
