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

> 后端默认监听 `:9688`（管理接口）和 `:9689`（客户端/外部 API 端口）

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

## 后端双端口架构

| 端口 | 配置项 | 用途 | 消费者 |
|------|--------|------|--------|
| `system.addr` (默认 9688) | 后台管理接口 | 后台 CRUD、权限、菜单等 | `web/`（管理后台） |
| `system.api-addr` (默认 9689) | 客户端/外部 API 接口 | 面向客户端和第三方的业务 API | `client/`（客户端）、外部系统 |

> 两个端口均从 `config.yaml` 读取，非硬编码。

### 运行模式（-type 参数）

通过启动参数 `-type` 控制启动哪些端口：

| 参数 | 说明 |
|------|------|
| `-type=all` | 同时启动管理端(9688)+客户端API(9689)，Docker 默认模式 |
| `-type=backend` | 仅启动管理端(9688) |
| `-type=api` | 仅启动客户端API(9689) |

```bash
# 示例
go run . -type=all          # 默认，两个端口都启动
go run . -type=backend      # 仅管理端
```

## 端口配置联动

修改后端端口后，须同步更新前端配置：

| 后端配置项 | 前端配置文件 | 对应变量 |
|-----------|-------------|---------|
| `system.addr` | `web/.env` | `VITE_SERVER_PORT`（代理目标端口） |
| `system.api-addr` | `client/.env` | `VITE_API_URL` 或代理目标 |

---

## 后端配置

### 配置文件层级

| 文件 | 用途 | Git | 说明 |
|------|------|-----|------|
| `config.example.yaml` | 完整配置模板（带注释） | 提交 | 所有字段带中文注释，新成员参考 |
| `config.minimal.yaml` | 极简配置模板 | 提交 | 最小可运行配置（SQLite + JWT key） |
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

### 配置示例 A — 完整配置（带注释）

> 对应实际文件：`server/config.example.yaml`

```yaml
# ===================== 系统核心配置 =====================
system:
  db-type: mysql          # 数据库类型: sqlite | mysql | pgsql | mssql | oracle
  oss-type: local          # 文件存储: local | aliyun | minio | aws | tencent | huawei
  addr: 9688               # 后台管理接口端口（web/ 连接此端口）
  api-addr: 9689           # 客户端/外部 API 端口（client/ 连接此端口）
  iplimit-count: 15000     # IP 限流：时间窗口内最大请求数
  iplimit-time: 3600       # IP 限流：时间窗口（秒）
  use-redis: false         # 是否启用 Redis 缓存
  use-mongo: false         # 是否启用 MongoDB
  use-strict-auth: true    # 是否启用严格鉴权（Casbin）
  time-zone: "UTC"         # 时区
  migration: true          # 启动时自动迁移数据库
  translation-dir: ./translation  # i18n 翻译文件目录
  environment: dev         # 环境: dev | production
  login-mode: simple       # 登录模式（见下方 login-mode 说明）

# ===================== 数据库配置 =====================
mysql:
  path: 127.0.0.1          # MySQL 地址
  port: "3306"             # MySQL 端口
  db-name: hab             # 数据库名
  username: root           # 用户名
  password: your-password  # 密码
  config: charset=utf8mb4&parseTime=True&loc=Local  # 连接参数
  log-mode: info           # SQL 日志级别: silent | error | warn | info
  max-idle-conns: 10       # 最大空闲连接数
  max-open-conns: 100      # 最大打开连接数

redis:
  addr: 127.0.0.1:6379     # Redis 地址
  password: ""             # Redis 密码
  db: 0                    # Redis 数据库编号

# ===================== JWT 认证 =====================
jwt:
  signing-key: <uuid>      # JWT 签名密钥（建议 uuidgen 生成）
  expires-time: 7d         # Token 过期时间
  buffer-time: 1d          # Token 刷新缓冲期
  issuer: qmPlus           # 签发者

# ===================== 验证码 =====================
captcha:
  key-long: 6              # 验证码位数
  img-width: 240           # 图片宽度
  img-height: 80           # 图片高度
  open-captcha: 0          # 0=总是需要, >0=错误N次后需要
  open-captcha-timeout: 3600  # 验证码缓存时间（秒）

# ===================== 代码生成器 =====================
autocode:
  web: web/src             # 前端代码生成目录
  server: server           # 后端代码生成目录
  module: hab              # Go module 名
  api-key: ""              # AutoCode API Key（留空=禁用，填入=启用）

# ===================== 文件存储 =====================
local:
  path: uploads/file       # 访问路径
  store-path: uploads/file # 存储路径

# ===================== 日志 =====================
zap:
  level: info              # 日志级别: debug | info | warn | error
  prefix: '[hab]'          # 日志前缀
  format: console          # 格式: console | json
  director: log            # 日志目录
  show-line: true          # 显示调用行号
  log-in-console: true     # 同时输出到控制台
  retention-day: -1        # 日志保留天数（-1=永久）
```

