# 系统工具集参考文档

本文档涵盖 hz-admin-base 中的系统级工具功能，包括导出模板、Excel 导入导出、操作记录、数据过滤、定时任务和系统状态监控。

---

## 1. 导出模板系统

### 1.1 数据模型

导出模板的核心模型位于 `server/model/system/sys_export_template.go`。

**SysExportTemplate 主表**

| 字段 | 类型 | 说明 |
|------|------|------|
| `HAB_MODEL` | 嵌入 | 提供 ID/CreatedAt/UpdatedAt/DeletedAt |
| `DBName` | `string` | 数据库名称（多库场景下指定目标库，空值表示默认库） |
| `Name` | `string` | 模板名称（导出文件名） |
| `TableName` | `string` | 目标数据表名称 |
| `TemplateID` | `string` | 模板唯一标识，前端组件通过此值绑定 |
| `TemplateInfo` | `string` | JSON 格式的列映射，key 为数据库列名，value 为 Excel 表头名称 |
| `Limit` | `*int` | 默认导出条数限制 |
| `Order` | `string` | 默认排序条件，如 `id desc` |
| `Conditions` | `[]Condition` | 查询条件列表（外键关联 TemplateID） |
| `JoinTemplate` | `[]JoinTemplate` | 表关联配置（外键关联 TemplateID） |

**Condition 条件表** (表名 `sys_export_template_condition`)

| 字段 | 说明 |
|------|------|
| `TemplateID` | 关联的模板标识 |
| `From` | 从请求查询参数中取值的 key |
| `Column` | 数据库表中用作过滤条件的列名 |
| `Operator` | SQL 操作符：`=`、`<>`、`>`、`<`、`LIKE`、`BETWEEN`、`NOT BETWEEN` |

**JoinTemplate 关联表** (表名 `sys_export_template_join`)

| 字段 | 说明 |
|------|------|
| `TemplateID` | 关联的模板标识 |
| `JOINS` | 关联方式：`LEFT JOIN` / `INNER JOIN` / `RIGHT JOIN` |
| `Table` | 关联目标表名 |
| `ON` | 关联条件，如 `table1.id = table2.fk_id` |

### 1.2 TemplateInfo 格式

TemplateInfo 是 JSON 字符串，key 为 SELECT 的列名，value 为 Excel 列标题：

```json
{
  "id": "编号",
  "name": "姓名",
  "created_at": "创建时间"
}
```

JOIN 模式下需使用 `表名.列名` 格式：

```json
{
  "users.name": "用户名",
  "orders.amount": "订单金额",
  "users.id as user_id": "用户ID"
}
```

### 1.3 Service 层核心方法

Service 位于 `server/service/system/sys_export_template.go`，使用 `excelize/v2` 库操作 Excel。

- **ExportExcel(templateID, values)** - 根据模板和 URL 参数导出数据到 Excel。支持动态条件过滤、limit/offset/order 参数覆盖、多表 JOIN、多数据库、时间类型自动格式化
- **ExportTemplate(templateID)** - 导出空的 Excel 模板（仅包含表头），用于导入时的格式参考
- **ImportExcel(templateID, file)** - 根据模板读取上传的 Excel 文件，自动映射列名并批量写入数据库（每批 1000 条），自动补充 `created_at` 和 `updated_at`

### 1.4 前端模板管理

模板管理页面位于 `web/src/view/systemTools/exportTemplate/exportTemplate.vue`，提供：
- 模板的 CRUD 操作（创建、编辑、复制、删除）
- 数据库和表选择联动
- AI 辅助填写模板信息（自动生成 TemplateInfo、名称、标识）
- 自动从表结构生成列映射
- 可视化配置 JOIN 关联和查询条件
- 生成前端使用代码片段

---

## 2. Excel 导入导出组件

前端提供两套 Excel 导入导出方案，分别用于不同场景。

### 2.1 基于模板的组件（简单方案）

位于 `web/src/components/exportExcel/` 目录。

**exportExcel.vue** - 导出按钮组件

