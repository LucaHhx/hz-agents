# 后端四层架构详解

## 1. 四层架构概览

```
┌─────────────────────────────────────────────────────┐
│                    Router 层                         │
│  定义 URL 路径 → HTTP 方法 → Handler 的映射关系       │
│  分配中间件（鉴权/操作记录等）                         │
│  文件: router/{module}/xxx.go                        │
└────────────────────┬────────────────────────────────┘
                     │ 调用
┌────────────────────▼────────────────────────────────┐
│                    API 层 (Handler)                  │
│  接收 HTTP 请求，解析参数，调用 Service              │
│  组装响应，不包含业务逻辑                            │
│  文件: api/v1/{module}/xxx.go                       │
└────────────────────┬────────────────────────────────┘
                     │ 调用
┌────────────────────▼────────────────────────────────┐
│                    Service 层                        │
│  核心业务逻辑，数据库 CRUD 操作                      │
│  事务管理，数据校验                                  │
│  文件: service/{module}/xxx.go                      │
└────────────────────┬────────────────────────────────┘
                     │ 操作
┌────────────────────▼────────────────────────────────┐
│                    Model 层                          │
│  数据库表结构定义（GORM struct）                     │
│  Request DTO / Response DTO                         │
│  文件: model/{module}/xxx.go                        │
│  文件: model/{module}/request/ 和 response/          │
└─────────────────────────────────────────────────────┘
```

---

## 2. 每层的职责和规范

### 2.1 Router 层

**位置**: `server/router/{module}/`

**职责**:
- 定义 URL 路径和 HTTP 方法
- 将路由绑定到 API 层的 Handler 函数
- 分配中间件（如操作记录 `middleware.OperationRecord()`）
- 区分 PrivateGroup（需鉴权）和 PublicGroup（公开）

**规范**:
- 每个资源一个文件，如 `sys_dictionary.go`
- Router struct 命名：`{Resource}Router`，如 `DictionaryRouter`
- 初始化方法命名：`Init{Resource}Router(Router, PublicGroup)`
- 写操作（POST/PUT/DELETE）通常使用 `middleware.OperationRecord()` 记录
- 读操作不需要操作记录中间件

**典型代码结构**:

```go
type DictionaryRouter struct{}

func (s *DictionaryRouter) InitSysDictionaryRouter(Router *gin.RouterGroup, PublicGroup *gin.RouterGroup) {
    // 需要操作记录的路由组
    sysDictionaryRouter := Router.Group("sysDictionary").Use(middleware.OperationRecord())
    // 不需要操作记录的路由组
    sysDictionaryRouterWithoutRecord := Router.Group("sysDictionary")
    {
        sysDictionaryRouter.POST("createSysDictionary", dictionaryApi.CreateSysDictionary)
        sysDictionaryRouter.DELETE("deleteSysDictionary", dictionaryApi.DeleteSysDictionary)
        sysDictionaryRouter.PUT("updateSysDictionary", dictionaryApi.UpdateSysDictionary)
    }
    {
        publicRouter := PublicGroup.Group("sysDictionary")
        publicRouter.GET("findSysDictionary", dictionaryApi.FindSysDictionary)
        sysDictionaryRouterWithoutRecord.GET("getSysDictionaryList", dictionaryApi.GetSysDictionaryList)
    }
}
```

### 2.2 API 层 (Handler)

**位置**: `server/api/v1/{module}/`

**职责**:
- 接收 HTTP 请求
- 参数绑定和初步校验（`ShouldBindJSON` / `ShouldBindQuery`）
- 调用 Service 层方法
- 使用 `response` 包统一返回结果
- 记录错误日志

**规范**:
- 每个资源一个文件，如 `sys_dictionary.go`
- API struct 命名：`{Resource}Api`，如 `DictionaryApi`
- **不包含任何业务逻辑**，只做参数解析和结果转发
- 使用 Swagger 注释标注接口文档
- 错误时先记录日志 `global.HAB_LOG.Error()`，再返回错误响应

