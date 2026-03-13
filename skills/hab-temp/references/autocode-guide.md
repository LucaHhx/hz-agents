# AutoCode 代码生成系统 -- 内部架构与原理

> 本文档聚焦 AutoCode 的**内部架构和工作原理**。API 调用操作（curl 命令、请求体格式、包管理、预览/生成/回滚流程）请参考 **hab-autocode skill**。

## 1. 系统架构总览

AutoCode 是 hz-admin-base 内置的代码生成引擎，根据字段定义自动生成完整的 CRUD 模块（后端 + 前端 + 数据库资源）。

**核心组件**

| 组件 | 源码位置 | 职责 |
|------|----------|------|
| `autoCodeTemplate` | `server/service/system/auto_code_template.go` | 代码生成入口：模板渲染、文件写入、AST 注入、资源创建 |
| `autoCodePackage` | `server/service/system/auto_code_package.go` | Package/Plugin 管理：模板目录扫描、生成路径映射、包创建/删除 |
| `autoCodeHistory` | `server/service/system/auto_code_history.go` | 历史记录管理、回滚操作 |
| `AutoCodeService` | `server/service/system/sys_auto_code_interface.go` | 数据库接口适配（MySQL/PostgreSQL/MSSQL/Oracle/SQLite） |
| `utils/ast` | `server/utils/ast/` | AST 解析注入工具集（30+ 文件） |
| 模板文件 | `server/resource/package/` | Go text/template 模板（13 个 .tpl 文件） |
| 请求模型 | `server/model/system/request/sys_auto_code.go` | `AutoCode`、`AutoCodeField`、`AutoFunc` 结构体 |
| 历史模型 | `server/model/system/sys_auto_code_history.go` | `SysAutoCodeHistory` 存储生成记录 |
| 包模型 | `server/model/system/sys_auto_code_package.go` | `SysAutoCodePackage` 存储包信息 |

**请求处理链路**

```
前端/API → Router (sys_auto_code.go, sys_auto_code_history.go)
         → API Handler (sys_auto_code.go)
         → Service (auto_code_template.go / auto_code_package.go / auto_code_history.go)
         → 模板渲染 + AST 注入 + 数据库资源创建
```

## 2. 模板系统

### 2.1 Package 模板目录结构

```
server/resource/package/
├── readme.txt.tpl                          # 说明文件（生成时跳过）
├── server/
│   ├── api/
│   │   ├── api.go.tpl                      # API 控制器（Create/Delete/Update/Find/GetList/Import/DataSource/Public）
│   │   └── enter.go.tpl                    # API 入口模板（空 ApiGroup struct，创建包时使用）
│   ├── router/
│   │   ├── router.go.tpl                   # 路由注册（三组路由：鉴权+记录 / 鉴权 / 公开）
│   │   └── enter.go.tpl                    # Router 入口模板（空 RouterGroup struct）
│   ├── service/
│   │   ├── service.go.tpl                  # Service 业务逻辑（CRUD + Import + DataSource）
│   │   └── enter.go.tpl                    # Service 入口模板（空 ServiceGroup struct）
│   ├── model/
│   │   └── model.go.tpl                    # Model 结构体（支持 IsAdd 增量模式和全新创建模式）
│   └── translation/
│       ├── zh-CN.json.tpl                  # 中文翻译（columns + enums + messages）
│       └── en-US.json.tpl                  # 英文翻译
└── web/
    ├── api/
    │   └── api.js.tpl                      # 前端 API 调用函数
    └── view/
        ├── table.vue.tpl                   # 表格页面（DiySearch + DiyTable + DiyForm + 导出/导入）
        └── form.vue.tpl                    # 表单弹窗（create/edit/view/copy 四种模式）
```

### 2.2 模板渲染机制

所有 `.tpl` 文件使用 Go 标准库 `text/template` 引擎渲染。数据上下文为 `request.AutoCode` 结构体。

**渲染流程**（`autoCodeTemplate.generate()` 方法）：

```
1. AutoCodePackage.templates() → 扫描模板目录，建立 "模板绝对路径 → 输出绝对路径" 映射
2. template.ParseFiles(key) → 解析每个 .tpl 文件为 Go template 对象
3. files.Execute(&builder, info) → 用 AutoCode 数据渲染模板，输出到 strings.Builder
4. AST 注入处理 → 对 enter.go 等文件执行 Parse → Injection → Format
```

