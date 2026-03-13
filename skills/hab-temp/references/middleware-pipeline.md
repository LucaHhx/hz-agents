# 中间件管道详解

本文档详细说明 hz-admin-base 后端中间件的设计、执行流程与配置方式。

## 1. 中间件列表和功能概述

| 中间件 | 文件 | 功能 |
|--------|------|------|
| CORS | `middleware/cors.go` | 跨域请求处理，支持全放行和白名单两种模式 |
| JWT | `middleware/jwt.go` | Token 鉴权，含自动续签机制 |
| Casbin RBAC | `middleware/casbin_rbac.go` | 基于 Casbin 的角色权限校验 |
| 操作记录 | `middleware/operation.go` | 记录请求/响应详情到数据库 |
| IP 限流 | `middleware/limit_ip.go` | 基于 Redis 的按 IP 请求频率限制 |
| API Key | `middleware/api_key.go` | API Key 与 JWT 双重认证（AutoCode 专用） |
| 错误恢复 | `middleware/error.go` | Panic recovery，防止服务崩溃 |
| 日志记录 | `middleware/logger.go` | 可定制的请求日志中间件 |
| TLS | `middleware/loadtls.go` | HTTPS 重定向 |

## 2. 请求处理管道流程图

```
客户端请求
    |
    v
+------------------+
| gin.Recovery()   |  <- Gin 内置 panic recovery
+------------------+
    |
    v
+------------------+
| gin.Logger()     |  <- 仅 DebugMode 启用，跳过特定路径
+------------------+
    |
    v
+------------------+
| CORS 中间件      |  <- 全局注册，处理 OPTIONS 预检
+------------------+
    |
    v
+--- 路由匹配 ----+
|                  |
|  PublicGroup     |  无鉴权，直接进入 Handler
|                  |
|  PrivateGroup    |  -> JWTAuth() -> CasbinHandler() -> Handler
|                  |
|  AutoCodeGroup   |  -> ApiKeyOrJWT() -> CasbinHandler() -> Handler
|                  |
+------------------+
    |
    v
  Handler 处理
    |
    v
  响应返回客户端
```

## 3. 每个中间件详细说明

### 3.1 CORS 中间件

**文件**: `middleware/cors.go`

提供两个函数：`Cors()` 和 `CorsByRules()`。

#### Cors() — 全放行模式

直接对所有请求设置跨域响应头：

```go
c.Header("Access-Control-Allow-Origin", origin)  // 动态反射 Origin
c.Header("Access-Control-Allow-Headers", "Content-Type,AccessToken,X-CSRF-Token,Authorization,Token,X-Token,X-User-Id")
c.Header("Access-Control-Allow-Methods", "POST, GET, OPTIONS,DELETE,PUT")
c.Header("Access-Control-Expose-Headers", "Content-Length, Access-Control-Allow-Origin, Access-Control-Allow-Headers, Content-Type, New-Token, New-Expires-At")
c.Header("Access-Control-Allow-Credentials", "true")
```

对 OPTIONS 预检请求直接返回 `204 No Content` 并终止处理链。

#### CorsByRules() — 规则模式

根据 `config.yaml` 中 `cors.mode` 配置决定行为：

- **`allow-all`**: 等同于 `Cors()`，全部放行
- **`strict-whitelist`**: 严格白名单模式，未匹配的 Origin 返回 `403 Forbidden`（健康检查 GET `/health` 除外）
- **默认（白名单非严格）**: 匹配的 Origin 添加跨域头，未匹配的仍放行但不添加跨域头

白名单匹配逻辑通过 `checkCors()` 遍历 `cors.whitelist` 配置数组，逐一比对 `AllowOrigin` 字段。

### 3.2 JWT 中间件

**文件**: `middleware/jwt.go`

#### Token 提取方式

通过 `utils.GetToken(c)` 提取 token。支持从请求头 `x-token`、Cookie 等位置获取（具体取决于 utils 实现）。

#### 验证流程

1. **空 token 检查**: token 为空时返回 `"未登录或非法访问"` 并 Abort
2. **黑名单检查**: 调用 `jwtService.IsBlacklist(token)` 检查 token 是否已失效（异地登录或主动注销），命中则清除 token 并返回错误
3. **解析 token**: 通过 `utils.NewJWT().ParseToken(token)` 解析 Claims
4. **过期处理**: 区分 `TokenExpired` 错误，返回 `"授权已过期"` 并清除 token
5. **注入 Claims**: 将解析出的 claims 写入 `c.Set("claims", claims)`

