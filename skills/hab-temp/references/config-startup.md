# 配置文件与启动指南

本文档详细说明 hz-admin-base 的配置体系、启动流程和开发环境搭建。

---

## 一、配置文件说明

### 1.1 配置文件体系

系统使用 YAML 格式的配置文件，文件关系如下：

| 文件 | 用途 | 是否入库 |
|------|------|----------|
| `config.example.yaml` | 完整配置模板，包含所有字段和默认值 | 是 |
| `config.yaml` | 实际运行配置（默认加载） | 否（.gitignore） |
| `config.local.yaml` | 本地开发配置（含敏感信息） | 否（.gitignore） |
| `config.cloud.yaml` | 云端/生产配置 | 否（.gitignore） |

**关键机制**：Viper 只加载一个配置文件，默认为 `config.yaml`。系统不会自动检测或合并 `config.local.yaml`。要使用 `config.local.yaml`，必须通过环境变量显式指定：

```bash
export HAB_CONFIG=config.local.yaml
```

推荐做法：复制 `config.example.yaml` 为 `config.local.yaml`，修改敏感字段（数据库密码、JWT 密钥等），然后设置 `HAB_CONFIG` 环境变量指向它。

### 1.2 配置节详细说明

#### system — 系统核心配置

| 配置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `db-type` | string | `sqlite` | 数据库类型：sqlite / mysql / pgsql / mssql / oracle |
| `oss-type` | string | `local` | 文件存储：local / aliyun / minio / aws / tencent / huawei |
| `addr` | int | `9688` | 后台管理接口端口（web/ 前端连接此端口） |
| `api-addr` | int | `9689` | 客户端/外部 API 端口（client/ 连接此端口） |
| `router-prefix` | string | `""` | API 路由前缀（如 /api/v1） |
| `iplimit-count` | int | `15000` | IP 限流：时间窗口内最大请求数 |
| `iplimit-time` | int | `3600` | IP 限流：时间窗口（秒） |
| `use-multipoint` | bool | `false` | 多点登录拦截（需 Redis） |
| `use-redis` | bool | `false` | 是否启用 Redis 缓存 |
| `use-mongo` | bool | `false` | 是否启用 MongoDB |
| `use-strict-auth` | bool | `true` | 严格鉴权模式（Casbin 树形角色分配） |
| `time-zone` | string | `UTC` | 时区（影响 time.Local） |
| `migration` | bool | `true` | 启动时自动迁移数据库表结构 |
| `translation-dir` | string | `./translation` | i18n 翻译文件目录 |
| `environment` | string | `dev` | 运行环境：dev / production |
| `login-mode` | string | `simple` | 登录模式：simple(无验证码) / captcha(需验证码) / strict(分步强验证) |

#### jwt — JWT 认证配置

| 配置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `signing-key` | string | 自动生成 UUID | JWT 签名密钥。留空则每次启动随机生成，建议手动设置固定值 |
| `expires-time` | string | `7d` | Token 过期时间（格式：Nd/Nh/Nm） |
| `buffer-time` | string | `1d` | Token 刷新缓冲期 |
| `issuer` | string | `hab` | JWT 签发者 |

> 重要：如果 `signing-key` 留空，每次重启后所有已发放的 Token 都会失效（因为密钥变了）。生产环境务必手动设置。

#### captcha — 验证码配置

| 配置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `key-long` | int | `6` | 验证码位数 |
| `img-width` | int | `240` | 图片宽度 |
| `img-height` | int | `80` | 图片高度 |
| `open-captcha` | int | `0` | 0 = 始终需要验证码，>0 = 错误 N 次后才需要 |
| `open-captcha-timeout` | int | `3600` | 验证码缓存时间（秒） |

#### zap — 日志配置

| 配置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `level` | string | `info` | 日志级别：debug / info / warn / error |
| `prefix` | string | `[hab]` | 日志前缀 |
| `format` | string | `console` | 输出格式：console / json |
| `director` | string | `log` | 日志文件目录 |
| `encode-level` | string | `LowercaseColorLevelEncoder` | 日志编码器 |
| `stacktrace-key` | string | `stacktrace` | 堆栈跟踪 key |
| `show-line` | bool | — | 显示调用行号 |
| `log-in-console` | bool | — | 同时输出到控制台 |
| `retention-day` | int | `-1` | 日志保留天数（-1 = 永久） |

