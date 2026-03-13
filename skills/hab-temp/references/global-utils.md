# 全局变量与工具函数参考文档

本文档涵盖 hz-admin-base 中的全局变量、基础模型、通用请求/响应结构、错误码体系、枚举定义、后端工具函数、前端全局注册与前端工具函数。

> **源码路径均相对于 `hz-admin-base/` 根目录。**

---

## 1. 后端全局变量

定义于 `server/global/global.go`。

| 变量名 | 类型 | 说明 |
|--------|------|------|
| `HAB_DB` | `*gorm.DB` | 默认数据库连接实例 |
| `HAB_DBList` | `map[string]*gorm.DB` | 多数据库连接池，key 为数据库别名 |
| `NoLogDB` | `*gorm.DB` | 不记录日志的数据库连接（内部操作专用） |
| `HAB_REDIS` | `redis.UniversalClient` | 默认 Redis 客户端 |
| `HAB_REDISList` | `map[string]redis.UniversalClient` | 多 Redis 连接池 |
| `HAB_MONGO` | `*qmgo.QmgoClient` | MongoDB 客户端 |
| `HAB_CONFIG` | `config.Server` | 系统配置对象（从 config.yaml 加载） |
| `HAB_VP` | `*viper.Viper` | Viper 配置管理实例 |
| `HAB_LOG` | `*zap.Logger` | Zap 日志记录器 |
| `HAB_Timer` | `timer.Timer` | 定时任务管理器（启动时已初始化） |
| `HAB_Concurrency_Control` | `*singleflight.Group` | 并发控制（防止重复请求） |
| `HAB_ROUTERS` | `gin.RoutesInfo` | 已注册的路由信息 |
| `HAB_ACTIVE_DBNAME` | `*string` | 当前活跃的数据库名 |
| `BlackCache` | `local_cache.Cache` | 本地黑名单缓存（JWT Token 黑名单） |
| `Json` | `sonic.ConfigFastest` | 高性能 JSON 序列化器（字节跳动 sonic 库） |

### 1.1 多数据库辅助函数

```go
// 通过别名获取数据库连接，不存在返回 nil
db := global.GetGlobalDBByDBName("business_db")

// 通过别名获取数据库连接，不存在则 panic
db := global.MustGetGlobalDBByDBName("business_db")

// 创建指定 skip 层级的日志器（调整调用栈层级）
logger := global.SkipLog(1)
```

---

## 2. 基础模型

定义于 `server/global/model.go`。

### 2.1 HAB_MODEL（标准模型 -- 含软删除）

所有业务表的默认基础模型：

```go
type HAB_MODEL struct {
    ID        uint           `gorm:"primarykey" json:"ID"`
    CreatedAt MySQLTime      // 创建时间
    UpdatedAt MySQLTime      // 更新时间
    DeletedAt gorm.DeletedAt `gorm:"index" json:"-"` // 软删除（JSON 不输出）
}
```

### 2.2 HAB_MODEL_NOD（无软删除模型）

日志表、流水表等不需要软删除的场景：

```go
type HAB_MODEL_NOD struct {
    ID        uint      `gorm:"primarykey" json:"ID"`
    CreatedAt MySQLTime
    UpdatedAt MySQLTime
}
```

### 2.3 HAB_MODEL_NOID（无 ID 模型）

关联表、中间表等不需要独立主键的场景：

```go
type HAB_MODEL_NOID struct {
    CreatedAt MySQLTime
    UpdatedAt MySQLTime
    DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
}
```

### 2.4 使用示例

```go
type MyBusiness struct {
    global.HAB_MODEL
    Name   string `json:"name" gorm:"column:name;comment:名称"`
    Status int    `json:"status" gorm:"column:status;comment:状态"`
}
```

---

## 3. MySQLTime 时间类型

定义于 `server/global/time.go`，统一 Go `time.Time` 与 MySQL 日期格式。

### 3.1 构造函数

| 函数 | 返回类型 | 说明 |
|------|----------|------|
| `global.Now()` | `*MySQLTime` | 当前时间（指针） |
| `global.NowMySQLTime()` | `MySQLTime` | 当前时间（值类型） |
| `global.NowMySQLTimeAdd(d)` | `*MySQLTime` | 当前时间 + 偏移量 |
| `global.NewMySQLTime(t)` | `*MySQLTime` | 从 `time.Time` 创建 |

### 3.2 实例方法

| 方法 | 说明 |
|------|------|
| `t.FormatTime()` | 格式化为 `"2006-01-02 15:04:05"`，零值返回空字符串 |
| `t.FormatDate()` | 格式化为 `"2006-01-02"`，零值返回空字符串 |
| `t.AddDays(n)` | 增加 n 天，返回新 `*MySQLTime` |
| `t.GetTime()` | 获取底层 `time.Time` |

### 3.3 序列化行为

- **JSON 序列化**：输出 `"2006-01-02 15:04:05"` 格式字符串，零值输出 `null`
- **JSON 反序列化**：解析 `"2006-01-02 15:04:05"` 格式，空字符串和 `"null"` 设为零值
- **GORM 写入**（`Value`）：零值写入 `nil`，非零值写入格式化字符串
- **GORM 读取**（`Scan`）：支持 `time.Time`、`[]byte`、`string` 三种来源

---

## 4. 运行模式

定义于 `server/global/mode.go`。