**路径映射规则**（`autoCodePackage.templates()` 方法决定）：

| 模板文件 | Package 模式输出路径 | Plugin 模式输出路径 |
|----------|---------------------|---------------------|
| `server/api/api.go.tpl` | `server/api/v1/{pkg}/{humpPkgName}.go` | `server/plugin/{pkg}/api/{humpPkgName}.go` |
| `server/model/model.go.tpl` | `server/model/{pkg}/{humpPkgName}.go` | `server/plugin/{pkg}/model/{humpPkgName}.go` |
| `server/router/router.go.tpl` | `server/router/{pkg}/{humpPkgName}.go` | `server/plugin/{pkg}/router/{humpPkgName}.go` |
| `server/service/service.go.tpl` | `server/service/{pkg}/{humpPkgName}.go` | `server/plugin/{pkg}/service/{humpPkgName}.go` |
| `web/api/api.js.tpl` | `web/src/api/{pkg}/{pkgName}.js` | `web/src/plugin/{pkg}/api/{pkgName}.js` |
| `web/view/table.vue.tpl` | `web/src/view/{pkg}/{pkgName}/{pkgName}.vue` | `web/src/plugin/{pkg}/view/{pkgName}.vue` |
| `web/view/form.vue.tpl` | `web/src/view/{pkg}/{pkgName}/{pkgName}Form.vue` | (内嵌在 table.vue 中) |
| `server/translation/zh-CN.json.tpl` | `server/translation/zh-CN/business/{pkgName}.json` | `server/plugin/{pkg}/locales/zh-CN/{pkgName}.json` |
| `server/translation/en-US.json.tpl` | `server/translation/en-US/business/{pkgName}.json` | `server/plugin/{pkg}/locales/en-US/{pkgName}.json` |

### 2.3 模板变量参考

所有模板使用 `request.AutoCode` 结构体作为数据上下文。

**顶层变量**

| 模板变量 | 类型 | 说明 | 示例值 |
|----------|------|------|--------|
| `{{.Package}}` | string | 包名 | `business` |
| `{{.PackageT}}` | string | 包名首字母大写（`Pretreatment()` 中计算） | `Business` |
| `{{.StructName}}` | string | 结构体名 | `Order` |
| `{{.Abbreviation}}` | string | 结构体简称（路由前缀） | `order` |
| `{{.PackageName}}` | string | 文件名称 | `order` |
| `{{.HumpPackageName}}` | string | Go 文件名 | `order` |
| `{{.Description}}` | string | 中文描述 | `订单管理` |
| `{{.TableName}}` | string | 数据库表名 | `biz_order` |
| `{{.BusinessDB}}` | string | 业务数据库名（空=默认库） | `""` |
| `{{.Module}}` | string | Go module 路径 | `hab` |
| `{{.GvaModel}}` | bool | 是否使用默认 Model（含 ID/CreatedAt/UpdatedAt/DeletedAt） | `true` |
| `{{.AutoCreateResource}}` | bool | 是否记录 CreatedBy/UpdatedBy/DeletedBy | `true` |
| `{{.AutoMigrate}}` | bool | 是否自动迁移表 | `true` |
| `{{.OnlyTemplate}}` | bool | 是否只生成模板（不含 CRUD 业务逻辑） | `false` |
| `{{.IsTree}}` | bool | 是否树形结构（改变 GetList 接口行为） | `false` |
| `{{.IsAdd}}` | bool | 是否增量模式（仅生成新字段片段，不生成完整文件） | `false` |
| `{{.GenerateServer}}` | bool | 是否生成后端代码 | `true` |
| `{{.GenerateWeb}}` | bool | 是否生成前端代码 | `true` |
| `{{.Fields}}` | `[]*AutoCodeField` | 字段列表 | - |
| `{{.PrimaryField}}` | `*AutoCodeField` | 主键字段（GvaModel 时自动设为 ID） | - |
| `{{.HasDataSource}}` | bool | 是否有数据源字段（`Pretreatment()` 中计算） | `false` |
| `{{.HasExcel}}` | bool | 是否有导入导出字段 | `true` |
| `{{.NeedJSON}}` | bool | 是否需要 `datatypes.JSON` import | `false` |
| `{{.DataSourceMap}}` | `map[string]*DataSource` | 数据源映射 | - |