#### autocode — 代码生成器

| 配置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `web` | string | `web/src` | 前端代码生成目录 |
| `server` | string | `server` | 后端代码生成目录 |
| `module` | string | 从 go.mod 读取 | Go module 名 |
| `ai-path` | string | `""` | AI 服务地址（可选） |
| `api-key` | string | `""` | AutoCode API Key |

#### local — 本地文件存储

| 配置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `path` | string | `uploads/file` | 访问路径 |
| `store-path` | string | `uploads/file` | 存储路径 |

#### redis — Redis 配置（可选）

| 配置项 | 类型 | 默认值 | 说明 |
|--------|------|--------|------|
| `addr` | string | `127.0.0.1:6379` | Redis 地址 |
| `password` | string | `""` | Redis 密码 |
| `db` | int | `0` | 数据库编号 |

仅在 `system.use-redis: true` 或 `system.use-multipoint: true` 时需要。

---

## 二、配置加载机制

### 2.1 Viper 加载流程

配置加载由 `server/core/viper.go` 中的 `Viper()` 函数负责：

1. 读取环境变量 `HAB_CONFIG` 获取配置文件路径，如果未设置则默认为 `config.yaml`
2. 创建 Viper 实例，设置配置文件路径和格式（yaml）
3. 调用 `v.ReadInConfig()` 读取配置文件
4. 调用 `v.WatchConfig()` 启用文件监听（基于 fsnotify）
5. 注册 `OnConfigChange` 回调：配置文件变更时自动重新 Unmarshal 并调用 `SetDefaults()`
6. 将配置反序列化到 `global.HAB_CONFIG`（类型为 `config.Server`）
7. 调用 `global.HAB_CONFIG.SetDefaults()` 填充所有未设置字段的默认值
8. 设置 `AutoCode.Root` 为项目根目录的绝对路径

### 2.2 优先级

代码注释中明确说明优先级：**命令行 > 环境变量 > 配置文件默认值**

实际流程中：
- `HAB_CONFIG` 环境变量决定加载哪个配置文件
- 配置文件中的值覆盖 `defaults.go` 中的默认值
- 配置文件中未设置的字段由 `SetDefaults()` 填充

### 2.3 默认值体系

`server/config/defaults.go` 中为每个配置节定义了 `setDefaults()` 方法。`Server.SetDefaults()` 按如下顺序调用：

1. `System.setDefaults()` — 核心配置默认值
2. `JWT.setDefaults()` — JWT 密钥自动生成 UUID
3. `Zap.setDefaults()` — 日志默认值
4. `Captcha.setDefaults()` — 验证码默认值
5. `AutoCode.setDefaults()` — 代码生成器默认值
6. `Local.setDefaults()` — 文件存储默认值
7. `Excel.setDefaults()` — Excel 目录默认值
8. 根据 `db-type` 选择对应数据库的默认值（仅设置当前使用的数据库类型）
9. `Redis.setDefaults()` — Redis 默认值

### 2.4 热更新

由于注册了 `v.WatchConfig()` 和 `OnConfigChange` 回调，修改配置文件后会自动重新加载。回调中会：
- 重新 Unmarshal 到 `global.HAB_CONFIG`
- 重新调用 `SetDefaults()` 确保默认值完整

> 注意：热更新不会重新初始化数据库连接、Redis 连接等已建立的资源。部分配置变更需要重启才能生效。

---

## 三、配置结构体

`server/config/config.go` 定义了顶层配置结构体 `Server`，包含所有配置节：

```
Server
├── System      // 系统核心
├── JWT         // JWT 认证
├── Zap         // 日志
├── Redis       // Redis
├── RedisList   // 多 Redis 实例
├── Mongo       // MongoDB
├── Email       // 邮件
├── Captcha     // 验证码
├── AutoCode    // 代码生成器
├── Mysql       // MySQL 配置
├── Mssql       // MSSQL 配置
├── Pgsql       // PostgreSQL 配置
├── Oracle      // Oracle 配置
├── Sqlite      // SQLite 配置
├── DBList      // 额外数据库列表
├── Local       // 本地文件存储
├── Qiniu       // 七牛 OSS
├── AliyunOSS   // 阿里云 OSS
├── HuaWeiObs   // 华为云 OBS
├── TencentCOS  // 腾讯云 COS
├── AwsS3       // AWS S3
├── CloudflareR2 // Cloudflare R2
├── Minio       // MinIO
├── DiskList    // 多磁盘列表
├── Excel       // Excel 模板
└── Cors        // 跨域配置
```