### login-mode 登录模式

| 值 | 说明 |
|------|------|
| `simple` | 仅用户名密码，无验证码 |
| `captcha` | 需要图形验证码 |
| `strict` | 分步强验证（密码 → 2FA） |

### pprof 调试

开发模式下（`environment: dev`），pprof 调试服务运行在 `:6060`，可通过 `http://localhost:6060/debug/pprof/` 访问。

### 配置示例 B — 极简配置（最小可运行）

> 对应实际文件：`server/config.minimal.yaml`

```yaml
system:
  db-type: sqlite          # 用 SQLite 免装数据库
  addr: 9688               # 后台管理接口端口（web/ 连接此端口）
  api-addr: 9689           # 客户端/外部 API 端口（client/ 连接此端口）
  time-zone: "UTC"         # 时区（启动时解析，不可为空）
  migration: true          # 启动时自动建表

sqlite:
  db-name: data            # 数据库文件名（生成 data.db，不可为空）

jwt:
  signing-key: <uuidgen生成>
  expires-time: 7d         # Token 过期时间（必填）
  buffer-time: 1d          # Token 刷新缓冲期（必填）
  issuer: qmPlus

zap:
  level: info
  format: console
  director: log
  show-line: true
  log-in-console: true
```

> 以上是启动不会 panic 的最小配置。其余未配置参数使用 Go 零值默认。
> SQLite 数据库文件自动创建在 `server/data.db`。
> 如需 MySQL，改为 `db-type: mysql` 并追加 `mysql:` 配置块（参考 config.example.yaml）。

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
VITE_SERVER_PORT = 9688       # 后端 API 端口（对应 system.addr）
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

`npm run serve` → `vite --host --mode development` → 加载 `.env.development`
`npm run dev` → `vite --host --mode dev` → 加载 `.env.dev`
`npm run build` → mode = production → 加载 `.env.production`

> **注意**：`serve` 和 `dev` **不等价**，它们的 `--mode` 不同，加载的环境文件也不同。
> 仓库默认提供 `.env.dev` 和 `.env.example`，没有 `.env.development`。
> 日常开发推荐使用 `npm run dev`（对应已有的 `.env.dev`）。

如需使用 `npm run serve`，须先创建对应的环境文件：
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
| 后端管理接口 | 9688 | `system.addr` |
| 后端客户端 API | 9689 | `system.api-addr` |
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

**修改后端管理接口端口（system.addr）：**
```yaml
system:
  addr: 8080       # 改后端管理端口
```
→ 同步更新 `web/.env`：
```bash
VITE_SERVER_PORT = 8080      # 要和 system.addr 一致
```

**修改后端客户端 API 端口（system.api-addr）：**
```yaml
system:
  api-addr: 8081   # 改客户端 API 端口
```
→ 同步更新 `client/.env`（如有）的 API 端口配置。

**修改前端端口：**
```bash
VITE_CLI_PORT = 3000         # 改前端开发服务器端口
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