**AutoCodeField 字段属性**（`{{range .Fields}}` 中使用）

| 属性 | 类型 | 说明 |
|------|------|------|
| `FieldName` | string | Go 字段名（如 `Title`） |
| `FieldDesc` | string | 中文描述（如 `标题`） |
| `FieldType` | string | 字段类型：`string`, `int`, `int32`, `int64`, `float64`, `bool`, `enum`, `datetime`, `date`, `json`, `array`, `binary`, `richtext`, `picture`, `pictures`, `video`, `file` |
| `FieldJson` | string | JSON tag 名（如 `title`） |
| `DataType` | string | 数据库列类型（如 `varchar`） |
| `DataTypeLong` | string | 数据库列长度（如 `255`） |
| `ColumnName` | string | 数据库列名（如 `title`） |
| `Comment` | string | 数据库字段注释 |
| `FieldSearchType` | string | 搜索类型：`=`, `!=`, `LIKE`, `>`, `<`, `>=`, `<=`, `BETWEEN`, `NOT BETWEEN` |
| `FieldIndexType` | string | 索引类型：`index`, `uniqueIndex` |
| `DefaultValue` | string | 默认值 |
| `Form` | bool | 是否在表单中显示 |
| `Table` | bool | 是否在表格中显示 |
| `Desc` | bool | 是否在详情中显示 |
| `Excel` | bool | 是否参与导入/导出 |
| `Require` | bool | 是否必填（控制后端校验） |
| `ErrorText` | string | 校验失败提示文字 |
| `Clearable` | bool | 前端控件是否可清空 |
| `Sort` | bool | 是否增加排序 |
| `PrimaryKey` | bool | 是否主键 |
| `DataSource` | `*DataSource` | 数据源配置 |
| `CheckDataSource` | bool | 数据源是否有效（`Pretreatment()` 中计算） |

### 2.4 模板语法要点

**条件分支** -- model.go.tpl 中按 FieldType 生成不同的 Go 类型和 GORM tag：

```go
{{- if eq .FieldType "string" }}
{{.FieldName}} string `json:"{{.FieldJson}}" gorm:"column:{{.ColumnName}};comment:{{.Comment}};size:{{.DataTypeLong}};"`
{{- else if eq .FieldType "datetime" }}
{{.FieldName}} *global.MySQLTime `json:"{{.FieldJson}}" gorm:"column:{{.ColumnName}};type:{{.DataType}};"`
{{- else if eq .FieldType "json" }}
{{.FieldName}} datatypes.JSON `json:"{{.FieldJson}}" gorm:"column:{{.ColumnName}};type:{{.DataType}};" swaggertype:"object"`
```

**IsAdd 增量模式** -- model.go.tpl 在 `{{- if .IsAdd}}` 分支中只输出字段片段（用于为已有 struct 追加字段），否则输出完整 struct 定义。

**OnlyTemplate 模式** -- api.go.tpl 和 service.go.tpl 中 `{{if not .OnlyTemplate}}` 包裹 CRUD 方法，OnlyTemplate=true 时只生成空 struct 和 Public 接口。

**IsTree 树形模式** -- model.go.tpl 添加 `Children`/`ParentID` 字段和 TreeNode 接口实现。service.go.tpl 的 `GetInfoList` 不接受分页参数，调用 `utils.BuildTree()` 构建树。

**数据库选择** -- service.go.tpl 顶部根据 `{{.BusinessDB}}` 决定使用默认库还是命名库：

```go
{{- if eq .BusinessDB "" }}
  {{- $db = "global.HAB_DB" }}
{{- else}}
  {{- $db = printf "global.MustGetGlobalDBByDBName(\"%s\")" .BusinessDB }}
{{- end}}
```

### 2.5 前端模板特殊语法

Vue 模板中使用 `{{ "{{" }}` 和 `{{ "}}" }}` 转义 Vue 的双花括号，避免与 Go template 冲突：

```vue
<el-button @click="getTableData()">{{ "{{" }} $t('common.search') {{ "}}" }}</el-button>
```

表单控件按 FieldType 渲染：
- `string` → `el-input`
- `bool` → `el-switch`
- `int`/`int32`/`int64`/`float64` → `el-input-number`
- `date` → `el-date-picker type="date"`
- `datetime` → `el-date-picker type="datetime"`
- `enum` → `el-select` + `el-option`
- `richtext`/`json`/`array`/`binary` → `el-input type="textarea"`
- DataSource 字段 → `el-select`（从关联表加载选项）

