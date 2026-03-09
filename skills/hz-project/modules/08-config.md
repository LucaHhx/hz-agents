# 模块 08 — 环境配置规范

## 概述

项目配置分为后端（Go/Viper）和前端（Vite 环境变量）两套体系。

## 后端配置

### 配置文件层级

| 文件 | 用途 | Git |
|------|------|-----|
| config.example.yaml | 示例配置（模板） | 提交 |
| config.yaml | 实际运行配置 | .gitignore |
| config.local.yaml | 本地开发覆盖 | .gitignore |

### 配置加载优先级

Viper 加载顺序（后者覆盖前者）：
1. config.yaml（默认配置文件）
2. 环境变量 `HAB_CONFIG`（或项目前缀 `<PREFIX>_CONFIG`）指定的文件路径

```go
// core/viper.go 逻辑
config := os.Getenv("HAB_CONFIG")  // 自定义项目改为 <PREFIX>_CONFIG
if config == "" {
    config = "config.yaml"
}
```

### 主要配置段

```yaml
# 系统核心
system:
  db-type: sqlite          # sqlite / mysql / pgsql
  addr: 9688               # 后端主端口
  api-addr: 9689           # API 端口
  use-redis: false          # 是否启用 Redis
  environment: dev          # dev / prod

# 数据库
mysql:
  path: 127.0.0.1
  port: "3306"
  db-name: my-project       # ← 改为项目名
  username: root
  password: your-password

# Redis（可选）
redis:
  addr: 127.0.0.1:6379
  password: ""
  db: 0

# JWT 认证
jwt:
  signing-key: <uuid>       # ← 每个项目生成唯一 key
  expires-time: 7d
  buffer-time: 1d
  issuer: qmPlus

# AutoCode 代码生成
autocode:
  web: web/src
  server: server
  module: my-project         # ← 改为 Go module 名
  api-key: ""                # 留空禁用，填值启用

# 日志
zap:
  level: info
  prefix: '[my-project]'    # ← 改为项目标识
  format: console
```

### SQLite 配置

默认使用 SQLite，无需额外服务：

```yaml
system:
  db-type: sqlite

sqlite:
  path: data.db
```

### MySQL 配置

```yaml
system:
  db-type: mysql

mysql:
  path: 127.0.0.1
  port: "3306"
  db-name: my_project
  username: root
  password: your-password
  config: charset=utf8mb4&parseTime=True&loc=Local
```

## 前端配置（web/）

### 环境变量文件

| 文件 | 用途 | Git |
|------|------|-----|
| .env | 基础配置 | 提交 |
| .env.development | 开发环境 | 提交 |
| .env.production | 生产环境 | 提交 |
| .env.local | 本地覆盖 | .gitignore |

### 常用变量

```bash
# .env
VITE_CLI_PORT = 8091          # 前端开发服务器端口
VITE_SERVER_PORT = 9688       # 后端 API 端口
VITE_BASE_API = /api          # API 路径前缀
VITE_BASE_PATH = /            # 部署基础路径（admin 时改为 /admin/）
```

### Vite 代理配置

`web/vite.config.js` 中的开发代理：

```js
server: {
  proxy: {
    '/api': {
      target: `http://127.0.0.1:${VITE_SERVER_PORT}`,
      changeOrigin: true,
    }
  }
}
```

## 前端配置（client/，可选）

client 目录的环境变量根据所选框架配置：

```bash
# .env (React + Vite)
VITE_API_URL = http://localhost:9688
VITE_APP_TITLE = My App
```

## 端口规划

| 服务 | 默认端口 | 说明 |
|------|---------|------|
| 后端主服务 | 9688 | system.addr |
| 后端 API | 9689 | system.api-addr |
| web 管理后台 | 8091 | VITE_CLI_PORT |
| client 前端 | 8093 | 按需配置 |
