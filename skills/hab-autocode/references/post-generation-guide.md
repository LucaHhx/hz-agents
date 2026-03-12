# 生成后完善指南 (autocode = 基站)

autocode 生成完整但通用的 CRUD 模块（代码、数据库表、API 路由、菜单、按钮权限、SysTableColumns、翻译文件）。以下步骤根据业务场景进行定制化完善。

## A. 完善 SysTableColumns 配置

通过 API `PUT /sysTableColumns/updateSysTableColumns` 或前端「列配置」管理页批量更新。

**列宽调整 (`with`)**

autocode 按类型设置默认列宽，实际应根据数据内容调整：

| 类型 | 默认值 | 调整建议 |
|------|--------|----------|
| string | 120 | 短字段（状态码、编号）缩窄至 60-80；长文本（地址、描述）扩宽至 200-300 |
| int/int32 | 80 | 金额等大数字可扩至 120 |
| int64/float64 | 100 | 同上 |
| datetime | 180 | 仅显示日期可缩至 120 |
| enum | 100 | 枚举文本短可缩至 60-80 |
| richtext | 280 | 通常不在表格展示完整内容 |
| json/array | 200 | 视内容而定 |

**必填标记 (`formMust`)**

- autocode 默认所有字段 `formMust: false`
- 对业务关键字段设 `formMust: true`（前端表单显示红色星号 *）
- 注意区分：autocode 的 `require` 控制**后端校验**，`formMust` 控制**前端表单星号显示**
- 通常两者应一致，但某些场景可分离（如后端允许空但前端建议填写）

**固定列 (`fixed`)**

- 关键标识列（如 ID、编号）设 `fixed: "left"`
- 列较多时操作列设 `fixed: "right"`
- 值为空字符串 `""` 表示不固定（默认）

**排序优化 (`sort`)**

- 调整 `sort` 值让重要业务列靠前
- autocode 按字段定义顺序递增设置 sort

**搜索配置 (`isAddSearch`)**

- autocode 默认 `isAddSearch: false`
- 对常用查询字段设 `isAddSearch: true`，使其出现在搜索区
- `searchWidth` 控制搜索框宽度（默认 0 表示自动）

**表单配置**

| 字段 | 说明 | 默认值 |
|------|------|--------|
| `formWith` | 表单项宽度百分比 | 45（约半行）；富文本/JSON 默认 93（近全行） |
| `formDisabled` | 创建后只读 | false；系统字段（ID、时间、操作人）默认 true |
| `formHidden` | 表单中隐藏 | false；系统字段默认 true |
| `formOrder` | 表单排序 | 按字段顺序递增 |
| `formMust` | 必填星号 | false（需手动设置） |

## B. 补充翻译文件

翻译文件路径：`server/translation/{lang}/business/{packageName}.json`

autocode 生成的翻译文件包含三段：`columns`（列名）、`enums`（枚举值）、`messages`（提示消息）。

**enum 占位符替换**

autocode 生成的 enum 值是占位符格式（如 `"1": "Status-1"`），需替换为真实业务含义：

```json
// Before (autocode 生成)
"enums": {
  "status": { "1": "Status-1", "2": "Status-2", "3": "Status-3" }
}

// After (业务完善)
"enums": {
  "status": { "1": "待处理", "2": "处理中", "3": "已完成" }
}
```

**messages 段**

添加业务特定提示消息（如确认操作、状态变更提示）：
```json
"messages": {
  "confirmComplete": "确认将此订单标记为已完成？",
  "cannotDeleteProcessing": "处理中的订单不可删除"
}
```

**en-US 同步**

同步更新 `server/translation/en-US/business/{packageName}.json`，确保中英文翻译一致。

## C. 按钮权限配置（仅 authority=1）

> **重要约束**：AI 只负责 authority=1（超管）的按钮权限配置，**绝不修改其他角色的权限**。其他角色的权限由管理员通过管理界面手动分配。

autocode 设置 `autoCreateBtnAuth: true` 时自动创建 9 个标准按钮权限（仅 authority=1）：

| 按钮名 | 说明 |
|--------|------|
| add | 新增 |
| batchDelete | 批量删除 |
| delete | 删除 |
| edit | 编辑 |
| info | 详情 |
| exportTemplate | 导出模板 |
| exportExcel | 导出 Excel |
| importExcel | 导入 Excel |
| columnConfig | 列配置 |

**自定义按钮**：在 `SysBaseMenuBtn` 添加新记录，前端使用 `v-auth="btnAuth.customName"` 控制显示。

**copy 按钮**：如需复制功能，手动添加 `copy` 按钮权限。

## D. 列权限配置（仅 authority=1）

- AI 只负责 authority=1 的列权限配置
- 其他角色的列权限由管理员通过「列配置」管理页手动分配
- 列权限通过 `useColsForRoute()` 和 `getColumns()` 在前端生效

## E. 业务完善检查清单

```
[ ] 翻译：enum 值替换为真实业务含义
[ ] 翻译：en-US 文件同步更新
[ ] 列配置：FormMust 标记业务必填字段
[ ] 列配置：列宽根据实际数据内容调整
[ ] 列配置：关键标识列设 Fixed("left")
[ ] 列配置：常用查询字段设 IsAddSearch(true)
[ ] 列配置：表单配置（formWith、formDisabled、formHidden、formOrder）
[ ] 权限：确认 authority=1 的按钮权限完整（不动其他角色）
[ ] 权限：确认 authority=1 的列权限完整（不动其他角色）
[ ] 前端：业务特定表单校验规则
[ ] 后端：业务特定 service 逻辑（如状态流转、计算字段）
```

## F. 参考文件

| 文件 | 用途 |
|------|------|
| `server/model/system/sys_table_columns.go` | SysTableColumns 数据模型（With, FormMust, Fixed 等字段定义） |
| `server/api/v1/system/sys_table_columns.go` | 表列批量更新 API |
| `server/model/system/sys_menu_btn.go` | 按钮权限模型（SysBaseMenuBtn） |
| `web/src/utils/btnAuth.js` | 前端按钮权限获取（useBtnAuth） |
| `web/src/utils/colAuth.js` | 前端列权限获取（useColsAuth, useColsForRoute） |
| `web/src/utils/columns.js` | 前端列配置获取（getColumns） |
| `server/translation/zh-CN/business/sysTableColumns.json` | 业务翻译格式参考 |
| `server/model/system/request/sys_auto_code.go` | autocode Columns() 方法（了解自动生成的默认值） |
