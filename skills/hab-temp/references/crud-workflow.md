# CRUD 开发全流程指南

> 从需求到代码生成、验证、优化的完整 CRUD 开发工作流。

## 1. 全流程总览

```
准备阶段 → 生成阶段 → 验证阶段 → 定制阶段 → 优化阶段 → 上线
   │          │          │          │           │
   │          │          │          ├─ 后端定制  │
   ├─ 需求分析 ├─ AutoCode ├─ 文件检查 ├─ 前端定制  ├─ 性能优化
   ├─ 表设计   ├─ 编译检查 ├─ 注入检查 └─ 翻译配置  ├─ 安全加固
   └─ 创建包            ├─ 数据库检查            └─ 代码质量
                        ├─ API 冒烟测试
                        └─ 前端页面验证
```

## 2. 准备阶段

### 2.1 需求分析

开始前明确以下信息：

- **字段清单**：每个字段的名称、Go 类型、数据库类型、是否必填、是否参与搜索
- **业务数据库**：使用默认库还是指定 BusinessDB
- **主键策略**：使用 GvaModel（自增 ID + 时间戳 + 操作人）还是自定义主键
- **特殊需求**：树形结构（IsTree）、数据源关联（DataSource）、文件上传、富文本
- **权限要求**：是否需要按钮权限、列权限、数据过滤
- **导入导出**：哪些字段需要 Excel 导入导出

### 2.2 数据库表设计规范

| 规范 | 说明 |
|------|------|
| 表名前缀 | 建议使用 `{包名}_` 前缀，如 `biz_order` |
| 列名风格 | snake_case，如 `order_no`、`created_at` |
| 主键 | 推荐使用 GvaModel（`ID uint` 自增主键） |
| 时间字段 | 使用 `*global.MySQLTime` 类型（模板自动处理） |
| 软删除 | GvaModel 自带 `deleted_at`，配合 `deleted_by` |
| 字符串长度 | 通过 `dataTypeLong` 设置，默认 255 |
| 索引 | 通过 `fieldIndexType` 设置（`index` 或 `uniqueIndex`） |
| JSON 字段 | 使用 `datatypes.JSON` 类型，数据库用 `json` |

**字段类型映射参考**：

| FieldType | Go 类型 | 数据库类型 | 前端组件 | 默认列宽 |
|-----------|---------|-----------|----------|---------|
| `string` | `string` | `varchar(size)` | `el-input` | 120 |
| `richtext` | `string` | 指定 `dataType` | `el-input[textarea]` | 280 |
| `int` | `int` | `int` | `el-input-number` | 80 |
| `int32` | `int32` | `int` | `el-input-number` | 80 |
| `int64` | `int64` | `bigint` | `el-input-number` | 100 |
| `float64` | `float64` | `double/decimal` | `el-input-number[precision=2]` | 100 |
| `bool` | `bool` | `tinyint` | `el-switch` | 80 |
| `enum` | `string` | 指定 `dataType` | `el-select` | 100 |
| `datetime` | `*global.MySQLTime` | `datetime` | `el-date-picker[datetime]` | 180 |
| `date` | `*global.MySQLTime` | `date` | `el-date-picker[date]` | 100 |
| `json` | `datatypes.JSON` | `json` | `el-input[textarea]` | 200 |
| `array` | `datatypes.JSON` | `json` | `el-input[textarea]` | 200 |
| `binary` | `[]byte` | 指定 `dataType` | `el-input[textarea]` | 150 |

### 2.3 创建 Package

如果目标 Package 不存在，需先创建。具体 API 调用请参考 **hab-autocode skill** 的包管理操作。

创建 Package 会自动生成以下骨架文件并通过 AST 注入到父级 enter.go：
- `server/api/v1/{pkg}/enter.go` -- 空的 `ApiGroup` struct
- `server/router/{pkg}/enter.go` -- 空的 `RouterGroup` struct
- `server/service/{pkg}/enter.go` -- 空的 `ServiceGroup` struct

