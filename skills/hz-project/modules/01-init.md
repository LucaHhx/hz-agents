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
- 数据库：SQLite（默认）/ MySQL

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
2. 交互问答收集项目信息（逐步引导，每次一个问题）
3. 拉取模板（git clone --depth 1 到临时目录，再复制到项目目录）
4. 项目定制化（config.example.yaml、Dockerfile、web 配置）
5. 数据库准备与初始化（SQLite 自动导入 / MySQL 引导安装）
6. 生成 config.local.yaml（含数据库连接信息 + JWT key）
7. 初始化 Git
8. 启动 PM 进行业务需求 brainstorming
9. 输出总结与下一步建议

## 初始化后如何启动

```bash
# 启动后端
cd server && HAB_CONFIG=config.local.yaml go run .

# 启动前端（另一个终端）
cd web && npm install && npm run serve

# 浏览器打开 http://localhost:8091
# 用 admin / 123456（或自定义密码）登录
```

详细配置说明见 `modules/08-config.md`。
