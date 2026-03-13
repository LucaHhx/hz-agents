# DiyTable / DiyForm 动态组件体系参考文档

## 1. 动态组件体系概览

hz-admin-base 提供了一套完整的**配置驱动**动态组件体系，核心理念是：后端通过 `sys_table_columns` 表存储每个业务表的字段配置，前端组件根据这些配置自动渲染表格、表单、搜索栏和弹窗。

### 组件关系图

```
页面（业务 .vue）
 ├── DiySearch（search.vue）     — 顶部搜索表单，根据 isAddSearch 字段自动生成
 ├── DiyTable（table.vue）       — 数据表格，根据 columns 配置自动渲染列
 │    ├── queryFrom.vue          — 列头内嵌的高级筛选弹出框
 │    └── coloptions.vue         — 列配置管理对话框（运行时调整列显示/宽度/类型等）
 ├── DiyForm（diyForm.vue）      — 新增/编辑/查看表单对话框
 │    └── fromColOptions.vue     — 表单列配置管理对话框
 ├── DiyPop（diyPop/index.vue）  — 通用弹窗容器（当前为空壳预留）
 └── DynamicForm（DynamicForm.vue） — 独立的 API 驱动动态表单
```

### 核心数据流

```
后端 sys_table_columns 表
  ↓ getStructNameColumns API
前端获取 columns 配置数组
  ↓ 传入 props
DiyTable / DiyForm / DiySearch 根据配置渲染
```

---

## 2. DiyTable 组件详解

**文件路径**: `web/src/components/diyTable/table.vue`

### 2.1 Props 列表

| Prop | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `structName` | String | 是 | - | 业务结构名称，用于 i18n 翻译 key 拼接 |
| `tableData` | Array | 是 | - | 表格数据数组 |
| `columns` | Array | 是 | - | 列配置数组（来自 sys_table_columns） |
| `rowKey` | String | 是 | `'ID'` | 行数据唯一标识字段名 |
| `showSelection` | Boolean | 否 | `false` | 是否显示多选列 |
| `total` | Number | 是 | `0` | 数据总条数（用于分页） |
| `getTableData` | Function | 是 | - | 获取表格数据的回调函数，分页/排序变化时自动调用 |
| `defaultSort` | Object | 否 | `{}` | 默认排序配置 |
| `sumData` | Object | 否 | `{}` | 自定义合计方法映射，key 为 jsonName |
| `height` | String/Number | 否 | `''` | 表格固定高度，为空时取 appStore 全局配置 |

### 2.2 列配置格式（sys_table_columns 数据结构）

每条列配置记录对应一个字段，字段详见第 6 节。组件通过 `columns.filter(column => column.isShow)` 决定哪些列可见。

### 2.3 内置功能

#### 分页
组件内置 `el-pagination`，支持页码切换和每页条数选择（5/10/30/50/100），变化时自动调用 `getTableData`。

```javascript
// 分页信息通过 getQueryInfo() 暴露
const pageInfo = ref({ page: 1, pageSize: 10, total: 0 })
```

#### 排序
列配置中 `sortable: true` 的列会在表头显示排序图标，点击循环切换：无序 -> 升序(asc) -> 降序(desc) -> 无序。支持多列排序，排序信息通过 `sortInfo` 传递给后端。

#### 合计行
当 `columns` 中存在 `isSum: true` 的列时，自动显示合计行。支持两种合计方式：
- **默认求和**: 自动对该列数值求和
- **自定义合计**: 通过 `sumData` prop 传入自定义函数

```javascript
// 自定义合计函数签名
sumData: {
  fieldName: ({ res, data, column }) => {
    // res: 已计算的其他列合计结果
    // data: 当前页全部行数据
    // column: 当前列配置
    return computedValue
  }
}
```

#### 多选
设置 `showSelection: true` 后显示勾选列，通过 `getSelectedData()` 获取选中行。

#### 双击复制
双击单元格自动复制该单元格内容到剪贴板。

#### 列类型渲染
根据列配置的 `type` 字段自动渲染不同格式：