```vue
<ExportExcel
  template-id="user_export"
  :condition="{ status: 1 }"
  :limit="1000"
  :offset="0"
  order="id desc"
/>
```

Props：`templateId`（必填）、`condition`（查询条件对象）、`limit`、`offset`、`order`。通过 URL 直接打开后端导出接口。

**exportTemplate.vue** - 下载空模板按钮

```vue
<ExportTemplate template-id="user_export" />
```

**importExcel.vue** - 导入按钮组件

```vue
<ImportExcel template-id="user_export" @on-success="refreshData" />
```

使用 `el-upload` 直接上传文件到后端 `/sysExportTemplate/importExcel` 接口。

### 2.2 自定义导出组件（高级方案）

**customExport.vue** - 前端分批导出

```vue
<CustomExport
  :fetch-function="getListApi"
  :search-info="searchParams"
  :columns="tableColumns"
  file-name="export_name"
  :batch-size="1000"
/>
```

功能特性：
- 下拉菜单支持"导出全部"、"导出当前条件"、"导出模板"三种模式
- 前端分批拉取数据，显示进度条
- 自动识别列类型（boolean/date/number/float/json/image）并格式化
- 含图片列时使用 ExcelJS 嵌入图片；纯文本时使用 XLSX 库高效导出
- Excel 文件结构：第 1 行 key、第 2 行 label、第 3 行 type、第 4 行起为数据
- 支持按钮权限控制（`btnAuth.exportExcel`、`btnAuth.exportTemplate`）

**customImport.vue** - 前端解析导入

```vue
<CustomImport
  :import-function="importApi"
  :columns="tableColumns"
  @import-success="refreshData"
/>
```

功能特性：
- 前端解析 Excel 文件（XLSX 库），自动根据类型行转换数据
- 支持"全量导入"（truncate + insert）和"增量导入"（append）两种模式
- 自动跳过格式提示行和空行
- 类型转换覆盖：boolean、number（各种整数/浮点类型）、json、string

---

## 3. 操作记录系统

### 3.1 数据模型

位于 `server/model/system/sys_operation_record.go`。

**SysOperationRecord 字段**

| 字段 | 类型 | 说明 |
|------|------|------|
| `Ip` | `string` | 请求来源 IP |
| `Method` | `string` | HTTP 请求方法（GET/POST/PUT/DELETE） |
| `Path` | `string` | 请求路径 |
| `Status` | `int` | HTTP 响应状态码 |
| `Latency` | `time.Duration` | 请求处理耗时 |
| `Agent` | `string` | User-Agent 信息 |
| `ErrorMessage` | `string` | 错误信息（如有） |
| `Body` | `string` | 请求 Body（text 类型） |
| `Resp` | `string` | 响应 Body（text 类型） |
| `UserID` | `int` | 操作用户 ID |
| `User` | `SysUser` | 关联的用户对象 |

### 3.2 自动记录机制

操作记录通过 Gin 中间件自动采集，拦截每个 HTTP 请求并记录上述字段。Service 位于 `server/service/system/sys_operation_record.go`。

### 3.3 查询特性

- 列表查询默认过滤 GET 请求（`method != 'GET'`），仅记录写操作
- 按当前登录用户过滤（`user_id = ?`）
- 支持按 Method、Path（模糊匹配）、Status 筛选
- 按 ID 降序排列，Preload 关联用户信息

### 3.4 前端展示

操作记录页面位于 `web/src/view/superAdmin/operation/sysOperationRecord.vue`，展示操作人、日期、状态码、请求 IP、方法、路径，Body 和 Resp 通过 Popover 弹窗查看 JSON 格式化内容。

---

## 4. 数据过滤系统

### 4.1 数据模型

位于 `server/model/system/sys_data_filter.go`，表名 `sys_data_filter`。

**SysDataFilter 字段**

