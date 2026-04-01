---
name: sync-model-field
description: >
  HAB 项目模型字段同步工具。当新增、修改或删除 Go model struct 字段时，
  自动同步到数据库 sys_table_columns、翻译文件、权限表等关联位置。
  触发场景：(1) 给业务模型加字段 (triggers: '加字段', '新增字段', 'add field', '添加列'),
  (2) 修改模型字段 (triggers: '改字段', '修改字段', 'rename field'),
  (3) 删除模型字段 (triggers: '删字段', '删除字段', 'remove field'),
  (4) 模型变更后需要同步数据库配置。
  此 skill 确保每次模型变更后，所有关联位置保持一致。
---

# Sync Model Field

> **⚠️ 使用前必读**: [KNOWN-ISSUES.md](KNOWN-ISSUES.md) — 已知问题与解决方案

修改 Go model struct 字段后，必须同步以下 5 个位置，缺一不可。

## 完整流程

### Step 1: 修改 Go Model Struct

编辑 `server/model/business/<model>.go`，添加/修改/删除字段。

记录关键信息（后续步骤需要）：
- **表名** (tbName): 如 `b_tables`，从 `TableName()` 方法获取
- **字段名** (jsonName): 如 `tableConfig`，Go struct tag 中的 json 名
- **列名** (columnName): 如 `table_config`，gorm tag 中的 column 名
- **Go 类型**: 如 `string`、`gtype.Map[string, interface{}]`
- **gorm type tag**: 如 `type:json`、`size:100`、`type:int`

### Step 2: ALTER TABLE 直接加列

不依赖 GORM AutoMigrate，直接执行 DDL 加列，避免启动时全表同步太慢。

根据 gorm tag 推导 MySQL 列定义：

```sql
ALTER TABLE <表名> ADD COLUMN <column_name> <MYSQL_TYPE> DEFAULT <default> COMMENT '<comment>';
```

**gorm tag → MySQL 类型映射：**

| gorm tag | MySQL 类型 |
|----------|-----------|
| `type:json` | `json` |
| `size:100` (string) | `varchar(100)` |
| `size:255` (string) | `varchar(255)` |
| `type:text` | `text` |
| `type:int` | `int` |
| `type:bigint` | `bigint` |
| `type:tinyint` | `tinyint` |
| `type:decimal(10,2)` | `decimal(10,2)` |
| string 无 size | `longtext` |
| bool | `tinyint` DEFAULT 0 |
| float64 | `double` |

**示例：**

```sql
-- JSON 字段
ALTER TABLE b_tables ADD COLUMN table_config json DEFAULT NULL COMMENT 'PP tableConfig缓存';

-- 字符串字段
ALTER TABLE b_tables ADD COLUMN custom_name varchar(200) DEFAULT '' COMMENT '自定义名称';

-- 布尔字段
ALTER TABLE b_tables ADD COLUMN enabled tinyint DEFAULT 1 COMMENT '是否启用';
```

如果需要加索引，追加：
```sql
ALTER TABLE <表名> ADD INDEX idx_<column_name> (<column_name>);
-- 或唯一索引
ALTER TABLE <表名> ADD UNIQUE INDEX idx_<column_name> (<column_name>);
```

### Step 3: 插入 sys_table_columns 记录

> ⚠️ 已知问题：见 [KNOWN-ISSUES.md](KNOWN-ISSUES.md) P001 — INSERT 必须包含所有字段，否则大量列为 NULL

用 mysql-operator skill 查询该表的 menu_id 和已有字段：

```sql
SELECT DISTINCT menu_id FROM sys_table_columns WHERE tb_name = '<表名>'
```

查询同表已有字段**完整记录**作为参考（必须用 `SELECT *`，了解每个字段的默认值）：

```sql
SELECT * FROM sys_table_columns WHERE tb_name = '<表名>' LIMIT 1
```

然后插入新字段记录（**必须包含所有字段**，不能只插核心字段）：

```sql
INSERT INTO sys_table_columns
  (tb_name, menu_id, struct_name, json_name, column_name, `with`, type,
   sortable, `filter`, default_filter, filter_list,
   sort, note, is_show, enum, fixed, format,
   is_add_search, search_width, is_additional, filter_id,
   form_disabled, form_hidden, form_with, form_order, form_must,
   is_having, is_sum, editor_filter_id,
   created_by, updated_by, deleted_by)
VALUES
  ('<表名>', <menu_id>, '<modelName>', '<jsonName>', '<columnName>', <width>, '<type>',
   <sortable>, <filter>, '<default_filter>', '<filter_list_json>',
   <sort>, '<note>', <is_show>, '[]', '', '',
   0, 120, 0, 0,
   <form_disabled>, <form_hidden>, 45, <form_order>, <form_must>,
   0, 0, 0,
   0, 1, 0)
```