| type 值 | 渲染方式 |
|---------|---------|
| `boolean` | 显示"是"/"否" |
| `date` | 只显示日期部分（截取空格前） |
| `datetime` | 显示完整日期时间 |
| `uintDate` | 通过 `$serverDate` 格式化无符号日期 |
| `tag` | 根据 `column.tagData` 映射渲染 el-tag |
| `enum` / `protoEnum` | 渲染为彩色 el-tag，颜色按枚举值索引取模 5 循环（primary/success/warning/danger/info） |
| `table` | 渲染为 SelectTool 关联表显示组件 |
| `image` | 渲染为 el-image（base64 图片） |
| 其他 | 纯文本显示，支持 format 格式化 |

### 2.4 自定义列（slot 机制）

DiyTable 提供 `operate` 具名 slot，用于在表格最右侧添加操作列：

```vue
<DiyTable :columns="columns" :table-data="tableData" ...>
  <template #operate="{ row }">
    <el-button @click="handleEdit(row)">编辑</el-button>
    <el-button @click="handleDelete(row)">删除</el-button>
  </template>
</DiyTable>
```

操作列自动固定在右侧（`fixed="right"`），最小宽度取自 `appStore.operateMinWith`（桌面端 240px，移动端 80px）。

### 2.5 查询表单集成

DiyTable 内部引用了 `queryFrom.vue` 组件，该组件以 Tooltip 弹出框形式出现在每列表头，提供列级精确筛选。筛选条件通过 `searchInfo` 合并到查询请求中。

### 2.6 暴露方法（defineExpose）

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `clearSearch()` | void | 清空搜索条件和排序，重置为 defaultSort |
| `getSelectedData()` | Array | 获取当前选中的行数据 |
| `getQueryInfo()` | Object | 返回 `{ pageInfo, searchInfo, sortInfo }` |

### 2.7 使用示例

```vue
<template>
  <div>
    <DiySearch ref="searchRef" :columns="columns" />
    <DiyTable
      ref="tableRef"
      struct-name="order"
      :columns="columns"
      :table-data="tableData"
      :total="total"
      :get-table-data="getTableData"
      row-key="ID"
      show-selection
    >
      <template #operate="{ row }">
        <el-button size="small" @click="openEdit(row)">编辑</el-button>
      </template>
    </DiyTable>
    <DiyForm ref="formRef" struct-name="order" :columns="columns" ... />
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { getStructNameColumns } from '@/api/system/sysTableColumns'

const columns = ref([])
const tableData = ref([])
const total = ref(0)
const tableRef = ref()
const searchRef = ref()

onMounted(async () => {
  const res = await getStructNameColumns({ structName: 'order' })
  columns.value = res.data
  getTableData()
})

const getTableData = async () => {
  const query = tableRef.value.getQueryInfo()
  const search = searchRef.value.getQueryInfo()
  // 合并分页、排序、搜索条件，调用业务 API
}
</script>
```

---

## 3. DiyForm 组件详解

**文件路径**: `web/src/components/diyForm/diyForm.vue`

### 3.1 Props 列表

| Prop | 类型 | 必填 | 默认值 | 说明 |
|------|------|------|--------|------|
| `structName` | String | 是 | - | 业务结构名称，用于 i18n |
| `columns` | Array | 是 | - | 列配置数组 |
| `callback` | Function | 否 | `null` | 提交完成后的回调函数 |
| `formatItem` | Function | 否 | `null` | 提交前数据格式化函数 |
| `findApi` | Function | 否 | `null` | 查询单条数据的 API 函数 |
| `createApi` | Function | 否 | `null` | 创建数据的 API 函数 |
| `updateApi` | Function | 否 | `null` | 更新数据的 API 函数 |
| `formData` | Object | 否 | `null` | 初始表单数据 |
| `defaultRules` | Object | 否 | `{}` | 自定义验证规则，与自动规则合并 |
| `initFormData` | Function | 否 | `() => {}` | 创建模式下的初始数据工厂函数 |
| `visibleColumnsFunc` | Function | 否 | `null` | 自定义列可见性判断函数 |
| `width` | String | 否 | `'50%'` | 对话框宽度 |
| `height` | String | 否 | `'50%'` | 对话框内容区最大高度 |

