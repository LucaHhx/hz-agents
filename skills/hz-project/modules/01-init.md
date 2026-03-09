# 模块 01 — 项目初始化

## 概述

从 `hz-admin-base` 模板创建新项目，支持三种项目形态。

## 模板来源

- 仓库：`https://github.com/LucaHhx/hz-admin-base.git`
- 框架：基于 GVA（gin-vue-admin）深度定制
- 包含：server（Go 后端）+ web（Vue 3 管理后台）

## 三种项目形态

### 1. 纯后台（server + web）

最常见形态，适合后台管理系统。

```
my-project/
├── server/          # Go 后端（Gin + GORM）
├── web/             # Vue 3 + Element Plus 管理后台
├── docs/            # 项目文档
└── .claude/         # hz-agents 链接
```

### 2. 后台 + 客户端（server + web + client）

适合有面向用户的客户端的项目（如 go-plus）。

```
my-project/
├── server/          # Go 后端（Gin + GORM）
├── web/             # Vue 3 + Element Plus 管理后台
├── client/          # 客户端前端（按需选择技术栈）
├── docs/            # 项目文档
└── .claude/         # hz-agents 链接
```

**client 技术栈选择（不从模板复制，用脚手架新建）：**
- React 19 + Vite + Tailwind CSS + Zustand（推荐，go-plus 实践验证）
- 其他 Vite 支持的框架

### 3. 纯 API（server）

仅后端，适合纯 API 服务。

```
my-project/
├── server/          # Go 后端（Gin + GORM）
├── docs/            # 项目文档
└── .claude/         # hz-agents 链接
```

## 技术栈

### 后端（server/）
- Go + Gin + GORM
- 配置：Viper（YAML）
- 日志：Zap
- 认证：JWT
- 数据库：SQLite（默认）/ MySQL / PostgreSQL

### 管理后台前端（web/）
- Vue 3 + Element Plus
- Pinia 状态管理
- Vue Router
- Vite 构建

### 客户端前端（client/，可选）
- 默认推荐：React 19 + Vite + Tailwind CSS 4 + Zustand
- 桌面：Tauri 2
- 移动端：Capacitor

## 入口命令

使用 `/hz-init` 命令启动交互式项目初始化。

详细定制化清单见 `references/init-checklist.md`。

## 初始化流程概览

1. 检测当前目录状态
2. 交互问答收集项目信息
3. 拉取模板（git clone --depth 1）
4. 项目定制化（批量替换 module、prefix 等）
5. 链接 hz-agents
6. 启动 PM 进行业务需求 brainstorming
7. 输出总结与下一步建议
