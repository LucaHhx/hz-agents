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