`System` 结构体（`server/config/system.go`）的每个字段都使用 `mapstructure` tag 将 YAML key 映射到 Go 字段名。

---

## 四、数据库配置

### 4.1 支持的数据库类型

通过 `system.db-type` 选择，支持五种数据库：

| db-type | 数据库 | 默认端口 | 默认用户名 | 默认数据库名 |
|---------|--------|----------|-----------|-------------|
| `sqlite` | SQLite | — | — | `data`（生成 data.db） |
| `mysql` | MySQL | 3306 | root | hab |
| `pgsql` | PostgreSQL | 5432 | postgres | hab |
| `mssql` | SQL Server | 1433 | sa | hab |
| `oracle` | Oracle | 1521 | system | hab |

### 4.2 通用数据库配置项

所有关系型数据库（除 SQLite 路径不同外）共享以下配置：

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `path` | `127.0.0.1` | 数据库地址 |
| `port` | 因数据库而异 | 端口 |
| `db-name` | `hab` | 数据库名 |
| `username` | 因数据库而异 | 用户名 |
| `password` | — | 密码（无默认值，需手动设置） |
| `config` | 因数据库而异 | 连接参数 |
| `log-mode` | `info` | SQL 日志级别：silent / error / warn / info |
| `max-idle-conns` | `10` | 最大空闲连接数 |
| `max-open-conns` | `100` | 最大打开连接数 |
| `engine` | `InnoDB` | 数据库引擎（MySQL 有效） |

### 4.3 SQLite 特殊配置

SQLite 不需要 host/port/username/password，仅需：

```yaml
sqlite:
  db-name: data       # 文件名（自动加 .db 后缀）
  path: ""            # 存储路径（空 = 当前目录）
```

SQLite 是默认的数据库类型，开箱即用，适合开发和小型部署。

### 4.4 MySQL 连接参数

```yaml
mysql:
  config: charset=utf8mb4&parseTime=True&loc=Local
```

- `charset=utf8mb4`：支持完整 Unicode（包括 emoji）
- `parseTime=True`：自动解析 TIME/DATE 类型
- `loc=Local`：使用本地时区

### 4.5 PostgreSQL 连接参数

```yaml
pgsql:
  config: "sslmode=disable TimeZone=UTC"
```

---

## 五、启动模式

### 5.1 三种运行模式

定义在 `server/global/mode.go`：

| 模式 | 常量 | 说明 |
|------|------|------|
| 全部 | `ModeAll` | 同时启动后台管理服务和 API 服务（默认） |
| 仅后台 | `ModeBackend` | 仅启动后台管理接口（端口 addr） |
| 仅 API | `ModeApi` | 仅启动客户端 API 接口（端口 api-addr） |

另有 `ModeTask` 定义但未在 ServiceList 中使用。

### 5.2 模式选择方式

通过命令行参数 `-type` 指定：

```bash
# 默认模式（全部启动）
go run main.go

# 仅启动后台管理
go run main.go -type=backend

# 仅启动 API 服务
go run main.go -type=api
```

`InitSysMode()` 在 `core.InitConf()` 中调用，解析 `-type` 参数后设置 `global.SysMode`。

### 5.3 启动流程

`main.go` 中的完整启动流程：

```
main()
├── core.InitServer()
│   ├── core.InitConf()
│   │   ├── Viper()           → 加载配置文件
│   │   ├── OtherInit()       → 其他初始化（读取 go.mod module 名等）
│   │   ├── Zap()             → 初始化日志
│   │   └── InitSysMode()     → 解析 -type 参数确定运行模式
│   ├── initialize.Gorm()     → 初始化数据库连接
│   ├── initialize.DBList()   → 初始化额外数据库
│   ├── RegisterTables()      → 自动迁移表结构（如果 migration=true）
│   ├── initialize.Redis()    → 初始化 Redis（如果需要）
│   └── initialize.Mongo()    → 初始化 MongoDB（如果需要）
├── pprof server on :6060     → 启动性能分析服务
├── 设置时区
└── switch SysMode:
    ├── ModeAll:
    │   ├── go RunApi()        → 协程启动 API 服务
    │   └── RunBackend()       → 主线程启动后台服务（阻塞）
    ├── ModeBackend:
    │   └── RunBackend()
    └── ModeApi:
        └── RunApi()
```