## 3. 生成阶段

### 3.1 使用 AutoCode 生成代码

通过 API 调用 AutoCode 生成 CRUD 代码。具体 curl 命令、请求体格式和字段定义，请参考 **hab-autocode skill**。

关键选项：

| 选项 | 推荐值 | 说明 |
|------|--------|------|
| `gvaModel` | `true` | 标准 ID + 时间戳 + 操作人字段 |
| `autoMigrate` | `true` | 自动创建数据库表 |
| `autoCreateApiToSql` | `true` | 自动注册 API（角色权限中可见） |
| `autoCreateMenuToSql` | `true` | 自动创建菜单（前端可见） |
| `autoCreateBtnAuth` | `true` | 自动创建 9 个标准按钮权限 |
| `autoCreateResource` | `true` | 记录 CreatedBy/UpdatedBy/DeletedBy |
| `generateServer` | `true` | 生成后端代码 |
| `generateWeb` | `true` | 生成前端代码 |

生成操作一次性完成：代码文件创建 + AST 注入 + 数据库建表 + API/菜单/按钮/列权限/导出模板注册 + 历史记录保存。

### 3.2 编译检查

生成后立即编译：

```bash
cd server && go build ./...
```

编译失败常见原因：
- **import 冲突**：AST 注入可能导致重复 import，手动检查 enter.go
- **类型未找到**：检查 model 文件是否正确生成
- **循环依赖**：检查包之间的 import 关系

## 4. 验证阶段

### 4.1 检查文件生成完整性

**后端文件清单**（Package 模式）：

```
[ ] server/api/v1/{pkg}/{humpPackageName}.go      # API 控制器
[ ] server/service/{pkg}/{humpPackageName}.go      # Service 逻辑
[ ] server/router/{pkg}/{humpPackageName}.go       # 路由注册
[ ] server/model/{pkg}/{humpPackageName}.go        # Model 结构体
[ ] server/translation/zh-CN/business/{pkgName}.json  # 中文翻译
[ ] server/translation/en-US/business/{pkgName}.json  # 英文翻译
```

**前端文件清单**：

```
[ ] web/src/view/{pkg}/{pkgName}/{pkgName}.vue         # 表格页面
[ ] web/src/view/{pkg}/{pkgName}/{pkgName}Form.vue     # 表单弹窗
[ ] web/src/api/{pkg}/{pkgName}.js                     # API 调用
```

### 4.2 检查 AST 注入完整性

**server/api/v1/{pkg}/enter.go**：
```go
type {Struct}Api struct {}
// 应包含 service 引用变量：
// var {abbr}Service = service.ServiceGroupApp.{Pkg}ServiceGroup.{Struct}Service
```

**server/router/{pkg}/enter.go**：
```go
type {Struct}Router struct {}
// 应包含 api 引用变量：
// var {abbr}Api = api.ApiGroupApp.{Pkg}ApiGroup.{Struct}Api
```

**server/service/{pkg}/enter.go**：
```go
type {Struct}Service struct {}
```

**server/initialize/router_biz.go**：
```go
{pkg}Router := router.RouterGroupApp.{Pkg}
{pkg}Router.Init{Struct}Router(privateGroup, publicGroup)
```

**server/initialize/gorm_biz.go**（autoMigrate=true 时）：
```go
db.AutoMigrate(&{pkg}.{Struct}{})
```

### 4.3 检查数据库记录

```sql
-- 确认表已创建
SHOW TABLES LIKE '{table_name}';

-- 确认 API 已注册（应有 7 条）
SELECT * FROM sys_apis WHERE api_group = '{abbreviation}';

-- 确认菜单已创建
SELECT * FROM sys_base_menus WHERE name = '{abbreviation}';

-- 确认按钮权限（应有 9 个）
SELECT * FROM sys_base_menu_btns WHERE sys_base_menu_id = {menuId};

-- 确认列配置
SELECT * FROM sys_table_columns WHERE struct_name = '{packageName}';
```