| 常量 | 值 | 说明 |
|------|----|------|
| `ModeApi` | `"api"` | 仅启动 API 服务 |
| `ModeBackend` | `"backend"` | 仅启动后台服务 |
| `ModeTask` | `"task"` | 仅启动定时任务 |
| `ModeAll` | `"all"` | 启动所有服务（默认） |

通过命令行参数 `-type` 指定：

```bash
./server -type=api       # 仅 API
./server -type=backend   # 仅后台
./server -type=task      # 仅定时任务
./server                 # 默认 all
```

代码中判断：

```go
if global.SysMode == global.ModeApi { ... }

// ServiceList = [ModeApi, ModeBackend, ModeAll]，用于判断是否属于服务类型
if utils.ContainsIn(global.ServiceList, global.SysMode) { ... }
```

---

## 5. 公共模型（common 包）

### 5.1 JSONMap（`server/model/common/basetypes.go`）

数据库 JSON 列的 map 类型，实现 `driver.Valuer` 和 `sql.Scanner` 接口：

```go
type JSONMap map[string]interface{}
```

自动处理序列化/反序列化，`nil` 值读出时初始化为空 map。

### 5.2 TreeNode 泛型接口

用于树形结构数据的通用接口：

```go
type TreeNode[T any] interface {
    GetChildren() []T
    SetChildren(children T)
    GetID() int
    GetParentID() int
}
```

---

## 6. 通用请求模型

定义于 `server/model/common/request/common.go`。

### 6.1 PageInfo 分页请求

```go
type PageInfo struct {
    Page     int    `json:"page" form:"page"`         // 页码（从 1 开始）
    PageSize int    `json:"pageSize" form:"pageSize"` // 每页大小（上限 100，默认 10）
    Keyword  string `json:"keyword" form:"keyword"`   // 搜索关键字
}
```

内置 `Paginate()` 方法直接作为 GORM Scope：

```go
db.Scopes(info.Paginate()).Find(&list)
```

### 6.2 其他请求模型

| 类型 | 用途 | 字段 |
|------|------|------|
| `GetById` | 按 ID 查询 | `ID int`，提供 `Uint()` 转换方法 |
| `IdsReq` | 批量操作 | `Ids []int` |
| `GetAuthorityId` | 角色查询 | `AuthorityId uint` |
| `Empty` | 空请求体 | 无字段 |

### 6.3 QueryInfo 高级查询（DiyTable 专用）

```go
type QueryInfo struct {
    PageInfo   *PageInfo              `json:"pageInfo"`
    SearchInfo map[string]*SearchInfo `json:"searchInfo"`  // key 为列名
    SortInfo   map[string]*SortInfo   `json:"sortInfo"`    // key 为列名
}

type SearchInfo struct {
    Option string `json:"option"` // 操作符：=, like, in, not in, between, not between
    Type   string `json:"type"`   // 数据类型
    Value  string `json:"value"`  // 搜索值（多值用逗号分隔）
}

type SortInfo struct {
    Index int    `json:"index"` // 排序优先级（越小越优先）
    Type  string `json:"type"`  // "asc" 或 "desc"
}
```

---

## 7. 通用响应模型

定义于 `server/model/common/response/`。

### 7.1 Response 结构体

```go
type Response struct {
    Code    int         `json:"code"`
    Data    interface{} `json:"data"`
    Message string      `json:"msg"`
}
```

### 7.2 PageResult 分页结果

```go
type PageResult struct {
    List     interface{} `json:"list"`
    Total    int64       `json:"total"`
    Page     int         `json:"page"`
    PageSize int         `json:"pageSize"`
    SumInfo  any         `json:"sumInfo"`  // 可选的汇总信息
}
```

### 7.3 响应函数速查表

| 函数 | 说明 |
|------|------|
| `Ok(c)` | 成功，无数据 |
| `OkWithMessage(msg, c)` | 成功 + 自定义消息 |
| `OkWithData(data, c)` | 成功 + 数据 |
| `OkWithDetailed(data, msg, c)` | 成功 + 数据 + 消息 |
| `FailWithMessage(msg, c)` | 失败 + 消息（code=7） |
| `FailWithMessageData(msg, data, c)` | 失败 + 消息 + 数据 |
| `FailWithDetailed(data, msg, c)` | 失败 + 数据 + 消息（参数顺序不同） |
| `FailWithErr(err, c)` | 失败 + error，自动解析 `code.CodeMsg` |
| `FailWithErrData(err, data, c)` | 失败 + error + 附加数据 |
| `FailWithCodeMessage(code, msg, c)` | 失败 + 指定错误码 |
| `NoAuth(msg, c)` | HTTP 401 未授权（code=7） |

### 7.4 FailWithErr 的错误码解析机制

`FailWithErr` 使用 `errors.As` 判断 error 是否为 `code.CodeMsg` 类型：
- 是：提取其 `Code` 和 `Msg` 字段
- 否：回退为 `code=7`，`msg=err.Error()`

```go
// Service 层返回带错误码的 error
return code.NewError(code.CodeBusinessError, "create")

// API 层自动解析
response.FailWithErr(err, c)
// 前端收到: { "code": 1002, "msg": "create", "data": null }
```

---

## 8. 错误码体系

系统有两套错误码体系：`code` 包（API 层）和 `enum` 包（业务层/外部接口）。

### 8.1 code 包（`server/code/`）

#### 基础错误码（`code.go`）

