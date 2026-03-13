---
name: hab-temp
description: "HAB Admin Base 模板知识库 — hz-admin-base 项目模板的完整参考指南。涵盖架构总览、前后端分层、认证权限（JWT+Casbin）、用户/角色/菜单管理、API/字典/参数管理、AutoCode 代码生成、CRUD 开发全流程（生成→验证→优化）、配置与启动、中间件管道、文件上传与云存储、国际化翻译、插件系统、DiyTable/DiyForm 动态组件、布局与主题、系统工具（导出/操作记录/数据过滤/定时任务）、全局变量与工具函数。触发条件：hz-admin-base 模板使用、模板功能查询、后端架构、前端架构、权限系统、CRUD 开发、AutoCode、代码生成后验证、代码优化、中间件、上传、字典、菜单、角色、用户管理、DiyTable、DiyForm、布局、主题、插件、翻译、定时任务、数据过滤、导出模板。"
---

# HAB Admin Base — 项目模板知识库

> hz-admin-base 模板的完整功能参考，帮助 AI 理解并使用该企业级后台管理框架模板

## 模板概述

hz-admin-base 是基于 **Go(Gin) + Vue3(Element Plus)** 的企业级后台管理系统模板，提供：
- 完整的 RBAC 权限管理（JWT + Casbin）
- AutoCode 代码自动生成
- 多数据库支持（MySQL/PostgreSQL/SQLite/SQL Server/Oracle）
- 多云存储支持（阿里云/腾讯云/AWS/七牛/MinIO/华为/Cloudflare）
- 插件系统、国际化、动态表单表格等企业级功能

## 参考文件索引

| # | 文件 | 关键词 | 说明 |
|---|------|--------|------|
| 1 | [architecture-overview.md](references/architecture-overview.md) | 架构, 目录, 技术栈, 分层, 总览 | 整体架构、目录结构、技术栈 |
| 2 | [backend-layers.md](references/backend-layers.md) | 后端, API, Router, Service, Model, 分层 | 后端四层架构详解 |
| 3 | [frontend-architecture.md](references/frontend-architecture.md) | 前端, Vue3, Element Plus, Pinia, 组件 | 前端架构与核心模块 |
| 4 | [auth-permission.md](references/auth-permission.md) | JWT, Casbin, RBAC, 权限, 认证, 鉴权, token | 认证与权限系统 |
| 5 | [user-role-menu.md](references/user-role-menu.md) | 用户, 角色, 菜单, 权限分配, 数据权限 | 用户/角色/菜单管理 |
| 6 | [api-dictionary-params.md](references/api-dictionary-params.md) | API管理, 字典, 参数, dictionary, params | API/字典/系统参数 |
| 7 | [autocode-guide.md](references/autocode-guide.md) | AutoCode, 代码生成, 自动代码, 模板, 包管理 | AutoCode 代码生成完整指南 |
| 8 | [crud-workflow.md](references/crud-workflow.md) | CRUD, 开发流程, 验证, 优化, 前端任务, 后端任务 | CRUD 开发全流程与最佳实践 |
| 9 | [config-startup.md](references/config-startup.md) | 配置, config, yaml, 启动, 端口, 环境, 模式 | 配置文件与启动指南 |
| 10 | [middleware-pipeline.md](references/middleware-pipeline.md) | 中间件, CORS, 限流, 日志, 操作记录 | 中间件管道详解 |
| 11 | [file-upload-oss.md](references/file-upload-oss.md) | 上传, OSS, 云存储, 文件, 图片 | 文件上传与多云存储 |
| 12 | [i18n-translation.md](references/i18n-translation.md) | 国际化, 翻译, i18n, 多语言, translation | 国际化翻译系统 |
| 13 | [plugin-system.md](references/plugin-system.md) | 插件, plugin, 扩展, 安装, 发布 | 插件系统 |
| 14 | [diy-components.md](references/diy-components.md) | DiyTable, DiyForm, 动态表格, 动态表单, 组件 | DiyTable/DiyForm 动态组件 |
| 15 | [layout-theme.md](references/layout-theme.md) | 布局, 主题, 暗黑模式, 侧边栏, 标签页 | 布局与主题系统 |
| 16 | [system-tools.md](references/system-tools.md) | 导出, 操作记录, 数据过滤, 定时任务, 运行状态 | 系统工具集 |
| 17 | [global-utils.md](references/global-utils.md) | 全局变量, 工具函数, 枚举, HAB_DB, 响应 | 全局变量与工具函数 |

## 使用方式

1. 根据用户问题匹配上表中的**关键词**
2. **Read** 对应参考文件获取详细内容
3. 多个主题相关时可同时读取多个文件

**匹配示例：**
- "模板整体架构是什么" → `references/architecture-overview.md`
- "后端代码怎么分层" → `references/backend-layers.md`
- "前端用了什么技术" → `references/frontend-architecture.md`
- "权限怎么控制" → `references/auth-permission.md`
- "怎么管理用户和角色" → `references/user-role-menu.md`
- "字典怎么用" → `references/api-dictionary-params.md`
- "怎么用 AutoCode 生成代码" → `references/autocode-guide.md`
- "CRUD 生成后要做什么" → `references/crud-workflow.md`
- "怎么配置项目" → `references/config-startup.md`
- "中间件有哪些" → `references/middleware-pipeline.md`
- "怎么上传文件" → `references/file-upload-oss.md`
- "怎么做多语言" → `references/i18n-translation.md`
- "插件怎么用" → `references/plugin-system.md`
- "DiyTable 怎么用" → `references/diy-components.md`
- "怎么切换布局/主题" → `references/layout-theme.md`
- "怎么导出数据" → `references/system-tools.md`
- "全局变量有哪些" → `references/global-utils.md`

**组合查询：**
- AutoCode + CRUD 验证 → `autocode-guide.md` + `crud-workflow.md`
- 权限 + 用户角色 → `auth-permission.md` + `user-role-menu.md`
- 前端开发 → `frontend-architecture.md` + `diy-components.md` + `layout-theme.md`
- 后端开发 → `backend-layers.md` + `middleware-pipeline.md` + `global-utils.md`
