# 整体架构总览

## 1. 项目定位

hz-admin-base (模块名 `hab`) 是一个基于 Go + Vue 3 的全栈后台管理系统框架，提供用户管理、权限控制、代码生成等基础功能，支持双端口架构同时服务后台管理和客户端 API。

---

## 2. 技术栈清单

### 2.1 后端 Go 依赖（关键包）

| 包名 | 版本 | 用途 |
|------|------|------|
| Go | 1.24.1 | 语言版本 |
| gin-gonic/gin | v1.10.0 | HTTP Web 框架 |
| gorm.io/gorm | v1.25.12 | ORM 框架 |
| gorm.io/driver/mysql | v1.5.7 | MySQL 驱动 |
| gorm.io/driver/postgres | v1.5.11 | PostgreSQL 驱动 |
| gorm.io/driver/sqlserver | v1.5.4 | SQL Server 驱动 |
| glebarez/sqlite | v1.11.0 | SQLite 驱动 |
| spf13/viper | v1.19.0 | 配置管理 |
| go.uber.org/zap | v1.27.0 | 结构化日志 |
| golang-jwt/jwt/v5 | v5.3.0 | JWT 鉴权 |
| casbin/casbin/v2 | v2.103.0 | RBAC 权限控制 |
| redis/go-redis/v9 | v9.7.0 | Redis 客户端 |
| qiniu/qmgo | v1.1.9 | MongoDB 客户端 |
| robfig/cron/v3 | v3.0.1 | 定时任务 |
| swaggo/swag | v1.16.4 | Swagger 文档生成 |
| swaggo/gin-swagger | v1.6.0 | Swagger UI 集成 |
| mojocn/base64Captcha | v1.3.8 | 验证码 |
| xuri/excelize/v2 | v2.9.0 | Excel 读写 |
| bytedance/sonic | v1.15.0 | 高性能 JSON 序列化 |
| fvbock/endless | v0.0.0 | 优雅重启 |
| unrolled/secure | v1.17.0 | HTTPS/安全中间件 |
| aliyun/aliyun-oss-go-sdk | v3.0.2 | 阿里云 OSS |
| minio/minio-go/v7 | v7.0.84 | MinIO 对象存储 |
| tencentyun/cos-go-sdk-v5 | v0.7.60 | 腾讯云 COS |
| streadway/amqp | v1.1.0 | RabbitMQ 消息队列 |
| go.uber.org/automaxprocs | v1.6.0 | 自动设置 GOMAXPROCS |
| shirou/gopsutil/v3 | v3.24.5 | 系统监控信息采集 |

### 2.2 前端 npm 依赖（关键包）

| 包名 | 版本 | 用途 |
|------|------|------|
| vue | ^3.5.7 | 核心框架 |
| vue-router | ^4.4.3 | 路由管理 |
| pinia | ^2.2.2 | 状态管理（替代 Vuex） |
| element-plus | ^2.8.5 | UI 组件库（主要） |
| ant-design-vue | ^4.2.6 | UI 组件库（辅助） |
| axios | ^1.7.7 | HTTP 请求 |
| vite | ^5.4.3 | 构建工具 |
| tailwindcss | ^3.4.10 | 原子化 CSS |
| echarts / vue-echarts | 5.5.1 / ^7.0.3 | 图表可视化 |
| @wangeditor/editor | ^5.1.23 | 富文本编辑器 |
| @form-create/element-ui | ^3.2.10 | 动态表单 |
| vue-i18n | ^11.0.0-rc.1 | 国际化 |
| sass | ^1.78.0 | CSS 预处理器 |
| sortablejs / vuedraggable | ^1.15.3 / ^4.1.0 | 拖拽排序 |
| exceljs | ^4.4.0 | 前端 Excel 处理 |
| @vueuse/core | ^11.0.3 | 组合式工具函数 |

---

## 3. 后端目录结构

