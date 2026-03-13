# 插件系统参考文档

## 1. 插件系统架构概览

系统提供两个版本的插件架构（v1 / v2），均基于 Gin 框架的路由机制实现模块化扩展。插件是独立于主业务代码（package 模式）之外的第二种代码组织方式，拥有自包含的 api/service/model/router/config/initialize 层级。

### 核心组件

| 组件 | 路径 | 职责 |
|------|------|------|
| v1 Plugin 接口 | `server/utils/plugin/plugin.go` | 定义 v1 插件的 Register + RouterPath |
| v2 Plugin 接口 | `server/utils/plugin/v2/plugin.go` | 定义 v2 插件的 Register（接收 Engine） |
| 插件初始化入口 | `server/initialize/plugin.go` | 统一调度 v1 和 v2 注册 |
| v1 业务注册 | `server/initialize/plugin_biz_v1.go` | v1 插件挂载点 |
| v2 业务注册 | `server/initialize/plugin_biz_v2.go` | v2 插件挂载点 |
| 插件安装/打包 Service | `server/service/system/auto_code_plugin.go` | zip 安装、打包、InitMenu、InitAPI |
| 插件 API Handler | `server/api/v1/system/auto_code_plugin.go` | 安装/打包/InitMenu/InitAPI 接口 |
| 插件模板文件 | `server/resource/plugin/` | AutoCode 生成插件时使用的模板 |
| AST 注入工具集 | `server/utils/ast/plugin_*.go` | 通过 AST 操作自动修改 Go 源码注册插件 |
| 路由注册 | `server/router/system/sys_auto_code.go` | 插件相关 API 路由定义 |

### 插件系统启动流程

```
main.go
  └→ initialize.Routers()
       ├→ InstallPlugin(PrivateGroup, PublicGroup, Router)  // 当前默认被注释
       │    ├→ bizPluginV1(PrivateGroup, PublicRouter)
       │    │    └→ holder(group...)  // 在此添加 v1 插件调用
       │    └→ bizPluginV2(engine)
       │         └→ PluginInitV2(engine, plugin.Plugin)  // 在此添加 v2 插件调用
       └→ initBizRouter(PrivateGroup, PublicGroup)  // 主业务路由
```

**重要**：在当前项目模板中，`InstallPlugin` 调用在 `router.go` 第 113 行被注释掉了：
```go
//InstallPlugin(PrivateGroup, PublicGroup, Router)
```
如果使用插件系统，需要取消该注释。

## 2. 插件版本（v1 vs v2）区别

### v1 插件

接口定义（`server/utils/plugin/plugin.go`）：
```go
type Plugin interface {
    Register(group *gin.RouterGroup)  // 接收路由组
    RouterPath() string               // 返回路由前缀
}
```

特点：
- 接收 `*gin.RouterGroup`，只能在指定的路由组下注册路由
- 需要实现 `RouterPath()` 方法返回路由前缀（如 `/email`）
- 通过 `PluginInit()` 函数注册，自动创建子路由组
- 注册入口在 `bizPluginV1()` -> `holder()` 函数中
- 所有路由共享同一个鉴权层（PrivateGroup 或 PublicGroup）

注册方式：
```go
// server/initialize/plugin_biz_v1.go
func PluginInit(group *gin.RouterGroup, Plugin ...plugin.Plugin) {
    for i := range Plugin {
        PluginGroup := group.Group(Plugin[i].RouterPath())
        Plugin[i].Register(PluginGroup)
    }
}

func bizPluginV1(group ...*gin.RouterGroup) {
    holder(group...)
}
```

### v2 插件

接口定义（`server/utils/plugin/v2/plugin.go`）：
```go
type Plugin interface {
    Register(group *gin.Engine)  // 接收完整 Engine
}
```

特点：
- 接收完整的 `*gin.Engine`，可以自由注册任意路由
- 不需要 `RouterPath()` 方法
- 可以自行管理 public/private 路由分组和中间件
- 通过 `PluginInitV2()` 函数注册
- **当前系统主要使用 v2 版本**，插件模板默认生成 v2 格式