| 常量 | 值 | 说明 |
|------|----|------|
| `CodeSuccess` | 0 | 成功 |
| `CodeError` | 7 | 通用错误 |
| `CodeUserError` | 1000 | 用户错误 |
| `CodeCommonError` | 1001 | 通用业务错误 |
| `CodeBusinessError` | 1002 | 业务操作错误（CRUD） |
| `CodeAccountError` | 1003 | 账户错误 |

**CodeMsg 类型**实现 `error` 接口，可直接 return：

```go
// 创建错误
err := code.NewError(code.CodeBusinessError, "订单已过期")

// 账户错误快捷方法
err := code.AccError("用户 %s 不存在", username)
```

#### 通用错误（`common.go`）

| 变量 | 说明 |
|------|------|
| `Err_Common_InvalidParams` | 参数无效 |
| `Err_Common_NoPermission` | 无权限 |
| `Err_Common_NoData` | 无数据 |
| `Err_Common_Unknown` | 未知错误 |
| `Err_Common_Err` | 通用错误 |

#### 业务 CRUD 错误（`business.go`）

| 变量 | Msg |
|------|-----|
| `Err_Business_Create` | `"create"` |
| `Err_Business_Import` | `"import"` |
| `Err_Business_Delete` | `"delete"` |
| `Err_Business_Update` | `"update"` |
| `Err_Business_Get` | `"get"` |
| `Err_Business_List` | `"list"` |
| `Err_Business_Export` | `"export"` |

> 这些 Msg 是英文 key，前端通过 i18n 翻译（格式：`error.1002.create`）。

#### 用户认证错误（`user.go`）

按功能分段：
- **1001-1003**：基础用户错误（用户不存在 / 密码错误 / 账户锁定）
- **1051-1054**：登录验证（验证码必须 / 验证码无效 / 用户名密码为空 / 权限拒绝）
- **1101-1102**：TOTP 错误（未绑定 / 验证码错误）
- **1201-1202**：Passkey 错误（未绑定 / 验证失败）
- **1301**：绑定操作过于频繁
- **1401**：恢复码无效
- **1501**：CSRF 验证失败
- **1601**：频率限制

### 8.2 enum 包错误码（`server/enum/code.go`）

面向外部接口和业务领域的精细错误码。每个 Code 对应一个 `CodeMsg` 类型（也实现 `error` 接口）。

| 范围 | 分类 | 关键常量 |
|------|------|----------|
| 0 / 7 / 404 | 通用状态 | `Code_Success` / `Code_Failed` / `Code_NotFind` |
| 101-103 | 商户相关 | `Code_MerchantNotFound` / `Code_MerchantInsufficient` / `Code_MerchantSignError` |
| 1001-1007 | 数据库错误 | `Code_DBError` ~ `Code_DBDeleteError` |
| 2001-2005 | 缓存错误 | `Code_CacheError` ~ `Code_CacheGetError` |
| 3001-3004 | 权限错误 | `Code_Unauthorized` ~ `Code_TokenInvalid` |
| 4001-4003 | 参数校验 | `Code_InvalidParams` / `Code_MissingParams` / `Code_InvalidFormat` |
| 5001-5003 | 网络错误 | `Code_NetworkError` / `Code_RequestTimeout` / `Code_ServiceDown` |
| 6001-6004 | 文件错误 | `Code_FileNotFound` ~ `Code_FileWriteError` |
| 7001-7003 | 系统内部 | `Code_InternalError` / `Code_ServiceError` / `Code_ConfigError` |
| 8001-8007 | 任务相关 | `Code_TaskError` / `Code_TaskStop` / `Code_TaskCancel` |
| 9001 | API 相关 | `Code_HeadError` |
| 10001-10004 | 订单相关 | `Code_OrderError` ~ `Code_Order_Over` |

使用预定义消息变量：

```go
return enum.Msg_DBRecordNotFound  // CodeMsg{Code: 1002, Msg: "Record not found in database"}
return enum.Msg_Sys_Busy          // CodeMsg{Code: 7001, Msg: "System is busy, please try again later"}
```

自定义消息：

```go
err := enum.NewCodeMsg(enum.Code_DBError, "用户 %s 数据异常", username)
```

### 8.3 两套错误码的使用场景

| 场景 | 使用哪套 |
|------|----------|
| API handler / Service CRUD 层 | `code` 包（`code.Err_Business_*`），前端 i18n 翻译 |
| 外部接口（商户 API、回调） | `enum` 包（`enum.Msg_*`），消息为英文，直接返回 |
| 参数验证（`utils.BindAndValidate`） | `enum` 包（`enum.Msg_InvalidParams`） |

---

## 9. 枚举定义（`server/enum/`）

### 9.1 基础常量（`base.go`）

```go
const Yes = 1; No = 2        // 是/否（int 型）
const Open = "open"; Close = "close"  // 开启/关闭（string 型）
```

### 9.2 缓存与消息键（`cache_key.go`）

```go
const Head_RepeatCount = "rabbit-count"        // RabbitMQ 消息重试次数 Header
const AppKey = "hab"                           // 应用标识
var CacheKey = fmt.Sprintf("{%s}", AppKey)     // Redis 键前缀 "{hab}"
```

### 9.3 gRPC 相关（`grpc.go`）

```go
const GrpcMd_Token = "grpc-token"   // gRPC metadata Token 键
const GrpcMd_Name  = "grpc-name"    // gRPC metadata 名称键
const Grpc_ServiceType_OpenVc = "openvc"
const OpenVcServiceName_Local = "openvc-local"
```

