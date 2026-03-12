# CRUD 框架全角色指南

## 什么是 AutoCode CRUD 模块

AutoCode 通过 API 自动生成标准 CRUD 代码（model + api handler + router + service + 前端页面），
覆盖：创建、删除、批量删除、更新、查询详情、分页列表。

生成后的代码是**基础框架**，各角色在此基础上做适配和定制，而非从零开始。

---

## 各角色需要知道的

### PM 视角

- CRUD 模块 = 单表增删改查，交互模式固定（列表页 + 表单弹窗 + 详情弹窗）
- 需求文档可精简：不需要详细描述 CRUD 交互流程，只需定义字段和业务规则
- 验收标准按固定模板：创建/编辑/删除/搜索/筛选/启用禁用/查看详情
- 不需要 UI 设计（使用框架默认样式）

### Tech Lead 视角

- 必须在 tech/tasks.md 中用 `[autocode]` 标记 CRUD 任务
- 角色规划中 ui 角色标注为 ❌（标准 CRUD 不需要设计）
- 不需要写 api-contracts.md（CRUD 接口由框架定义）
- 代码审查时重点检查：Save vs Updates、Create/Update struct 分离、enter.go 注册、GORM tag

### Backend 视角

- AutoCode 生成基础代码，backend 只做**定制化适配**（非从零开始）
- 禁止重复创建 AutoCode 已生成的文件
- 必须执行集成检查清单（enter.go、router_biz.go、config migration）
- GORM 硬性规则：禁用 Save()、varchar 带长度、Count/Order 分离、Create/Update struct 分离

### Frontend 视角

- AutoCode 生成 Vue 页面，frontend 只做**二次适配**
- 常见适配任务：枚举值中文显示、Switch 组件绑定、搜索栏定制
- **关键**：Switch toggle 只发送 `{ID, enabled}`，不发送全部字段
- **关键**：翻译文件在后端 `server/translation/` 目录，前端从后端 API 获取翻译
- 不需要参考 UI 设计稿（标准 CRUD 用框架默认样式）

### UI 视角

- 标准 CRUD = 不参与，不产出任何设计文件
- 只写一行说明："标准 CRUD，使用框架默认样式"
- 只有被 Tech Lead 标注为"需要定制"的页面才产出 merge.html

### QA 视角

- 使用标准 CRUD 测试模板（固定 9 项测试）
- 测试前先做健全性检查（编译、注册、GORM tag）
- 重点关注：Switch toggle、部分更新、默认排序、必填字段校验
- 常见 Bug 模式：Save 覆盖字段、Create/Update 共用 struct、varchar 无长度、enter.go 缺注册
- 翻译文件在后端 `server/translation/`，前端从 API 获取翻译数据