**典型代码结构**:

```go
type DictionaryApi struct{}

func (s *DictionaryApi) CreateSysDictionary(c *gin.Context) {
    // 1. 参数绑定
    var dictionary system.SysDictionary
    err := c.ShouldBindJSON(&dictionary)
    if err != nil {
        response.FailWithMessage(err.Error(), c)
        return
    }
    // 2. 调用 Service
    err = dictionaryService.CreateSysDictionary(dictionary)
    if err != nil {
        // 3. 错误日志 + 错误响应
        global.HAB_LOG.Error("创建失败!", zap.Error(err))
        response.FailWithMessage("Creation failed", c)
        return
    }
    // 4. 成功响应
    response.OkWithMessage("Success", c)
}
```

### 2.3 Service 层

**位置**: `server/service/{module}/`

**职责**:
- 实现核心业务逻辑
- 执行数据库 CRUD 操作（通过 `global.HAB_DB`）
- 数据校验（如唯一性检查）
- 事务管理

**规范**:
- 每个资源一个文件，如 `sys_dictionary.go`
- Service struct 命名：`{Resource}Service`，如 `DictionaryService`
- 通过 `global.HAB_DB` 直接操作数据库（不使用额外的 DAO 层）
- 返回值统一为 `(err error)` 或 `(data T, err error)`

**典型代码结构**:

```go
type DictionaryService struct{}

func (dictionaryService *DictionaryService) CreateSysDictionary(sysDictionary system.SysDictionary) (err error) {
    // 唯一性校验
    if !errors.Is(global.HAB_DB.First(&system.SysDictionary{}, "type = ?", sysDictionary.Type).Error, gorm.ErrRecordNotFound) {
        return errors.New("存在相同的type，不允许创建")
    }
    // 执行创建
    err = global.HAB_DB.Create(&sysDictionary).Error
    return err
}
```

### 2.4 Model 层

**位置**: `server/model/{module}/`

**职责**:
- 定义数据库表结构（GORM struct）
- 定义 Request DTO（在 `request/` 子目录）
- 定义 Response DTO（在 `response/` 子目录）

**规范**:
- 实体 struct 继承 `global.HAB_MODEL`（提供 ID + 时间戳 + 软删除）
- 使用 GORM tag 定义列名和注释
- 使用 JSON tag 定义序列化字段名
- 使用 `form` tag 支持 query 参数绑定
- 实现 `TableName()` 方法指定表名

**典型代码结构**:

```go
type SysDictionary struct {
    global.HAB_MODEL
    Name                 string                `json:"name" form:"name" gorm:"column:name;comment:字典名（中）"`
    Type                 string                `json:"type" form:"type" gorm:"column:type;comment:字典名（英）"`
    Status               *bool                 `json:"status" form:"status" gorm:"column:status;comment:状态"`
    Desc                 string                `json:"desc" form:"desc" gorm:"column:desc;comment:描述"`
    SysDictionaryDetails []SysDictionaryDetail `json:"sysDictionaryDetails" form:"sysDictionaryDetails"`
}

func (SysDictionary) TableName() string {
    return "sys_dictionaries"
}
```

---

## 3. enter.go 注册机制详解

每层都有一个 `enter.go` 文件，通过 struct 嵌套和全局变量实现层间串联。这是整个框架的核心组织模式。

### 3.1 三个全局入口变量

```
api/v1/enter.go       → var ApiGroupApp = new(ApiGroup)
router/enter.go       → var RouterGroupApp = new(RouterGroup)
service/enter.go      → var ServiceGroupApp = new(ServiceGroup)
```

### 3.2 顶层 enter.go 的结构

**api/v1/enter.go** — 聚合所有模块的 ApiGroup：

```go
var ApiGroupApp = new(ApiGroup)

type ApiGroup struct {
    SystemApiGroup   system.ApiGroup
    BusinessApiGroup business.ApiGroup
    ApiApiGroup      api.ApiGroup
}
```

**router/enter.go** — 聚合所有模块的 RouterGroup：