### 9.4 时间常量（`time.go`）

```go
const NxTime = 15 * time.Second  // Redis NX 锁默认过期时间
```

### 9.5 用户类型（`user.go`）

```go
type SysUserType int
const (
    SysUserTypeAdmin    SysUserType = 0  // 管理员
    SysUserTypeAgent    SysUserType = 1  // Agent
    SysUserTypeMerchant SysUserType = 2  // 商户
)
```

### 9.6 业务枚举（`dis.go` -- 重要类型摘要）

| 类型名 | 说明 | 常见值 |
|--------|------|--------|
| `BankType` | 银行类型 | `bca`, `bri`, `bni`, `mandiri`, `cimb`, `dana` |
| `AccType` | 账户类型 | `common`, `make`, `audit` |
| `ImportType` | 导入类型 | `full`（全量）, `append`（增量） |
| `GrpcType` | gRPC 服务类型 | `openvc`, `serial`, `chrome`, `serve` |
| `OrderStatus` | 订单状态 | `unknown`, `created`, `submit`, `success`, `fail`, `processing`, `timeout`, `checked` |
| `Status` | 通用状态 | `unknown`, `success`, `fail`, `processing`, `timeout` |
| `CallBackStatus` | 回调状态 | `unknown`, `success`, `fail` |
| `AccStatus` | 账号在线状态 | `unknown`, `offline`, `online`, `vpn_online` |
| `UseStatus` | 使用状态 | `normal`, `disabled` |
| `TranStatus` | 交易状态 | `unknown`, `success`, `fail`, `processing`, `timeout`, `refund` |
| `TranType` | 交易类型 | `CR`（入账）, `DB`（出账）, `BP`（批次） |
| `OrderType` | 订单类型 | `payin`, `payout`, `batch`, `fee` 等 |
| `PayStatus` | 支付状态 | `ready`, `processing`, `error` |
| `BatchPayStatus` | 批次支付状态 | `pending`, `processing`, `make_order`, `wait_match`, `success`, `fail`, `timeout` |
| `BatchPayOrderStatus` | 批次订单状态 | `init`, `checked`, `pending`, `processing`, `make_order`, `wait_match`, `success`, `fail`, `timeout` |

---

## 10. 后端工具函数

### 10.1 参数绑定与验证（`utils/validator.go`）

#### BindAndValidate -- 推荐方式

一行完成 JSON 绑定 + struct tag 验证：

```go
var req MyRequest
if err := utils.BindAndValidate(c, &req); err != nil {
    response.FailWithErr(err, c)
    return
}
```

内部流程：`ShouldBindJSON` -> `ValidateStruct`（使用 go-playground/validator）

**翻译规则**：自动将 validator 错误翻译为可读英文消息（`required` -> `"XXX is required."`）。

#### 其他绑定函数

| 函数 | 输入 | 用途 |
|------|------|------|
| `BindAndValid(data []byte, req)` | JSON 字节 | 非 HTTP 场景（如 MQ 消息） |
| `BindMapValid(data map[string]interface{}, req)` | map | map 转 struct + 验证 |
| `ValidateStruct(s)` | struct | 单独验证 struct tag |

#### Verify -- 自定义规则验证

```go
if err := utils.Verify(req, utils.Rules{
    "Name":   {utils.NotEmpty()},
    "Amount": {utils.Gt("0"), utils.Le("1000000")},
    "Email":  {utils.RegexpMatch(`^\w+@\w+\.\w+$`)},
}); err != nil {
    response.FailWithMessage(err.Error(), c)
    return
}
```

规则函数：`NotEmpty()`, `Lt()`, `Le()`, `Eq()`, `Ne()`, `Ge()`, `Gt()`, `RegexpMatch(rule)`

### 10.2 预定义验证规则（`utils/verify.go`）

| 规则变量 | 验证的字段 |
|----------|------------|
| `IdVerify` | `ID` 不为空 |
| `LoginVerify` | `Username` 不为空 |
| `RegisterVerify` | `Username`, `NickName`, `Password`, `AuthorityId` |
| `PageInfoVerify` | `Page`, `PageSize` |
| `MenuVerify` | `Path`, `Name`, `Component`, `Sort>=0` |
| `ApiVerify` | `Path`, `Description`, `ApiGroup`, `Method` |
| `AuthorityVerify` | `AuthorityName` |
| `ChangePasswordVerify` | `Password`, `NewPassword` |

### 10.3 Claims 用户信息提取（`utils/claims.go`）

从 Gin Context 的 JWT Token 中提取用户信息：

| 函数 | 返回值 | 说明 |
|------|--------|------|
| `GetUserID(c)` | `uint` | 用户 ID |
| `GetUserName(c)` | `string` | 用户名 |
| `GetUserNickName(c)` | `string` | 昵称 |
| `GetUserUuid(c)` | `uuid.UUID` | 用户 UUID |
| `GetUserAuthorityId(c)` | `uint` | 角色 ID |
| `GetUserInfo(c)` | `*CustomClaims` | 完整 Claims |
| `GetUserTypeInfo(c)` | `(SysUserType, string)` | 用户类型 + 参数 |
| `GetClaims(c)` | `(*CustomClaims, error)` | 解析 Token |
| `GetToken(c)` | `string` | 获取 Token（优先 Cookie，回退 Header x-token） |
| `SetToken(c, token, maxAge)` | - | 设置 Token Cookie |
| `ClearToken(c)` | - | 清除 Token Cookie |
| `LoginToken(user)` | `(token, claims, err)` | 生成登录 Token |