#### Token 自动续签机制

```go
if claims.ExpiresAt.Unix()-time.Now().Unix() < claims.BufferTime {
    // 距离过期时间小于 BufferTime 时触发续签
    dr, _ := utils.ParseDuration(global.HAB_CONFIG.JWT.ExpiresTime)
    claims.ExpiresAt = jwt.NewNumericDate(time.Now().Add(dr))
    newToken, _ := j.CreateTokenByOldToken(token, *claims)
    c.Header("new-token", newToken)
    c.Header("new-expires-at", strconv.FormatInt(newClaims.ExpiresAt.Unix(), 10))
    utils.SetToken(c, newToken, int(dr.Seconds()))
}
```

核心逻辑：当 token 剩余有效时间小于 `BufferTime` 时，自动签发新 token 并通过响应头 `new-token` 和 `new-expires-at` 返回给前端。如果开启了多点登录限制（`UseMultipoint`），还会通过 Redis 记录新的活跃 JWT。

在 `c.Next()` 之后，还会检查 context 中是否有其他中间件/handler 设置的 `new-token`，并将其写入响应头。

#### 预留功能（默认关闭）

代码中注释了"已登录用户被管理员禁用"的检查逻辑，可按需开启。该功能会通过 UUID 查询用户状态，发现禁用则将 token 加入黑名单。

### 3.3 Casbin RBAC 中间件

**文件**: `middleware/casbin_rbac.go`

#### 策略检查流程

1. 从 context 获取 Claims（优先从 `c.Get("claims")` 取，否则通过 `utils.GetClaims` 解析）
2. **超级管理员直接放行**: `AuthorityId == 1` 时跳过权限检查，直接 `c.Next()`
3. 构建 Casbin 三元组：
   - **sub** (主体): `AuthorityId` 转字符串
   - **obj** (资源): 请求 Path 去除 `RouterPrefix` 前缀
   - **act** (动作): HTTP Method（GET/POST/PUT/DELETE 等）
4. 调用 `casbinService.Casbin()` 获取 Enforcer 实例
5. 执行 `e.Enforce(sub, obj, act)` 判断是否有权限
6. 无权限时返回 `"insufficient_permissions"` 并 Abort

#### 关键特点

- 超级管理员（AuthorityId=1）享有全部权限，不经过 Casbin 策略匹配
- 路径会自动去除 `RouterPrefix`，确保策略定义与实际路由前缀无关
- 权限不足统一返回 `insufficient_permissions`，不区分"无策略"和"策略拒绝"

### 3.4 操作记录中间件

**文件**: `middleware/operation.go`

#### 记录的信息

```go
record := system.SysOperationRecord{
    Ip:     c.ClientIP(),           // 客户端 IP
    Method: c.Request.Method,       // HTTP 方法
    Path:   c.Request.URL.Path,     // 请求路径
    Agent:  c.Request.UserAgent(),  // User-Agent
    Body:   "",                     // 请求体（见下方规则）
    UserID: userId,                 // 用户 ID
}
```

在 `c.Next()` 之后还会记录：
- `ErrorMessage`: 错误信息
- `Status`: HTTP 状态码
- `Latency`: 请求耗时
- `Resp`: 响应体内容

#### Body 记录机制

| 场景 | Body 记录内容 |
|------|--------------|
| GET 请求 | Query 参数序列化为 JSON |
| 非 GET 请求 | 读取 `Request.Body` 后塞回（`io.NopCloser`） |
| `multipart/form-data` | 固定记为 `"[文件]"` |
| Body 超过 1024 字节 | 固定记为 `"[超出记录长度]"` |

#### 响应体捕获

通过自定义 `responseBodyWriter` 包装 `gin.ResponseWriter`，在 `Write` 方法中同时写入 buffer 和原始 Writer，从而捕获完整响应体。

对于文件下载类型的响应（通过 Content-Type/Content-Disposition 判断），如果响应体超过 1024 字节也会截断。

#### 性能优化

使用 `sync.Pool` 复用 byte 切片，减少 GC 压力。

### 3.5 IP 限流中间件

**文件**: `middleware/limit_ip.go`

#### 算法

采用 Redis 计数器 + 过期时间的固定窗口限流算法：