```go
var RouterGroupApp = new(RouterGroup)

type RouterGroup struct {
    System   system.RouterGroup
    Business business.RouterGroup
    Api      api.RouterGroup
}
```

**service/enter.go** — 聚合所有模块的 ServiceGroup：

```go
var ServiceGroupApp = new(ServiceGroup)

type ServiceGroup struct {
    SystemServiceGroup   system.ServiceGroup
    BusinessServiceGroup business.ServiceGroup
}
```

### 3.3 模块级 enter.go 的结构

以 system 模块为例，每层的 `enter.go` 将该模块所有资源的 struct 嵌入到一个 Group struct 中：

**api/v1/system/enter.go**:

```go
type ApiGroup struct {
    DBApi
    JwtApi
    DictionaryApi
    // ... 所有 system 模块的 API struct
}

// 包级变量引用 Service 层
var (
    dictionaryService = service.ServiceGroupApp.SystemServiceGroup.DictionaryService
    userService       = service.ServiceGroupApp.SystemServiceGroup.UserService
    // ...
)
```

**router/system/enter.go**:

```go
type RouterGroup struct {
    DictionaryRouter
    UserRouter
    // ... 所有 system 模块的 Router struct
}

// 包级变量引用 API 层
var (
    dictionaryApi = api.ApiGroupApp.SystemApiGroup.DictionaryApi
    // ...
)
```

**service/system/enter.go**:

```go
type ServiceGroup struct {
    DictionaryService
    UserService
    // ... 所有 system 模块的 Service struct
}
```

### 3.4 串联关系图

```
initialize/router.go
  │
  ├── router.RouterGroupApp.System.InitSysDictionaryRouter(...)
  │         │
  │         └── router/system/enter.go
  │               └── dictionaryApi = api.ApiGroupApp.SystemApiGroup.DictionaryApi
  │                                         │
  │                                         └── api/v1/system/enter.go
  │                                               └── dictionaryService = service.ServiceGroupApp.SystemServiceGroup.DictionaryService
  │                                                                              │
  │                                                                              └── service/system/enter.go
  │                                                                                    └── DictionaryService struct
```

这种设计的优点：
- **零耦合注册**: 新增模块只需在对应层的 enter.go 中添加一行嵌入
- **统一访问**: 任何地方都可以通过 `service.ServiceGroupApp.XXX` 访问服务
- **零初始化**: 使用 `new()` 创建空 struct，所有方法都是值接收者，无需构造函数

---

## 4. 新增业务模块时每层要做什么

以新增一个 `Article` 模块为例，需要在四层分别操作：

### 4.1 Model 层

创建 `model/business/article.go`:

```go
package business

import "hab/global"

type Article struct {
    global.HAB_MODEL
    Title   string `json:"title" gorm:"column:title;comment:标题"`
    Content string `json:"content" gorm:"column:content;type:text;comment:内容"`
    Status  int    `json:"status" gorm:"column:status;default:1;comment:状态"`
}

func (Article) TableName() string {
    return "biz_articles"
}
```

如需分页查询，在 `model/business/request/` 中创建请求 DTO:

```go
package request

import "hab/model/common/request"

type ArticleSearch struct {
    request.PageInfo
    Title  string `json:"title" form:"title"`
    Status *int   `json:"status" form:"status"`
}
```

### 4.2 Service 层

创建 `service/business/article.go`:

```go
package business

type ArticleService struct{}

func (s *ArticleService) CreateArticle(article business.Article) error {
    return global.HAB_DB.Create(&article).Error
}
// ... 其他 CRUD 方法
```

在 `service/business/enter.go` 中注册:

```go
type ServiceGroup struct {
    ArticleService  // 添加这一行
}
```

### 4.3 API 层

创建 `api/v1/business/article.go`:

```go
package business

type ArticleApi struct{}

func (a *ArticleApi) CreateArticle(c *gin.Context) {
    // 参数绑定 → 调用 service → 返回响应
}
```