### 10.4 哈希与加密（`utils/hash.go`）

```go
hash := utils.BcryptHash(password)           // bcrypt 加密密码
ok := utils.BcryptCheck(password, hash)       // 校验密码
md5 := utils.MD5V([]byte("data"))             // MD5 哈希
md5 := utils.Md5Str("data")                   // MD5 字符串快捷方法
b64 := utils.Base64Str("data")                // Base64 编码
```

### 10.5 签名工具（`utils/sign.go`）

```go
// 生成签名（struct -> map -> 排序拼接 -> MD5）
sign := utils.MakeSign(data, secret)

// 验证签名
ok := utils.VerifySign(data, sign, secret)

// 底层：将 map 的 key 字母排序，拼接为 "k1=v1&k2=v2" + secret，然后 MD5
raw := utils.MakeOriginSign(params, secret)
sign := utils.Md5Sign(params, secret)

// 结构体展开为 map（包括嵌套结构体）
m := utils.StructToSpreadMap(myStruct)
```

### 10.6 字符串工具（`utils/strings.go`）

| 函数 | 说明 |
|------|------|
| `String(val)` | 任意类型转 string（支持 float64 精确转换） |
| `StringMust(val, def...)` | 同上，失败时返回默认值 |
| `StringToInt[T](num)` | 字符串转泛型整数 |
| `IsEmptyStr(val *string)` | 指针字符串判空 |
| `ConvStr(val *string)` | 指针字符串安全取值 |
| `Atoi(s)` | `strconv.Atoi` 忽略错误版 |
| `Itoa[V Int](i)` | 泛型整数转字符串 |
| `CutToInt[T](s, sep)` | 字符串切割为两个整数 |
| `RemoveBytes(s, v)` | 高性能移除指定字节 |
| `StrReplace(s, reps)` | 模板替换（`@key` -> `value`） |
| `FormatCommand(s)` | 将命令字符串按空格分割（合并连续空格） |
| `StringToFloat(s)` | 字符串转 float64（自动去千分位逗号） |
| `FloatWithCommas(f)` | 浮点数添加千分位逗号 |
| `FloatWithIndCommas(f)` | 浮点数转印尼格式（千分位用点，小数用逗号） |
| `IntWithCommas(n)` | 整数添加千分位逗号 |
| `RemoveFloatZeros(s)` | 去除小数末尾零 |
| `RepeatCount(table)` | 从 RabbitMQ Header 获取重试次数 |

### 10.7 数学工具（`utils/math.go`）

使用 `shopspring/decimal` 库保证精度：

| 函数 | 说明 |
|------|------|
| `Sum[T Number](num...)` | 精确求和 |
| `Mul[T, V Number](d1, num...)` | 精确连续乘法 |
| `Div[T, V Number](d1, num...)` | 精确连续除法（除零返回 0） |
| `MulToInt[T, V](d1, num...)` | 乘法后取整数部分 |
| `DivToInt[T, V](d1, num...)` | 除法后取整数部分 |
| `DivRound[T, V](d1, num, round)` | 除法后保留指定小数位 |
| `Mul100[T](num)` | 乘 100 取整（元转分） |
| `Div100[T](num)` | 除 100（分转元） |
| `Div100ToInt[T](num)` | 除 100 取整 |
| `Abs[T Signed](num)` | 绝对值 |
| `Avg[T Number](num...)` | 平均值 |
| `NearKey[T](nums, num)` | 在降序数组中找最近值的索引 |
| `NearVal[T](nums, num)` | 在降序数组中找最近的值 |
| `Range(n1, n2)` | 生成整数序列 `[n1, n2]` |
| `IsNumber(v)` | 判断 interface{} 是否为数字类型 |
| `DivToIntRate(f1, f2)` | 除法后乘 100 取整（百分比） |

### 10.8 切片工具（`utils/slices.go`）

| 函数 | 说明 |
|------|------|
| `ContainsIn[T](ts, t)` | 元素是否在切片中 |
| `ContainsInArr[T](ts, nts)` | 两个切片是否有交集 |
| `ArrIn[T](ts, nts...)` | nts 中所有元素都在 ts 中 |
| `ArrNotIn[T](ts, nts...)` | nts 中所有元素都不在 ts 中 |
| `InArr[V](v, sl)` | 同 ContainsIn（别名） |
| `SplitInt[V](s, sep)` | 字符串分割为整数切片 |
| `JoinInt[V](arr, sep)` | 整数切片连接为字符串 |
| `IntArr(arr)` | `[]string` -> `[]int` |
| `IntArrType[T, V](arr)` | 数字类型切片转换 |
| `StringArr[V](arr)` | 整数切片 -> 字符串切片 |
| `SliceGet[T](s, index)` | 安全取值（支持负索引，越界返回零值） |
| `ArrFind[T](s, f)` | 查找第一个满足条件的元素 |
| `GetValues[T](arr)` | 指针切片取值 |
| `Last[T](ts)` | 获取最后一个元素（空切片返回零值） |
| `LockArr[T]` | 线程安全切片（`Add` / `Get`） |

### 10.9 Map 工具（`utils/map.go`）

