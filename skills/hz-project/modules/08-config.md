# 模块 08 — 环境配置与项目启动

## 快速启动

### 前置条件

- 已完成 `/hz-init` 初始化（包含数据库准备和配置生成）
- 或已有一个 hab 框架项目

### 启动后端

```bash
cd server

# 方式 1：使用 config.local.yaml（hz-init 生成的配置）
HAB_CONFIG=config.local.yaml go run .

# 方式 2：使用默认 config.yaml
# 如果你的配置文件名为 config.yaml，直接运行
go run .
```

> 后端默认监听 `:9688`（主服务）和 `:9689`（API 端口）

### 启动管理后台（web）

```bash
cd web

# 首次启动需安装依赖
npm install

# 开发模式启动（使用 .env.example 中的配置）
npm run serve
```

> 前端默认监听 `:8091`，自动代理 `/api` 请求到后端 `:9688`

### 启动客户端（client，可选）

```bash
cd client
npm install
npm run dev
```

### 验证

1. 浏览器打开 `http://localhost:8091`
2. 用 `admin` / `123456`（或自定义密码）登录
3. 看到管理后台页面即表示成功

---

## 后端配置

### 配置文件层级

| 文件 | 用途 | Git | 说明 |
|------|------|-----|------|
| `config.example.yaml` | 模板参考 | 提交 | 不含敏感信息，新成员参考 |
| `config.yaml` | 默认运行配置 | .gitignore | viper 默认加载此文件 |
| `config.local.yaml` | 本地开发配置 | .gitignore | hz-init 生成，通过 HAB_CONFIG 指定 |

### 配置加载机制

```go
// core/viper.go
config := os.Getenv("HAB_CONFIG")  // 环境变量优先
if config == "" {
    config = "config.yaml"         // 默认 config.yaml
}
```

**两种使用方式（二选一）：**

1. **推荐：使用 config.local.yaml + 环境变量**
   ```bash
   HAB_CONFIG=config.local.yaml go run .
   ```
   hz-init 生成的就是这个文件，含数据库密码和 JWT key。

2. **传统：复制为 config.yaml**
   ```bash
   cp config.local.yaml config.yaml
   go run .
   ```
   不需要设环境变量，但要注意不要提交到 git。

### 主要配置段

```yaml
# ===================== 系统核心 =====================
system:
  db-type: sqlite          # sqlite / mysql
  addr: 9688               # 后端主端口
  api-addr: 9689           # API 端口
  use-redis: false          # 是否启用 Redis
  use-strict-auth: true     # 严格权限校验
  migration: true           # 启动时自动迁移
  environment: dev          # dev / prod

# ===================== 数据库 =====================
# SQLite（db-type: sqlite 时生效）
sqlite:
  path: data.db

# MySQL（db-type: mysql 时生效）
mysql:
  path: 127.0.0.1
  port: "3306"
  db-name: my-project
  username: root
  password: your-password
  config: charset=utf8mb4&parseTime=True&loc=Local
  log-mode: info
  max-idle-conns: 10
  max-open-conns: 100

# Redis（可选，use-redis: true 时需要）
redis:
  addr: 127.0.0.1:6379
  password: ""
  db: 0

# ===================== JWT 认证 =====================
jwt:
  signing-key: <uuid>       # 每个项目生成唯一 key（uuidgen）
  expires-time: 7d
  buffer-time: 1d
  issuer: qmPlus

# ===================== 代码生成器 =====================
autocode:
  web: web/src
  server: server
  module: my-project         # 项目名，影响代码生成路径
  api-key: ""                # 留空禁用 API Key 认证

# ===================== 日志 =====================
zap:
  level: info
  prefix: '[my-project]'    # 项目标识
  format: console
  director: log
  show-line: true
  log-in-console: true
```

### 环境变量

| 变量 | 说明 | 示例 |
|------|------|------|
| `HAB_CONFIG` | 指定配置文件路径 | `config.local.yaml` |

> Go module 前缀统一保持 `hab` / `HAB_`，所有项目不做替换。

---

## 前端配置（web/）

### 环境变量文件

| 文件 | 用途 | Git |
|------|------|-----|
| `.env.example` | 开发环境配置模板 | 提交 |
| `.env.dev` | dev 模式配置 | 提交 |
| `.env.production` | 生产环境（如有） | 提交 |
| `.env.local` | 本地覆盖（如需） | .gitignore |

### 配置变量

```bash
# .env.example（开发模式配置）
ENV = 'development'
VITE_CLI_PORT = 8091          # 前端开发服务器端口
VITE_SERVER_PORT = 9688       # 后端 API 端口
VITE_BASE_API = /api          # API 路径前缀
VITE_FILE_API = /api          # 文件 API 路径前缀
VITE_BASE_PATH = http://127.0.0.1  # 后端地址
VITE_POSITION = close         # open 启用 Vue DevTools
VITE_EDITOR = vscode          # 编辑器
VITE_DEFAULT_LOCALE = zh-CN   # 默认语言
```

### Vite 加载机制

```js
// vite.config.js
const NODE_ENV = mode || 'development'
const envFiles = [`.env.${NODE_ENV}`]
// 读取对应环境的 .env 文件
```

`npm run serve` 默认 mode = development → 加载 `.env.development`
`npm run build` 默认 mode = production → 加载 `.env.production`

如果文件不存在（如只有 `.env.example`），需要复制：
```bash
cp .env.example .env.development
```

### 代理配置

`web/vite.config.js` 自动配置开发代理：

```js
proxy: {
  [process.env.VITE_BASE_API]: {   // 默认 /api
    target: `${VITE_BASE_PATH}:${VITE_SERVER_PORT}/`,  // http://127.0.0.1:9688/
    changeOrigin: true,
    rewrite: path => path.replace(/^\/api/, '')
  }
}
```

前端请求 `/api/xxx` → 代理到 `http://127.0.0.1:9688/xxx`

---

## 端口规划

| 服务 | 默认端口 | 配置位置 |
|------|---------|---------|
| 后端主服务 | 9688 | `system.addr` |
| 后端 API | 9689 | `system.api-addr` |
| web 管理后台 | 8091 | `VITE_CLI_PORT` |
| client 前端 | 8093 | 按需配置 |

---

## 常见配置场景

### 切换数据库类型

SQLite → MySQL：
1. 修改 `config.local.yaml` 中 `system.db-type: mysql`
2. 填写 `mysql` 配置段的连接信息
3. 导入种子数据：`mysql -u root -p <db> < server/docs/hab.sql`

MySQL → SQLite：
1. 修改 `system.db-type: sqlite`
2. 导入种子数据：`sqlite3 server/data.db < server/docs/hab-sqlite.sql`

### 修改端口

后端端口（修改 config）：
```yaml
system:
  addr: 8080       # 改后端端口
```

前端端口（修改 .env）：
```bash
VITE_CLI_PORT = 3000         # 改前端端口
VITE_SERVER_PORT = 8080      # 要和后端一致
```

### 启用 Redis

```yaml
system:
  use-redis: true

redis:
  addr: 127.0.0.1:6379
  password: ""
  db: 0
```

### 生产环境配置

```yaml
system:
  environment: prod
  migration: false    # 生产不自动迁移

zap:
  level: warn          # 减少日志
  log-in-console: false
```