在 `api/v1/business/enter.go` 中注册:

```go
type ApiGroup struct {
    ArticleApi  // 添加这一行
}

var (
    articleService = service.ServiceGroupApp.BusinessServiceGroup.ArticleService
)
```

### 4.4 Router 层

创建 `router/business/article.go`:

```go
package business

type ArticleRouter struct{}

func (r *ArticleRouter) InitArticleRouter(Router *gin.RouterGroup, PublicGroup *gin.RouterGroup) {
    articleRouter := Router.Group("article").Use(middleware.OperationRecord())
    {
        articleRouter.POST("createArticle", articleApi.CreateArticle)
        articleRouter.DELETE("deleteArticle", articleApi.DeleteArticle)
        articleRouter.PUT("updateArticle", articleApi.UpdateArticle)
    }
    {
        Router.Group("article").GET("getArticleList", articleApi.GetArticleList)
    }
}
```

在 `router/business/enter.go` 中注册:

```go
type RouterGroup struct {
    ArticleRouter  // 添加这一行
}

var (
    articleApi = api.ApiGroupApp.BusinessApiGroup.ArticleApi
)
```

### 4.5 路由注册

在 `initialize/router_biz.go` 中添加路由初始化调用:

```go
businessRouter.InitArticleRouter(PrivateGroup, PublicGroup)
```

### 4.6 数据库迁移

在 `initialize/ensure_tables.go` 中添加自动迁移。

---

## 5. Request/Response 模型规范

### 5.1 通用 Request 模型

定义在 `model/common/request/common.go`，所有分页查询复用：

```go
// 分页请求
type PageInfo struct {
    Page     int    `json:"page" form:"page"`         // 页码
    PageSize int    `json:"pageSize" form:"pageSize"` // 每页大小
    Keyword  string `json:"keyword" form:"keyword"`   // 关键字
}

// ID 查询
type GetById struct {
    ID int `json:"id" form:"id"`
}

// 批量 ID 操作
type IdsReq struct {
    Ids []int `json:"ids" form:"ids"`
}

// 通用查询信息（分页 + 搜索 + 排序）
type QueryInfo struct {
    PageInfo   *PageInfo              `json:"pageInfo" form:"pageInfo"`
    SearchInfo map[string]*SearchInfo `json:"searchInfo" form:"searchInfo"`
    SortInfo   map[string]*SortInfo   `json:"sortInfo" form:"sortInfo"`
}
```

`PageInfo` 还提供 `Paginate()` 方法，可直接作为 GORM Scope 使用：

```go
// Service 层使用方式
db.Scopes(info.Paginate()).Find(&list)
```

### 5.2 模块级 Request 模型

在 `model/{module}/request/` 中定义，嵌入通用 `PageInfo` 并添加模块特有字段：

```go
type SysDictionaryDetailSearch struct {
    request.PageInfo
    SysDictionaryID int `json:"sysDictionaryID" form:"sysDictionaryID"`
}
```

### 5.3 通用 Response 模型

`model/common/response/common.go` 定义分页响应结构:

```go
type PageResult struct {
    List     interface{} `json:"list"`
    Total    int64       `json:"total"`
    Page     int         `json:"page"`
    PageSize int         `json:"pageSize"`
    SumInfo  any         `json:"sumInfo"`
}
```

### 5.4 模块级 Response 模型

在 `model/{module}/response/` 中定义接口特有的返回结构，用于需要聚合多个数据源或转换格式的场景。

---

## 6. 通用响应格式

所有接口通过 `model/common/response/response.go` 中的工具函数统一返回。

### 6.1 响应结构体

```go
type Response struct {
    Code    int         `json:"code"`
    Data    interface{} `json:"data"`
    Message string      `json:"msg"`
}
```

### 6.2 可用的响应工具函数