注册方式：
```go
// server/initialize/plugin_biz_v2.go
func PluginInitV2(group *gin.Engine, plugins ...plugin.Plugin) {
    for i := 0; i < len(plugins); i++ {
        plugins[i].Register(group)
    }
}

func bizPluginV2(engine *gin.Engine) {
    // 在此添加 v2 插件注册
}
```

### 版本选择建议

| 场景 | 推荐版本 | 原因 |
|------|---------|------|
| 简单插件，路由统一在某前缀下 | v1 | 接口简单，自动管理路由分组 |
| 需要同时有公开和鉴权路由 | v2 | 可自行创建 public/private 分组 |
| 需要自定义中间件链 | v2 | 完全控制 Engine |
| 新项目 | v2 | 系统默认模板、AutoCode 均面向 v2 |

## 3. 插件模板结构

插件通过 AutoCode 系统创建，模板文件位于 `server/resource/plugin/`。

### Server 端模板（20 个文件）

```
server/resource/plugin/server/
  plugin.go.template              # 插件主入口（实现 v2 Plugin 接口）
  plugin/
    plugin.go.template            # 插件配置变量定义（var Config config.Config）
  config/
    config.go.template            # 配置结构体定义（空壳，按需填充）
  initialize/
    router.go.template            # 路由初始化（自动创建 public + private 分组）
    gorm.go.template              # 数据库表自动迁移（AutoMigrate 空壳）
    api.go.template               # API 权限初始化数据（使用 plugin-tool/utils）
    menu.go.template              # 菜单初始化数据（使用 plugin-tool/utils）
    viper.go.template             # 配置文件读取（从 config.yaml 读取）
  model/
    model.go.template             # 数据模型定义（含 GORM tag）
    request/
      request.go.template         # 请求/搜索参数结构体
  api/
    api.go.template               # API Handler（完整 CRUD + Swagger 注释）
    enter.go.template             # API 入口聚合（var Api = new(api)）
  service/
    service.go.template           # 业务逻辑层（完整 CRUD 实现）
    enter.go.template             # Service 入口聚合
  router/
    router.go.template            # 路由定义（public/private/操作记录中间件）
    enter.go.template             # Router 入口聚合
  gen/
    gen.go.template               # gorm gen 代码生成配置
```

### Web 端模板（3 个文件）

```
server/resource/plugin/web/
  api/
    api.js.template               # 前端 API 调用封装（axios request）
  view/
    view.vue.template             # Vue 页面组件（表格 + 搜索 + CRUD 完整页面）
  form/
    form.vue.template             # 表单组件（新建/编辑共用）
```

### 插件主入口模板详解

`plugin.go.template` 生成的文件实现 v2 Plugin 接口：

```go
package myPlugin

import (
    "context"
    "hab/plugin/myPlugin/initialize"
    interfaces "hab/utils/plugin/v2"
    "github.com/gin-gonic/gin"
)

var _ interfaces.Plugin = (*plugin)(nil)  // 编译期接口检查
var Plugin = new(plugin)                   // 导出的插件实例

type plugin struct{}

func (p *plugin) Register(group *gin.Engine) {
    ctx := context.Background()
    initialize.Gorm(ctx)         // 数据库迁移
    initialize.Router(group)     // 注册路由
    // initialize.Viper()        // 可选：加载配置
    // initialize.Api(ctx)       // 可选：注册 API 权限
    // initialize.Menu(ctx)      // 可选：注册菜单
}
```

### 路由初始化模板详解

`initialize/router.go.template` 自动划分公开和鉴权路由：

```go
func Router(engine *gin.Engine) {
    public := engine.Group(global.HAB_CONFIG.System.RouterPrefix).Group("")
    public.Use()
    private := engine.Group(global.HAB_CONFIG.System.RouterPrefix).Group("")
    private.Use(middleware.JWTAuth()).Use(middleware.CasbinHandler())
    // 生成的 router 会在这里调用各个路由注册函数
}
```