```go
// 过滤 map，返回满足条件的子 map
filtered := utils.MapFilter(data, func(k string, v int) bool { return v > 0 })

// 过滤 map，返回满足条件的 key 切片
keys := utils.MapFilterKey(data, func(k string, v int) bool { return v > 0 })
```

### 10.10 时间工具（`utils/time.go`）

| 函数 | 说明 |
|------|------|
| `NowTime()` | 返回当前 `*time.Time` |
| `NowTimeAdd(d)` | 返回当前时间 + 偏移量 |
| `NowTimeRange()` | 返回当天的 `[00:00:00, 次日00:00:00]` |
| `IntDate(t)` | `time.Time` -> `uint`（如 `20201201`） |
| `DateInt(i)` | `uint`（如 `20201201`）-> `time.Time` |
| `DaysInMonth(t)` | 获取某月的天数 |
| `GetTimeWeek(t)` | 获取当周星期一 00:00:00 |
| `GetTimeMonth(t)` | 获取当月 1 号 00:00:00 |
| `GetTimeDay(t)` | 获取当天 00:00:00 |
| `GetTimeHour(t)` | 获取当前小时 00 分 |
| `TimeOffset(t)` | 将 UTC 时间加上本地时区偏移后格式化 |

`ParseDuration`（`utils/human_duration.go`）：扩展标准 `time.ParseDuration`，支持 `"7d"` 天数格式。

### 10.11 缓存工具（`utils/cache.go`）

封装 Redis 操作，自动使用 `global.Json`（sonic）进行序列化：

| 函数 | 说明 |
|------|------|
| `GetCacheKey(place, keys...)` | 生成缓存 key：`place:key1:key2` |
| `GetCache(key, to)` | 读取并反序列化到 `to` |
| `SetCache(key, data, expiration)` | 序列化并写入 |
| `DelCache(key...)` | 删除缓存（支持多 key） |
| `SetHCache(key, field, data)` | Hash 写入 |
| `GetHCache(key, field, to)` | Hash 读取 |
| `DelHCache(key, field)` | Hash 字段删除 |
| `GetHAllCache[T](key, maps)` | Hash 全量读取到 `map[string]T` |
| `AtomicOperate(evals...)` | Lua 原子操作（多命令合并执行） |

### 10.12 Redis 分布式锁（`utils/redis_nx.go`）

```go
// 方式一：创建锁并检查是否成功
nx := utils.NewRedisNx("lock:order:123", 15*time.Second)
if nx == nil {
    return errors.New("操作太频繁")
}
defer nx.Del()

// 方式二：手动控制
nx := utils.NewNx("lock:key")
if nx.SetNx(15 * time.Second) {
    defer nx.Del()
    // 执行业务
}

// 检查锁状态
if nx.IsLocked() { ... }

// 静态删除
utils.DeleteRedisNx("lock:order:123")
```

### 10.13 Redis Lua 脚本（`utils/redis.go`）

```go
// 原子 HINCRBY，减少时检查不能小于 0
newVal, err := utils.LuaHINCRBY("balance:hash", "user1", -100)

// 批量 HINCRBY（全部满足才执行，否则整体失败）
vals, err := utils.LuaHINCRBYList("balance:hash", fields, values)

// 批量 HGET 为 int64
vals, err := utils.LuaHGETInt64("balance:hash", "field1", "field2")
```

### 10.14 JSON 工具（`utils/json.go`）

```go
// 使用 sonic 编码（比标准库快）
data, err := utils.JsonEncode(obj)

// 使用 sonic 解码
err := utils.JsonDecode(data, &obj)

// 获取 JSON 字符串中的所有 key（保持顺序）
keys, err := utils.GetJSONKeys(`{"a":1,"b":2}`)  // ["a", "b"]
```

### 10.15 随机数工具（`utils/rand.go`）

```go
code := utils.RandNum6()         // 6 位随机数字字符串（100000-999999）
n := utils.RandInt(100)           // [0, 100) 随机整数
s := utils.RandString(16)         // 16 位随机字母数字字符串
```

> 使用 `crypto/rand` 而非 `math/rand`，密码学安全。

### 10.16 Base36 唯一码（`utils/base62.go`）

```go
code := utils.GenerateCode(12345)  // 将 ID 混淆后编码为 8 位 Base36 字符串
```

通过质数乘法混淆 ID，防止顺序猜测。

### 10.17 通用辅助函数（`utils/helper.go`）

```go
// 三元表达式
val := utils.If(condition, trueVal, falseVal)

// panic 恢复（用于 goroutine）
go func() {
    defer utils.PanicRecover()
    // ...
}()

// 分批处理
err := utils.ProcessInBatches(items, 100, func(batch []Item) error {
    return db.Create(&batch).Error
})
```

### 10.18 表达式引擎（`utils/expression.go`）

对结构体字段进行动态表达式求值：

```go
exp, _ := utils.NewExpression(myStruct)
result, err := exp.Evaluate("{Amount} > 100 && {Status} == \"success\"")
// 支持: contains({Tags}, "vip") -> 展开为数组元素逐一比较
```

### 10.19 DiyTable 查询引擎（`utils/table_query.go`）

核心函数 `TableQuery` 处理动态列权限下的搜索/排序/分页：

```go
count, err := utils.TableQuery(db, queryInfo, c)
```

支持的 SearchInfo.Option：`=`, `like`, `in`, `not in`, `between`, `not between`