| 函数 | 用途 | 示例场景 |
|------|------|----------|
| `Ok(c)` | 无数据的成功响应 | — |
| `OkWithMessage(msg, c)` | 带消息的成功响应 | 创建/更新/删除成功 |
| `OkWithData(data, c)` | 带数据的成功响应 | 查询单条记录 |
| `OkWithDetailed(data, msg, c)` | 带数据和消息的成功响应 | 查询列表 |
| `FailWithMessage(msg, c)` | 带消息的失败响应 | 通用错误提示 |
| `FailWithMessageData(msg, data, c)` | 带消息和数据的失败响应 | 错误时返回额外信息 |
| `FailWithDetailed(data, msg, c)` | 带数据和消息的失败响应 | 同上 |
| `FailWithErr(err, c)` | 从 error 提取 code 和 msg | 使用 CodeMsg 错误体系时 |
| `FailWithErrData(err, data, c)` | 从 error 提取 code 并附带数据 | — |
| `FailWithCodeMessage(code, msg, c)` | 指定错误码的失败响应 | 精确控制错误码 |
| `NoAuth(msg, c)` | 401 未授权响应 | Token 过期或无效 |

### 6.3 错误码体系

定义在 `code/code.go`：

```go
type Code int

const (
    CodeSuccess       Code = 0     // 成功
    CodeError         Code = 7     // 通用错误
    CodeUserError     Code = 1000  // 用户错误
    CodeCommonError   Code = 1001  // 通用错误
    CodeBusinessError Code = 1002  // 业务错误
    CodeAccountError  Code = 1003  // 账户错误
)
```

`CodeMsg` 实现了 `error` 接口，可以在 Service 层创建带错误码的 error：

```go
// Service 层返回带错误码的错误
return code.NewError(code.CodeBusinessError, "库存不足")

// API 层用 FailWithErr 自动提取 code
response.FailWithErr(err, c)
// 响应: {"code": 1002, "data": null, "msg": "库存不足"}
```

### 6.4 标准使用模式

```go
// 创建操作 — 只返回消息
response.OkWithMessage("Success", c)

// 查询单条 — 返回数据 + 消息
response.OkWithDetailed(gin.H{"resysDictionary": sysDictionary}, "ok", c)

// 查询列表 — 返回 PageResult
response.OkWithDetailed(response.PageResult{
    List:     list,
    Total:    total,
    Page:     pageInfo.Page,
    PageSize: pageInfo.PageSize,
}, "Success", c)

// 错误 — 记录日志 + 返回错误消息
global.HAB_LOG.Error("创建失败!", zap.Error(err))
response.FailWithMessage("Creation failed", c)
```

---

## 7. 完整 CRUD 示例：SysDictionary（字典管理）

以下是字典管理模块的完整四层代码，展示了一个标准 CRUD 模块的实现方式。

### 7.1 Model 层 — `model/system/sys_dictionary.go`

```go
package system

import "hab/global"

type SysDictionary struct {
    global.HAB_MODEL
    Name                 string                `json:"name" form:"name" gorm:"column:name;comment:字典名（中）"`
    Type                 string                `json:"type" form:"type" gorm:"column:type;comment:字典名（英）"`
    Status               *bool                 `json:"status" form:"status" gorm:"column:status;comment:状态"`
    Desc                 string                `json:"desc" form:"desc" gorm:"column:desc;comment:描述"`
    SysDictionaryDetails []SysDictionaryDetail `json:"sysDictionaryDetails" form:"sysDictionaryDetails"`
}

func (SysDictionary) TableName() string {
    return "sys_dictionaries"
}
```

### 7.2 Service 层 — `service/system/sys_dictionary.go`