1. 检查 Redis 中是否存在该 key（`HAB_Limit` + ClientIP）
2. **不存在**: 使用 Redis Pipeline 原子执行 `INCR` + `EXPIRE`，创建计数器并设置过期时间
3. **已存在**: 获取当前计数值，如果 >= limit 则拒绝请求，否则 `INCR` 递增

#### 配置

```go
func DefaultLimit() gin.HandlerFunc {
    return LimitConfig{
        GenerationKey: DefaultGenerationKey,    // key = "HAB_Limit" + ClientIP
        CheckOrMark:   DefaultCheckOrMark,      // Redis 计数逻辑
        Expire:        global.HAB_CONFIG.System.LimitTimeIP,   // 窗口时间（秒）
        Limit:         global.HAB_CONFIG.System.LimitCountIP,  // 窗口内最大请求数
    }.LimitWithTime()
}
```

#### Redis/内存模式

- **Redis 可用时**: 使用 Redis 存储计数器，支持多实例分布式限流
- **Redis 不可用时**: `DefaultCheckOrMark` 直接 return nil（不进行限流），即降级为无限流状态
- 支持自定义 `GenerationKey` 和 `CheckOrMark` 函数，可实现更复杂的限流策略（如按用户、按接口等）

#### 限流提示

超限后返回中文提示，包含剩余等待时间：`"请求太过频繁, 请 Xs 秒后尝试"`。

### 3.6 API Key 中间件

**文件**: `middleware/api_key.go`

#### 使用场景

专为 AutoCode 路由组设计，允许外部工具（如 CLI、CI/CD）通过 API Key 访问代码生成相关接口，无需用户登录。

#### 验证逻辑

```
ApiKeyOrJWT()
    |
    +-- x-api-key 请求头存在 && config 中配置了 ApiKey?
    |       |
    |       +-- 匹配成功 -> 注入超级管理员 Claims -> c.Next()
    |       +-- 匹配失败 -> 返回 "invalid api key" -> Abort
    |
    +-- 否则 -> 降级到标准 JWTAuth() 流程
```

命中 API Key 后注入的 Claims：
- `UUID`: `00000000-0000-0000-0000-000000000001`
- `ID`: 1, `Username`: "api-key", `AuthorityId`: 1（超级管理员）
- `ExpiresAt`: 当前时间 + 24 小时

### 3.7 错误恢复中间件

**文件**: `middleware/error.go`

`GinRecovery(stack bool)` 使用 `defer + recover` 捕获 panic：

1. **Broken pipe 检查**: 检测是否为连接断开导致的 panic（`broken pipe` 或 `connection reset by peer`），此类错误仅记录日志，不写入响应
2. **常规 panic**: 根据 `stack` 参数决定是否记录完整调用栈（`debug.Stack()`），然后返回 `500 Internal Server Error`
3. 日志通过 `zap` 记录，包含请求信息（`httputil.DumpRequest`）

注意：在 `initialize/router.go` 中，使用的是 `gin.Recovery()` 而非此自定义中间件。如需更详细的 panic 日志，可替换为 `GinRecovery(true)`。

### 3.8 日志记录中间件

**文件**: `middleware/logger.go`

提供高度可定制的日志中间件，核心是 `Logger` 结构体：

```go
type Logger struct {
    Filter        func(c *gin.Context) bool       // 自定义过滤（返回 true 跳过 body 读取）
    FilterKeyword func(layout *LogLayout) bool     // 关键字过滤/脱敏
    AuthProcess   func(c *gin.Context, layout *LogLayout)  // 鉴权信息提取
    Print         func(LogLayout)                  // 日志输出（用户自定义）
    Source        string                           // 服务标识
}
```

`LogLayout` 记录的字段：
- `Time`, `Path`, `Query`, `Body`, `IP`, `UserAgent`, `Error`, `Cost`, `Source`
- `Metadata`: 可存储自定义元数据

`DefaultLogger()` 将日志序列化为 JSON 输出到 stdout，适配 k8s 日志收集。

### 3.9 TLS 中间件

**文件**: `middleware/loadtls.go`

使用 `github.com/unrolled/secure` 库实现 HTTPS 重定向：

```go
middleware := secure.New(secure.Options{
    SSLRedirect: true,
    SSLHost:     "localhost:443",
})
```

将所有 HTTP 请求重定向到 HTTPS。默认 SSLHost 硬编码为 `localhost:443`，生产环境需修改。