辅助函数：
- `GetColumns(db, c)` -- 获取当前角色有权看到的列
- `GetUpdateColumns(db, c)` -- 获取当前角色有权更新的列
- `GetColumnsMap(tableName, aid)` -- 获取列权限 map

### 10.20 其他工具

| 文件 | 函数 | 说明 |
|------|------|------|
| `gin.go` | `GetIp(c)` | 获取客户端 IP |
| `response.go` | `ResponseBodyWriter` | 响应体拦截 Writer（操作记录中间件用） |
| `ip.go` | `GetIpInfo(ip)` | 调用外部 API 查询 IP 地理位置 |

---

## 11. 前端全局注册（`web/src/core/`）

### 11.1 hab.js -- Vue 插件入口

```js
import { register } from './global'
export default {
  install: (app) => {
    register(app)
  }
}
```

在 `main.js` 中通过 `app.use(hab)` 安装。

### 11.2 global.js -- 全局注册逻辑

`register(app)` 完成以下工作：

1. **注册所有 Element Plus 图标组件**（`@element-plus/icons-vue`）
2. **注册 SvgIcon 组件** -- 统一的 SVG 图标组件
3. **扫描并注册项目 SVG 图标** -- `src/assets/icons/**/*.svg` + `src/plugin/**/assets/icons/**/*.svg`
4. **挂载全局配置** -- `app.config.globalProperties.$GIN_VUE_ADMIN = config`

图标注册规则：
- 文件名即组件名，如 `dashboard.svg` -> `<dashboard />`
- 插件图标带前缀：`src/plugin/myPlugin/assets/icons/foo.svg` -> `<myPlugin-foo />`
- 文件名含空格的图标会被跳过并报错

### 11.3 config.js -- 网站配置

```js
const config = {
  appName: 'ADMIN',    // 应用名称
  appLogo: 'logo.svg', // Logo 文件名
  showViteLogo: true,  // 是否显示 Vite 日志
  logs: []             // 图标注册日志
}
```

---

## 12. 前端工具函数（`web/src/utils/`）

### 12.1 request.js -- HTTP 请求封装

基于 axios 的请求客户端，核心特性：

- **自动 Loading**：请求发出 400ms 后显示 Loading，响应后关闭
- **Token 注入**：自动添加 `x-token` 和 `x-user-id` Header
- **Token 刷新**：响应 Header 中有 `new-token` 时自动更新
- **错误码判断**：`code === 0` 或 `code === undefined` 视为成功
- **i18n 错误翻译**：非零 code 通过 `error.{code}.{msg}` 翻译错误消息
- **HTTP 错误处理**：401 跳转登录、500 清缓存重登、404 提示

```js
import service from '@/utils/request'

// 不显示 Loading
service({ url: '/api/xxx', method: 'post', donNotShowLoading: true, data })

// 自定义 Loading 容器
service({ url: '/api/xxx', method: 'get', loadingOption: { target: domEl } })
```

### 12.2 format.js -- 格式化函数

| 函数 | 说明 |
|------|------|
| `formatBoolean(bool)` | 布尔值转 "是"/"否" |
| `formatDate(time)` | 时间格式化为 `yyyy-MM-dd hh:mm:ss` |
| `filterDict(value, options)` | 从字典选项中匹配 label |
| `filterDataSource(dataSource, value)` | 数据源匹配（支持数组值） |
| `formatNumber(number, format)` | 数字格式化，支持千分位和运算前缀 |
| `unformatNumber(formattedValue, format)` | `formatNumber` 的逆运算 |
| `formatString(string, format)` | 字符串模板格式化 |
| `setBodyPrimaryColor(color, darkMode)` | 设置全局主题色 CSS 变量 |
| `getBaseUrl()` | 获取 API Base URL |
| `CreateUUID()` | 生成 UUID 字符串 |
| `ReturnArrImg(arr)` | 图片路径补全（相对路径加前缀） |
| `onDownloadFile(url)` | 打开文件下载 |

`formatNumber` 的 format 格式：`"运算:numeral格式"`
```js
formatNumber(10000, '/100:0,0.00')  // 先除100，再格式化 -> "100.00"
formatNumber(0.5, '*100:0.[00]')    // 先乘100，再格式化 -> "50"
formatNumber(1234.5, '0,0.00')      // 直接格式化 -> "1,234.50"
```

### 12.3 date.js -- 日期工具

```js
import { formatTimeToStr, getTodayRange, getLastNDaysRange } from '@/utils/date'

formatTimeToStr(new Date(), 'yyyy-MM-dd hh:mm:ss')
getTodayRange()         // ["2026-03-13 00:00:00", "2026-03-13 23:59:59"]
getLastNDaysRange(7)    // 近7天范围
```

### 12.4 time.js -- 时区转换（Luxon）

```js
import { convertDateTime, convertDate } from '@/utils/time'

convertDateTime('2026-03-13 12:00:00')  // -> ISO 格式 UTC 时间
convertDate('2026-03-13')               // -> ISO 格式 UTC 日期
```

### 12.5 dictionary.js -- 字典查询

```js
import { getDict, showDictLabel } from '@/utils/dictionary'

const options = await getDict('order_status')      // 获取字典选项
const label = showDictLabel(options, 'success')     // 根据 value 获取 label
```

### 12.6 params.js -- 系统参数

```js
import { getParams } from '@/utils/params'
const value = await getParams('site_name')
```

