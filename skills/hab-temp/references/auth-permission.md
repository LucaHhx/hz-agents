# 认证与权限系统

本文档详细描述 hz-admin-base 的认证（Authentication）和权限（Authorization）体系，涵盖后端 JWT/Casbin 机制和前端权限指令。

---

## 1. 认证流程总览

整体认证流程如下：

```
用户登录 → 后端验证凭证 → 生成 JWT Token → 写入 Cookie(x-token)
    → 前端后续请求自动携带 x-token
    → JWT 中间件提取 Token → 黑名单检查 → 解析 Claims → 注入 Context
    → Casbin 中间件读取 Claims → 检查角色对 API 的访问权限
    → 放行或拦截
```

关键文件：

| 模块 | 文件路径 |
|------|---------|
| JWT 中间件 | `server/middleware/jwt.go` |
| Casbin 中间件 | `server/middleware/casbin_rbac.go` |
| API Key 中间件 | `server/middleware/api_key.go` |
| JWT 工具 | `server/utils/jwt.go` |
| Claims 工具 | `server/utils/claims.go` |
| JWT 配置 | `server/config/jwt.go` |
| Casbin 服务 | `server/service/system/sys_casbin.go` |
| JWT 黑名单服务 | `server/service/system/jwt_black_list.go` |
| 登录接口 | `server/api/v1/system/sys_user.go` |
| 路由初始化 | `server/initialize/router.go` |

---

## 2. JWT 配置和实现详解

### 2.1 配置结构

JWT 配置定义在 `config/jwt.go`，通过 YAML 配置文件加载：

```go
type JWT struct {
    SigningKey   string  // jwt 签名密钥
    ExpiresTime  string  // 过期时间，如 "7d"、"24h"
    BufferTime   string  // 缓冲时间，如 "1d"
    Issuer       string  // 签发者标识
}
```

- **SigningKey**: HMAC-SHA256 签名密钥，所有 Token 的生成和验证都依赖此密钥。
- **ExpiresTime**: Token 有效期，支持 `ParseDuration` 解析（如 `"7d"` 表示 7 天）。
- **BufferTime**: 临近过期时的缓冲区间。Token 剩余有效期小于 BufferTime 时，中间件自动签发新 Token 并通过响应头 `new-token` / `new-expires-at` 返回给前端。
- **Issuer**: JWT 的 `iss` 字段值。

### 2.2 Claims 结构

Claims 定义在 `model/system/request/jwt.go`：

```go
type CustomClaims struct {
    BaseClaims
    BufferTime int64
    jwt.RegisteredClaims
}

type BaseClaims struct {
    UUID        uuid.UUID
    ID          uint
    Username    string
    NickName    string
    AuthorityId uint          // 当前生效的角色 ID
    Type        enum.SysUserType  // 用户类型（0=管理员, 1=普通用户, 2=商户）
    Parameter   string            // 用户自定义参数
}
```

`RegisteredClaims` 包含标准 JWT 字段：`Audience`（固定 "HAB"）、`NotBefore`、`ExpiresAt`、`Issuer`。

### 2.3 Token 创建

在 `utils/jwt.go` 中：

```go
func (j *JWT) CreateClaims(baseClaims BaseClaims) CustomClaims
func (j *JWT) CreateToken(claims CustomClaims) (string, error)
func (j *JWT) CreateTokenByOldToken(oldToken string, claims CustomClaims) (string, error)
```

- 使用 `jwt.SigningMethodHS256` 算法签名。
- `CreateTokenByOldToken` 使用 `singleflight`（`HAB_Concurrency_Control.Do`）避免并发刷新时生成多个新 Token。

### 2.4 Token 传输

Token 通过两种方式传输（`utils/claims.go` 中的 `GetToken`）：

1. **Cookie**: `x-token`（优先读取）
2. **Header**: `x-token`（Cookie 不存在时读取，并自动回写到 Cookie）

---

## 3. JWT 中间件工作机制

`middleware/jwt.go` 中的 `JWTAuth()` 中间件按以下步骤工作：

### 步骤 1: 提取 Token

```go
token := utils.GetToken(c)
```

先从 Cookie 读取 `x-token`，读取不到则从请求头 `x-token` 读取。如果 Token 为空，返回 `401 未登录或非法访问`。

