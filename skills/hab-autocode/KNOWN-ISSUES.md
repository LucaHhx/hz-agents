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

## 4. AutoCode 生成后必须用 sync-model-field 做完整检查

- **现象**: AutoCode 生成 CRUD 后，以下问题高频出现：
  1. `sys_table_columns` 多出 `CreatedBy/UpdatedBy/DeletedBy` 三条记录，但 Go model 的 `HAB_MODEL` / `HAB_MODEL_NOD` 根本没这些字段 → 前端 DiyTable 请求时报 `Error 1054 Unknown column 'b_xxx.created_by'`
  2. 菜单 `parent_id=0`，出现在根级而非目标父菜单下
  3. `translation/{zh-CN,en-US}/menu.json` 缺少菜单翻译，侧边栏显示英文 key
  4. `translation/{zh-CN,en-US}/business/xxx.json` 里的 `CreatedBy/UpdatedBy/DeletedBy` 翻译也是多出来的
  5. `decimal(18,2)` 精度丢失为 `decimal(10,0)`
- **原因**: AutoCode 模板假设用的是带 by 字段的 GVA 原版 Model，但本项目 `HAB_MODEL` / `HAB_MODEL_NOD` 都**不带** `CreatedBy/UpdatedBy/DeletedBy`（见 `server/global/model.go`）。所以 AutoCode 生成的 `sys_table_columns` + 翻译里这三条都是垃圾数据。

- **仲裁原则：⚠️ 一律以 Go 模型字段为准**

  碰到 DB / `sys_table_columns` / 翻译文件互相对不上时，**不要**反向"给 DB 补列让 sys_table_columns 对得上"——应该**以 Go struct 字段为唯一真源**，多余的元数据（sys_table_columns 行、权限行、翻译条目）全部**删掉**。

  ❌ 错误做法：`ALTER TABLE b_xxx ADD COLUMN created_by bigint ...`（给 DB 加不该有的列）
  ✅ 正确做法：
  ```sql
  -- 1. sys_authority_cols 先删（外键关联）
  DELETE FROM sys_authority_cols
   WHERE sys_table_columns_id IN (
     SELECT id FROM sys_table_columns
      WHERE tb_name='b_xxx' AND json_name IN ('CreatedBy','UpdatedBy','DeletedBy'));
  -- 2. 再删 sys_table_columns 本体
  DELETE FROM sys_table_columns
   WHERE tb_name='b_xxx' AND json_name IN ('CreatedBy','UpdatedBy','DeletedBy');
  -- 3. 翻译文件移除对应 key（zh-CN + en-US 都要）
  ```

- **完整检查清单**: AutoCode 生成后执行：

  ```
  AutoCode createTemp 完成
       ↓
  1. 对齐 sys_table_columns vs Go struct：
     SELECT json_name FROM sys_table_columns WHERE tb_name='b_xxx'
     对比 Go struct 字段（含 HAB_MODEL 展开字段）
     → 多出来的（如 CreatedBy/UpdatedBy/DeletedBy）删掉
     → 少了的才走 sync-model-field 补
  2. 菜单归属：SELECT id, parent_id FROM sys_base_menus WHERE name='xxx' → UPDATE parent_id + sort
  3. 菜单翻译：检查 translation/{zh-CN,en-US}/menu.json 是否有对应条目 → 补充
  4. 字段翻译：检查 translation/{zh-CN,en-US}/business/xxx.json → 与 sys_table_columns 完全一一对应，多的删、少的补
  5. 权限检查：SELECT authority_id, COUNT(*) FROM sys_authority_cols 看每个角色条数 = sys_table_columns 条数
  6. decimal/json/uniqueIndex 等 gorm tag 对齐检查
  7. go build ./... 编译验证
  ```

  **简化版**：用 `/sync-model-field` 命令，它会按"Go 模型为真源"原则对齐。

- **强制规则**: 使用 hab-autocode 之后必须使用 sync-model-field 检查，不可跳过
- **日期**: 2026-04-16（初版） / 2026-04-23（更新："以 Go 模型为准"仲裁原则）
- **来源**:
  - 初版: 12-provider-api 需求，4 张表生成后遇到全部 4 类问题
  - 更新: b_table_currency_configs 生成后重犯同样问题（误往 DB 加列，应删 sys_table_columns 行）