### 路由定义模板详解

`router/router.go.template` 按 CRUD 操作分组路由：

```go
func (r *myStruct) Init(public *gin.RouterGroup, private *gin.RouterGroup) {
    // 写操作 — 带 OperationRecord 中间件
    {
        group := private.Group("myAbbr").Use(middleware.OperationRecord())
        group.POST("createMyStruct", apiMyStruct.CreateMyStruct)
        group.DELETE("deleteMyStruct", apiMyStruct.DeleteMyStruct)
        group.DELETE("deleteMyStructByIds", apiMyStruct.DeleteMyStructByIds)
        group.PUT("updateMyStruct", apiMyStruct.UpdateMyStruct)
    }
    // 读操作 — 无额外中间件
    {
        group := private.Group("myAbbr")
        group.GET("findMyStruct", apiMyStruct.FindMyStruct)
        group.GET("getMyStructList", apiMyStruct.GetMyStructList)
    }
    // 公开接口 — 无鉴权
    {
        group := public.Group("myAbbr")
        group.GET("getMyStructPublic", apiMyStruct.GetMyStructPublic)
    }
}
```

## 4. AST 自动注入机制

AutoCode 生成插件代码后，系统通过 Go AST 操作自动修改现有源文件来完成注册。这是插件系统最核心的技术实现。

### AST 操作类型体系

定义在 `server/utils/ast/ast_type.go` 中：

| 类型常量 | 对应文件 | 操作说明 |
|---------|---------|---------|
| `TypePluginGen` | `server/plugin/{pkg}/gen/main.go` | 向 gen 的 ApplyBasic 添加模型 |
| `TypePluginApiEnter` | `server/plugin/{pkg}/enter.go` | 向 enter 结构体添加 API 字段 |
| `TypePluginRouterEnter` | `server/plugin/{pkg}/enter.go` | 向 enter 结构体添加 Router 字段 |
| `TypePluginServiceEnter` | `server/plugin/{pkg}/enter.go` | 向 enter 结构体添加 Service 字段 |
| `TypePluginInitializeV1` | `server/initialize/plugin_biz_v1.go` | 向 v1 注册函数添加调用 |
| `TypePluginInitializeV2` | `server/initialize/plugin_biz_v2.go` | 向 v2 注册函数添加调用 |
| `TypePluginInitializeGorm` | `server/plugin/{pkg}/initialize/gorm.go` | 向 AutoMigrate 添加模型参数 |
| `TypePluginInitializeRouter` | `server/plugin/{pkg}/initialize/router.go` | 向路由初始化添加调用 |
| `TypePluginInitializeApi` | `server/plugin/{pkg}/initialize/api.go` | API 权限数据 |
| `TypePluginInitializeMenu` | `server/plugin/{pkg}/initialize/menu.go` | 菜单数据 |

### AST 操作器

每个操作器都实现统一的 Parse -> Injection/Rollback -> Format 流程：

#### PluginEnter（`server/utils/ast/plugin_enter.go`）

管理插件的 enter.go 文件，处理结构体字段注入和变量声明：

```go
type PluginEnter struct {
    Type            Type    // TypePluginApiEnter / TypePluginRouterEnter / TypePluginServiceEnter
    Path            string  // enter.go 文件路径
    ImportPath      string  // 导入路径
    StructName      string  // 要添加的结构体字段名
    StructCamelName string  // 字段类型（小驼峰）
    ModuleName      string  // 变量名（如 PackageName.GroupName.ServiceName）
    GroupName       string  // 分组名
    PackageName     string  // 包名
    ServiceName     string  // 服务名
}
```

Injection 操作：
1. 添加 import 语句
2. 向第一个 struct 添加字段 `StructName StructCamelName`
3. 如果不是 ServiceEnter 类型，还会添加变量声明 `var ModuleName = PackageName.GroupName.ServiceName`