| 字段 | 类型 | 说明 |
|------|------|------|
| `Name` | `string` | 过滤器名称 |
| `Sql` | `string` | 基础 SQL 查询语句 |
| `Columns` | `gtype.Arr[SysDataFilterColumn]` | 列配置（JSON 存储） |
| `Key` | `string` | 数据主键字段名 |
| `Label` | `string` | 显示标题字段名 |
| `Value` | `string` | 取值字段名 |
| `OrderBy` | `string` | 排序规则 |
| `Note` | `string` | 备注说明 |
| `CreatedBy/UpdatedBy/DeletedBy` | `uint` | 操作审计字段 |

**SysDataFilterColumn 列配置**

| 字段 | 类型 | 说明 |
|------|------|------|
| `ColumnName` | `string` | 数据库列名 |
| `Label` | `string` | 列显示标题 |
| `IsShow` | `bool` | 是否在界面显示 |
| `Filter` | `bool` | 是否参与过滤搜索 |
| `Sort` | `int` | 排序序号 |

### 4.2 Service 核心逻辑

位于 `server/service/system/sys_data_filter.go`。

**ExecuteSql(sqlStr)** - 执行 SQL 并返回列结构信息（通过 `LIMIT 0` 获取列类型而不取数据）。用于前端配置时自动获取列信息。

**FilterData(filters, id)** - 核心过滤方法：
1. 根据 ID 加载过滤器配置
2. 找出标记为 `Filter=true` 的列
3. 对每个 filter 关键字，在所有过滤列上生成 `LIKE` 条件并用 `OR` 连接
4. 多个 filter 之间用 `AND` 连接
5. 将条件作为 `HAVING` 子句拼接到原始 SQL 后执行

**ImportSysDataFilter(tep, list)** - 支持两种导入模式：
- `ImportType_Full`：先 TRUNCATE 清空表再批量写入
- `ImportType_Append`：保留现有数据，追加写入（重置 ID 和时间戳）

### 4.3 前端界面

管理页面位于 `web/src/view/system/sysDataFilter/`，提供：
- 过滤器的 CRUD 管理
- 使用 `SelectTool` 组件展示过滤效果
- 支持 CustomExport/CustomImport 进行数据导入导出
- 表格列配置（ColOptions）和权限控制

---

## 5. 定时任务系统

### 5.1 Timer 接口

定时任务基于 `robfig/cron/v3` 封装，接口定义在 `server/utils/timer/timed_task.go`。

**Timer 接口方法**

| 方法 | 说明 |
|------|------|
| `AddTaskByFunc(cronName, spec, func, taskName)` | 通过函数添加任务（分钟级 Cron） |
| `AddTaskByFuncWithSecond(cronName, spec, func, taskName)` | 通过函数添加任务（秒级 Cron） |
| `AddTaskByJob(cronName, spec, job, taskName)` | 通过 Job 接口添加任务（分钟级） |
| `AddTaskByJobWithSeconds(cronName, spec, job, taskName)` | 通过 Job 接口添加任务（秒级） |
| `FindCronList()` | 获取所有 cronName 及其任务列表 |
| `FindCron(cronName)` | 获取指定 cronName 的 taskManager |
| `FindTask(cronName, taskName)` | 查找指定任务 |
| `StartCron(cronName)` | 启动指定 cron |
| `StopCron(cronName)` | 停止指定 cron |
| `RemoveTask(cronName, id)` | 按 EntryID 删除任务 |
| `RemoveTaskByName(cronName, taskName)` | 按 taskName 删除任务 |
| `Clear(cronName)` | 清除指定 cronName 的所有任务 |
| `Close()` | 停止所有任务并释放资源 |

参数说明：
- `cronName`：cron 组名称，同一 cronName 下的任务共享同一个 cron 调度器
- `spec`：Cron 表达式。分钟级格式 `分 时 日 月 周`（如 `*/5 * * * *` 每 5 分钟），秒级格式 `秒 分 时 日 月 周`
- `taskName`：任务名称标识

### 5.2 全局实例

```go
global.HAB_Timer  // timer.Timer 类型，系统启动时已初始化
```

### 5.3 注册方式

