# 故障排查手册

## 1. 符号链接问题

### 症状
- skill/command/agent 无法识别
- Claude 报告找不到 skill 文件

### 排查

```bash
# 检查链接状态
ls -la .claude/skills/
ls -la .claude/commands/
ls -la .claude/agents/

# 检查 link.sh 中的路径
cat .claude/link.sh | grep HZ_AGENTS

# 检查目标目录是否存在
ls "$(cat .claude/link.sh | grep HZ_AGENTS | cut -d= -f2 | tr -d '"')"
```

### 修复

```bash
# 重新执行链接
cd .claude && bash link.sh

# 如果路径不对，手动修正
# 编辑 .claude/link.sh，将 HZ_AGENTS 改为实际路径
```

## 2. 配置文件问题

### 症状
- `Fatal error config file: Config File "config.yaml" Not Found`
- 配置项不生效

### 排查

```bash
# 确认工作目录
pwd  # 应该在 server/ 目录或项目根目录

# 确认配置文件存在
ls server/config.yaml

# 检查环境变量
echo $HAB_CONFIG  # 或 $<PREFIX>_CONFIG

# 检查配置文件语法
python3 -c "import yaml; yaml.safe_load(open('server/config.yaml'))"
```

### 修复

```bash
# 从示例创建配置
cp server/config.example.yaml server/config.yaml

# 或指定配置文件路径
export HAB_CONFIG=./config.yaml
cd server && go run .
```

## 3. 端口冲突

### 症状
- `listen tcp :9688: bind: address already in use`
- 前端 dev server 启动失败

### 排查

```bash
# 查找占用进程
lsof -i :9688   # 后端
lsof -i :9689   # API
lsof -i :8091   # web 前端
lsof -i :8093   # client 前端

# 杀死占用进程
kill -9 <PID>
```

### 修复

修改端口配置：
- 后端：`server/config.yaml` → `system.addr` 和 `system.api-addr`
- web 前端：`web/.env` → `VITE_CLI_PORT`
- client 前端：`client/.env` → `VITE_CLI_PORT`

## 4. Agent 执行问题

### 症状
- Agent 无法读写文件
- Agent 执行命令被拒绝
- "permission denied" 错误

### 排查

```bash
# 检查 settings.local.json
cat .claude/settings.local.json

# 确认权限配置
python3 -c "
import json
with open('.claude/settings.local.json') as f:
    print(json.dumps(json.load(f), indent=2))
"
```

### 修复

确保 `settings.local.json` 包含必要权限：
```json
{
  "permissions": {
    "allow": [
      "Bash(npm:*)",
      "Bash(npx:*)",
      "Bash(go:*)",
      "Bash(python3:*)",
      "Bash(docker:*)",
      "Bash(git:*)"
    ]
  }
}
```

## 5. Docker 构建问题

### 症状
- `CGO_ENABLED` 相关错误
- Go 依赖下载超时
- node_modules 导致镜像过大

### 排查与修复

#### CGO 问题（SQLite 需要）

```dockerfile
# Dockerfile 中需要
RUN apk add --no-cache gcc musl-dev
ENV CGO_ENABLED=1
```

#### Go 代理（国内）

```dockerfile
ENV GOPROXY=https://goproxy.cn,direct
```

#### .dockerignore

确保包含：
```
node_modules
.git
.claude
docs
deploy
*.md
```

#### 多阶段构建示例

```dockerfile
# 构建阶段
FROM golang:1.25-alpine AS builder
RUN apk add --no-cache gcc musl-dev
WORKDIR /build
COPY server/ .
RUN CGO_ENABLED=1 go build -o server .

# 运行阶段
FROM alpine:latest
RUN apk add --no-cache ca-certificates
WORKDIR /srv/app
COPY --from=builder /build/server .
COPY --from=builder /build/config.yaml .
EXPOSE 9688
CMD ["./server"]
```