#### PluginInitializeRouter（`server/utils/ast/plugin_initialize_router.go`）

向路由初始化函数中注入路由注册调用：

```go
type PluginInitializeRouter struct {
    AppName              string  // 应用名称
    GroupName            string  // 分组名称
    PackageName          string  // 包名
    FunctionName         string  // 函数名
    LeftRouterGroupName  string  // 左路由组（如 PrivateGroup）
    RightRouterGroupName string  // 右路由组（如 PublicGroup）
}
```

注入的代码形如：`PackageName.AppName.GroupName.FunctionName(LeftGroup, RightGroup)`

#### PluginInitializeGorm（`server/utils/ast/plugin_initialize_gorm.go`）

向 `AutoMigrate()` 调用中添加模型参数：

```go
type PluginInitializeGorm struct {
    StructName  string  // 模型结构体名
    PackageName string  // 模型所在包名
    IsNew       bool    // true: new(pkg.Model) / false: &pkg.Model{}
}
```

#### PluginInitializeV2（`server/utils/ast/plugin_initialize_v2.go`）

向 `bizPluginV2()` 函数中注入 v2 插件注册调用：

```go
type PluginInitializeV2 struct {
    PluginPath  string  // plugin_biz_v2.go 路径
    ImportPath  string  // 插件导入路径
    PackageName string  // 插件包名
}
```

注入的代码：`PluginInitV2(engine, packageName.Plugin)`

#### PluginGen（`server/utils/ast/plugin_gen.go`）

向 gorm gen 的 `ApplyBasic()` 调用中添加模型：

```go
type PluginGen struct {
    StructName  string  // 模型名
    PackageName string  // 包名
    IsNew       bool    // 使用 new() 还是 &Type{}
}
```

### AST 注入 vs 回滚

所有 AST 操作器都支持双向操作：
- **Injection**：向目标文件注入代码（创建时调用）
- **Rollback**：从目标文件移除注入的代码（回滚/删除时调用）

回滚机制保证了代码生成的可逆性。

## 5. 插件注册与初始化机制

### 启动注册流程

1. 应用启动时 `initialize.Routers()` 构建路由
2. 调用 `InstallPlugin(PrivateGroup, PublicRouter, engine)`（需取消注释）
3. 该函数先检查 `global.HAB_DB == nil`，未初始化数据库则跳过
4. 分别调用 `bizPluginV1(PrivateGroup, PublicRouter)` 和 `bizPluginV2(engine)`
5. v1 通过 `holder()` 函数注册，v2 直接在 `bizPluginV2()` 中注册

### 插件自动发现

`autoCodePackage.All()` 方法（`service/system/auto_code_package.go`）会自动扫描 `server/plugin/` 目录，发现符合标准结构的插件并将其显示在 AutoCode 的包列表中：

```go
pluginPath := filepath.Join(root, server, "plugin")
pluginDir, _ := os.ReadDir(pluginPath)
for _, dir := range pluginDir {
    if dir.IsDir() {
        // 检查必须包含以下子目录：
        // api, config, initialize, model, plugin, router, service
        // 全部匹配才识别为有效插件
    }
}
```

必须包含的子目录：`api`、`config`、`initialize`、`model`、`plugin`、`router`、`service`。

### 手动注册 v2 插件

在 `server/initialize/plugin_biz_v2.go` 中：

```go
import myPlugin "hab/plugin/myPlugin"

func bizPluginV2(engine *gin.Engine) {
    PluginInitV2(engine, myPlugin.Plugin)
}
```

### 手动注册 v1 插件

在 `server/initialize/router_biz.go` 的 `holder()` 中：

```go
func holder(routers ...*gin.RouterGroup) {
    PluginInit(routers[0], myPlugin.Plugin)
}
```

## 6. 插件开发完整指南

### 方式一：通过 AutoCode 创建（推荐）

#### 步骤 1：创建插件骨架