```
server/
├── main.go                 # 程序入口，启动不同模式的服务
├── core/                   # 核心启动逻辑（Viper/Zap/Server 初始化）
│   └── server.go           # InitServer / RunWindowsServer / RunApiServer
├── global/                 # 全局变量和常量
│   ├── global.go           # HAB_DB / HAB_REDIS / HAB_CONFIG / HAB_LOG 等
│   ├── model.go            # HAB_MODEL 基础模型（ID + 时间戳 + 软删除）
│   ├── mode.go             # 运行模式定义（all / backend / api / task）
│   └── time.go             # 自定义时间类型
├── config/                 # 配置结构体定义（对应 YAML 配置文件）
├── initialize/             # 初始化模块
│   ├── gorm.go             # 数据库连接初始化
│   ├── gorm_mysql.go       # MySQL 专用初始化
│   ├── gorm_pgsql.go       # PostgreSQL 专用初始化
│   ├── redis.go            # Redis 初始化
│   ├── mongo.go            # MongoDB 初始化
│   ├── router.go           # 路由注册总入口（Routers / ApiRouters）
│   ├── router_biz.go       # 业务模块路由注册
│   ├── ensure_tables.go    # 数据库表自动迁移
│   ├── timer.go            # 定时任务初始化
│   └── validator.go        # 参数校验器初始化
├── api/v1/                 # API 控制器层（Handler）
│   ├── enter.go            # ApiGroupApp 全局入口
│   ├── system/             # 系统模块 API（用户/角色/菜单/字典等）
│   ├── business/           # 业务模块 API
│   └── api/                # 客户端 API
├── router/                 # 路由定义层
│   ├── enter.go            # RouterGroupApp 全局入口
│   ├── system/             # 系统模块路由
│   ├── business/           # 业务模块路由
│   └── api/                # 客户端 API 路由
├── service/                # 业务逻辑层
│   ├── enter.go            # ServiceGroupApp 全局入口
│   ├── system/             # 系统模块服务
│   └── business/           # 业务模块服务
├── model/                  # 数据模型层
│   ├── common/             # 通用模型
│   │   ├── request/        # 通用请求结构（PageInfo / GetById / IdsReq）
│   │   └── response/       # 通用响应结构（Response / PageResult）
│   ├── system/             # 系统模块模型
│   │   ├── request/        # 系统模块请求 DTO
│   │   └── response/       # 系统模块响应 DTO
│   ├── business/           # 业务模块模型
│   └── gtype/              # 自定义 GORM 类型
├── middleware/             # Gin 中间件
│   ├── jwt.go              # JWT 鉴权
│   ├── casbin_rbac.go      # Casbin RBAC 权限校验
│   ├── cors.go             # CORS 跨域
│   ├── operation.go        # 操作记录
│   ├── api_key.go          # API Key 认证
│   └── logger.go           # 请求日志
├── code/                   # 错误码定义
│   ├── code.go             # Code 类型和通用错误码
│   ├── common.go           # 通用业务错误码
│   ├── business.go         # 业务错误码
│   └── user.go             # 用户相关错误码
├── enum/                   # 枚举常量
├── utils/                  # 工具函数
├── docs/                   # Swagger 自动生成文档
├── resource/               # 静态资源（模板等）
├── timedtask/              # 定时任务定义
├── translation/            # 翻译/国际化
├── cmd/                    # 命令行子命令
├── config.example.yaml     # 配置文件示例
└── Dockerfile              # Docker 构建文件
```

---

## 4. 前端目录结构

```
web/src/
├── App.vue                 # 根组件
├── main.js                 # 应用入口
├── permission.js           # 路由权限守卫
├── api/                    # 后端 API 接口封装（按模块分文件）
├── assets/                 # 静态资源（图片/图标等）
├── components/             # 全局通用组件
├── core/                   # 核心配置（路由配置/全局设置等）
├── directive/              # 自定义指令
├── hooks/                  # 组合式函数（Composables）
├── i18n/                   # 国际化语言包
├── pinia/                  # Pinia 状态管理 store
├── router/                 # Vue Router 路由定义
├── style/                  # 全局样式
├── styles/                 # 额外样式文件
├── utils/                  # 工具函数
├── view/                   # 页面视图组件（按业务模块组织）
└── pathInfo.json           # 路径元信息配置
```

---

## 5. 系统启动流程

系统启动遵循以下严格顺序：

```
main.go
  │
  ├── core.InitServer()                    # 总初始化入口
  │     │
  │     ├── core.InitConf()                # 配置初始化
  │     │     ├── core.Viper()             # 读取 YAML 配置 → global.HAB_VP / HAB_CONFIG
  │     │     ├── initialize.OtherInit()   # 其他初始化（如 BlackCache）
  │     │     ├── core.Zap()               # 初始化 zap 日志 → global.HAB_LOG
  │     │     └── global.InitSysMode()     # 解析 -type 参数确定运行模式
  │     │
  │     ├── initialize.Gorm()              # 根据配置选择数据库驱动，建立连接 → global.HAB_DB
  │     ├── initialize.DBList()            # 初始化多数据源
  │     ├── initialize.RegisterTables()    # 自动迁移数据库表（当 Migration=true）
  │     ├── initialize.Redis()             # 初始化 Redis（当 UseRedis=true）
  │     └── initialize.Mongo()             # 初始化 MongoDB（当 UseMongo=true）
  │
  ├── pprof server (:6060)                 # 启动性能分析服务器（后台 goroutine）
  │
  ├── time.LoadLocation()                  # 设置系统时区
  │
  └── 根据 SysMode 启动服务：
        │
        ├── ModeAll (默认):
        │     ├── go RunApi()              # 后台 goroutine 启动客户端 API 服务
        │     └── RunBackend()             # 主 goroutine 启动后台管理服务（阻塞）
        │           ├── initialize.Timer() # 初始化定时任务
        │           └── core.RunWindowsServer()
        │                 ├── system.LoadAll()        # 从 DB 加载 JWT 等数据
        │                 ├── initialize.Routers()    # 注册所有后台路由
        │                 └── ListenAndServe(:9688)   # 启动 HTTP 监听
        │
        ├── ModeBackend:
        │     └── RunBackend()             # 仅启动后台管理服务
        │
        └── ModeApi:
              └── RunApi()                 # 仅启动客户端 API 服务
                    ├── system.LoadAll()
                    ├── initialize.ApiRouters()
                    └── ListenAndServe(:9689)
```