### 3.2 表单类型（formType）

通过 `openDialog(type, data)` 方法设置：

| type | 说明 |
|------|------|
| `create` | 新建模式，使用 `initFormData()` 初始化，调用 `createApi` |
| `edit` | 编辑模式，通过 `findApi` 获取数据，调用 `updateApi` |
| `view` | 查看模式，所有字段禁用，无提交按钮 |
| `copy` | 复制模式，获取数据后删除 ID 和时间戳，调用 `createApi` |
| `external` | 外部数据模式，直接使用传入的 data 对象，调用 `createApi` |

### 3.3 字段类型支持

DiyForm 根据 `column.type` 自动渲染对应表单控件：

| type 值 | 渲染控件 | 说明 |
|---------|---------|------|
| `boolean` / `bool` | el-switch | 开关 |
| `table` | SelectTool | 关联表选择器，使用 `editorFilterId` |
| `enum` | el-select | 下拉选择，选项来自 `column.enum` |
| `protoEnum` | el-select | 同 enum 但值转为 Number |
| `enums` | el-select | 同 enum（兼容写法） |
| `date` / `datetime` / `uintDate` | el-date-picker | 日期/时间选择器 |
| `int64` / `int32` / `amount` / `number` | el-input-number | 数字输入（整数） |
| `float` / `double` / `float64` | el-input-number | 数字输入（precision: 4） |
| `textarea` | el-input(textarea) | 多行文本输入 |
| `string` | el-input | 单行文本输入 |
| `object` | span | 只读显示 |
| `jsonStr` | el-input(textarea) | JSON 字符串，自动序列化/反序列化 |
| 其他 | el-input(textarea) | 默认多行文本 |

### 3.4 验证规则

验证规则由两部分合并：
1. **自动规则**: 列配置中 `formMust: true` 的字段自动添加 `{ required: true, message: 'required' }`
2. **自定义规则**: 通过 `defaultRules` prop 传入，会覆盖同名字段的自动规则

```javascript
// 自动生成的规则
columns.forEach(column => {
  if (column.formMust) {
    rules[column.jsonName] = [{ required: true, message: 'required' }]
  }
})
// 最终规则 = { ...autoRules, ...defaultRules }
```

### 3.5 自定义 slot

DiyForm 提供多种 slot 用于自定义：

| slot 名称 | 作用域参数 | 说明 |
|-----------|-----------|------|
| `column-{jsonName}` | `{ column, row, viewType, isDisabled }` | 替换特定字段的渲染 |
| `additional` | `{ columns, row, isDisabledMap }` | 在表单末尾追加额外内容 |
| `header-left` | - | 对话框标题左侧自定义内容 |
| `header-center` | - | 对话框标题中间自定义内容 |
| `header-right` | - | 对话框标题右侧自定义内容 |

```vue
<!-- 自定义某个字段的渲染 -->
<DiyForm ref="formRef" ...>
  <template #column-status="{ column, row, isDisabled }">
    <el-radio-group v-model="row.status" :disabled="isDisabled">
      <el-radio :label="1">启用</el-radio>
      <el-radio :label="0">禁用</el-radio>
    </el-radio-group>
  </template>
  <template #additional="{ row }">
    <el-form-item label="备注">
      <el-input v-model="row.remark" type="textarea" />
    </el-form-item>
  </template>
</DiyForm>
```

### 3.6 列可见性与排序

- `formHidden: true` 的字段在表单中隐藏
- `visibleColumnsFunc` 可动态控制字段可见性：`(column, formData) => boolean`
- 字段按 `formOrder` 升序排列

### 3.7 字段禁用逻辑

```javascript
const isDisabled = (column) => {
  return isView || (column.formDisabled && (formType === 'update' || formType === 'edit'))
}
```
- 查看模式：所有字段禁用
- 编辑模式：`formDisabled: true` 的字段禁用（通常是主键或创建后不可修改的字段）