### 4.4 冒烟测试

启动服务后，测试基本 CRUD 接口：

```bash
# 获取 Token
TOKEN=$(curl -s 'http://localhost:8888/base/login' \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"123456"}' | jq -r '.data.token')

# 创建记录
curl -X POST 'http://localhost:8888/{abbr}/create{Struct}' \
  -H "x-token: $TOKEN" -H 'Content-Type: application/json' \
  -d '{...}'

# 查询列表
curl -X POST 'http://localhost:8888/{abbr}/get{Struct}List' \
  -H "x-token: $TOKEN" -H 'Content-Type: application/json' \
  -d '{"pageInfo":{"page":1,"pageSize":10}}'

# 查询单条
curl 'http://localhost:8888/{abbr}/find{Struct}?ID=1' -H "x-token: $TOKEN"

# 更新记录
curl -X PUT 'http://localhost:8888/{abbr}/update{Struct}' \
  -H "x-token: $TOKEN" -H 'Content-Type: application/json' \
  -d '{"ID":1,...}'

# 删除记录
curl -X DELETE 'http://localhost:8888/{abbr}/delete{Struct}?ID=1' -H "x-token: $TOKEN"
```

### 4.5 前端页面验证

- [ ] 菜单出现在侧边栏
- [ ] 表格正常加载数据
- [ ] 列名显示翻译文本（非 JSON key）
- [ ] 新增/编辑/删除/查看操作正常
- [ ] 搜索和排序功能正常
- [ ] 导入导出功能正常（如有 Excel 字段）

## 5. 前端定制任务清单

AutoCode 生成的前端代码基于 DiyTable + DiyForm 动态组件，大部分配置由 `sys_table_columns` 驱动。前端的主要工作是**验证和微调配置**。

### 5.1 表单配置

- [ ] 检查表单弹窗四种模式（create/edit/view/copy）正常
- [ ] `formMust` 标记业务必填字段（前端红色星号）
- [ ] `formWith` 宽度合理（默认 45%，richtext/json 默认 93%）
- [ ] `formOrder` 排序符合业务逻辑
- [ ] `formDisabled` / `formHidden` 对系统字段正确设置
- [ ] 枚举字段的 `enum` 数组完整（替换默认 `["1","2","3"]` 占位符）

**type 值关键问题**：AutoCode 可能将数据库 `int` 映射为 `type: "int"`，DiyForm 不识别此值（渲染为 textarea），必须改为 `int32`。

DiyForm 支持的 type 值：`string`, `bool`/`boolean`, `int32`, `int64`, `number`, `amount`, `float`, `float64`, `date`, `datetime`, `uintDate`, `enum`/`protoEnum`, `textarea`, `table`, `object`

### 5.2 列表配置

- [ ] 列宽（`with`）根据实际数据内容调整
- [ ] 重要列设置 `fixed: "left"`，操作列设置 `fixed: "right"`
- [ ] `sort` 值让业务关键列靠前
- [ ] `isShow` 隐藏不需要展示的列
- [ ] `sortable` 确认需要排序的列

### 5.3 搜索条件

- [ ] 为常用查询字段设置 `isAddSearch: true`
- [ ] `searchWidth` 根据搜索框内容调整
- [ ] `defaultFilter` 和 `filterList` 配置合理

### 5.4 翻译文件

- [ ] `server/translation/zh-CN/business/{pkgName}.json` 中 columns 翻译完整
- [ ] enum 占位符已替换为真实业务含义
- [ ] `messages` 段添加业务特定提示
- [ ] `server/translation/en-US/business/{pkgName}.json` 同步更新
- [ ] 菜单翻译在 `server/translation/{lang}/menu.json` 中有对应条目