## 3. AST 自动注入机制

AST 注入是 AutoCode 最核心的机制之一。通过 Go 标准库 `go/ast`、`go/parser`、`go/format` 解析并修改现有 Go 源码文件，自动注册新生成的模块到系统中。

### 3.1 统一接口

所有注入操作实现 `ast.Ast` 接口（`server/utils/ast/interfaces.go`）：

```go
type Ast interface {
    Parse(filename string, writer io.Writer) (file *ast.File, err error)
    Rollback(file *ast.File) error
    Injection(file *ast.File) error
    Format(filename string, writer io.Writer, file *ast.File) error
}
```

注入流程：`Parse() → Injection() → Format()` -- 读取 → 修改 AST → 写回格式化代码
回滚流程：`Parse() → Rollback() → Format()` -- 读取 → 从 AST 移除 → 写回

### 3.2 Package 模式注入类型（8 种）

| 类型常量 | 实现结构体 | 注入目标文件 | 注入内容 |
|----------|-----------|-------------|----------|
| `TypePackageApiEnter` | `PackageEnter` | `server/api/v1/enter.go` | 在 `ApiGroup` struct 添加 `{Pkg}ApiGroup` 字段 + import |
| `TypePackageRouterEnter` | `PackageEnter` | `server/router/enter.go` | 在 `RouterGroup` struct 添加 `{Pkg}` 字段 + import |
| `TypePackageServiceEnter` | `PackageEnter` | `server/service/enter.go` | 在 `ServiceGroup` struct 添加 `{Pkg}ServiceGroup` 字段 + import |
| `TypePackageApiModuleEnter` | `PackageModuleEnter` | `server/api/v1/{pkg}/enter.go` | 添加 `{Struct}Api` struct + `{abbr}Service` 变量引用 |
| `TypePackageRouterModuleEnter` | `PackageModuleEnter` | `server/router/{pkg}/enter.go` | 添加 `{Struct}Router` struct + `{abbr}Api` 变量引用 |
| `TypePackageServiceModuleEnter` | `PackageModuleEnter` | `server/service/{pkg}/enter.go` | 添加 `{Struct}Service` struct |
| `TypePackageInitializeRouter` | `PackageInitializeRouter` | `server/initialize/router_biz.go` | 在 `initBizRouter()` 中添加 `{pkg}Router.Init{Struct}Router(privateGroup, publicGroup)` |
| `TypePackageInitializeGorm` | `PackageInitializeGorm` | `server/initialize/gorm_biz.go` | 在 `RegisterTables()` 中添加 `db.AutoMigrate(&{pkg}.{Struct}{})` |

**注入示例 -- PackageInitializeRouter**

注入前的 `router_biz.go`：
```go
func initBizRouter(privateGroup, publicGroup *gin.RouterGroup) {
    // 已有路由
}
```

注入后：
```go
func initBizRouter(privateGroup, publicGroup *gin.RouterGroup) {
    businessRouter := router.RouterGroupApp.Business
    // 已有路由
    {
        businessRouter.InitOrderRouter(privateGroup, publicGroup)
    }
}
```

**注入示例 -- PackageModuleEnter（api enter.go）**

注入前：
```go
package business

type ApiGroup struct {}
```

注入后：
```go
package business

import "hab/service"

type ApiGroup struct {
    OrderApi
}

var orderService = service.ServiceGroupApp.BusinessServiceGroup.OrderService
```

### 3.3 Plugin 模式注入类型（7 种）

| 类型常量 | 注入目标文件 | 注入内容 |
|----------|-------------|----------|
| `TypePluginInitializeV2` | `server/initialize/plugin_biz_v2.go` | 注册插件到系统（创建包时执行，生成模块时跳过） |
| `TypePluginApiEnter` | `server/plugin/{pkg}/api/enter.go` | 添加 API struct + service 引用 |
| `TypePluginRouterEnter` | `server/plugin/{pkg}/router/enter.go` | 添加 Router struct + api 引用 |
| `TypePluginServiceEnter` | `server/plugin/{pkg}/service/enter.go` | 添加 Service struct |
| `TypePluginGen` | `server/plugin/{pkg}/gen/main.go` | 添加 model import 和 struct 引用 |
| `TypePluginInitializeGorm` | `server/plugin/{pkg}/initialize/gorm.go` | 添加 AutoMigrate |
| `TypePluginInitializeRouter` | `server/plugin/{pkg}/initialize/router.go` | 添加路由注册 |