### 3.8 暴露方法

| 方法 | 说明 |
|------|------|
| `openDialog(type, data)` | 打开对话框，type 见 3.2，data 为行数据（编辑/查看时传入） |

---

## 4. DiySearch 组件

**文件路径**: `web/src/components/diySearch/search.vue`

DiySearch 是顶部搜索表单组件，自动根据列配置中 `isAddSearch: true` 的字段生成搜索表单项。

### Props

| Prop | 类型 | 说明 |
|------|------|------|
| `columns` | Array | 完整列配置数组，内部自动过滤 `isAddSearch` |
| `defaultFilter` | Object | 默认筛选值，key 为 columnName |

### 搜索控件类型

根据 `column.type` 和 `column.defaultFilter` 自动渲染：

| 条件 | 控件 |
|------|------|
| `type === 'boolean'/'bool'` | el-select（true/false 选项） |
| `type === 'table'` | SelectTool 关联表选择器 |
| `type === 'enum'` + `defaultFilter === 'in'` | el-select 多选 |
| `type === 'enum'` | el-select 单选 |
| `type === 'date'/'datetime'/'uintDate'` + `defaultFilter === 'between'` | el-date-picker 范围选择 |
| `type === 'date'/'datetime'/'uintDate'` | el-date-picker 单选 |
| 其他 + `defaultFilter === 'between'` | 双 el-input 范围输入 |
| 其他 + `defaultFilter === 'in'` | el-select 多值输入（allow-create） |
| 其他 | el-input 文本输入 |

### 暴露方法

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `getQueryInfo(def?)` | Object | 返回搜索条件 `{ columnName: { option, type, value } }`，可传入默认值合并 |
| `clearSearch()` | void | 清空所有搜索条件 |
| `setSearchInfo(searchInfo)` | void | 从外部设置搜索条件（用于恢复搜索状态） |

搜索值转换规则：
- 布尔值转为 `'1'` / `'0'`
- 数组用逗号连接
- 数字类型会先 `unformatNumber` 去除格式化

---

## 5. DiyPop 弹窗组件

**文件路径**: `web/src/components/diyPop/index.vue`

当前为预留组件（文件内容为空），可用于后续扩展通用弹窗功能。

---

## 6. sys_table_columns 配置字段详解

**后端模型**: `server/model/system/sys_table_columns.go`

### 主要字段

| 字段 | 类型 | 数据库列 | 说明 |
|------|------|---------|------|
| `ID` | uint | 主键 | 自增主键 |
| `tbName` | string | tb_name | 数据库表名 |
| `menuId` | uint | menu_id | 关联菜单 ID，与 tbName + structName 构成联合唯一索引 |
| `structName` | string | struct_name | Go 结构体名称，也是前端的业务标识 |
| `jsonName` | string | json_name | JSON 字段名（前端使用的属性名） |
| `columnName` | string | column_name | 数据库列名（用于后端查询） |
| `with` | int32 | with | 列宽度（px），小于 120 时自动设为 120 |
| `type` | string | type | 字段类型，见下方类型枚举 |
| `sortable` | bool | sortable | 是否可排序 |
| `filter` | bool | filter | 是否可筛选 |
| `defaultFilter` | string | default_filter | 默认筛选方式：`=`/`>`/`>=`/`<`/`<=`/`like`/`in`/`between` |
| `filterList` | []string | filter_list | 可选筛选方式列表（JSON 数组） |
| `sort` | int | sort | 列显示排序 |
| `note` | string | note | 备注说明 |
| `isShow` | bool | is_show | 是否在表格中显示 |
| `enum` | []string | enum | 枚举值列表（JSON 数组） |
| `fixed` | string | fixed | 列固定位置：`none`/`left`/`right` |
| `format` | string | format | 格式化模板（用于数字/字符串格式化） |
| `isAddSearch` | bool | is_add_search | 是否加入搜索表单 |
| `searchWidth` | int32 | search_width | 搜索表单项宽度（px） |
| `isAdditional` | bool | is_additional | 是否为附加字段 |
| `isHaving` | bool | is_having | 是否使用 HAVING 条件查询 |
| `filterId` | uint | filter_id | 关联表筛选配置 ID（表格列显示用） |
| `editorFilterId` | uint | editor_filter_id | 关联表编辑器筛选配置 ID（表单编辑用） |
| `isSum` | bool | is_sum | 是否参与合计行计算 |