---

## 6. 双端口架构说明

系统采用双端口设计，通过 `-type` 命令行参数控制运行模式：

| 模式 | 端口 | 路由前缀 | 用途 | 鉴权方式 |
|------|------|----------|------|----------|
| backend | 9688 (System.Addr) | 可配置 RouterPrefix | 后台管理 API | JWT + Casbin RBAC |
| api | 9689 (System.ApiAddr) | `/api` | 客户端/对外 API | 按需配置 |
| all (默认) | 两个端口同时 | 各自独立 | 同时启动两个服务 | 各自独立 |

### 后台管理服务 (端口 9688)

路由分为三组：

- **PublicGroup**: 无需鉴权的公开路由（登录、验证码、字典查询等）
- **PrivateGroup**: 需要 JWT + Casbin 双重验证的管理路由
- **AutoCodeGroup**: 支持 API Key 或 JWT 双重认证的代码生成路由

路由注册流程见 `initialize/router.go` 中的 `Routers()` 函数。

### 客户端 API 服务 (端口 9689)

独立的 Gin Engine，路由统一挂在 `/api` 前缀下，通过 `initialize/router.go` 中的 `ApiRouters()` 函数注册。适用于小程序、APP 等客户端场景。

### 启动命令

```bash
# 同时启动两个服务（默认）
./server

# 仅启动后台管理服务
./server -type=backend

# 仅启动客户端 API 服务
./server -type=api
```

---

## 7. 前后端交互模式

### 7.1 API 调用方式

前端通过 `axios` 发起 HTTP 请求，接口封装在 `web/src/api/` 目录下，按模块分文件（如 `auth.js`、`authority.js`、`casbin.js` 等）。

### 7.2 统一响应格式

所有后端接口返回统一的 JSON 结构：

```json
{
  "code": 0,
  "data": {},
  "msg": "ok"
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| code | int | 状态码。`0` 表示成功，`7` 表示通用错误，`1000+` 为业务错误码 |
| data | any | 返回的数据体 |
| msg | string | 提示消息 |

### 7.3 分页响应格式

分页列表接口的 `data` 字段使用 `PageResult` 结构：

```json
{
  "code": 0,
  "data": {
    "list": [],
    "total": 100,
    "page": 1,
    "pageSize": 10,
    "sumInfo": null
  },
  "msg": "success"
}
```

### 7.4 鉴权流程

1. 前端登录获取 JWT Token
2. 后续请求在 Header 中携带 `x-token` 或 `Authorization`
3. 后端 `middleware/jwt.go` 校验 Token 有效性
4. 后端 `middleware/casbin_rbac.go` 校验当前角色是否有权访问该接口路径

### 7.5 错误码体系

```go
CodeSuccess       Code = 0     // 成功
CodeError         Code = 7     // 通用错误
CodeUserError     Code = 1000  // 用户错误
CodeCommonError   Code = 1001  // 通用错误
CodeBusinessError Code = 1002  // 业务错误
CodeAccountError  Code = 1003  // 账户错误
```

前端根据 `code` 值做不同处理，如 `code=7` 时 HTTP 状态仍为 200 但前端会弹出错误提示，`401` 状态码则触发重新登录。

---

## 8. 关键全局变量

在 `global/global.go` 中定义，整个应用通过这些变量共享状态：

| 变量名 | 类型 | 说明 |
|--------|------|------|
| `HAB_DB` | `*gorm.DB` | 主数据库连接 |
| `HAB_DBList` | `map[string]*gorm.DB` | 多数据源连接池 |
| `NoLogDB` | `*gorm.DB` | 不记录日志的数据库会话 |
| `HAB_REDIS` | `redis.UniversalClient` | Redis 客户端 |
| `HAB_MONGO` | `*qmgo.QmgoClient` | MongoDB 客户端 |
| `HAB_CONFIG` | `config.Server` | 全局配置（对应 YAML） |
| `HAB_VP` | `*viper.Viper` | Viper 配置实例 |
| `HAB_LOG` | `*zap.Logger` | 全局日志实例 |
| `HAB_Timer` | `timer.Timer` | 定时任务管理器 |
| `HAB_ROUTERS` | `gin.RoutesInfo` | 已注册路由信息 |
| `BlackCache` | `local_cache.Cache` | JWT 黑名单缓存 |

---

## 9. 基础模型

所有业务实体继承 `global.HAB_MODEL`，提供统一的主键和时间戳字段：

```go
type HAB_MODEL struct {
    ID        uint           `gorm:"primarykey" json:"ID"`
    CreatedAt MySQLTime      // 创建时间
    UpdatedAt MySQLTime      // 更新时间
    DeletedAt gorm.DeletedAt `gorm:"index" json:"-"` // 软删除
}
```

另有 `HAB_MODEL_NOD`（无软删除）和 `HAB_MODEL_NOID`（无主键 ID）两个变体供特殊场景使用。
