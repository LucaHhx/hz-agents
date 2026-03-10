# 项目技术栈规范

所有技术选型必须基于以下标准栈，除非有充分理由并记录在 design.md 中。

## Backend — Go

| 类别 | 技术 | 说明 |
|------|------|------|
| 语言 | Go 1.25+ | |
| Web 框架 | Gin | 高性能 HTTP 框架 |
| ORM | GORM | 数据库操作与自动迁移 |
| 数据库 | MySQL（默认） | 支持 SQLite / MySQL / PostgreSQL / MSSQL / Oracle |
| 认证 | golang-jwt/jwt v5 | JWT Token 鉴权 |
| 权限 | Casbin | RBAC 权限管理（use-strict-auth 控制） |
| 配置 | Viper | 多格式配置管理 (YAML) |
| 日志 | Zap | 结构化日志 |
| 校验 | go-playground/validator v10 | 请求参数校验 |

**后端项目结构:**
```
server/
├── main.go              # 入口
├── api/v1/              # API handler（按包分组：system/, business/）
├── model/               # GORM 数据模型
├── service/             # 业务逻辑
├── router/              # 路由定义
├── middleware/           # 中间件（JWT, API Key, Casbin 等）
├── config/              # 配置结构体
├── core/                # 核心启动
├── global/              # 全局变量（DB, Config, Log）
├── initialize/          # 初始化（DB, Router, Logger）
├── code/                # 错误码
└── config.yaml          # 配置文件
```

> **AutoCode**: 标准 CRUD 模块可通过 `hab-autocode` skill 自动生成前后端代码。

## Frontend (Web/Admin) — Vue 3

适用于从 hz-admin-base 模板创建的管理后台（`web/` 目录）。

| 类别 | 技术 | 说明 |
|------|------|------|
| 框架 | Vue 3 | 渐进式 UI 框架 |
| 组件库 | Element Plus | 企业级 UI 组件 |
| 状态管理 | Pinia | Vue 官方状态管理 |
| 路由 | Vue Router 4 | 客户端路由 |
| 构建 | Vite | 开发服务器与构建 |
| HTTP | Axios | API 请求 |

**管理后台项目结构:**
```
web/
├── src/
│   ├── api/             # API 请求封装
│   ├── view/            # 页面组件
│   ├── components/      # 通用组件
│   ├── pinia/           # Pinia 状态
│   ├── router/          # Vue Router 路由
│   └── utils/           # 工具函数
├── package.json
├── vite.config.js
└── .env
```

> **注意**: web/ 和 client/ 技术栈根据项目类型选择。纯后台项目只有 web/；有客户端的项目同时有 web/ 和 client/。

## Frontend (Client) — React + TypeScript + Tauri

| 类别 | 技术 | 说明 |
|------|------|------|
| 框架 | React 19 | UI 框架 |
| 语言 | TypeScript 5.9+ | 类型安全 |
| 构建 | Vite 7+ | 开发服务器与构建 |
| 样式 | Tailwind CSS 4+ | 原子化 CSS |
| 组件库 | shadcn/ui | 可定制的 React 组件库 |
| 状态管理 | Zustand | 轻量状态管理 |
| HTTP | Axios | API 请求 |
| 路由 | React Router DOM 7+ | 客户端路由 |
| 桌面 | Tauri 2.x (Rust) | 跨平台桌面应用 |
| 移动端 | Capacitor 8+ | iOS / Android 支持 |
| 代码规范 | ESLint + typescript-eslint | Lint 检查 |

**前端项目结构:**
```
frontend/
├── src/
│   ├── api/             # Axios 请求封装
│   ├── pages/           # 页面组件
│   ├── components/      # 通用组件
│   ├── stores/          # Zustand 状态
│   ├── types/           # TypeScript 类型定义
│   ├── hooks/           # 自定义 Hooks
│   └── utils/           # 工具函数
├── src-tauri/           # Tauri Rust 代码
│   └── Cargo.toml
├── package.json
├── vite.config.ts
├── tsconfig.json
└── tailwind.config.ts
```

## 后端双端口架构

| 端口 | 配置项 | 用途 | 消费者 |
|------|--------|------|--------|
| `system.addr` (默认 9688) | 后台管理接口 | 后台 CRUD、权限、菜单等 | `web/`（管理后台） |
| `system.api-addr` (默认 9689) | 客户端/外部 API 接口 | 面向客户端和第三方的业务 API | `client/`（客户端）、外部系统 |

> 两个端口均从 `config.yaml` 读取，非硬编码。

## 端口配置联动

修改后端端口后，须同步更新前端配置：

| 后端配置项 | 前端配置文件 | 对应变量 |
|-----------|-------------|---------|
| `system.addr` | `web/.env` | `VITE_SERVER_PORT`（代理目标端口） |
| `system.api-addr` | `client/.env` | `VITE_API_URL` 或代理目标 |

## 配置示例 A — 完整配置（带注释）

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
  login-mode: simple       # 登录模式: simple(无验证码) | captcha(需验证码) | strict(分步强验证)

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

## 配置示例 B — 极简配置（最小可运行）

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

## 通用约定

| 约定 | 说明 |
|------|------|
| 前端端口 | Vite 默认 5173（web/ 和 client/ 需分别配置避免冲突） |
| 认证方案 | JWT Bearer Token |
| 响应格式 | `{ code, data, msg }` 统一封装 |
| 数据库迁移 | GORM AutoMigrate |