**字段说明：**

| 字段 | 说明 | 常见值 |
|------|------|--------|
| `struct_name` | **模型名**（不是字段名），如 `bGameRounds` | 参考同表已有记录 |
| `with` | 列表列宽(px) | 字符串 120, JSON 200, ID 80 |
| `sortable` | 是否支持排序 | 0 或 1 |
| `filter` | 是否支持筛选 | 0 或 1 |
| `default_filter` | 筛选方式 | `like`、`=`、空字符串 |
| `filter_list` | 筛选选项 JSON | `[]` 或 `["=","!=","like","in","not in"]` |
| `note` | 字段备注 | gorm comment 内容 |
| `enum` | 枚举选项 JSON | `[]` |
| `form_hidden` | 表单中隐藏 | 系统写入字段设 1，用户编辑字段设 0 |
| `form_with` | 表单宽度 | 一般 45 |
| `form_order` | 表单排序 | 参考同表 sort 顺序 |
| `form_must` | 表单必填 | 0 或 1 |
| `form_disabled` | 表单禁用 | 0 或 1 |

**类型映射参考：**

| Go 类型 | sys_table_columns type |
|---------|----------------------|
| string | string |
| int/uint/int64 | int64 |
| int32 | int32 |
| float64 | float64 |
| bool | bool |
| time.Time | datetime |
| JSON/Map | jsonStr |
| 枚举字符串 | enum |
| 外键关联 | table |

**is_show 规则：** 后台列表需要展示的字段设 1，内部数据字段设 0。

### Step 4: 更新翻译文件

在以下两个文件的 `columns` 对象中添加翻译：

- `server/translation/zh-CN/business/<model>.json` — 中文翻译
- `server/translation/en-US/business/<model>.json` — 英文翻译

翻译文件名通过查看同目录下已有文件确定（通常与模型名对应）。

```json
{
  "columns": {
    "existingField": "已有字段",
    "newField": "新字段中文名"
  }
}
```

如果字段是枚举类型，还需在 `enums` 对象中添加枚举值翻译。

### Step 5: 分配字段权限

查询哪些角色已有该表的字段权限：

```sql
SELECT DISTINCT authority_id
FROM sys_authority_cols
WHERE sys_table_columns_id IN
  (SELECT ID FROM sys_table_columns WHERE tb_name = '<表名>')
```

为每个 authority_id 插入新字段的权限记录（使用 Step 2 中插入后获得的新字段 ID）：

```sql
INSERT INTO sys_authority_cols
  (authority_id, sys_menu_id, sys_base_menu_btn_id, sys_table_columns_id)
VALUES
  (<authority_id>, <menu_id>, NULL, <新字段ID>)
```

如果有多个 authority_id，每个都要插入一条。

## 删除字段时

反向操作：
1. 从 Go model 删除字段
2. `ALTER TABLE <表名> DROP COLUMN <column_name>;`
3. `DELETE FROM sys_authority_cols WHERE sys_table_columns_id = <ID>`
4. `DELETE FROM sys_table_columns WHERE ID = <ID>`
5. 从翻译文件中移除对应 key

## 修改字段时

更新相关记录：
1. 修改 Go model struct
2. `ALTER TABLE <表名> CHANGE <old_column> <new_column> <MYSQL_TYPE>;`（改名）或 `ALTER TABLE <表名> MODIFY <column_name> <NEW_TYPE>;`（改类型）
3. `UPDATE sys_table_columns SET json_name=..., column_name=... WHERE ID = <ID>`
4. 更新翻译文件中的 key

## 验证清单

完成后确认：
- [ ] Go model struct 已修改
- [ ] `go build ./...` 编译通过
- [ ] ALTER TABLE 已执行（数据库列已同步）
- [ ] sys_table_columns 记录已插入/更新
- [ ] zh-CN 翻译已添加
- [ ] en-US 翻译已添加
- [ ] sys_authority_cols 权限已分配（所有相关 authority_id）