### 12.7 btnAuth.js -- 按钮权限

```js
import { useBtnAuth, useBtnAuthForRoute } from '@/utils/btnAuth'

const btns = useBtnAuth()  // 获取当前路由的按钮权限
if (btns.canCreate) { ... }

const btns2 = useBtnAuthForRoute('orderList')  // 按路由名获取
```

### 12.8 columns.js -- 动态列获取

```js
import { getColumns } from '@/utils/columns'
const cols = await getColumns('MyStructName')
```

### 12.9 export.js -- 批量导出

```js
import { batchExport, generateTemplateData } from '@/utils/export'

const result = await batchExport(
  fetchFunction,   // API 函数
  searchInfo,      // 搜索条件
  1000,            // 每批数量
  (page, total, loaded, all) => { /* 进度回调 */ },
  (allData, total) => { /* 完成回调 */ }
)

// 生成 Excel 模板数据（4行：key, label, type, 格式提示）
const [keys, labels, types, hints] = generateTemplateData(columns)
```

### 12.10 asyncRouter.js -- 动态路由

```js
import { asyncRouterHandle } from '@/utils/asyncRouter'
asyncRouterHandle(asyncRoutes)  // 将后端返回的路由配置转为 Vue 组件
```

### 12.11 其他前端工具

| 文件 | 说明 |
|------|------|
| `event.js` | `addEventListen` / `removeEventListen` 封装 |
| `page.js` | `getPageTitle()` -- 获取页面标题（来自 config.appName） |
| `bus.js` | 事件总线 |
| `clipboard.js` | 剪贴板操作 |
| `closeThisPage.js` | 关闭当前标签页 |
| `colAuth.js` | 列权限 |
| `rand.js` | 前端随机数 |
| `stringFun.js` | 字符串处理 |
| `image.js` | 图片处理 |
| `downloadImg.js` | 图片下载 |
| `lolocale.js` | 国际化消息获取 |
| `doc.js` | 文档相关 |
| `sysDataFilterCache.js` | 系统数据筛选缓存 |
| `cache.js` | 本地缓存 |

---

## 13. 注意事项和常见问题

### 13.1 两套错误码不要混用

- `code.CodeMsg` 和 `enum.CodeMsg` 是**不同类型**，虽然结构相同
- `response.FailWithErr` 解析的是 `code.CodeMsg`，如果传入 `enum.CodeMsg` 会回退为 `code=7`
- 在 Service/API 层统一使用 `code` 包；在外部接口/中间件层使用 `enum` 包

### 13.2 MySQLTime 零值行为

- `MySQLTime` 零值 JSON 序列化为 `null`，GORM 写入为 `nil`
- 判断是否为空：`t.Time.IsZero()`，而非 `t == nil`（值类型不会为 nil）
- `FormatTime()` / `FormatDate()` 对 nil 指针和零值都返回空字符串

### 13.3 分页限制

- `PageInfo.Paginate()` 内置 PageSize 上限 100，默认 10
- 前端批量导出使用 `batchExport` 分页拉取，不要一次请求所有数据

### 13.4 数学运算必须用 decimal

直接使用 `float64` 运算会丢失精度。所有涉及金额的计算必须使用 `utils.Sum/Mul/Div` 系列函数，底层使用 `shopspring/decimal`。

### 13.5 Redis 分布式锁注意

- `NewRedisNx` 返回 `nil` 表示获锁失败，必须检查
- 务必使用 `defer nx.Del()` 释放锁
- 默认 NX 超时 15 秒（`enum.NxTime`），长任务需要自定义过期时间

### 13.6 前端 Token 机制

- Token 同时存在 Cookie（`x-token`）和 Pinia Store 中
- 请求拦截器自动注入 `x-token` 和 `x-user-id` Header
- 响应 Header 中的 `new-token` 会自动刷新 Token
- 401 响应自动弹出重新登录对话框

### 13.7 前端错误码 i18n 翻译

API 返回非零 code 时，前端按 `error.{code}.{msg}` 查找翻译：
- 翻译存在：显示翻译文本
- 翻译不存在且 key 格式为 `error.{code}.error`：回退显示 `response.data.data || response.data.msg`

### 13.8 BindAndValidate vs Verify

- `BindAndValidate` 使用 struct tag（`binding:"required,min=1"`），适合标准验证
- `Verify` 使用自定义 Rules map，适合需要自定义错误消息或动态规则的场景
- 推荐新代码统一使用 `BindAndValidate`，简单场景在 struct tag 中定义规则

### 13.9 DiyTable 查询的 SearchInfo.Option

| Option | SQL 行为 | Value 格式 |
|--------|---------|-----------|
| `=`, `>`, `<`, `>=`, `<=`, `!=` | 直接比较 | 单值 |
| `like` | `LIKE '%value%'` | 单值 |
| `in` | `IN (v1, v2, ...)` | 逗号分隔 |
| `not in` | `NOT IN (v1, v2, ...)` | 逗号分隔 |
| `between` | `>= v1 AND < v2` | 逗号分隔两个值 |
| `not between` | `< v1 OR >= v2` | 逗号分隔两个值 |

### 13.10 全局变量线程安全

- `HAB_DBList` 的读写通过 `sync.RWMutex`（`lock`）保护
- `ColumnsCache` 使用 concurrent-map，线程安全
- `LockArr[T]` 提供线程安全的切片追加
