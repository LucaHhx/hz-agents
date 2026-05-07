# Sync Model Field — 常见问题与解决方案

> 由 skill-doctor 维护，记录 AI 使用本 skill 时遇到的问题和解决方案。
> AI 使用本 skill 前应先阅读此文件，避免重复踩坑。

## [P001] [已修复] sys_table_columns INSERT 字段不完整，大量列为 NULL

- **现象**: 按 SKILL.md 的 INSERT 模板插入 sys_table_columns 后，`with`、`default_filter`、`filter_list`、`note`、`enum`、`fixed`、`format`、`is_add_search`、`search_width`、`is_additional`、`filter_id`、`form_disabled`、`form_hidden`、`form_with`、`form_order`、`is_having`、`form_must`、`editor_filter_id`、`is_sum`、`created_by`、`updated_by`、`deleted_by` 等 22 个字段全部为 NULL
- **原因**: SKILL.md Step 3 的 INSERT 模板只包含了 10 个核心字段 `(tb_name, menu_id, struct_name, json_name, column_name, type, is_show, sort, sortable, filter)`，遗漏了其余 22 个字段
- **方案**:
  1. INSERT 时必须先查询同表已有字段作为参考：`SELECT * FROM sys_table_columns WHERE tb_name = '<表名>' LIMIT 1`
  2. 使用完整的 INSERT 语句，包含所有非系统字段（参考同表已有记录的默认值）
  3. 关键字段说明：
     - `struct_name`: 填模型名（如 `bGameRounds`），不是 Go struct 字段名
     - `with`: 列表列宽（px），字符串一般 120，JSON 一般 200
     - `note`: 字段备注/说明
     - `default_filter`: 筛选方式，常见 `like`/`=`，不需要筛选填空字符串
     - `filter_list`: 筛选选项 JSON 数组，不需要填 `[]`
     - `enum`: 枚举选项 JSON 数组，不需要填 `[]`
     - `form_hidden`: 系统自动写入的字段设 1（表单中隐藏）
     - `form_with`: 表单宽度，一般 45
     - `form_order`: 表单排序，参考同表其他字段顺序
     - 数值类型字段 NULL 默认值应为 0，字符串类型应为空字符串
- **日期**: 2026-03-31

## [P002] 删除字段时遗漏 sys_authority_cols 权限清理

- **现象**: 从 sys_table_columns 删除字段记录后，sys_authority_cols 中残留孤儿记录（sys_table_columns_id 指向已删除的 ID），不会报错但造成数据污染
- **原因**: 批量删除多个字段时容易忘记先清理权限表
- **方案**: 删除字段时，**必须先删 sys_authority_cols 再删 sys_table_columns**：
  ```sql
  -- 1. 先删权限
  DELETE FROM sys_authority_cols WHERE sys_table_columns_id IN (<IDs>);
  -- 2. 再删字段配置
  DELETE FROM sys_table_columns WHERE id IN (<IDs>);
  -- 3. 最后删数据库列
  ALTER TABLE <表名> DROP COLUMN <column_name>;
  ```
- **验证**: 删除后运行 `SELECT * FROM sys_authority_cols WHERE sys_table_columns_id = <ID>` 确认返回空
- **日期**: 2026-04-10

## [P003] 关联表字段（type='table'）：何时使用、如何配置

### 何时使用关联表类型

**规则：凡是存储另一张表主键 ID 的外键字段，都应该使用 type='table'。**

判断标准：
- Go model 中字段类型为 `int`/`uint`，名称以 `Id` 结尾（如 `orgId`, `agentId`, `vendorId`, `upstreamId`）
- 该字段值是另一张表的 ID，列表页应该显示关联表的名称而不是数字 ID
- 表单中应该是下拉选择器而不是手动输入数字

**不使用的情况**：
- 纯数值字段（如 `rateLimit`、`sort`、`balance`）虽然也是 int 但不是外键
- 自关联 ID（如 `parentId`）需要特殊处理（树形选择器），不适合标准关联表

### 配置步骤

**Step 1: 创建 sys_data_filter 数据源**

```sql
-- 查看已有数据源作为参考
SELECT * FROM sys_data_filter;

-- 创建新数据源
INSERT INTO sys_data_filter (name, `sql`, columns, `key`, value, label, created_at, updated_at)
VALUES (
  '组织列表',                          -- 数据源名称
  'SELECT id, name FROM b_organizations WHERE enabled = 1 AND deleted_at IS NULL',  -- 查询 SQL
  '[{"sort":0,"label":"编号","filter":true,"isShow":true,"columnName":"id"},
    {"sort":1,"label":"名称","filter":true,"isShow":true,"columnName":"name"}]',     -- 显示列配置
  'id',                                -- key: 主键字段名（绑定到 form 的值）
  'id',                                -- value: 同 key
  'name',                              -- label: 下拉选项显示的字段名
  NOW(), NOW()
);
```