### 3.4 AST 工具文件说明

| 文件 | 职责 |
|------|------|
| `ast.go` | 通用 AST 辅助函数（`FindFunction`、`CreateStmt`、`AddImport` 等） |
| `ast_enter.go` | `ImportReference()` -- 向 Go 文件注入 import、struct 字段、路由变量 |
| `ast_auto_enter.go` | `ImportForAutoEnter()` -- 向 struct 添加匿名字段（模块 enter.go） |
| `ast_router.go` | `AddRouterCode()` -- 向 router_biz.go 注入路由初始化调用 |
| `ast_gorm.go` | `AddRegisterTablesAst()` -- 向 gorm_biz.go 注入 AutoMigrate 调用 |
| `ast_rollback.go` | `RollBackAst()` -- 回滚 gorm_biz.go 和 router_biz.go 的注入 |
| `ast_type.go` | 类型常量定义（15 种注入类型） |
| `interfaces.go` | `Ast` 接口定义 |
| `interfaces_base.go` | 基础辅助接口 |
| `package_enter.go` | `PackageEnter` 实现 -- 向父级 enter.go 添加 struct 字段 + import |
| `package_module_enter.go` | `PackageModuleEnter` 实现 -- 向模块 enter.go 添加 struct + service 变量 |
| `package_initialize_router.go` | `PackageInitializeRouter` 实现 -- 注入路由初始化 |
| `package_initialize_gorm.go` | `PackageInitializeGorm` 实现 -- 注入 AutoMigrate |
| `plugin_enter.go` | `PluginEnter` 实现 |
| `plugin_gen.go` | `PluginGen` 实现 |
| `plugin_initialize_gorm.go` | `PluginInitializeGorm` 实现 |
| `plugin_initialize_router.go` | `PluginInitializeRouter` 实现 |
| `plugin_initialize_v2.go` | `PluginInitializeV2` 实现 |
| `import.go` | `NewImport` -- import 语句的注入和回滚 |

### 3.5 回滚机制

回滚通过 `ast_rollback.go` 中的两个函数实现：

**RollGormBack(pk, model)**：
1. 读取 `initialize/gorm_biz.go`，解析为 AST
2. 遍历所有 `CallExpr` 节点，找到包含 `{pk}.{model}` 参数的 `AutoMigrate` 调用
3. 从 `Args` 列表中移除该参数
4. 如果该 package 只剩这一个 model（`pkNum == 1`），同时移除对应的 import 语句
5. 写回文件

**RollRouterBack(pk, model)**：
1. 读取 `initialize/router_biz.go`，找到 `initBizRouter` 函数
2. 找到包含 `{pk}Router` 变量的 `BlockStmt`
3. 从 block 中移除 `Init{model}Router` 调用语句
4. 如果 block 只剩变量定义（`len(block.List) == 1`），移除整个 block
5. 写回文件

## 4. 代码生成完整流程

`autoCodeTemplate.Create()` 方法的完整执行步骤：

```
 1. 查询 Package → global.HAB_DB.Where("package_name = ?").First(&autoPkg)
 2. 检查 Package 结构完整性 → checkPackage() 验证 enter.go 文件存在
 3. 检查重复 → AutocodeHistory.Repeat() 防止同 StructName/Abbreviation 重复创建
 4. generate() 核心生成：
    ├── AutoCodePackage.templates() → 扫描模板目录，建立映射
    ├── template.ParseFiles() → 解析每个 .tpl 文件
    ├── files.Execute() → 渲染模板
    └── AST 注入 → Parse → Injection → Format
 5. 写入文件 → os.MkdirAll + os.WriteFile
 6. 创建 API 记录 → 向 sys_apis 表插入 7 条记录（Create/Delete/DeleteByIds/Update/Find/GetList/Import）
 7. 创建菜单 → 向 sys_base_menus 插入菜单记录
 8. 创建按钮权限 → 9 个 SysBaseMenuBtn（add/batchDelete/delete/edit/info/exportTemplate/exportExcel/importExcel/columnConfig）
 9. 创建列配置 → 为每个字段创建 SysTableColumns 记录（含列宽、排序、筛选配置）
10. 创建列权限 → SysAuthorityCol 关联 authorityId=1
11. 创建按钮权限关联 → SysAuthorityBtn 关联 authorityId=1
12. 创建菜单权限 → SysAuthorityMenu 关联 authorityId=1
13. 创建导出模板 → 如有 Excel 字段，创建 SysExportTemplate 记录
14. 保存历史 → SysAutoCodeHistory（含 templates 映射、injections 信息、apiIDs、menuID）
```