### 步骤 2: 黑名单检查

```go
if jwtService.IsBlacklist(token) { ... }
```

使用内存缓存 `global.BlackCache` 检查 Token 是否已被拉黑。黑名单数据在启动时通过 `LoadAll()` 从数据库 `jwt_blacklists` 表加载到内存。被拉黑的 Token 返回 `"您的帐户异地登陆或令牌失效"`。

### 步骤 3: 解析 Token

```go
claims, err := j.ParseToken(token)
```

解析失败时根据错误类型返回不同提示：
- `TokenExpired` → "授权已过期"
- `TokenMalformed` → "这不是一个token"
- `TokenSignatureInvalid` → "无效签名"

### 步骤 4: 注入 Claims

```go
c.Set("claims", claims)
```

将解析后的 Claims 存入 Gin Context，后续中间件和业务处理器通过 `utils.GetUserID(c)`、`utils.GetUserAuthorityId(c)` 等辅助函数读取。

### 步骤 5: 自动续签（Buffer 机制）

```go
if claims.ExpiresAt.Unix()-time.Now().Unix() < claims.BufferTime {
    // 生成新 Token，通过 Header 返回
    c.Header("new-token", newToken)
    c.Header("new-expires-at", ...)
    utils.SetToken(c, newToken, ...)  // 同时更新 Cookie
}
```

当 Token 剩余有效期小于 `BufferTime` 时，自动签发新 Token。前端收到 `new-token` 响应头后应替换旧 Token。

---

## 4. Casbin RBAC 权限模型

### 4.1 模型定义

Casbin 模型在 `service/system/sys_casbin.go` 中以字符串形式定义：

```
[request_definition]
r = sub, obj, act

[policy_definition]
p = sub, obj, act

[role_definition]
g = _, _

[policy_effect]
e = some(where (p.eft == allow))

[matchers]
m = r.sub == p.sub && keyMatch2(r.obj, p.obj) && r.act == p.act
```

- **sub**: 角色 ID（字符串形式，如 `"888"`）
- **obj**: API 路径（如 `/user/getUserList`）
- **act**: HTTP 方法（如 `GET`、`POST`）
- **keyMatch2**: 支持路径参数匹配（如 `/user/:id` 匹配 `/user/123`）

### 4.2 策略存储

策略使用 `gorm-adapter` 持久化到数据库表 `casbin_rule`：

| Ptype | V0 (角色ID) | V1 (路径) | V2 (方法) |
|-------|------------|----------|----------|
| p | 888 | /user/getUserList | POST |
| p | 888 | /user/changePassword | POST |

### 4.3 权限检查流程（CasbinHandler 中间件）

```go
func CasbinHandler() gin.HandlerFunc {
    return func(c *gin.Context) {
        // 1. 从 Context 获取 Claims
        waitUse := claims.(*systemReq.CustomClaims)

        // 2. 超级管理员（AuthorityId == 1）直接放行
        if waitUse.AuthorityId == 1 { c.Next(); return }

        // 3. 获取请求信息
        obj := strings.TrimPrefix(path, routerPrefix)  // 去掉路由前缀
        act := c.Request.Method
        sub := strconv.Itoa(int(waitUse.AuthorityId))

        // 4. Casbin 策略检查
        success, _ := e.Enforce(sub, obj, act)
        if !success { c.Abort(); return }
    }
}
```

重要特性：
- **超级管理员免检**: `AuthorityId == 1` 的用户跳过所有 Casbin 检查。
- **路由前缀剥离**: 检查前自动去除 `RouterPrefix`，确保策略中的路径不含前缀。
- **缓存加速**: 使用 `SyncedCachedEnforcer`，缓存过期时间 3600 秒。

### 4.4 策略管理

`CasbinService` 提供以下方法：

| 方法 | 功能 |
|------|------|
| `UpdateCasbin(adminID, authorityID, infos)` | 全量更新某角色的 API 权限 |
| `GetPolicyPathByAuthorityId(authorityID)` | 获取某角色的所有 API 权限列表 |
| `ClearCasbin(v, p...)` | 清除指定角色的所有策略 |
| `UpdateCasbinApi(oldPath, newPath, oldMethod, newMethod)` | API 变更时同步更新策略 |
| `SyncPolicy(db, authorityId, rules)` | 在事务中同步策略 |
| `FreshCasbin()` | 重新加载策略到内存 |

