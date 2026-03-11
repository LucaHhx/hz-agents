# 常见编排模式

> 以下示例中 `$PM` = `.claude/skills/process-manager/scripts`

## HAB/GVA 项目（最常用）

```bash
$PM/list.sh

# 后端（必须指定 HAB_CONFIG）
$PM/start.sh backend "go run ." --cwd ./server --env "HAB_CONFIG=config.local.yaml"
sleep 3
$PM/search.sh backend "server run success|listening on"

# 前端
$PM/start.sh frontend "npm run serve" --cwd ./web
sleep 3
$PM/search.sh frontend "ready in|Local:|compiled"
```

就绪标志：
- 后端：`server run success on`, `listening on`
- 前端：`ready in`, `compiled successfully`, `Local:`

## 前后端开发环境（通用）

```bash
$PM/list.sh

# 先启动后端
$PM/start.sh backend "go run ." --cwd ./server --env "HAB_CONFIG=config.local.yaml"
sleep 3
$PM/search.sh backend "listening on|started"

# 后端就绪后启动前端
$PM/start.sh frontend "npm run dev" --cwd ./web
sleep 3
$PM/search.sh frontend "ready in|Local:"
```

## 微服务编排

```bash
# 并行启动无依赖服务
$PM/start.sh auth-svc "go run ./cmd/auth" --cwd ./server
$PM/start.sh user-svc "go run ./cmd/user" --cwd ./server

sleep 3
$PM/search.sh auth-svc "listening on"
$PM/search.sh user-svc "listening on"

# 启动依赖服务
$PM/start.sh gateway "go run ./cmd/gateway" --cwd ./server
```

## 开发工具链

```bash
$PM/start.sh tailwind "npx tailwindcss -i ./src/input.css -o ./dist/output.css --watch" --cwd ./web
$PM/start.sh typecheck "npx tsc --watch --noEmit" --cwd ./web
$PM/start.sh test-watch "npx vitest --watch" --cwd ./web
```

## 服务健康检查

```bash
$PM/list.sh
$PM/logs.sh backend --lines 10
$PM/logs.sh frontend --lines 10
$PM/search.sh backend "error|panic|fatal"
$PM/search.sh frontend "error|Error"
```

## 优雅关闭

```bash
# 按依赖反向顺序关闭
$PM/stop.sh frontend
$PM/stop.sh backend
$PM/clean.sh
```

或一键：

```bash
$PM/stop.sh --all
$PM/clean.sh --all
```