翻译 key 在前端通过 `$t('business.{packageName}.columns.{fieldJson}')` 引用。

```json
{
  "columns": { "orderNo": "订单号", "status": "状态" },
  "enums": {
    "status": { "1": "待处理", "2": "处理中", "3": "已完成" }
  },
  "messages": {
    "confirmComplete": "确认将此订单标记为已完成？"
  }
}
```

### 5.5 按钮权限

- [ ] 9 个标准按钮权限已创建（仅 authorityId=1）
- [ ] 如需 copy 功能，手动添加 `copy` 按钮权限
- [ ] 其他角色的权限由管理员通过管理界面手动分配

标准按钮：`add`, `batchDelete`, `delete`, `edit`, `info`, `exportTemplate`, `exportExcel`, `importExcel`, `columnConfig`

### 5.6 自定义列渲染（Slot 机制）

DiyTable 支持通过 slot 自定义列渲染：

```vue
<Table :tableData="tableData" :columns="columns" ref="tableRef">
  <template #operate="scope">
    <el-button @click="handleView(scope.row)">查看</el-button>
  </template>
  <template #status="scope">
    <el-tag :type="scope.row.status === 'active' ? 'success' : 'danger'">
      {{ scope.row.status }}
    </el-tag>
  </template>
</Table>
```

DiyForm 自定义字段通过 slot 扩展（`column-{jsonName}`、`additional`）。

## 6. 后端定制任务清单

### 6.1 业务逻辑定制

生成的 Service 层是通用 CRUD，需根据业务需求定制：

- [ ] **Create**：添加业务校验（唯一性检查、关联数据校验、自动生成编号、设置默认状态）
- [ ] **Update**：改用 `Updates()` 替代 `Save()`（避免覆盖未传字段）
- [ ] **Delete**：添加级联检查（如有关联子表不允许删除）
- [ ] **GetList**：添加自定义搜索条件或数据权限过滤
- [ ] **Import**：根据业务需求定制导入逻辑（数据校验、去重）
- [ ] **Public**：实现公开接口的具体业务逻辑

```go
// 示例：创建时添加业务校验
func (s *OrderService) CreateOrder(order *business.Order, c *gin.Context) error {
    if order.Amount <= 0 {
        return errors.New("金额必须大于0")
    }
    order.OrderNo = generateOrderNo()
    order.Status = "pending"
    return global.HAB_DB.Create(order).Error
}
```

### 6.2 数据校验

- [ ] API 层使用 `binding` tag（如 `binding:"required,min=3,max=50"`）
- [ ] Service 层添加业务规则校验
- [ ] 错误码使用项目标准 code 包

### 6.3 数据权限过滤

```go
// 非超管按创建人过滤数据
authorityId := utils.GetUserAuthorityId(c)
if authorityId != 1 {
    db = db.Where("created_by = ?", utils.GetUserID(c))
}
```

或通过 `SysDataFilter` 配置声明式数据过滤。

### 6.4 索引优化

- [ ] 高频查询字段添加 `index`
- [ ] 唯一约束字段添加 `uniqueIndex`
- [ ] 组合查询考虑复合索引（需在 model 中手动添加）

### 6.5 添加自定义方法

使用 hab-autocode skill 的 addFunc API 为模块添加新方法。自动追加 API handler + Service 方法 + 前端 API 函数 + 路由注入。

### 6.6 GORM 注意事项

| 场景 | 问题 | 解决方案 |
|------|------|----------|
| 更新零值 | `Save()` 全量更新，零值可能丢失 | 使用 `Updates()` + map |
| 批量更新 | `Save()` 性能差 | 使用 `Updates()` 指定字段 |
| 软删除查询 | 默认过滤已删除记录 | 使用 `Unscoped()` |
| 关联查询 | 默认不加载关联 | 使用 `Preload()` 或 `Joins()` |
| 事务 | 删除需要先更新 deleted_by | 使用 `Transaction()` |
| JSON 字段 | `datatypes.JSON` | 查询用 `JSON_CONTAINS`，更新用 `gorm.Expr` |

