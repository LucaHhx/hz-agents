# 模块 05 — 多端项目规范

## 概述

当项目同时包含管理后台（web）和客户端前端（client）时，需要特殊的目录结构和任务路由规则。

## 目录映射

| 代码目录 | 角色目录 | 任务标签 | 技术栈 |
|---------|---------|---------|--------|
| server/ | backend/ | 无标签 | Go + Gin + GORM |
| web/ | frontend/ | `[web]` | Vue 3 + Element Plus |
| client/ | frontend/ | `[client]` | React 19 + Tailwind（或自选） |

**关键规则：**
- `server/` ↔ `backend/` — 无标签，所有后端任务默认属于 server
- `web/` 和 `client/` 都映射到 `frontend/` 角色目录
- 用 `[web]` 和 `[client]` 标签区分不同端的前端任务

## frontend/design.md 分段规范

多端项目的 frontend/design.md 必须按端分段：

```markdown
# 前端技术方案 — [需求名称]

## [web] 管理后台

### 技术栈
- Vue 3 + Element Plus + Pinia + Vue Router

### 页面设计
- [web] 用户管理页 — 表格 + CRUD 弹窗
- [web] 权限设置页 — 角色/菜单/API 权限树

### 组件设计
- [web] UserTable — 用户列表表格组件
- [web] RolePermission — 权限配置组件

---

## [client] 客户端

### 技术栈
- React 19 + Tailwind CSS + Zustand

### 页面设计
- [client] 首页 — 数据展示 + 快捷操作
- [client] 用户中心 — 个人信息管理

### 组件设计
- [client] Dashboard — 数据卡片组件
- [client] ProfileForm — 个人信息表单
```

## frontend/tasks.md 标签路由

```markdown
# 前端技术任务

| ID | 任务 | 状态 |
|----|------|------|
| 1 | [web] 实现用户管理表格页 | 待办 |
| 2 | [web] 实现角色权限配置页 | 待办 |
| 3 | [client] 实现首页 Dashboard | 待办 |
| 4 | [client] 实现用户中心页面 | 待办 |
| 5 | [web] 对接用户 CRUD API | 待办 |
| 6 | [client] 对接用户信息 API | 待办 |
```

## 前端开发路由规则

hz-frontend agent 处理任务时：

1. 读取 `frontend/tasks.md` 中的任务
2. 检查任务标签：
   - `[web]` → 在 `web/` 目录编码，使用 Vue 3 + Element Plus
   - `[client]` → 在 `client/` 目录编码，使用 React/其他
   - 无标签 → 根据项目结构判断：
     - 只有 `web/` → 默认在 web/ 编码
     - 只有 `client/` → 默认在 client/ 编码
     - 都有 → 报错，要求补充标签

## Tech Lead 注意事项

创建 L3 角色目录时：
- 检查项目是否有 `web/` 和 `client/` 两个前端目录
- 如果是多端项目，frontend/design.md 必须按 `## [web]` 和 `## [client]` 分段
- frontend/tasks.md 中的任务必须加 `[web]` 或 `[client]` 前缀标签
- backend/ 不受多端影响，正常处理

## 单端项目

如果项目只有一个前端目录：
- 只有 `web/`（纯后台项目）→ 不需要标签，所有任务默认在 web/ 编码
- 只有 `client/`（无管理后台）→ 不需要标签，但这种情况较少见

向后兼容：如果只有 `web/` 且是 React 项目（非 hz-admin-base 模板），保持原有行为。
