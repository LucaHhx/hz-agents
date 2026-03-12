# 响应格式、错误码、基础模型与工具函数

> HAB 框架核心模式速查，涵盖 API 响应、错误体系、数据模型基类和常用工具。

## 一、标准响应格式

所有 API 统一返回 JSON 格式：

```json
{
  "code": 0,
  "data": {},
  "msg": "操作成功"
}
```

- `code` — 0 表示成功，非 0 表示错误
- `data` — 业务数据（成功时）
- `msg` — 提示信息

## 二、响应 Helper 函数

位置：`server/model/common/response/response.go`

### 成功响应

| 函数 | 用途 |
|------|------|
| `response.Ok(c)` | 成功，无数据 |
| `response.OkWithMessage(msg, c)` | 成功，自定义消息 |
| `response.OkWithData(data, c)` | 成功，返回数据 |
| `response.OkWithDetailed(data, msg, c)` | 成功，数据+消息 |

### 失败响应

| 函数 | 用途 |
|------|------|
| `response.FailWithMessage(msg, c)` | 失败，错误消息 |
| `response.FailWithErr(err, c)` | 失败，从 error 对象提取 code+msg |
| `response.FailWithCodeMessage(code, msg, c)` | 失败，指定错误码 |
| `response.FailWithDetailed(data, msg, c)` | 失败，数据+消息 |
| `response.FailWithMessageData(msg, data, c)` | 失败，消息+数据 |
| `response.NoAuth(msg, c)` | 401 未授权 |

### 典型用法

```go
func GetXxx(c *gin.Context) {
    var req request.GetById
    if err := c.ShouldBindJSON(&req); err != nil {
        response.FailWithMessage(err.Error(), c)
        return
    }
    data, err := xxxService.GetXxx(req.Uint())
    if err != nil {
        response.FailWithMessage("获取失败", c)
        return
    }
    response.OkWithData(data, c)
}
```

## 三、错误码体系

位置：`server/code/`

### 结构

```go
// code.CodeMsg 定义
type CodeMsg struct {
    Code int
    Msg  string
}

// 创建新错误
err := code.NewError(code.CodeUserError, "用户不存在")
```

### 基础错误码

| 码 | 常量 | 含义 |
|----|------|------|
| 0 | `CodeSuccess` | 成功 |
| 7 | `CodeError` | 通用错误 |
| 1000 | `CodeUserError` | 用户相关错误 |
| 1001 | `CodeCommonError` | 通用业务错误 |
| 1002 | `CodeBusinessError` | 业务逻辑错误 |
| 1003 | `CodeAccountError` | 账号错误 |

### 用户/认证错误码（1001-1699）

| 范围 | 分类 |
|------|------|
| 1001-1099 | 用户错误（不存在、锁定、密码错误） |
| 1101-1199 | TOTP 相关 |
| 1201-1299 | Passkey 相关 |
| 1301-1399 | 绑定频率限制 |
| 1401-1499 | 恢复码 |
| 1501-1599 | CSRF/安全 |
| 1601-1699 | 频率限制 |

> 业务模块可在 1002+ 基础上自定义错误码，建议在 `server/code/business.go` 中集中管理。

## 四、三种基础 Model

位置：`server/global/model.go`

| Model | 字段 | 用途 |
|-------|------|------|
| `HAB_MODEL` | ID + CreatedAt + UpdatedAt + DeletedAt | 标准模型，带软删除 |
| `HAB_MODEL_NOD` | ID + CreatedAt + UpdatedAt | 无软删除（物理删除场景） |
| `HAB_MODEL_NOID` | CreatedAt + UpdatedAt + DeletedAt | 无自增 ID（复合主键场景） |

```go
// 典型用法：业务 model 嵌入基础 model
type Supplier struct {
    global.HAB_MODEL
    Name   string `json:"name" gorm:"size:200"`
    Code   string `json:"code" gorm:"size:50;uniqueIndex"`
}
```

### MySQLTime 自定义时间类型

所有基础 Model 的时间字段使用 `MySQLTime` 类型，支持自定义 JSON 序列化格式。

## 五、常用 Utils

位置：`server/utils/`

### 用户信息提取（claims.go）

从 Gin Context 的 JWT Claims 中提取用户信息：

| 函数 | 返回值 | 说明 |
|------|--------|------|
| `utils.GetUserID(c)` | `uint` | 当前用户 ID |
| `utils.GetUserUuid(c)` | `uuid.UUID` | 用户 UUID |
| `utils.GetUserName(c)` | `string` | 用户名 |
| `utils.GetUserNickName(c)` | `string` | 昵称 |
| `utils.GetUserAuthorityId(c)` | `uint` | 角色 ID |
| `utils.GetUserInfo(c)` | `CustomClaims` | 完整 Claims |
| `utils.GetClaims(c)` | `*CustomClaims` | 解析 JWT Claims |

### Token 管理（claims.go）

| 函数 | 说明 |
|------|------|
| `utils.GetToken(c)` | 从 Cookie/Header 获取 token |
| `utils.SetToken(c, token, maxAge)` | 设置 token 到 Cookie |
| `utils.ClearToken(c)` | 清除 token |

### 密码工具（hash.go）

| 函数 | 说明 |
|------|------|
| `utils.BcryptHash(password)` | bcrypt 哈希加密 |
| `utils.BcryptCheck(password, hash)` | 验证密码 |
| `utils.MD5V(str)` | MD5 哈希（遗留兼容） |