**严格权限模式** (`UseStrictAuth`): 开启后，管理员只能为下级角色分配自己已有的 API 权限。

---

## 5. API Key 认证机制

`middleware/api_key.go` 中的 `ApiKeyOrJWT()` 提供双重认证能力，主要用于 AutoCode 等自动化场景：

### 工作流程

```
检查请求头 x-api-key
    ├── 匹配配置中的 AutoCode.ApiKey → 注入超级管理员 Claims → 放行
    ├── 不匹配 → 返回 "invalid api key"
    └── 未提供 → fallback 到标准 JWTAuth() 流程
```

### 注入的 Claims

API Key 认证成功后注入的 Claims：

```go
BaseClaims{
    UUID:        "00000000-0000-0000-0000-000000000001",
    ID:          1,
    Username:    "api-key",
    NickName:    "API Key User",
    AuthorityId: 1,  // 超级管理员权限
}
```

因为 `AuthorityId` 为 1，所以 Casbin 中间件也会对其放行。

---

## 6. 路由分组与中间件应用

在 `initialize/router.go` 中定义了三个路由分组：

### PublicGroup — 公开路由（无需认证）

```go
PublicGroup := Router.Group(global.HAB_CONFIG.System.RouterPrefix)
```

注册的路由：
- `GET /health` — 健康检查
- `InitBaseRouter(PublicGroup)` — 登录、验证码等基础路由
- `InitInitRouter(PublicGroup)` — 系统初始化路由
- 各模块的公开部分（字典查询、参数查询等）

### PrivateGroup — 需认证路由

```go
PrivateGroup := Router.Group(global.HAB_CONFIG.System.RouterPrefix)
PrivateGroup.Use(middleware.JWTAuth()).Use(middleware.CasbinHandler())
```

中间件链：`JWT 验证` → `Casbin 权限检查`

注册的路由包括：用户管理、菜单管理、角色管理、API 管理、字典管理、操作记录等所有需要登录的功能。

### AutoCodeGroup — 支持 API Key 的路由

```go
AutoCodeGroup := Router.Group(global.HAB_CONFIG.System.RouterPrefix)
AutoCodeGroup.Use(middleware.ApiKeyOrJWT()).Use(middleware.CasbinHandler())
```

中间件链：`API Key 或 JWT 验证` → `Casbin 权限检查`

仅用于：
- `InitAutoCodeRouter` — 代码生成功能
- `InitAutoCodeHistoryRouter` — 代码生成历史

---

## 7. 前端权限实现

### 7.1 v-auth 指令（角色级别显隐）

定义在 `web/src/directive/auth.js`，基于用户的 `authorityId` 控制元素显隐：

```html
<!-- 仅角色 ID 为 1 的用户可见 -->
<el-button v-auth="1">超管按钮</el-button>

<!-- 角色 ID 为 1 或 888 的用户可见 -->
<el-button v-auth="[1, 888]">管理按钮</el-button>

<!-- 取反：角色 ID 不是 1 的用户可见 -->
<el-button v-auth.not="1">非超管按钮</el-button>
```

实现原理：在 `mounted` 钩子中比较 `binding.value` 与 `userInfo.authorityId`，不匹配则 `removeChild` 移除 DOM 元素。

### 7.2 按钮权限（btnAuth）

定义在 `web/src/utils/btnAuth.js`：

```js
import { useBtnAuth } from '@/utils/btnAuth'

const btnAuth = useBtnAuth()
// btnAuth 是一个对象，key 为按钮名称，value 为按钮 ID
// 例如 { add: 1, edit: 2, delete: 3 }
```

数据来源于路由 `meta.btns`，由后端菜单接口返回，表示当前角色在当前菜单下被授权的按钮。

```html
<el-button v-if="btnAuth.add">新增</el-button>
<el-button v-if="btnAuth.edit">编辑</el-button>
```

`useBtnAuthForRoute(name)` 可获取指定路由名称的按钮权限，适用于跨页面权限判断。

### 7.3 列权限（colAuth）

定义在 `web/src/utils/colAuth.js`：

