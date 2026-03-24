# HAB AutoCode — 已知问题与经验

## 1. 已有 CRUD 模块增加字段

**场景**: AutoCode 已经生成了某个模块的 CRUD 代码（model/api/router/service/前端页面），现在需要给模型增加几个新字段。

**错误做法**: ❌ 写 Go 初始化脚本（如 `initialize/xxx_table_columns.go`）在启动时自动插入 SysTableColumns 记录 — 会导致后续数据被覆盖。

**正确操作步骤**:

### Step 1: 后端 Model 增加字段

在 `server/model/business/<module>.go` 的 struct 中添加字段，带完整的 GORM tag：

```go
NewField string `json:"newField" gorm:"column:new_field;comment:字段说明;size:100;"`
```

> **注意**: 如果字段名与 GORM 的内置方法冲突（如 `TableName` 与 `TableName()` 方法），需要用不同的 Go 字段名（如 `BoundTableName`），但保持 `json:"tableName"` 和 `gorm:"column:table_name"` 不变。

GORM AutoMigrate 会在服务启动时自动添加数据库列，无需手动 SQL。

### Step 2: SysTableColumns 列配置 — 直接操作数据库

**绝不写初始化脚本**，使用 mysql-operator skill 直接执行 SQL：

```sql
-- 1. 查找该模块已有列的 menuId 和当前排序
SELECT id, json_name, menu_id, sort, form_order
FROM sys_table_columns
WHERE struct_name = '<structName>' AND tb_name = '<tableName>'
ORDER BY sort;

-- 2. 插入新列配置（字段名必须与 SysTableColumns struct 一致）
INSERT INTO sys_table_columns (
  tb_name, struct_name, json_name, column_name, menu_id, type,
  is_show, sort, `with`, note,
  form_with, form_hidden, form_order, form_must, form_disabled,
  sortable, `filter`, created_by
) VALUES (
  '<tableName>', '<structName>', 'newField', 'new_field', <menuId>, 'string',
  1, <sort>, 120, '备注',
  45, 0, <formOrder>, 0, 0,
  0, 0, 0
);

-- 3. 如果新列排在中间，调整后续列的 sort 值
UPDATE sys_table_columns SET sort = sort + N
WHERE struct_name = '<structName>' AND tb_name = '<tableName>'
  AND json_name IN ('CreatedAt', 'UpdatedAt', 'DeletedAt');

-- 4. 查询需要添加列权限的角色
SELECT DISTINCT authority_id FROM sys_authority_cols WHERE sys_menu_id = <menuId>;

-- 5. 插入列权限记录（新列的 ID 可从插入结果或 SELECT 获取）
INSERT INTO sys_authority_cols (authority_id, sys_menu_id, sys_table_columns_id)
VALUES (<authorityId>, <menuId>, <newColumnId>);
```

**关键参数说明**:
- `form_hidden=1`: 字段在表单中隐藏（由其他控件联动填充时设置）
- `form_hidden=0`: 字段在表单中显示（用户可直接输入）
- `is_show=1`: 字段在列表中显示
- `with`: 列宽度（像素），string 默认 120，bool 默认 80
- `form_with`: 表单宽度百分比，默认 45
- `sort`: 列表中的排列顺序
- `form_order`: 表单中的排列顺序

### Step 3: 前端自定义渲染（可选）

DiyFrom 会自动渲染新字段。如需自定义渲染（如选择器、特殊组件）：

```vue
<template #column-newField="{ formData }">
  <!-- 自定义组件 -->
</template>
```

### 实际案例

需求 2-channel-table-binding：给 Channel 模型增加 tableId/tableName/gameType 三个字段。
- tableId: `form_hidden=0`（用自定义选择器重写渲染）
- tableName/gameType: `form_hidden=1`（由机台选择器联动自动填充）

**日期**: 2026-03-20
**来源**: 需求 2-channel-table-binding 开发实践

## 2. 新增字段后必须同步更新翻译文件

- **现象**: 新增的字段在前端 DiyTable 列头显示为 jsonName 原文（如 `tableId`），而非中文翻译
- **原因**: 翻译文件 `server/translation/{lang}/business/<module>.json` 中缺少新字段的翻译条目
- **方案**:

  在 `server/translation/` 下找到对应模块的翻译文件，在 `columns` 对象中追加新字段：

  **zh-CN/business/<module>.json**:
  ```json
  {
    "columns": {
      "newField": "新字段中文名"
    }
  }
  ```

  **en-US/business/<module>.json**:
  ```json
  {
    "columns": {
      "newField": "New Field"
    }
  }
  ```

  > 翻译文件的 key 必须与 sys_table_columns 中的 `jsonName` 一致。

- **检查清单**: 增加字段时，除了 Model + DB 列配置 + 权限，还要检查 `server/translation/zh-CN/` 和 `server/translation/en-US/` 下的翻译文件。
- **日期**: 2026-03-20
- **来源**: 需求 2-channel-table-binding，tableId/tableName/gameType 翻译遗漏

## 3. business 包下的表名必须使用 b_ 前缀

- **现象**: AutoCode 生成的 business 模块默认表名无前缀（如 `channels`），与系统表混在一起不易区分
- **原因**: 项目约定 business 包下的数据库表统一使用 `b_` 前缀
- **方案**:

  1. 修改 `server/model/business/<module>.go` 中的 `TableName()` 方法，返回 `b_<原表名>`
  2. 如果表已存在，用 SQL 重命名：`RENAME TABLE <old> TO b_<old>`
  3. 同步更新 `sys_table_columns` 中的 `tb_name`：`UPDATE sys_table_columns SET tb_name = 'b_<old>' WHERE tb_name = '<old>'`

  ```sql
  RENAME TABLE channels TO b_channels;
  UPDATE sys_table_columns SET tb_name = 'b_channels' WHERE tb_name = 'channels';
  ```

- **检查清单**: AutoCode 生成后，立即检查 TableName() 返回值是否带 `b_` 前缀
- **日期**: 2026-03-20
- **来源**: 需求 2-channel-table-binding，Channel 表名修正