```go
package system

type DictionaryService struct{}

// 创建 — 先校验唯一性再插入
func (s *DictionaryService) CreateSysDictionary(sysDictionary system.SysDictionary) (err error) {
    if !errors.Is(global.HAB_DB.First(&system.SysDictionary{}, "type = ?", sysDictionary.Type).Error, gorm.ErrRecordNotFound) {
        return errors.New("存在相同的type，不允许创建")
    }
    return global.HAB_DB.Create(&sysDictionary).Error
}

// 删除 — 级联删除关联的 DictionaryDetails
func (s *DictionaryService) DeleteSysDictionary(sysDictionary system.SysDictionary) (err error) {
    err = global.HAB_DB.Where("id = ?", sysDictionary.ID).Preload("SysDictionaryDetails").First(&sysDictionary).Error
    if err != nil {
        return err
    }
    if err = global.HAB_DB.Delete(&sysDictionary).Error; err != nil {
        return err
    }
    if sysDictionary.SysDictionaryDetails != nil {
        return global.HAB_DB.Where("sys_dictionary_id=?", sysDictionary.ID).Delete(sysDictionary.SysDictionaryDetails).Error
    }
    return
}

// 更新 — 用 map 避免零值问题
func (s *DictionaryService) UpdateSysDictionary(sysDictionary *system.SysDictionary) (err error) {
    var dict system.SysDictionary
    sysDictionaryMap := map[string]interface{}{
        "Name": sysDictionary.Name, "Type": sysDictionary.Type,
        "Status": sysDictionary.Status, "Desc": sysDictionary.Desc,
    }
    if err = global.HAB_DB.Where("id = ?", sysDictionary.ID).First(&dict).Error; err != nil {
        return errors.New("查询字典数据失败")
    }
    if dict.Type != sysDictionary.Type {
        if !errors.Is(global.HAB_DB.First(&system.SysDictionary{}, "type = ?", sysDictionary.Type).Error, gorm.ErrRecordNotFound) {
            return errors.New("存在相同的type，不允许创建")
        }
    }
    return global.HAB_DB.Model(&dict).Updates(sysDictionaryMap).Error
}

// 查询单条 — 支持按 ID 或 Type 查询，预加载关联
func (s *DictionaryService) GetSysDictionary(Type string, Id uint, status *bool) (sysDictionary system.SysDictionary, err error) {
    flag := status == nil || *status
    err = global.HAB_DB.Where("(type = ? OR id = ?) and status = ?", Type, Id, flag).
        Preload("SysDictionaryDetails", func(db *gorm.DB) *gorm.DB {
            return db.Where("status = ?", true).Order("sort")
        }).First(&sysDictionary).Error
    return
}

// 查询列表 — 全量返回
func (s *DictionaryService) GetSysDictionaryInfoList() (list interface{}, err error) {
    var sysDictionarys []system.SysDictionary
    err = global.HAB_DB.Find(&sysDictionarys).Error
    return sysDictionarys, err
}
```

### 7.3 API 层 — `api/v1/system/sys_dictionary.go`

