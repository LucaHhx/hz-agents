# Go/Gin 请求结构体设计模式

> 从实际项目 Bug 中总结的请求结构体硬性规则。

## 核心规则：Create 和 Update 必须分离 struct

**根因**：Create 需要 `binding:"required"` 校验必填字段，Update 只更新传入的字段。
如果共用 struct，Update 请求也会被 `required` 拦截，导致部分更新失败。

### 标准模式

```go
// CreateXxxRequest — 创建请求，必填字段用 required
type CreateXxxRequest struct {
    Name        string  `json:"name" binding:"required"`
    Code        string  `json:"code" binding:"required"`
    Description string  `json:"description"`
    Enabled     bool    `json:"enabled"`
}

// UpdateXxxRequest — 更新请求，无 required，指针区分未传/零值
type UpdateXxxRequest struct {
    ID          uint    `json:"ID" binding:"required"`  // 只有 ID 是 required
    Name        *string `json:"name"`
    Code        *string `json:"code"`
    Description *string `json:"description"`
    Enabled     *bool   `json:"enabled"`
}
```

### 为什么 Update 用指针类型

| JSON 值 | `string` 类型 | `*string` 类型 |
|---------|--------------|---------------|
| `"name": "张三"` | `"张三"` | `&"张三"` |
| `"name": ""` | `""` | `&""` |
| 字段未传 | `""` | `nil` |

- `nil` = 字段未传，不更新
- `&""` = 明确传了空字符串，更新为空
- 非指针无法区分这两种情况

### Switch Toggle 场景

前端 Switch 组件切换时，只发送 `{ID, enabled}`：

```go
// 前端请求体
{
    "ID": 1,
    "enabled": true
}

// 后端处理
func UpdateXxx(c *gin.Context) {
    var req UpdateXxxRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        // 因为 UpdateXxxRequest 中只有 ID 是 required
        // 所以只传 {ID, enabled} 不会被拦截
        response.FailWithMessage(err.Error(), c)
        return
    }
    // Updates 只更新非 nil 字段
    // name=nil 不会被更新，enabled=&true 会被更新
}
```

## 反模式

### ❌ Create/Update 共用 struct

```go
// 错误：共用导致 Update 被 required 拦截
type XxxRequest struct {
    Name    string `json:"name" binding:"required"`
    Enabled bool   `json:"enabled"`
}

// 前端 Switch toggle 只传 {ID, enabled}
// → name 未传 → binding:"required" 校验失败 → 400 错误
```

### ❌ Update struct 使用非指针类型

```go
// 错误：非指针无法区分"未传"和"传零值"
type UpdateXxxRequest struct {
    Name    string `json:"name"`
    Enabled bool   `json:"enabled"`
}
// Updates(struct) 跳过零值 → enabled=false 无法保存
```

## 检查命令

```bash
# 检查是否存在 Create/Update 共用 struct（只有一个 XxxRequest）
grep -rn 'type.*Request struct' server/model/ | sort

# 检查 Update struct 中是否有非 ID 的 required
grep -A20 'UpdateXxx\|Update.*Request' server/model/ | grep 'required'
```

## 框架内置请求/响应类型

HAB 框架在 `server/model/common/request/` 中提供了常用的内置请求类型，业务代码直接组合使用：

| 类型 | 字段 | 用途 |
|------|------|------|
| `PageInfo` | Page, PageSize, Keyword | 分页请求基础类型，配合 `Paginate()` scope |
| `GetById` | ID int | 单条查询，提供 `Uint()` helper 转换 |
| `IdsReq` | Ids []int | 批量操作（批量删除等） |
| `QueryInfo` | PageInfo + SearchInfo + SortInfo | 高级搜索排序，支持动态条件 |
| `Empty` | （无字段） | 空请求体占位 |

```go
// 分页示例
type GetXxxListRequest struct {
    request.PageInfo           // 嵌入分页
    Status  *int  `json:"status"`
}

// service 中使用 Paginate scope
db.Scopes(utils.Paginate(info.Page, info.PageSize)).Find(&list)
```