### FormInfo 嵌入字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `formWith` | int | 表单项宽度百分比（30-100） |
| `formDisabled` | bool | 编辑模式下是否禁用 |
| `formHidden` | bool | 是否在表单中隐藏 |
| `formOrder` | int | 表单项排序顺序 |
| `formMust` | bool | 是否必填 |

### type 字段可选值

| 值 | 说明 | 表格渲染 | 表单渲染 |
|----|------|---------|---------|
| `string` | 字符串 | 纯文本 | el-input |
| `richtext` | 富文本 | 纯文本 | el-input(textarea) |
| `bool` / `boolean` | 布尔值 | 是/否 | el-switch |
| `enum` | 枚举 | 彩色 el-tag | el-select |
| `protoEnum` | Proto 枚举 | 彩色 el-tag | el-select(Number) |
| `table` | 关联表 | SelectTool 只读 | SelectTool 可选 |
| `int32` | 32位整型 | 纯文本 | el-input-number |
| `int64` | 64位整型 | 纯文本 | el-input-number |
| `int` | 整型 | 纯文本 | el-input-number |
| `float64` | 浮点型 | 纯文本 | el-input-number(4位精度) |
| `datetime` | 日期时间 | 原样显示 | el-date-picker |
| `date` | 日期 | 截取日期部分 | el-date-picker |
| `uintDate` | 无符号日期 | $serverDate 格式化 | el-date-picker |
| `json` | JSON 对象 | 纯文本 | el-input(textarea) |
| `jsonStr` | JSON 字符串 | 纯文本 | el-input(textarea)，自动序列化 |
| `array` | 数组 | 纯文本 | el-input(textarea) |
| `binary` | 二进制 | 纯文本 | el-input(textarea) |
| `image` | 图片 | el-image(base64) | - |
| `object` | 对象 | 纯文本 | span 只读 |
| `textarea` | 多行文本 | 纯文本 | el-input(textarea) |
| `amount` / `number` | 金额/数字 | 纯文本 | el-input-number |

---

## 7. 前后端联动

### 7.1 配置获取流程

```
前端页面 onMounted
  → 调用 getStructNameColumns({ structName: 'xxx' })
  → 后端 SysTableColumnsService.GetStructNameColumns()
  → 查询 sys_table_columns WHERE struct_name = 'xxx'
  → 预加载 SysDataFilter 关联
  → 返回 columns 数组
  → 前端将 columns 分别传给 DiyTable / DiyForm / DiySearch
```

### 7.2 配置更新流程

通过 `coloptions.vue`（表格列配置）或 `fromColOptions.vue`（表单列配置）可在运行时调整配置：

```
用户点击设置按钮
  → 弹出配置对话框
  → 修改 isShow / with / type / sortable / enum 等
  → 点击确认
  → 调用 updateSysTableColumnsInfo API
  → 后端批量更新 sys_table_columns 记录
```

### 7.3 查询条件序列化

DiySearch 和 queryFrom 组件将搜索条件序列化为统一格式：

```javascript
{
  column_name: {
    option: "like",      // 查询操作符
    type: "string",      // 字段类型
    value: "keyword"     // 查询值（字符串化）
  }
}
```

这个结构直接对应后端的通用查询解析逻辑。

### 7.4 关联 API

| API 函数 | URL | 说明 |
|----------|-----|------|
| `getStructNameColumns` | GET `/sysTableColumns/getStructNameColumns` | 按 structName 获取列配置 |
| `updateSysTableColumnsInfo` | PUT `/sysTableColumns/updateSysTableColumnsInfo` | 批量更新列配置 |
| `syncSysTableColumnsInfo` | GET `/sysTableColumns/syncSysTableColumnsInfo` | 同步列配置 |
| `createSysTableColumns` | POST `/sysTableColumns/createSysTableColumns` | 创建单条配置 |
| `getSysTableColumnsList` | GET `/sysTableColumns/getSysTableColumnsList` | 分页获取配置列表 |

