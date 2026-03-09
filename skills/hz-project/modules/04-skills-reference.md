# 模块 04 — 技能速查表

## 概述

hz-agents 提供三类组件：Skills（知识库）、Commands（可执行命令）、Agents（专业代理）。

## Skills（知识库）

当用户问题匹配时自动触发，提供领域知识。

| Skill | 说明 | 触发场景 |
|-------|------|---------|
| hz-project | 项目全生命周期管理 | 项目初始化、管理、部署 |
| brainstorming | 创意设计探索 | 任何创造性工作前的设计讨论 |
| create-docs | 文档结构管理 | 初始化/管理 docs/ 目录 |
| create-skill | 创建新 skill | 扩展 hz-agents 技能 |
| create-command | 创建新 command | 扩展 hz-agents 命令 |
| create-agent | 创建新 agent | 扩展 hz-agents 代理 |
| hab-autocode | AutoCode 代码生成 | CRUD 模块自动生成 |
| ui-ux-pro-max | UI/UX 设计 | 界面设计与视觉效果 |
| tauri-v2 | Tauri 桌面应用 | 跨平台桌面开发 |
| tailwindcss-advanced-components | Tailwind 高级组件 | 复杂 UI 组件开发 |
| agent-browser | 浏览器自动化 | 网页测试与数据提取 |
| mysql-operator | MySQL 操作 | 数据库查询与管理 |
| redis-operator | Redis 操作 | 缓存查询与管理 |
| process-manager | 进程管理 | 启动/管理后台服务 |
| subagent-driven-development | 子代理驱动开发 | 并行执行实现计划 |

## Commands（可执行命令）

用户通过 `/command-name` 触发。

### 评审类

| 命令 | 说明 |
|------|------|
| /review-pm | PM 评审/完善需求业务文档 |
| /review-tech | Tech Lead 创建/更新技术方案 |
| /review-ui | UI 设计师产出/更新设计稿 |
| /review-qa | QA 执行验收测试 |
| /review-all | PM + Tech Lead + UI 全面评审 |

### 开发类

| 命令 | 说明 |
|------|------|
| /dev-tech | Tech Lead 带队前后端开发 |
| /dev-frontend | 前端开发实现代码 |
| /dev-backend | 后端开发实现代码 |

### 工具类

| 命令 | 说明 |
|------|------|
| /cmd-autocode | AutoCode 交互式代码生成向导 |
| /hz-init | 交互式项目初始化 |

### 统一调度类

| 命令 | 说明 |
|------|------|
| /unify-doc-review | PM + Tech Lead + UI 文档协作评审 |
| /unify-dev | 全团队协作开发 |
| /unify-fix | 自动诊断并修复 bug |

## Agents（专业代理）

通过 commands 或直接调用触发。

| Agent | 角色 | 核心能力 |
|-------|------|---------|
| hz-pm | 产品经理 | 需求分析、文档管理、验收标准 |
| hz-tech-lead | 开发总管 | 技术选型、架构设计、任务拆解 |
| hz-ui | UI 设计师 | 视觉设计、设计系统、响应式布局 |
| hz-frontend | 前端开发 | 页面实现、组件开发、状态管理 |
| hz-backend | 后端开发 | API 实现、数据模型、业务逻辑 |
| hz-qa | QA 测试 | 测试用例、API 测试、E2E 验收 |