### 4.1 Pretreatment 预处理

`AutoCode.Pretreatment()` 在生成前被调用，执行以下计算：

1. 设置 `Module` 为配置中的 Go module 名
2. Go 关键字处理：如果 `Abbreviation` 是关键字，追加 `_`
3. test 后缀处理：如果 `HumpPackageName` 以 "test" 结尾，追加 `_`
4. 遍历 Fields 设置标志位：`HasExcel`、`NeedJSON`、`NeedSort`、`HasFile`、`HasPic`、`HasTimer`、`HasRichText`、`HasDataSource`、`HasArray`
5. 收集 DictTypes
6. 计算 `PrimaryField`（GvaModel 时自动设为 ID）
7. 计算 `PackageT`（Package 首字母大写）

### 4.2 自动创建的列配置

`AutoCode.Columns()` 方法为每个字段生成 `SysTableColumns` 记录。自动设置的默认值：

| 字段类型 | 默认列宽 | 默认筛选方式 | 可用筛选操作 |
|----------|---------|-------------|-------------|
| `string` | 120 | `like` | `=`, `!=`, `like`, `in`, `not in` |
| `richtext` | 280 | `like` | 同 string |
| `bool` | 80 | `=` | `=`, `!=` |
| `enum` | 100 | `=` | `=`, `!=` |
| `int`/`int32` | 80 | `=` | `=`, `!=`, `>`, `>=`, `<`, `<=`, `in`, `not in`, `between`, `not between` |
| `int64`/`float64` | 100 | `=` | 同 int |
| `datetime` | 180 | `between` | `=`, `!=`, `>`, `>=`, `<`, `<=`, `between`, `not between` |
| `date` | 100 | `between` | 同 datetime |
| `json`/`array` | 200 | `like` | `=`, `!=`, `like` |
| `binary` | 150 | `like` | `=`, `!=` |

GvaModel=true 时额外生成 7 个系统字段列配置：ID、CreatedAt、UpdatedAt、DeletedAt、CreatedBy、UpdatedBy、DeletedBy，其中 DeletedAt/DeletedBy 的 `IsShow` 为 false。

## 5. 生成的代码结构与各文件作用

### 5.1 Package 模式输出

```
server/
├── api/v1/{pkg}/{humpPkgName}.go           # API 控制器：接收请求、参数校验、调用 service、返回响应
├── api/v1/{pkg}/enter.go                    # [AST 注入] {Struct}Api struct + service 变量引用
├── api/v1/enter.go                          # [AST 注入] ApiGroup 添加 {Pkg}ApiGroup 字段
├── service/{pkg}/{humpPkgName}.go           # Service 层：CRUD 业务逻辑、数据库操作
├── service/{pkg}/enter.go                   # [AST 注入] {Struct}Service struct
├── service/enter.go                         # [AST 注入] ServiceGroup 添加 {Pkg}ServiceGroup 字段
├── router/{pkg}/{humpPkgName}.go            # 路由注册：三组路由（鉴权+记录/鉴权/公开）
├── router/{pkg}/enter.go                    # [AST 注入] {Struct}Router struct + api 变量引用
├── router/enter.go                          # [AST 注入] RouterGroup 添加 {Pkg} 字段
├── model/{pkg}/{humpPkgName}.go             # Model：struct 定义 + GORM tag + TableName()
├── initialize/router_biz.go                 # [AST 注入] initBizRouter 添加 Init{Struct}Router 调用
├── initialize/gorm_biz.go                   # [AST 注入] RegisterTables 添加 AutoMigrate
└── translation/
    ├── zh-CN/business/{pkgName}.json        # 中文翻译
    └── en-US/business/{pkgName}.json        # 英文翻译

web/src/
├── view/{pkg}/{pkgName}/{pkgName}.vue       # 表格页面：DivSearch + Table + DiyForm + 按钮权限
├── view/{pkg}/{pkgName}/{pkgName}Form.vue   # 表单弹窗：create/edit/view/copy 四种模式
└── api/{pkg}/{pkgName}.js                   # API 调用：为每个 CRUD 操作生成对应函数
```