```go
// 生成的默认代码使用 Save() -- 全量更新
db.Save(&order)

// 推荐：部分字段更新
db.Model(&order).Updates(map[string]interface{}{
    "status": "completed",
    "amount": 100.5,
})
```

## 7. sys_table_columns 配置详解

`SysTableColumns` 控制 DiyTable 和 DiyForm 的动态渲染，每个字段一条记录。

### 7.1 列配置字段

| 字段 | 类型 | 说明 | AutoCode 默认值 |
|------|------|------|----------------|
| `tbName` | string | 数据库表名 | 自动填充 |
| `menuId` | uint | 关联菜单 ID | 自动填充 |
| `structName` | string | 结构名称 | 自动填充 |
| `jsonName` | string | JSON 字段名 | 自动填充 |
| `columnName` | string | 数据库列名 | 自动填充 |
| `with` | int32 | 列宽（px） | 按类型设置 |
| `type` | string | 字段类型 | 同 fieldType |
| `sortable` | bool | 是否可排序 | `true` |
| `filter` | bool | 是否可筛选 | `true` |
| `defaultFilter` | string | 默认筛选方式 | string→like, int→=, datetime→between |
| `filterList` | []string | 可用筛选操作符 | 按类型设置 |
| `sort` | int | 列显示顺序 | 按字段顺序递增 |
| `note` | string | 备注 | 字段 comment |
| `isShow` | bool | 是否显示列 | `true`（DeletedAt/DeletedBy 为 `false`） |
| `enum` | []string | 枚举值列表 | enum 类型默认 `["1","2","3"]` |
| `fixed` | string | 固定列 | `""`（空=不固定） |
| `isAddSearch` | bool | 添加到搜索区 | `false` |
| `searchWidth` | int32 | 搜索框宽度 | `0`（自动） |
| `isSum` | bool | 是否求和 | `false` |

### 7.2 FormInfo 字段

| 字段 | 类型 | 说明 | AutoCode 默认值 |
|------|------|------|----------------|
| `formWith` | int | 表单项宽度% | 45（richtext/json 为 93） |
| `formDisabled` | bool | 表单禁用 | `false`（系统字段为 `true`） |
| `formHidden` | bool | 表单隐藏 | `false`（系统字段为 `true`） |
| `formOrder` | int | 表单排序 | 按字段顺序递增 |
| `formMust` | bool | 必填星号 | `false`（需手动设置） |

### 7.3 通过 API 更新配置

```
PUT /sysTableColumns/updateSysTableColumns
```

或通过前端「列配置」管理页（columnConfig 按钮）批量更新。

### 7.4 GvaModel 自动生成的系统字段配置

开启 `gvaModel: true` 时，AutoCode 额外生成 7 个系统字段的列配置：

| 字段 | isShow | formDisabled | formHidden | 说明 |
|------|--------|-------------|------------|------|
| ID | true | true | true | 主键，表格显示但表单隐藏 |
| CreatedAt | true | true | true | 创建时间 |
| UpdatedAt | true | true | true | 修改时间 |
| DeletedAt | false | true | true | 删除时间，默认不显示 |
| CreatedBy | true | true | true | 创建人 |
| UpdatedBy | true | true | true | 修改人 |
| DeletedBy | false | true | true | 删除人，默认不显示 |

## 8. 验证方法

### 8.1 编译检查

```bash
cd server && go build ./...
```

### 8.2 功能测试（9 项标准测试）