**columns JSON 格式说明**：
| 字段 | 说明 |
|------|------|
| columnName | SQL 结果中的列名 |
| label | 下拉选项中该列的标题 |
| isShow | 是否在下拉选项中显示该列 |
| filter | 是否支持搜索过滤 |
| sort | 显示顺序 |

**Step 2: 更新 sys_table_columns**

```sql
UPDATE sys_table_columns 
SET type = 'table', 
    filter_id = <新数据源ID>,           -- 列表页和搜索栏使用
    editor_filter_id = <新数据源ID>     -- 编辑表单使用
WHERE struct_name = 'BOperator' AND json_name = 'orgId';
```

**Step 3: 验证效果**

框架自动处理以下场景（无需写前端代码）：
- **列表页**: 显示关联表的 label 字段值（如组织名称），而不是数字 ID
- **编辑表单**: 渲染为 SelectTool 远程搜索下拉框
- **搜索栏**: 渲染为 SelectTool 筛选组件

### 前端工作原理

DiyForm/DiyTable 检测到 `type='table'` 时自动渲染 `<SelectTool>` 组件：
1. SelectTool 根据 `filterId` 调用 `GET /sysDataFilter/findSysDataFilter` 获取配置
2. 再调用 `POST /sysDataFilter/filterData` 执行 SQL 获取选项数据
3. 用 `key` 字段绑定值，`label` 字段显示文本
4. 支持远程搜索（用户输入时模糊匹配 columns 中 filter=true 的列）

### SQL 编写注意

- **必须加 `WHERE deleted_at IS NULL`**：排除软删除的记录
- **建议加 `WHERE enabled = 1`**：只显示启用的记录（如果表有 enabled 字段）
- **只 SELECT 需要的列**：id + 显示字段即可，不要 SELECT *

### 已配置的数据源参考

| ID | 名称 | SQL | 用途 |
|----|------|-----|------|
| 2 | 上游列表 | SELECT id, name FROM b_upstreams WHERE enabled = 1 AND deleted_at IS NULL | 机台表的 upstreamId |
| 3 | 供应商列表 | SELECT id, name FROM b_vendors WHERE enabled = 1 AND deleted_at IS NULL | 机台表的 vendorId |
| 4 | 代理列表 | SELECT id, name FROM b_agents WHERE enabled = 1 AND deleted_at IS NULL | 组织表的 agentId |
| 5 | 组织列表 | SELECT id, name FROM b_organizations WHERE enabled = 1 AND deleted_at IS NULL | 商户表的 orgId |

- **日期**: 2026-04-10

## [P004] Unknown column 错误 —— 以 Go 模型为准，对字段表做删补（不改 Go 模型）

- **现象**: `Error 1054 (42S22): Unknown column 'b_xxx.<col>' in 'field list'`。例如 `b_game_user_actions.created_by`。典型触发点：
  - GORM `Find`/`First`/`Model(...).Select(*)` 按 struct 字段拼 SELECT
  - DiyTable / DiyForm 按 `sys_table_columns` 元数据拼 SELECT
- **原因**: AutoCode 生成 / 重生成时，Go 模型、DB 表列、`sys_table_columns` 元数据、翻译四个位置并不总是同步。任何一处错位都会导致查询引用不存在的列 → 报错
- **核心原则**: **Go 模型是唯一真相源，绝不改 Go 模型去迁就错误状态**。对照 Go 模型，对「字段表」（DB 表列 + `sys_table_columns` + 翻译 + 权限）做删 / 补，让它们和 Go 模型对齐

### 排查步骤

1. **读 Go 模型**，列出真实字段清单（含嵌入的 `global.HAB_MODEL` 提供的 `ID / CreatedAt / UpdatedAt / DeletedAt`；模型里显式写的字段也算——如果有 `CreatedBy/UpdatedBy/DeletedBy` 也要算进去）：
   ```
   server/model/**/<model>.go
   ```

2. **查 DB 表当前列**（mysql-operator）：
   ```sql
   SHOW COLUMNS FROM b_xxx;
   ```

3. **查 sys_table_columns 当前元数据**：
   ```sql
   SELECT id, json_name, column_name, struct_name
     FROM sys_table_columns
    WHERE tb_name = 'b_xxx'
    ORDER BY sort;
   ```