定时任务注册入口在 `server/initialize/timer.go`，调用 `timedtask.BackendTimerTask()`。

任务定义在 `server/timedtask/base.go`：

```go
func BackendTimerTask() {
    // 每1分钟执行一次
    if _, err := global.HAB_Timer.AddTaskByFunc("test", "* * * * *", test, "test"); err != nil {
        global.HAB_LOG.Error("add timer test error:", zap.Error(err))
    }
}
```

### 5.4 扩展定时任务

在 `server/timedtask/` 目录下新建文件，编写任务函数或 Job struct，然后在 `BackendTimerTask()` 中注册：

```go
// 方式一：函数方式
global.HAB_Timer.AddTaskByFunc("myGroup", "0 2 * * *", myTask, "dailyCleanup")

// 方式二：Job 接口方式（需实现 Run() 方法）
type MyJob struct{}
func (j MyJob) Run() { /* 任务逻辑 */ }
global.HAB_Timer.AddTaskByJob("myGroup", "*/30 * * * *", MyJob{}, "halfHourJob")

// 秒级任务
global.HAB_Timer.AddTaskByFuncWithSecond("myGroup", "*/10 * * * * *", myFunc, "every10sec")
```

---

## 6. 系统运行状态监控

### 6.1 后端 API

API 位于 `server/api/v1/system/sys_system.go`。

- `GetServerInfo` (`POST /system/getServerInfo`) - 返回服务器运行状态信息
- `GetSystemConfig` (`POST /system/getSystemConfig`) - 获取系统配置
- `SetSystemConfig` (`POST /system/setSystemConfig`) - 设置系统配置
- `ReloadSystem` (`POST /system/reloadSystem`) - 重启系统服务

### 6.2 监控指标

前端页面 `web/src/view/system/state.vue` 展示四个模块，每 10 秒自动刷新：

**Runtime 运行时信息**
- `goos` - 操作系统类型
- `numCpu` - CPU 数量
- `compiler` - 编译器
- `goVersion` - Go 版本
- `numGoroutine` - 当前 Goroutine 数量

**Disk 磁盘信息**（支持多挂载点）
- `mountPoint` - 挂载点
- `totalMb` / `totalGb` - 总容量
- `usedMb` / `usedGb` - 已用容量
- `usedPercent` - 使用百分比（仪表盘展示）

**CPU 信息**
- `cores` - 物理核心数
- `cpus[]` - 每个核心的使用率百分比（进度条展示）

**RAM 内存信息**
- `totalMb` - 总内存
- `usedMb` - 已用内存
- `usedPercent` - 使用百分比（仪表盘展示）

颜色阈值：0-20% 绿色、20-40% 黄色、40%+ 红色。

---

## 7. 扩展与自定义指南

### 7.1 新增导出模板

1. 在模板管理页面创建模板，填写表名、TemplateInfo JSON、查询条件
2. 记下 `templateID`，在业务页面使用 `<ExportExcel template-id="xxx" />` 或 `<CustomExport />` 组件
3. 多表导出需配置 JoinTemplate 关联关系

### 7.2 自定义操作记录

操作记录通过中间件自动采集。如需扩展：
- 修改中间件以增加自定义字段
- 调整查询 Service 的过滤条件（默认排除 GET 请求）

### 7.3 新增数据过滤器

1. 在数据过滤管理页面创建过滤器
2. 编写 SQL 查询，系统自动识别列结构
3. 配置列的显示/过滤属性
4. 在业务页面通过 `SelectTool` 组件引用过滤器 ID

### 7.4 添加定时任务

1. 在 `server/timedtask/` 创建任务文件
2. 在 `BackendTimerTask()` 中使用 `global.HAB_Timer.AddTaskByFunc()` 注册
3. 使用 `FindCronList()` 或 `FindTask()` 监控任务状态

### 7.5 扩展系统监控

系统状态通过 `systemConfigService.GetServerInfo()` 采集。如需增加监控指标：
- 后端在 service 层扩展采集逻辑
- 前端在 `state.vue` 中增加展示卡片