使用 AutoCode 系统，选择"插件模式"（template = "plugin"），填写：
- Package：插件包名（如 `announcement`）
- StructName：主结构体名（如 `Announcement`）
- 数据模型字段定义

系统会基于 `server/resource/plugin/` 下的模板自动生成完整代码。

#### 步骤 2：检查生成结构

生成后代码位于：
- Server 端：`server/plugin/<pluginName>/`
- Web 端：`web/plugin/<pluginName>/`（如果勾选了生成前端）

```
server/plugin/<pluginName>/
  plugin.go                   # 插件入口 — 实现 v2 Plugin 接口
  plugin/plugin.go            # 配置变量
  config/config.go            # 配置结构体
  initialize/
    router.go                 # 路由初始化（自动划分 public/private）
    gorm.go                   # 数据库迁移
    api.go                    # API 权限初始化数据
    menu.go                   # 菜单初始化数据
    viper.go                  # 配置读取
  model/
    model.go                  # 数据模型
    request/request.go        # 请求参数
  api/
    api.go                    # Handler（CRUD + Swagger 注释）
    enter.go                  # 入口聚合
  service/
    service.go                # 业务逻辑
    enter.go                  # 入口聚合
  router/
    router.go                 # 路由定义
    enter.go                  # 入口聚合
  gen/
    gen.go                    # gorm gen 配置
```

前端目录：
```
web/plugin/<pluginName>/
  api/<packageName>.js        # API 调用
  view/<packageName>.vue      # 页面组件
  form/<packageName>.vue      # 表单组件
```

**注意**：前端组件路径在菜单中配置为 `plugin/<pluginName>/view/<packageName>.vue`，而非 `view/` 开头。

#### 步骤 3：完善插件入口

编辑 `plugin.go`，根据需要启用可选的初始化步骤：

```go
func (p *plugin) Register(group *gin.Engine) {
    ctx := context.Background()
    initialize.Viper()          // 如果有自定义配置
    initialize.Gorm(ctx)        // 数据库迁移
    initialize.Router(group)    // 路由注册
    initialize.Api(ctx)         // API 权限注册
    initialize.Menu(ctx)        // 菜单注册
}
```

#### 步骤 4：注册插件

在 `server/initialize/plugin_biz_v2.go` 中添加：

```go
import myPlugin "hab/plugin/myPlugin"

func bizPluginV2(engine *gin.Engine) {
    PluginInitV2(engine, myPlugin.Plugin)
}
```

同时确保 `router.go` 中 `InstallPlugin` 调用未被注释。

#### 步骤 5：完善业务逻辑

根据业务需求修改：
- `model/model.go` — 数据模型和 GORM tag
- `service/service.go` — 数据库查询和业务逻辑
- `api/api.go` — 请求处理和响应
- `router/router.go` — 路由映射

#### 步骤 6：配置数据库迁移

在 `initialize/gorm.go` 的 `AutoMigrate()` 中添加模型：

```go
func Gorm(ctx context.Context) {
    err := global.HAB_DB.WithContext(ctx).AutoMigrate(
        &model.MyModel{},
    )
}
```

### 方式二：使用 AddFunc 为已有插件添加方法

AutoCode 的 `AddFunc` 功能可以为已有插件添加新的 API 方法：

```go
type AutoFunc struct {
    Package         string  // 插件包名
    FuncName        string  // 方法名
    Router          string  // 路由路径
    Method          string  // HTTP 方法（GET/POST/PUT/DELETE）
    IsPlugin        bool    // 标记为插件模式
    IsAuth          bool    // 是否需要鉴权
}
```

当 `IsPlugin = true` 时，生成的文件路径会自动调整：
- API 文件：`server/plugin/<package>/api/<humpPackageName>.go`
- Service 文件：`server/plugin/<package>/service/<humpPackageName>.go`
- Router 文件：`server/plugin/<package>/router/<humpPackageName>.go`
- JS 文件：`web/plugin/<package>/api/<packageName>.js`