### 5.4 RunBackend 和 RunApi 的区别

**RunBackend**（后台管理）：
1. 初始化定时任务 `initialize.Timer()`
2. 调用 `core.RunWindowsServer()`
3. 加载 JWT 数据 `system.LoadAll()`
4. 初始化路由 `initialize.Routers()`
5. 监听 `system.addr` 端口（默认 9688）

**RunApi**（客户端 API）：
1. 调用 `core.RunApiServer()`
2. 加载 JWT 数据 `system.LoadAll()`
3. 初始化路由 `initialize.ApiRouters()`（独立的路由集）
4. 监听 `system.api-addr` 端口（默认 9689）

### 5.5 平台相关的 HTTP Server 实现

`initServer()` 函数有两个平台特定实现：

| 文件 | 平台 | 实现 | 特性 |
|------|------|------|------|
| `core/server_other.go` | Linux / macOS | `endless.NewServer` | 支持 graceful restart（零停机重启） |
| `core/server_win.go` | Windows | `http.Server` | 标准 HTTP Server |

两者共享相同的超时配置：`ReadHeaderTimeout = 10min`，`WriteTimeout = 10min`，`MaxHeaderBytes = 1MB`。

### 5.6 自动 GOMAXPROCS

`main.go` 导入了 `go.uber.org/automaxprocs`（init-only import），会在启动时自动将 `GOMAXPROCS` 设置为容器的 CPU 限制值，避免在 Docker/K8s 环境中过度占用 CPU。

---

## 六、双端口架构

系统设计了双端口架构，将后台管理和客户端 API 分离：

| 服务 | 默认端口 | 路由初始化 | 用途 |
|------|----------|-----------|------|
| Backend | 9688 (addr) | `initialize.Routers()` | 后台管理页面 API、CRUD 操作、系统管理 |
| API | 9689 (api-addr) | `initialize.ApiRouters()` | 面向客户端/外部的 API |

### 6.1 Backend 路由组架构（端口 9688）

`initialize.Routers()` 定义了三个路由组，均挂载在 `router-prefix` 下：

| 路由组 | 中间件 | 用途 |
|--------|--------|------|
| `PublicGroup` | 无鉴权 | 健康检查 `/health`、登录、初始化、字典公开接口 |
| `PrivateGroup` | `JWTAuth()` + `CasbinHandler()` | 需要登录的后台管理接口（用户、菜单、角色、操作记录等） |
| `AutoCodeGroup` | `ApiKeyOrJWT()` + `CasbinHandler()` | AutoCode 代码生成接口，支持 API Key 或 JWT 双重认证 |

此外还包含：
- Swagger 文档路由 `GET /swagger/*any`
- 静态文件服务（如果 `local.store-path` 不为空）
- 业务路由 `initBizRouter(PrivateGroup, PublicGroup)`

### 6.2 API 路由组架构（端口 9689）

`initialize.ApiRouters()` 是独立的 Gin Engine，路由组前缀固定为 `/api`（不受 `router-prefix` 配置影响）：
- 公开组包含 `/api/health` 健康检查
- 业务 API 路由通过 `router.RouterGroupApp.Api` 注册

### 6.3 双端口架构优势

- 后台管理和客户端 API 可以独立部署和扩展
- 可以对两个端口配置不同的防火墙规则和限流策略
- 支持单独启动某一个服务（`-type=backend` 或 `-type=api`）

---

## 七、前端构建配置

### 7.1 Vite 配置概览

`web/vite.config.js` 主要配置：

**路径别名：**
```javascript
alias: {
  '@': path.resolve(__dirname, './src'),    // @ 指向 src 目录
  'vue$': 'vue/dist/vue.runtime.esm-bundler.js',
  'vue-i18n': 'vue-i18n/dist/vue-i18n.runtime.esm-bundler.js'
}
```