```js
import { useColsAuth } from '@/utils/colAuth'

const colAuth = useColsAuth()
// colAuth 是一个对象，key 为列名，value 为列 ID
```

数据来源于路由 `meta.cols`，控制表格中哪些列对当前角色可见。

---

## 8. 多点登录拦截机制

通过配置 `System.UseMultipoint` 开启，依赖 Redis：

### 开启多点登录拦截后的 TokenNext 流程

```
1. 尝试从 Redis 获取用户的现有 JWT（key = username）
2. 如果 Redis 中无记录 → 正常签发并存入 Redis
3. 如果 Redis 中已有 JWT →
   a. 将旧 JWT 加入黑名单（数据库 + 内存缓存）
   b. 将新 JWT 存入 Redis
   c. 返回新 JWT
```

效果：同一用户只能有一个有效 Token，新设备登录会挤掉旧设备。

### Token 自动续签时的多点登录处理

在 JWT 中间件的 Buffer 续签逻辑中，如果开启了多点登录拦截，会同步更新 Redis 中的 JWT 记录。

---

## 9. 登录模式

系统通过 `System.LoginMode` 配置支持三种登录模式：

### simple 模式（默认）

- 仅需用户名 + 密码
- 不需要验证码
- 验证通过后直接签发 JWT

### captcha 模式

- 需用户名 + 密码 + 图片验证码
- 验证码由 `/base/captcha` 接口生成
- 防止暴力破解

### strict 模式

- 需用户名 + 密码 + 图片验证码
- 额外检查用户是否拥有"账户状态"角色
- Token 签发方式不同：使用 `pwd.SetPwdToken` 生成特殊 Token，而非标准 JWT

### 多因素认证登录

除密码登录外，系统还支持：

| 方式 | 端点 | 说明 |
|------|------|------|
| TOTP 登录 | `POST /auth/totp/login` | 用户名 + Google Authenticator 验证码 |
| Passkey 登录 | `POST /auth/passkey/assertion/verify` | WebAuthn 无密码登录 |

绑定流程：
1. `POST /auth/password/verify` — 密码预验证，获取 `bindSession`
2. `POST /auth/totp/bind/init` + `POST /auth/totp/bind/verify` — 绑定 TOTP
3. `POST /auth/passkey/attestation/options` + `POST /auth/passkey/attestation/verify` — 绑定 Passkey

---

## 10. 常见问题和注意事项

### Token 相关

- **x-token 位置**: Cookie 和 Header 都支持，Cookie 优先。前端应将 Token 同时存储在两个位置以确保兼容性。
- **续签丢失**: Buffer 续签通过响应头返回新 Token，前端必须监听 `new-token` 响应头并及时替换。
- **并发续签**: 使用 `singleflight` 机制避免并发请求时生成多个新 Token。

### Casbin 相关

- **超管免检**: `AuthorityId == 1` 的超级管理员不经过 Casbin 检查，直接放行所有 API。
- **策略缓存**: Casbin 使用 `SyncedCachedEnforcer`，修改策略后会自动刷新。如果遇到权限不生效，可调用 `FreshCasbin()` 手动刷新。
- **路径匹配**: 使用 `keyMatch2`，支持 `/path/:param` 风格的路由参数匹配。
- **路由前缀**: Casbin 策略中的路径不含 `RouterPrefix`，中间件会自动剥离前缀再匹配。

### 安全注意事项

- **SigningKey**: 必须保密且足够复杂，泄露将导致任意 Token 伪造。
- **黑名单**: 依赖内存缓存（`BlackCache`），服务重启时从数据库重新加载。如果使用多实例部署，需确保黑名单同步。
- **API Key**: 配置在 `AutoCode.ApiKey` 中，拥有超级管理员权限，仅用于自动化工具，切勿暴露。
- **密码存储**: 使用 `bcrypt` 哈希存储，`utils.BcryptHash` 加密，`utils.BcryptCheck` 验证。

### 前端权限注意事项

- `v-auth` 指令在 `mounted` 时执行，是一次性判断，不会响应角色切换。用户切换角色后需刷新页面。
- `btnAuth` 和 `colAuth` 数据来自路由 meta，由后端菜单接口动态注入，无需前端硬编码。
- 前端权限仅控制 UI 展示，实际的 API 访问控制由后端 Casbin 中间件保证。