4. **三者对照，按下表处理（永远以 Go 模型为准）**：

   | Go 模型 | DB 表 | sys_table_columns | 动作 |
   |--------|-------|-------------------|------|
   | ✓ | ✗ | ? | **ALTER TABLE ADD COLUMN** 把列补到 DB（类型按 gorm tag 推，参考 SKILL.md Step 2） |
   | ✓ | ✓ | ✗ | **INSERT** 到 sys_table_columns（SKILL.md Step 3）+ 翻译 + 权限 |
   | ✗ | ✓ | ? | **ALTER TABLE DROP COLUMN** 把多余列从 DB 删除 |
   | ✗ | ✗ | ✓ | **DELETE** 掉 sys_table_columns 多余元数据（先清 sys_authority_cols，见 P002 顺序）+ 删翻译 |
   | ✗ | ✓ | ✓ | 先删 sys_authority_cols → 删 sys_table_columns → ALTER DROP COLUMN → 删翻译 |

5. 对齐后重启服务复测，确认 Unknown column 消失。

### 具体例子：b_game_user_actions.created_by

- Go 模型 `GameUserAction` 显式有 `CreatedBy/UpdatedBy/DeletedBy`（见 `server/model/gameData/game_user_actions.go`）→ **Go 有**
- DB 表 `SHOW COLUMNS` 没有这 3 列 → 走「Go 有 / DB 没有」分支，补列：
  ```sql
  ALTER TABLE b_game_user_actions ADD COLUMN created_by bigint DEFAULT 0 COMMENT '创建者';
  ALTER TABLE b_game_user_actions ADD COLUMN updated_by bigint DEFAULT 0 COMMENT '更新者';
  ALTER TABLE b_game_user_actions ADD COLUMN deleted_by bigint DEFAULT 0 COMMENT '删除者';
  ```
- 再查 sys_table_columns 是否缺对应元数据，缺则按 SKILL.md Step 3 补

### 反例：不要做的事

- ❌ 为了消错误，从 Go struct 删字段 —— 这是改真相源去迁就错误状态
- ❌ 只改 DB 不改 sys_table_columns（或反过来）—— 两端必须都对齐 Go

- **预防**: AutoCode 重生成后，立即跑一次「Go ↔ DB ↔ sys_table_columns」三方对账
- **日期**: 2026-04-16 / 更正 2026-04-20

## [P005] AutoCode 生成后菜单在根级，需手动归入父菜单

- **现象**: AutoCode 生成的菜单 `parent_id = 0`，出现在侧边栏顶级而不是期望的父菜单下
- **原因**: AutoCode 不知道菜单应该放在哪个父菜单下，默认放根级
- **方案**: 生成后必须手动更新 parent_id 和 sort：
  ```sql
  SELECT id, name FROM sys_base_menus WHERE name = '目标父菜单';
  UPDATE sys_base_menus SET parent_id = <父ID>, sort = <序号> WHERE id = <新菜单ID>;
  ```
- **日期**: 2026-04-16

## [P006] AutoCode 生成后菜单翻译缺失

- **现象**: 侧边栏菜单显示为英文 key（如 `bWalletTransaction`）而不是中文名
- **原因**: AutoCode 不会自动更新 `translation/{zh-CN,en-US}/menu.json`，只生成字段级翻译
- **方案**: 生成后手动在菜单翻译文件中补充（每个菜单需要 key + 中文名两条）：
  ```json
  // translation/zh-CN/menu.json
  "bWalletTransaction": "Wallet流水",
  "Wallet流水": "Wallet流水"
  ```
- **日期**: 2026-04-16

## [P007] AutoCode 生成的 decimal 字段精度丢失

- **现象**: 模型定义 `type:decimal(18,2)` 但 DB 实际列为 `decimal(10,0)`
- **原因**: AutoCode 的 `dataTypeLong: "18,2"` 可能没正确传递精度到建表
- **方案**: 生成后检查金额列精度：`SHOW COLUMNS FROM b_xxx WHERE Field = 'amount'`，不对则修：
  ```sql
  ALTER TABLE b_xxx MODIFY COLUMN amount decimal(18,2) DEFAULT NULL;
  ```
- **日期**: 2026-04-16

## [P008] 枚举字段翻译直接照搬 gorm comment + sys_table_columns.enum 没配好

- **现象**:
  - 字段翻译 `"actionType": "动作类型 bet_submit/candy_drop_choice"`（把 gorm comment 整串塞进去了），列表表头展示时又长又丑
  - `sys_table_columns.type='string'`、`enum='[]'`，DiyTable 识别不出是枚举，筛选器是文本输入框而不是下拉选择
  - `translations/{zh-CN,en-US}/business/<model>.json` 里没有 `enums` 段，前端显示的是 `bet_submit` / `candy_drop_choice` 裸字符串