**开发服务器：**
```javascript
server: {
  host: '0.0.0.0',        // 允许外部访问
  open: true,              // 自动打开浏览器
  port: process.env.VITE_CLI_PORT,  // 从 .env 读取端口
  proxy: {
    [process.env.VITE_BASE_API]: {     // 代理 /api 路径
      target: `${VITE_BASE_PATH}:${VITE_SERVER_PORT}/`,  // 转发到后端
      changeOrigin: true,
      rewrite: (path) => path.replace(/^\/api/, '')       // 去掉 /api 前缀
    }
  }
}
```

**构建配置：**
```javascript
build: {
  target: 'esnext',
  minify: 'esbuild',         // 使用 esbuild 压缩
  sourcemap: false,           // 不生成 sourcemap
  outDir: 'dist',
  // 文件名带哈希，防止缓存
}
esbuild: {
  drop: ['console', 'debugger']  // 生产构建移除 console 和 debugger
}
```

**插件：**
- `@vitejs/plugin-vue` — Vue 3 支持
- `vite-plugin-vue-devtools` — 开发工具（通过 VITE_POSITION=open 启用）
- `svgBuilder` — SVG 图标自动导入
- `vite-plugin-banner` — 构建产物添加版本标记
- `VueFilePathPlugin` — 组件文件路径信息

### 7.2 环境变量文件

**`.env.example`**（模板）：
```
ENV = 'development'
VITE_CLI_PORT = 8091
VITE_SERVER_PORT = 9688
VITE_BASE_API = /api
VITE_FILE_API = /api
VITE_BASE_PATH = http://127.0.0.1
VITE_POSITION = close
VITE_EDITOR = vscode
VITE_DEFAULT_LOCALE = zh-CN
```

**`.env.dev`**（开发环境）：
```
ENV = 'dev'
VITE_CLI_PORT = 8093
VITE_SERVER_PORT = 9788
VITE_BASE_API = /api
VITE_FILE_API = /api
VITE_BASE_PATH = http://127.0.0.1
VITE_POSITION = close
VITE_EDITOR = vscode
VITE_DEFAULT_LOCALE = zh-CN
```

| 变量 | 说明 |
|------|------|
| `ENV` | 环境标识 |
| `VITE_CLI_PORT` | 前端开发服务器端口 |
| `VITE_SERVER_PORT` | 后端服务端口（代理目标） |
| `VITE_BASE_API` | API 前缀路径（代理匹配路径） |
| `VITE_FILE_API` | 文件 API 前缀 |
| `VITE_BASE_PATH` | 后端基础 URL |
| `VITE_POSITION` | DevTools 开关（open/close） |
| `VITE_EDITOR` | 点击组件跳转的编辑器（vscode） |
| `VITE_DEFAULT_LOCALE` | 默认语言 |

Vite 通过 mode 加载对应的 `.env.{mode}` 文件。`vite.config.js` 中使用 `dotenv.parse` 手动加载环境变量。

---

## 八、开发环境启动步骤

### 8.1 后端启动

```bash
cd server

# 1. 复制配置文件
cp config.example.yaml config.yaml
# 或者使用本地配置：
cp config.example.yaml config.local.yaml

# 2.（可选）指定配置文件路径
export HAB_CONFIG=config.local.yaml

# 3. 安装依赖
go mod tidy

# 4. 启动（默认 ModeAll，同时启动管理端口 9688 和 API 端口 9689）
go run main.go

# 仅启动后台管理
go run main.go -type=backend

# 仅启动 API
go run main.go -type=api
```

默认使用 SQLite，无需额外安装数据库，`migration: true` 会自动创建表结构。

### 8.2 前端启动

```bash
cd web

# 1. 安装依赖
npm install

# 2. 复制环境变量文件
cp .env.example .env.development

# 3. 确认 .env.development 中的 VITE_SERVER_PORT 与后端 system.addr 一致

# 4. 启动开发服务器
npm run serve
```

前端开发服务器默认在 `http://localhost:8091` 启动，通过 proxy 将 `/api` 请求转发到 `http://127.0.0.1:9688`。