---

## 8. DynamicForm 独立动态表单

**文件路径**: `web/src/components/diyForm/DynamicForm.vue`

DynamicForm 与 DiyForm 不同，它不依赖 sys_table_columns，而是通过 API 获取独立的表单配置。

### Props

| Prop | 类型 | 说明 |
|------|------|------|
| `modelValue` | Object | 表单数据（支持 v-model） |
| `formType` | String | 表单类型标识，用于从 API 获取配置 |
| `size` | String | 表单尺寸，默认 `'default'` |
| `inline` | Boolean | 是否内联布局 |
| `disabled` | Boolean | 是否禁用 |
| `showActions` | Boolean | 是否显示操作按钮 |
| `customRules` | Object | 自定义验证规则 |
| `autoLoad` | Boolean | 是否自动加载配置，默认 `true` |

### 配置结构

从 `GET /form/config?type={formType}` 获取，返回 `formOptions` 数组：

```javascript
[
  {
    name: "fieldName",
    type: "string",       // string/text/int/float/bool/enum/date/time
    required: true,
    default_value: "",
    options: ["a", "b"]   // enum 类型的选项
  }
]
```

### 暴露方法

| 方法 | 说明 |
|------|------|
| `validate()` | 验证并提交表单 |
| `resetFields()` | 重置表单 |
| `clearValidate()` | 清除验证状态 |
| `reloadConfig()` | 重新加载 API 配置 |

---

## 9. 扩展和自定义指南

### 9.1 添加新的字段类型

1. 在 `coloptions.vue` 的 `typeOptions` 数组中添加新类型选项
2. 在 `table.vue` 的 `<template #default>` 中添加对应的渲染逻辑（`v-else-if`）
3. 在 `diyForm.vue` 中添加对应的表单控件渲染
4. 在 `search.vue` 中添加对应的搜索控件渲染

### 9.2 自定义列渲染

使用 DiyTable 的 `operate` slot，或在业务页面通过条件渲染覆盖默认行为。

### 9.3 自定义表单字段

使用 DiyForm 的 `column-{jsonName}` slot 替换特定字段的渲染逻辑。

### 9.4 添加搜索条件

设置列配置的 `isAddSearch: true` 和适当的 `defaultFilter` 即可自动在 DiySearch 中出现。

---

## 10. 常见问题

### Q: 列宽度设置不生效？
A: `with` 字段值小于 120 时会被自动设为 `'120px'`，这是 table.vue 中的最小宽度保护。

### Q: 枚举列显示原始值而非标签？
A: 确保 i18n 翻译文件中存在对应的 key：`business.{structName}.enums.{jsonName}.{enumValue}`。枚举值中的点号(`.`)会被 `replaceAll('.', '')` 移除后匹配。

### Q: 表单字段不显示？
A: 检查列配置的 `formHidden` 是否为 `true`。如果使用了 `visibleColumnsFunc`，确认其返回 `true`。

### Q: 搜索条件没有传到后端？
A: 确认字段的 `isAddSearch` 为 `true` 且 `defaultFilter` 已设置。DiySearch 的 `getQueryInfo()` 会跳过值为 `null`、空字符串或空数组的条件。

### Q: 表单编辑模式下某些字段无法修改？
A: 这是 `formDisabled: true` 的设计行为，编辑/更新模式下这些字段自动禁用。如需修改，将 `formDisabled` 设为 `false`。

### Q: 合计行数据不正确？
A: 默认合计只对当前页数据求和。如需后端全量合计，通过 `sumData` prop 传入自定义合计函数，在函数中使用后端返回的合计值。

### Q: 关联表字段显示为空？
A: 检查 `filterId`（表格显示用）和 `editorFilterId`（表单编辑用）是否正确配置，这两个 ID 指向 `sys_data_filter` 表的配置。