### 5.2 Plugin 模式输出

```
server/plugin/{pkg}/
├── api/{humpPkgName}.go                    # API 控制器
├── api/enter.go                            # [AST 注入] API struct
├── service/{humpPkgName}.go                # Service 层
├── service/enter.go                        # [AST 注入] Service struct
├── router/{humpPkgName}.go                 # 路由注册
├── router/enter.go                         # [AST 注入] Router struct
├── model/{humpPkgName}.go                  # Model
├── gen/main.go                             # [AST 注入] model import + struct 引用
├── config/                                 # 插件配置
├── initialize/
│   ├── gorm.go                             # [AST 注入] AutoMigrate
│   └── router.go                           # [AST 注入] 路由注册
├── plugin.go                               # 插件入口
└── locales/
    ├── zh-CN/{pkgName}.json                # 中文翻译
    └── en-US/{pkgName}.json                # 英文翻译

web/src/plugin/{pkg}/
├── view/{pkgName}.vue                      # 前端页面
└── api/{pkgName}.js                        # API 调用
```

## 6. 生成的 CRUD 方法详解

### 6.1 API 层

| 方法 | HTTP Method | 路由 | 功能 | 参数来源 |
|------|-------------|------|------|----------|
| `Create{Struct}` | POST | `/{abbr}/create{Struct}` | 创建记录 | JSON Body |
| `Import{Struct}` | POST | `/{abbr}/import{Struct}` | 导入（全量/追加） | JSON Body（type + list） |
| `Delete{Struct}` | DELETE | `/{abbr}/delete{Struct}` | 删除单条 | Query 参数（主键） |
| `Delete{Struct}ByIds` | DELETE | `/{abbr}/delete{Struct}ByIds` | 批量删除 | Query 参数数组 |
| `Update{Struct}` | PUT | `/{abbr}/update{Struct}` | 更新记录 | JSON Body |
| `Find{Struct}` | GET | `/{abbr}/find{Struct}` | 按主键查询 | Query 参数 |
| `Get{Struct}List` | POST | `/{abbr}/get{Struct}List` | 分页列表 | JSON Body（QueryInfo） |
| `Get{Struct}DataSource` | GET | `/{abbr}/get{Struct}DataSource` | 获取数据源 | 无参数（仅 HasDataSource） |
| `Get{Struct}Public` | GET | `/{abbr}/get{Struct}Public` | 公开接口 | 无需鉴权 |

### 6.2 Service 层

| 方法 | GORM 操作 | 特殊行为 |
|------|-----------|----------|
| `Create{Struct}` | `db.Create()` | AutoCreateResource 时设置 `CreatedBy` |
| `Import{Struct}` | Full: `TRUNCATE + Create`; Append: `Create(ID=0)` | 事务操作 |
| `Delete{Struct}` | 事务：`Update(deleted_by) + Delete` | IsTree 时检查子节点 |
| `Delete{Struct}ByIds` | 事务：`Update(deleted_by) + Delete IN` | - |
| `Update{Struct}` | `db.Save()` | AutoCreateResource 时设置 `UpdatedBy` |
| `Get{Struct}` | `db.Where().First()` | - |
| `Get{Struct}InfoList` | `utils.TableQuery() + GetColumns()` | IsTree 时调用 `utils.BuildTree()` |
| `Get{Struct}DataSource` | 查询关联表 `SELECT label, value` | - |
| `Get{Struct}Public` | 空实现 | 需自行实现业务逻辑 |

### 6.3 路由分组

路由模板将接口分为三组，安全级别递减：

```
{abbr}Router               → 需要 JWT 鉴权 + 操作记录中间件（Create/Delete/DeleteByIds/Update/Import）
{abbr}RouterWithoutRecord   → 需要 JWT 鉴权但无操作记录（Find/GetList）
{abbr}RouterWithoutAuth     → 不需要鉴权（Public/DataSource）
```

## 7. Package vs Plugin 模式对比