- **原因**: Go 模型的 gorm comment 经常写成 `comment:动作类型 bet_submit/candy_drop_choice` 这种"字段名 + 枚举提示"。执行 SKILL.md Step 3 / Step 4 时如果直接把 comment 原值作 `note` 和翻译 value，就会被一路带进列表表头。并且枚举的 `type/enum/enums` 三处专属配置经常被遗漏
- **方案（四处同步设置）**:
  1. **Go 模型 gorm comment 拆两层**（可选但推荐）：
     - `comment:动作类型`（纯字段名，用于 DB 列注释）
     - 枚举值走 Go 代码里的 `const` 定义，不在 comment 里堆字符串
  2. **sys_table_columns 正确配置**：
     ```sql
     UPDATE sys_table_columns
        SET type = 'enum',                              -- 类型改 enum（原来可能是 string）
            `enum` = '["bet_submit","candy_drop_choice"]',  -- ⚠️ 简单字符串数组，不是对象数组
            note = '动作类型',                           -- 只放字段名，不带枚举值
            `filter` = 1,
            default_filter = '=',
            filter_list = '["=","!=","in","not in"]'
      WHERE tb_name = 'b_game_user_actions'
        AND json_name = 'actionType';
     ```
     **格式强制**：`enum` 必须是简单 JSON 字符串数组（如 `["bcgame","pgplay"]`），
     **不是** `[{"label":...,"value":...}]` 对象数组——前端 DiyForm/DiyTable 的
     renderer 只识别简单数组格式，塞对象数组不会报错，但会渲染成文本框而不是下拉。
     label 从翻译文件 `enums.{jsonName}.{value}` 查，所以翻译段必须同时配好（见 3）。
     参考同表已有 enum 字段的真实格式：
     `SELECT json_name, \`enum\` FROM sys_table_columns WHERE tb_name='<表名>' AND type='enum'`
  3. **翻译 `columns` 只写字段名 + `enums` 嵌套对象结构**：
     ```json
     // translations/zh-CN/business/game_user_actions.json
     {
       "columns": {
         "actionType": "动作类型"          // ❌ 不要写 "动作类型 bet_submit/candy_drop_choice"
       },
       "enums": {                          // ✅ 嵌套对象！不要用扁平 "actionType.bet_submit" key
         "actionType": {
           "bet_submit": "投注提交",
           "candy_drop_choice": "糖果选择"
         }
       }
     }
     ```
     **关键**：vue-i18n 以 `.` 作为嵌套层级分隔符，扁平 key `"actionType.bet_submit"`
     会被解析成嵌套路径查询，结果一定 miss → 前端显示 raw path
     `business.xxx.enums.actionType.bet_submit`。必须用嵌套对象结构。
     参考同目录已正常工作的翻译文件（如 \`bGameUsers.json\` / \`table.json\`）。
     en-US 同步添加
  4. **验证**：刷新后台页面，确认
     - 表头显示 "动作类型"（短）
     - 列值显示中文枚举（"投注提交" / "糖果选择"）而不是 raw 字符串
     - 搜索栏显示下拉框而不是文本输入

- **适用范围**: 凡是 Go 模型中带有 `const` 枚举定义（如 `ActionBetSubmit = "bet_submit"`）的 string/int 字段，都要走这套配置
- **预防**: SKILL.md Step 3 的 `note` 字段规定**只取 gorm comment 的前半部分字段名**，不把 "xx/yy/zz" 枚举说明带进去；Step 4 翻译同理
- **日期**: 2026-04-20 / 更正 2026-04-22（enum 格式必须是简单数组而非对象数组）

### 2026-04-22 更正一：enum 格式是简单数组

最初提出本条目时示例写成 `[{"label":..,"value":..}]` 对象数组，是错的。
实战验证（b_upstreams.type）：用对象数组时前端读不到下拉，依然是文本框。
改成简单字符串数组 `["bcgame","pgplay"]` 后前端立即渲染为下拉。

排查方式：SELECT 同表其它已经工作正常的 enum 字段，对比格式。
项目里可用参考：\`b_tables.gameType\` / \`b_tables.videoChannel\` / \`b_game_users.status\`。

### 2026-04-22 更正二：enums 翻译结构是嵌套对象，不是扁平 key

最初示例 `"actionType.bet_submit": "投注提交"` 这种扁平 key 前端**找不到**。
vue-i18n 以 `.` 作为层级分隔符，会把它解析成嵌套查询 → miss → 前端显示
raw path `business.xxx.enums.actionType.bet_submit`。

正确结构（参考 bGameUsers.json / table.json / bGameRounds.json 这些
**原本就正常工作的**翻译）：
\`\`\`json
"enums": {
  "actionType": {
    "bet_submit": "投注提交"
  }
}
\`\`\`

同一个 2026-04-22 修复批次里，`upstream.json` / `failoverLog.json` /
`gameUserAction.json` 六个文件都从扁平 key 改为嵌套对象。KNOWN-ISSUES
示例亦一并纠正。

**排查指引**：前端看到 raw key `business.xxx.enums.yyy.zzz` 而非翻译值时，
十有八九是扁平 key 问题；打开同目录已正常工作的翻译对照结构即可。