## 4. 路由分组中间件应用方式

在 `initialize/router.go` 的 `Routers()` 函数中定义了三个路由分组：

### 全局中间件（所有请求）

```go
Router := gin.New()
Router.Use(gin.Recovery())        // Panic recovery
Router.Use(middleware.Cors())     // CORS 处理（在路由匹配前执行）
```

DebugMode 下还启用了 `gin.LoggerWithConfig()`，并跳过特定高频接口的日志。

### PublicGroup — 公开路由

```go
PublicGroup := Router.Group(global.HAB_CONFIG.System.RouterPrefix)
```

无任何鉴权中间件，用于：
- `/health` 健康检查
- `InitBaseRouter` 基础功能路由（登录、注册等）
- `InitInitRouter` 系统初始化路由
- 部分路由的公开端点（如字典查询、参数查询）

### PrivateGroup — 私有路由

```go
PrivateGroup := Router.Group(global.HAB_CONFIG.System.RouterPrefix)
PrivateGroup.Use(middleware.JWTAuth()).Use(middleware.CasbinHandler())
```

中间件链：`JWT 鉴权` -> `Casbin 权限校验`，用于：
- API 管理、用户管理、菜单管理、角色管理
- 字典管理、操作记录、导出模板等后台功能

### AutoCodeGroup — 自动化代码路由

```go
AutoCodeGroup := Router.Group(global.HAB_CONFIG.System.RouterPrefix)
AutoCodeGroup.Use(middleware.ApiKeyOrJWT()).Use(middleware.CasbinHandler())
```

中间件链：`API Key 或 JWT 鉴权` -> `Casbin 权限校验`，用于：
- `InitAutoCodeRouter` 代码生成接口
- `InitAutoCodeHistoryRouter` 代码生成历史

## 5. 自定义中间件指南

### 创建新中间件

在 `server/middleware/` 目录下创建新文件，遵循标准 Gin 中间件签名：

```go
package middleware

import "github.com/gin-gonic/gin"

func MyMiddleware() gin.HandlerFunc {
    return func(c *gin.Context) {
        // 前置处理（请求进入前）

        c.Next()  // 调用后续 handler

        // 后置处理（响应返回前）
    }
}
```

### 注册中间件

在 `initialize/router.go` 中按需注册：

```go
// 全局注册
Router.Use(middleware.MyMiddleware())

// 分组注册
PrivateGroup.Use(middleware.MyMiddleware())

// 单路由注册
router.GET("/path", middleware.MyMiddleware(), handler)
```

### 获取当前用户信息

```go
// 从 context 获取 JWT Claims
claims, _ := utils.GetClaims(c)
userId := claims.BaseClaims.ID
authorityId := claims.AuthorityId
```

### 中断请求链

```go
c.Abort()       // 中断后续 handler
c.AbortWithStatus(http.StatusForbidden)  // 中断并设置状态码
```

## 6. 注意事项

1. **中间件执行顺序**: Gin 中间件按注册顺序执行。全局中间件先于分组中间件，分组中间件按 `Use` 调用顺序依次执行
2. **CORS 必须在最前面**: CORS 中间件在路由匹配之前执行，确保 OPTIONS 预检请求不会被后续鉴权中间件拦截
3. **JWT 在 Casbin 之前**: Casbin 依赖 JWT 中间件注入的 Claims 来获取用户角色信息，顺序不可颠倒
4. **操作记录中间件未全局启用**: 当前代码中 `OperationRecord()` 未在路由初始化中注册，需手动添加到需要记录的路由分组
5. **IP 限流依赖 Redis**: 无 Redis 时限流自动降级为不限流，生产环境务必配置 Redis
6. **Token 续签的前端配合**: 前端需监听响应头中的 `new-token` 和 `new-expires-at`，及时更新本地存储的 token
7. **TLS 中间件的 SSLHost**: 默认硬编码为 `localhost:443`，部署时需根据实际域名修改
8. **API Key 安全**: API Key 拥有超级管理员权限，务必妥善保管，仅用于可信环境（CLI、CI/CD）
9. **Body 读取限制**: 操作记录中间件对超过 1024 字节的 Body 会截断，文件上传请求固定记录为 `[文件]`
10. **多点登录控制**: 当 `System.UseMultipoint` 启用时，JWT 续签会通过 Redis 记录活跃 token，实现同一用户同时只能在一处登录