```go
package system

type DictionaryApi struct{}

// @Router /sysDictionary/createSysDictionary [post]
func (s *DictionaryApi) CreateSysDictionary(c *gin.Context) {
    var dictionary system.SysDictionary
    if err := c.ShouldBindJSON(&dictionary); err != nil {
        response.FailWithMessage(err.Error(), c)
        return
    }
    if err := dictionaryService.CreateSysDictionary(dictionary); err != nil {
        global.HAB_LOG.Error("创建失败!", zap.Error(err))
        response.FailWithMessage("Creation failed", c)
        return
    }
    response.OkWithMessage("Success", c)
}

// @Router /sysDictionary/deleteSysDictionary [delete]
func (s *DictionaryApi) DeleteSysDictionary(c *gin.Context) {
    var dictionary system.SysDictionary
    if err := c.ShouldBindJSON(&dictionary); err != nil {
        response.FailWithMessage(err.Error(), c)
        return
    }
    if err := dictionaryService.DeleteSysDictionary(dictionary); err != nil {
        global.HAB_LOG.Error("删除失败!", zap.Error(err))
        response.FailWithMessage("Deletion failed", c)
        return
    }
    response.OkWithMessage("Success", c)
}

// @Router /sysDictionary/updateSysDictionary [put]
func (s *DictionaryApi) UpdateSysDictionary(c *gin.Context) {
    var dictionary system.SysDictionary
    if err := c.ShouldBindJSON(&dictionary); err != nil {
        response.FailWithMessage(err.Error(), c)
        return
    }
    if err := dictionaryService.UpdateSysDictionary(&dictionary); err != nil {
        global.HAB_LOG.Error("更新失败!", zap.Error(err))
        response.FailWithMessage("Update failed", c)
        return
    }
    response.OkWithMessage("Success", c)
}

// @Router /sysDictionary/findSysDictionary [get]
func (s *DictionaryApi) FindSysDictionary(c *gin.Context) {
    var dictionary system.SysDictionary
    if err := c.ShouldBindQuery(&dictionary); err != nil {
        response.FailWithMessage(err.Error(), c)
        return
    }
    sysDictionary, err := dictionaryService.GetSysDictionary(dictionary.Type, dictionary.ID, dictionary.Status)
    if err != nil {
        global.HAB_LOG.Error("字典未创建或未开启!", zap.Error(err))
        response.FailWithMessage("Dictionary not created or not opened", c)
        return
    }
    response.OkWithDetailed(gin.H{"resysDictionary": sysDictionary}, "ok", c)
}

// @Router /sysDictionary/getSysDictionaryList [get]
func (s *DictionaryApi) GetSysDictionaryList(c *gin.Context) {
    list, err := dictionaryService.GetSysDictionaryInfoList()
    if err != nil {
        global.HAB_LOG.Error("获取失败!", zap.Error(err))
        response.FailWithMessage("Failed to get", c)
        return
    }
    response.OkWithDetailed(list, "Success", c)
}
```

### 7.4 Router 层 — `router/system/sys_dictionary.go`

```go
package system

type DictionaryRouter struct{}

func (s *DictionaryRouter) InitSysDictionaryRouter(Router *gin.RouterGroup, PublicGroup *gin.RouterGroup) {
    sysDictionaryRouter := Router.Group("sysDictionary").Use(middleware.OperationRecord())
    sysDictionaryRouterWithoutRecord := Router.Group("sysDictionary")
    {
        sysDictionaryRouter.POST("createSysDictionary", dictionaryApi.CreateSysDictionary)
        sysDictionaryRouter.DELETE("deleteSysDictionary", dictionaryApi.DeleteSysDictionary)
        sysDictionaryRouter.PUT("updateSysDictionary", dictionaryApi.UpdateSysDictionary)
    }
    {
        publicRouter := PublicGroup.Group("sysDictionary")
        publicRouter.GET("findSysDictionary", dictionaryApi.FindSysDictionary)
        sysDictionaryRouterWithoutRecord.GET("getSysDictionaryList", dictionaryApi.GetSysDictionaryList)
    }
}
```

### 7.5 enter.go 注册（每层各一行）

```go
// api/v1/system/enter.go
type ApiGroup struct {
    DictionaryApi  // ← 嵌入
    // ...
}
var dictionaryService = service.ServiceGroupApp.SystemServiceGroup.DictionaryService

// router/system/enter.go
type RouterGroup struct {
    DictionaryRouter  // ← 嵌入
    // ...
}
var dictionaryApi = api.ApiGroupApp.SystemApiGroup.DictionaryApi

// service/system/enter.go
type ServiceGroup struct {
    DictionaryService  // ← 嵌入
    // ...
}
```

### 7.6 路由注册调用

在 `initialize/router.go` 的 `Routers()` 函数中：

```go
systemRouter.InitSysDictionaryRouter(PrivateGroup, PublicGroup)
```

### 7.7 最终生成的 API 端点

| 方法 | 路径 | 鉴权 | 操作记录 |
|------|------|------|----------|
| POST | /sysDictionary/createSysDictionary | JWT + Casbin | 是 |
| DELETE | /sysDictionary/deleteSysDictionary | JWT + Casbin | 是 |
| PUT | /sysDictionary/updateSysDictionary | JWT + Casbin | 是 |
| GET | /sysDictionary/findSysDictionary | 公开 | 否 |
| GET | /sysDictionary/getSysDictionaryList | JWT + Casbin | 否 |