| 维度 | Package 模式 | Plugin 模式 |
|------|-------------|-------------|
| 代码位置 | 分散在 `api/v1/`、`service/`、`router/`、`model/` | 集中在 `plugin/{pkg}/` 目录 |
| 聚合方式 | 通过 enter.go 和父级 enter.go 注入 | 通过 `plugin.go` + `plugin_biz_v2.go` 注册 |
| 独立性 | 与系统紧耦合 | 可独立开发、打包、安装 |
| 额外目录 | 无 | 包含 `config/`、`initialize/`、`gen/`、`plugin.go` |
| 路由注册 | 注入到 `router_biz.go` | 注入到 `initialize/router.go`（插件内） |
| GORM 注册 | 注入到 `gorm_biz.go` | 注入到 `initialize/gorm.go`（插件内） |
| 翻译文件 | `translation/{lang}/business/{name}.json` | `plugin/{pkg}/locales/{lang}/{name}.json` |
| 菜单 component | `view/{pkg}/{name}/{name}.vue` | `plugin/{pkg}/view/{name}.vue` |
| 适用场景 | 常规业务模块 | 可复用/可分发的功能模块 |
| 打包分发 | 不支持 | 支持 `pubPlug` API 打包 |

## 8. AddFunc -- 为已有模块添加方法

`autoCodeTemplate.AddFunc()` 使用 `server/resource/function/` 下的模板为已有模块追加新 API 方法：

```
1. 查询包类型（Package 或 Plugin）
2. 追加 API 代码 → 读取 function/api.go.tpl → 渲染 → 追加到 api/{pkg}/{humpPkgName}.go
3. 追加 Service 代码 → 读取 function/server.go.tpl → 渲染 → 追加到 service/{pkg}/{humpPkgName}.go
4. 追加 JS 代码 → 读取 function/api.js.tpl → 渲染 → 追加到 web/api/{pkg}/{pkgName}.js
5. AST 注入路由 → 解析路由文件，在对应 BlockStmt 中追加路由语句
   - isAuth=true → 注入到第一个 BlockStmt（鉴权路由组）
   - isAuth=false → 注入到最后一个 BlockStmt（公开路由组）
```

AI 模式（`isAi: true`）时，使用 `apiFunc`/`serverFunc`/`jsFunc` 字段传入的自定义代码替代模板生成的代码。

## 9. 数据库适配层

`AutoCodeService` 通过 `Database()` 方法返回数据库适配器，支持五种数据库：

| 适配器 | 文件 | 数据库 |
|--------|------|--------|
| `AutoCodeMysql` | `sys_auto_code_mysql.go` | MySQL |
| `AutoCodePgsql` | `sys_auto_code_pgsql.go` | PostgreSQL |
| `AutoCodeMssql` | `sys_auto_code_mssql.go` | Microsoft SQL Server |
| `AutoCodeOracle` | `sys_auto_code_oracle.go` | Oracle |
| `AutoCodeSqlite` | `sys_auto_code_sqlite.go` | SQLite |

每个适配器实现 `Database` 接口的三个方法：
- `GetDB()` -- 获取数据库列表
- `GetTables()` -- 获取指定数据库的所有表
- `GetColumn()` -- 获取指定表的所有字段信息（列名、类型、长度、注释、Go 类型映射）

## 10. 配置项

配置位于 `config.yaml` 的 `autocode` 段：

| 配置项 | 类型 | 说明 | 默认值 |
|--------|------|------|--------|
| `root` | string | 项目根目录 | 代码级默认值 |
| `server` | string | 后端目录名 | `server` |
| `web` | string | 前端目录路径 | `web/src` |
| `module` | string | Go module 名 | 自动从 `go.mod` 读取 |
| `api-key` | string | API Key（用于 CLI/AI 调用） | 无默认值，需手动配置 |

## 11. 与 hab-autocode skill 的关系

本文档聚焦 AutoCode 系统的**内部架构和工作原理**。具体的 API 调用操作请参考 **hab-autocode skill**：

| 操作需求 | 参考文档 |
|----------|----------|
| 创建 Package | hab-autocode 的包管理 API |
| 生成 CRUD 代码 | hab-autocode 的 createTemp API |
| 预览代码 | hab-autocode 的 preview API |
| 回滚代码 | hab-autocode 的 rollback API |
| 添加方法 | hab-autocode 的 addFunc API |
| 字段定义参考 | hab-autocode 的 `field-reference.md` |
| 生成后完善 | hab-autocode 的 `post-generation-guide.md` |
| CRUD 开发全流程 | hab-temp 的 `crud-workflow.md` |
