---
name: hz-project
description: "HZ Project — 项目全生命周期管理。从模板创建项目、管理文档、开发迭代、部署上线的完整知识库。触发条件：项目初始化、创建新项目、使用模板、项目管理、文档架构、角色分工、开发流程、迭代方式、技能/命令/代理用法、多端项目结构、扩展 hz-agents、AutoCode 代码生成、环境配置、部署上线、常见问题排查。"
---

---
name: hz-project
description: "HZ Project — 项目全生命周期管理。从模板创建项目、管理文档、开发迭代、部署上线的完整知识库。触发条件：项目初始化、创建新项目、使用模板、项目管理、文档架构、角色分工、开发流程、迭代方式、技能/命令/代理用法、多端项目结构、扩展 hz-agents、AutoCode 代码生成、环境配置、部署上线、常见问题排查。"
---

# HZ Project — 项目全生命周期管理

> 从模板创建项目、管理文档、开发迭代、部署上线的完整知识库

## 触发条件

当用户询问以下任何主题时触发本 skill：
- 项目初始化、创建新项目、使用模板
- 项目管理、文档架构、角色分工
- 开发流程、迭代方式
- 技能/命令/代理用法
- 多端项目结构
- 扩展 hz-agents
- AutoCode 代码生成
- 环境配置
- 部署上线
- 常见问题排查

## 模块索引

| # | 模块 | 文件 | 关键词 | 说明 |
|---|------|------|--------|------|
| 1 | 项目初始化 | modules/01-init.md | 初始化, 新项目, hz-init, 模板, clone | 从 hz-admin-base 模板创建项目 |
| 2 | 项目管理 | modules/02-management.md | docs, 文档, 三层架构, 角色, docs.py | docs 三层架构与角色分工 |
| 3 | 开发流程 | modules/03-workflow.md | 流程, 迭代, review, dev, 开发 | 标准开发迭代流程 |
| 4 | 技能速查 | modules/04-skills-reference.md | skill, command, agent, 技能, 命令 | 所有技能/命令/代理速查 |
| 5 | 多端规范 | modules/05-multi-endpoint.md | 多端, web, client, 前端, 标签 | 多端项目结构与任务路由 |
| 6 | 扩展指南 | modules/06-extension.md | 扩展, 自定义, 新skill, 新command | 如何扩展 hz-agents |
| 7 | AutoCode | modules/07-autocode.md | autocode, 代码生成, CRUD | AutoCode 代码生成入口 |
| 8 | 环境配置与启动 | modules/08-config.md | config, 配置, 环境变量, yaml, 启动, start, .env, 端口, 双端口 | 双端口架构、完整/极简配置示例、端口联动、项目启动指南 |
| 9 | 部署指南 | modules/09-deploy.md | 部署, deploy, docker, 发布 | 本地/远程部署指南 |
| 10 | 常见问题 | modules/10-faq.md | 问题, 报错, 失败, 排查 | FAQ 与故障排查 |
| 11 | 数据库准备 | modules/11-database-setup.md | 数据库, MySQL, SQLite, 安装, 初始化 | 数据库选择、安装、初始化 |

## 参考文件

| 文件 | 说明 |
|------|------|
| references/init-checklist.md | 项目初始化后的定制化清单 |
| references/deploy-guide.md | 部署模式详解与脚本模板 |
| references/troubleshooting.md | 故障排查手册 |
| references/gorm-pitfalls.md | GORM 5 条硬性规则 |
| references/crud-framework-guide.md | CRUD 全角色指南 |
| references/go-request-patterns.md | Go/Gin 请求结构体模式 |
| references/known-issues.md | 已知问题库（BUG-001~010） |
| references/doc-simplification.md | 文档精简策略 |
| references/hab-integration-checklist.md | AutoCode 集成检查清单 |
| references/response-and-errors.md | 响应格式、错误码、基础模型、工具函数 |

## 使用方式

1. 根据用户问题匹配上表中的**关键词**
2. **Read** 对应模块文件获取详细内容
3. 多个模块相关时可同时读取多个文件
4. 参考文件按需读取（init-checklist 配合 01-init，deploy-guide 配合 09-deploy）

**示例：**
- 用户问"怎么创建新项目" → 读取 `modules/01-init.md` + `references/init-checklist.md`
- 用户问"怎么部署到服务器" → 读取 `modules/09-deploy.md` + `references/deploy-guide.md`
- 用户问"前端任务标签怎么用" → 读取 `modules/05-multi-endpoint.md`
- GORM 问题 → `references/gorm-pitfalls.md` + `references/known-issues.md`
- AutoCode 后续集成 → `references/hab-integration-checklist.md`
- 请求结构设计 → `references/go-request-patterns.md`
- 简单 CRUD 文档 → `references/doc-simplification.md` + `references/crud-framework-guide.md`
- 响应/错误码/模型 → `references/response-and-errors.md`