路由注入的代码格式也不同于 package 模式：
- Package 模式：`abbreviationRouter.METHOD("/path", abbreviationApi.FuncName)`
- Plugin 模式：`group.METHOD("/path", apiStructName.FuncName)`

## 7. 插件安装流程

### 安装接口

- 路由：`POST /autoCode/installPlugin`（需鉴权）
- Handler：`AutoCodePluginApi.Install`
- Service：`autoCodePlugin.Install`

### 后端安装逻辑

`service/system/auto_code_plugin.go` 中的 `Install()` 方法：

1. 创建临时目录 `./hab-plug-temp/`
2. 保存并解压上传的 zip 文件
3. 过滤 macOS 特殊文件（`.DS_Store`、`__MACOSX`）
4. 在解压路径中查找 `server/plugin` 和 `web/plugin` 目录标记
5. 如果两者都不存在，返回"非标准插件"错误
6. 将 server 端文件复制到项目的 `server/plugin/` 目录
7. 将 web 端文件复制到项目的 `web/plugin/` 目录（注意：源路径和目标路径通过 AutoCode 配置计算）
8. 如果目标目录已存在同名插件，拒绝安装并提示手动处理
9. 清理临时目录

### 安装结果

返回 web 和 server 两个安装状态码：
- `code: 1` — 安装成功
- `code: -1` — 安装失败（纯后端插件的 web 部分、或纯前端插件的 server 部分会返回 -1，属于正常情况）

### 标准插件包结构

```
<pluginName>.zip
  └ <pluginName>/
      ├ server/plugin/<pluginName>/   # 后端代码（完整的插件目录结构）
      │   ├ plugin.go
      │   ├ api/
      │   ├ config/
      │   ├ initialize/
      │   ├ model/
      │   ├ plugin/
      │   ├ router/
      │   └ service/
      └ web/plugin/<pluginName>/      # 前端代码
          ├ api/
          ├ view/
          └ form/
```

## 8. 插件发布（打包）流程

### 打包接口

- 路由：`POST /autoCode/pubPlug?plugName=xxx`（需鉴权）
- Handler：`AutoCodePluginApi.Packaged`
- Service：`autoCodePlugin.PubPlug`

### 后端打包逻辑

1. 验证插件名称非空，使用 `filepath.Clean` 防止路径穿越
2. 检查 `web/plugin/<pluginName>` 和 `server/plugin/<pluginName>` 目录都存在
3. 使用 `archiver` 库将两个目录打包为 zip
4. zip 内部路径格式：`<pluginName>/web/plugin/<pluginName>/` 和 `<pluginName>/server/plugin/<pluginName>/`
5. zip 文件保存在 server 根目录

### InitMenu 接口

- 路由：`POST /autoCode/initMenu`（公开路由）
- 功能：读取插件的 `initialize/menu.go`，通过 AST 操作替换菜单数组
- 流程：
  1. 解析 `menu.go` 的 AST
  2. 查找 `model.SysBaseMenu` 类型的数组
  3. 创建父级菜单（插件名 + 传入的 parentMenu）
  4. 从数据库查询选中的菜单记录
  5. 合并后生成 Go 结构体代码写回文件

### InitAPI 接口

- 路由：`POST /autoCode/initAPI`（公开路由）
- 功能：类似 InitMenu，读取 `initialize/api.go` 并替换 API 数组
- 流程：从数据库查询选中的 API 记录，生成 Go 结构体代码写回文件

## 9. plugin 模式 vs package 模式

AutoCode 支持两种代码组织模式，在 `SysAutoCodePackage.Template` 字段中区分：

| 特性 | package 模式 | plugin 模式 |
|------|-------------|-------------|
| Template 值 | `"package"` | `"plugin"` |
| 后端目录 | `server/api/v1/{pkg}/`、`server/service/{pkg}/` 等 | `server/plugin/{pkg}/` 下自包含 |
| 前端目录 | `web/src/view/{pkg}/` | `web/plugin/{pkg}/` |
| 菜单 component | `view/{pkg}/{name}/{name}.vue` | `plugin/{pkg}/view/{name}.vue` |
| 路由注册 | 注入 `router_biz.go` | 注入 `plugin_biz_v2.go` |
| 代码耦合 | 与主项目 enter.go 文件绑定 | 完全自包含，可独立打包 |
| 可移植性 | 低（分散在多个目录） | 高（可打包为 zip 分发） |
| 适用场景 | 项目核心业务 | 可复用的功能模块 |