| # | 测试项 | 验证要点 |
|---|--------|----------|
| 1 | 创建记录 | 必填校验、类型校验、数据持久化 |
| 2 | 编辑记录 | 数据回显、部分更新 |
| 3 | 删除单条 | 软删除、deleted_by 记录 |
| 4 | 批量删除 | 多选删除、deleted_by 批量更新 |
| 5 | 查询详情 | 数据完整性 |
| 6 | 分页列表 | 分页参数、排序、默认排序 |
| 7 | 搜索筛选 | 各筛选操作符（=、like、between 等） |
| 8 | 导入 | 全量导入（TRUNCATE）、追加导入 |
| 9 | 导出 | 列映射、数据格式 |

### 8.3 权限测试

- [ ] 超管（authorityId=1）访问所有功能
- [ ] 未授权角色 API 返回 403
- [ ] 按钮权限：未授权按钮不显示
- [ ] 列权限：未授权列不返回数据

### 8.4 集成检查清单

```
[ ] go build ./... 编译通过
[ ] enter.go 注册完整（api/router/service 三层）
[ ] router_biz.go 路由初始化注入正确
[ ] gorm_biz.go AutoMigrate 注入正确
[ ] 数据库表已创建且字段正确
[ ] sys_apis 表有 7 条 API 记录
[ ] sys_base_menus 表有菜单记录
[ ] sys_base_menu_btns 表有 9 个按钮
[ ] sys_table_columns 表有列配置记录
[ ] 翻译文件存在且内容正确
```

## 9. 优化建议

### 9.1 性能优化

**数据库**：
- 为高频查询字段添加索引
- 列表查询已使用 `utils.GetColumns()` 按权限选列，避免 `SELECT *`
- 分页查询必须传 pageSize 上限
- Import 全量模式使用 `TRUNCATE + Create` 在事务中执行

**API**：
- 列表接口默认分页（PageSize 不超过 100）
- 对不常变化的数据源接口添加 Redis 缓存

**前端**：
- 大数据量表格使用虚拟滚动
- 搜索防抖（DivSearch 组件已内置）
- 大数据导出使用 CustomExport 的 `batchSize` 分批

### 9.2 安全优化

- [ ] 敏感字段不在列表和导出中返回（`isShow: false`）
- [ ] 批量删除添加数量限制
- [ ] Import 接口添加文件大小和行数限制
- [ ] 自定义 SQL 使用参数化查询（GORM 默认已参数化）
- [ ] 操作记录中间件已自动配置在写入类路由上

### 9.3 代码质量

**Create/Update struct 分离**（推荐）：

```go
type CreateOrderReq struct {
    OrderNo string  `json:"orderNo" binding:"required"`
    Amount  float64 `json:"amount" binding:"required,gt=0"`
}

type UpdateOrderReq struct {
    ID     uint   `json:"id" binding:"required"`
    Status string `json:"status"`
}
```

**错误处理规范**：

```go
// 使用 errors.Wrap 提供上下文
return errors.Wrap(err, "创建订单失败")

// 使用 zap 结构化日志
global.HAB_LOG.Error("订单创建失败",
    zap.String("orderNo", order.OrderNo),
    zap.Error(err),
)
```

## 10. 常见问题与解决方案

### 10.1 编译失败

| 错误 | 原因 | 解决 |
|------|------|------|
| `undefined: {pkg}.{Struct}` | Model 文件未生成或包名不对 | 检查 `model/{pkg}/{humpPackageName}.go` |
| `imported and not used` | AST 注入了多余的 import | 手动删除未使用的 import |
| `duplicate field` | 重复创建导致 enter.go 字段重复 | 回滚后重新生成 |
| `cannot use ... as type` | 类型不匹配 | 检查 service 引用链和类型声明 |

### 10.2 前端页面空白

| 检查项 | 说明 |
|--------|------|
| 菜单 component 路径 | 确认 `view/{pkg}/{packageName}/{packageName}.vue` 正确 |
| 前端文件存在 | vue 和 js 文件已生成 |
| 角色菜单权限 | 当前角色已分配该菜单 |
| 浏览器控制台 | 检查 JS 报错和 404 请求 |
| 路由刷新 | 重新登录刷新菜单缓存 |