### 8.3 前后端端口对应关系

```
浏览器 → http://localhost:8091 (Vite Dev Server)
         ├── 静态资源 → Vite 直接处理
         └── /api/* → 代理到 http://127.0.0.1:9688 (Backend)
                       （rewrite 去掉 /api 前缀）

外部客户端 → http://server:9689 (API Server)
```

确保 `.env.development` 中的 `VITE_SERVER_PORT` 与 `config.yaml` 中的 `system.addr` 一致。

---

## 九、环境变量说明

### 9.1 后端环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `HAB_CONFIG` | 配置文件路径 | `config.yaml` |

这是后端唯一使用的环境变量。所有其他配置通过 YAML 文件管理。

### 9.2 前端环境变量

所有前端环境变量以 `VITE_` 开头（Vite 的约定），在 `.env.{mode}` 文件中定义。详见第七节。

### 9.3 命令行参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `-type` | 启动模式：all / backend / api | `all` |

---

## 十、配置最佳实践和常见问题

### 10.1 最佳实践

**配置文件管理：**
- 永远不要将包含真实密码的配置文件提交到 Git
- 使用 `config.local.yaml` + `.gitignore` 管理敏感配置
- 通过 `HAB_CONFIG` 环境变量在不同环境切换配置文件

**数据库选择：**
- 开发环境：使用 SQLite（零配置，开箱即用）
- 生产环境：使用 MySQL 或 PostgreSQL
- 切换数据库只需修改 `db-type`，并填写对应数据库的连接信息

**JWT 密钥：**
- 开发环境可以留空（每次启动自动生成）
- 生产环境必须手动设置固定值，否则重启后所有用户 Token 失效
- 建议使用 `uuidgen` 生成

**Redis：**
- 如果不需要多点登录拦截，可以不启用 Redis
- `use-multipoint: true` 会强制启用 Redis 初始化

### 10.2 常见问题

**Q: 创建了 config.local.yaml 但系统没有加载它？**

系统不会自动检测 `config.local.yaml`。必须通过环境变量显式指定：`export HAB_CONFIG=config.local.yaml`。Viper 只加载一个文件，不会合并多个配置文件。也可以创建一个符号链接：`ln -sf config.local.yaml config.yaml`。

**Q: 启动时报 "Fatal error config file" 怎么办？**

检查配置文件是否存在。默认查找当前目录下的 `config.yaml`，如果使用了 `HAB_CONFIG` 环境变量，确认路径正确。注意 `.gitignore` 中 `config.yaml` 和 `config.local.yaml` 都被排除了，clone 后需要从 `config.example.yaml` 复制创建。

**Q: 前端代理返回 502 或连接超时？**

1. 确认后端已启动且端口正确
2. 检查 `.env.development` 中 `VITE_SERVER_PORT` 是否与后端 `system.addr` 一致
3. 确认后端监听地址不是 `127.0.0.1`（如果前端在容器中）

**Q: 修改了 config.yaml 但没有生效？**

- 部分配置支持热更新（Viper WatchConfig），但数据库连接、Redis 连接等资源在启动时初始化，修改后需要重启
- 检查是否修改了正确的配置文件（可能 `HAB_CONFIG` 指向了其他文件）

**Q: SQLite 数据库文件在哪里？**

默认在 `server/` 目录下生成 `data.db` 文件。可以通过 `sqlite.path` 配置修改存储路径。

**Q: 如何切换到 MySQL？**

```yaml
system:
  db-type: mysql

mysql:
  path: 127.0.0.1
  port: "3306"
  db-name: hab
  username: root
  password: your-password
  config: charset=utf8mb4&parseTime=True&loc=Local
```

确保 MySQL 服务已启动，并提前创建数据库。`migration: true` 会自动创建表结构。

**Q: 两个端口可以合并成一个吗？**

可以只使用 `ModeBackend` 模式（`-type=backend`），此时只启动 addr 端口。但如果业务需要面向客户端的独立 API，建议保持双端口架构。

**Q: pprof 服务的用途？**

`main.go` 会在 `localhost:6060` 启动 pprof 性能分析服务，仅监听 localhost，用于开发调试。可通过 `go tool pprof http://localhost:6060/debug/pprof/profile` 采集性能数据。