## 10. API 路由定义

插件相关的 API 路由在 `server/router/system/sys_auto_code.go` 中定义：

```go
// 需要鉴权的路由
autoCodeRouter.POST("pubPlug", autoCodePluginApi.Packaged)       // 打包插件
autoCodeRouter.POST("installPlugin", autoCodePluginApi.Install)  // 安装插件

// 公开路由（不需要鉴权）
publicAutoCodeRouter.POST("initMenu", autoCodePluginApi.InitMenu) // 同步插件菜单
publicAutoCodeRouter.POST("initAPI", autoCodePluginApi.InitAPI)   // 同步插件 API
```

## 11. 注意事项和常见问题

### 关键注意事项

1. **InstallPlugin 默认被注释**：`server/initialize/router.go` 第 113 行的 `InstallPlugin` 调用默认被注释。使用插件系统前必须取消注释，否则所有插件都不会被加载。

2. **v2 是推荐版本**：模板默认生成 v2 格式。v1 仅用于兼容旧插件。

3. **插件安装后需要重启服务**：Go 是编译型语言，安装新插件后需要重新编译并重启服务。

4. **数据库依赖**：`InstallPlugin` 会检查 `global.HAB_DB` 是否为 nil，未初始化数据库时插件不会被加载。

5. **plugin-tool 工具包**：菜单和 API 的注册依赖 `plugin/plugin-tool/utils` 包提供的 `RegisterMenus` 和 `RegisterApis` 方法。该包在模板中被引用但不在 base 项目中预置，需要在项目中自行创建或从其他项目引入。

6. **配置文件**：如果插件需要自定义配置，需在项目的 `config.yaml` 中添加对应的配置段，键名与插件包名一致。`initialize/viper.go` 会通过 `global.HAB_VP.UnmarshalKey("pluginName", &plugin.Config)` 读取。

### 常见问题

**Q: 为什么安装插件后路由没有生效？**
A: 检查以下几点：
- `router.go` 中的 `InstallPlugin` 是否取消了注释
- `plugin_biz_v2.go` 中是否添加了插件注册调用
- 是否重新编译并重启了服务

**Q: 为什么 AutoCode 中看不到我的插件包？**
A: 插件目录必须包含所有标准子目录：`api`、`config`、`initialize`、`model`、`plugin`、`router`、`service`。缺少任何一个都不会被识别。

**Q: 同名插件冲突怎么办？**
A: 安装时如果目标目录已存在同名插件，会拒绝自动安装。需要手动删除旧版本后重新安装，或手动合并代码。

**Q: 非标准插件错误是什么意思？**
A: zip 包解压后的路径中必须包含 `server/plugin` 或 `web/plugin` 目录标记。如果路径结构不符合规范，安装程序无法自动识别，需按文档手动迁移。

**Q: 纯后端/纯前端插件的安装结果如何理解？**
A: 纯后端插件安装后 web 部分返回 `code: -1` 是正常的，反之亦然。提示信息中会说明"如果为纯后端/前端插件请忽略此条提示"。

**Q: macOS 用户打包的插件在其他系统安装异常？**
A: 系统已自动处理 `.DS_Store` 和 `__MACOSX` 文件的过滤，通常不会有问题。如果仍有异常，建议在打包前手动清理。

**Q: 插件如何读取主项目的数据库连接？**
A: 插件通过 `global.HAB_DB` 直接使用主项目的数据库连接，无需额外配置。如果需要使用其他数据库，可通过 `global.MustGetGlobalDBByDBName("dbName")` 获取。