### 10.3 API 404

| 检查项 | 说明 |
|--------|------|
| router_biz.go | 包含 `Init{Struct}Router(privateGroup, publicGroup)` |
| 路由文件 | `router/{pkg}/{humpPackageName}.go` 路由注册正确 |
| 服务重启 | 修改路由后需要重启后端 |
| API 路径 | 前端调用路径与后端注册路径一致 |
| Casbin 策略 | `sys_apis` 中有对应记录且角色已授权 |

### 10.4 权限不足（403）

| 检查项 | 说明 |
|--------|------|
| API 授权 | 角色管理 → API 权限 → 勾选对应 API |
| 菜单授权 | 角色管理 → 菜单权限 → 勾选对应菜单 |
| 按钮授权 | 角色管理 → 按钮权限 → 勾选需要的按钮 |
| Casbin 缓存 | 修改权限后可能需要重启服务 |

### 10.5 数据不显示

| 检查项 | 说明 |
|--------|------|
| 列权限 | `sys_authority_cols` 中有对应记录 |
| columns 配置 | `sys_table_columns` 中 `isShow = true` |
| 翻译文件 | JSON 无语法错误 |
| API 返回 | 浏览器 Network 检查返回数据 |

### 10.6 表单提交失败

| 错误 | 原因 | 解决 |
|------|------|------|
| `invalid params` | 必填字段未填 | 检查 `binding:"required"` 和前端必填配置 |
| `record not found` | 更新时 ID 不存在 | 检查传递的 ID 值 |
| 日期格式错误 | 前后端格式不匹配 | 确认 `value-format` 为 `YYYY-MM-DD HH:mm:ss` |
| 类型错误 | type 与字段类型不匹配 | 修改 sys_table_columns 的 type 值 |

### 10.7 回滚相关

| 问题 | 解决 |
|------|------|
| 回滚后编译失败 | 手动检查 enter.go / router_biz.go / gorm_biz.go 残留代码 |
| 回滚后表还存在 | 手动 `DROP TABLE` 或设 `deleteTable: true` |
| 回滚后菜单还存在 | 手动删除或设 `deleteMenu: true` |
| 回滚文件在哪 | `rm_file/{timestamp}/` 目录（非永久删除） |

## 11. 快速参考

### 生成后最小可用清单

```
[ ] go build ./... 编译通过
[ ] sys_table_columns 的 type 值检查（int → int32）
[ ] 翻译文件 enum 占位符替换
[ ] formMust 标记业务必填字段
[ ] 页面正常加载、CRUD 操作正常
```

### 生成后生产就绪清单

```
[ ] 所有最小可用清单项
[ ] Service 层 Save → Updates 改造
[ ] 业务校验逻辑（唯一性、关联、状态流转）
[ ] 索引优化
[ ] 列宽、列顺序、固定列配置
[ ] 搜索条件配置（isAddSearch）
[ ] 翻译文件完善（columns + enums + messages + en-US）
[ ] 菜单翻译
[ ] 非超管角色权限分配
[ ] 敏感字段保护
[ ] 导入导出配置
```

### 相关文档索引

| 文档 | 位置 | 内容 |
|------|------|------|
| AutoCode 内部架构 | hab-temp `autocode-guide.md` | 模板系统、AST 注入、生成流程 |
| AutoCode API 操作 | hab-autocode `SKILL.md` | curl 命令、请求体格式、包管理 |
| 字段定义参考 | hab-autocode `field-reference.md` | AutoCode/AutoCodeField/AutoFunc 完整字段 |
| 生成后完善 | hab-autocode `post-generation-guide.md` | SysTableColumns 配置、翻译、按钮权限 |
| DiyTable/DiyForm | hab-temp `diy-components.md` | 动态组件配置和 slot 扩展 |
| 后端分层架构 | hab-temp `backend-layers.md` | 各层职责、QueryInfo、TableQuery 等后端模式 |
