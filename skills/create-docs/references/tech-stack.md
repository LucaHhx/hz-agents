# 项目技术栈规范

所有技术选型必须基于以下标准栈，除非有充分理由并记录在 design.md 中。

## Backend — Go

| 类别 | 技术 | 说明 |
|------|------|------|
| 语言 | Go 1.25+ | |
| Web 框架 | Gin | 高性能 HTTP 框架 |
| ORM | GORM + SQLite Driver | 数据库操作与自动迁移 |
| 数据库 | SQLite | 轻量嵌入式数据库，无需独立服务 |
| 认证 | golang-jwt/jwt v5 | JWT Token 鉴权 |
| 配置 | Viper | 多格式配置管理 (YAML) |
| 日志 | Zap | 结构化日志 |
| 校验 | go-playground/validator v10 | 请求参数校验 |

**后端项目结构:**
```
server/
├── cmd/server/          # 入口 main.go
├── internal/
│   ├── handler/         # HTTP 处理器
│   ├── service/         # 业务逻辑
│   ├── repository/      # 数据库访问
│   ├── model/           # 数据模型 (GORM)
│   ├── middleware/       # 中间件 (JWT 鉴权等)
│   └── router/          # 路由定义
├── pkg/
│   ├── database/        # SQLite 连接初始化
│   ├── response/        # 统一响应格式
│   └── utils/           # JWT 工具等
├── config/              # 配置加载
└── go.mod
```

## Frontend — React + TypeScript + Tauri

| 类别 | 技术 | 说明 |
|------|------|------|
| 框架 | React 19 | UI 框架 |
| 语言 | TypeScript 5.9+ | 类型安全 |
| 构建 | Vite 7+ | 开发服务器与构建 |
| 样式 | Tailwind CSS 4+ | 原子化 CSS |
| 状态管理 | Zustand | 轻量状态管理 |
| HTTP | Axios | API 请求 |
| 路由 | React Router DOM 7+ | 客户端路由 |
| 桌面 | Tauri 2.x (Rust) | 跨平台桌面应用 |
| 移动端 | Capacitor 8+ | iOS / Android 支持 |
| 代码规范 | ESLint + typescript-eslint | Lint 检查 |

**前端项目结构:**
```
frontend/
├── src/
│   ├── api/             # Axios 请求封装
│   ├── pages/           # 页面组件
│   ├── components/      # 通用组件
│   ├── stores/          # Zustand 状态
│   ├── types/           # TypeScript 类型定义
│   ├── hooks/           # 自定义 Hooks
│   └── utils/           # 工具函数
├── src-tauri/           # Tauri Rust 代码
│   └── Cargo.toml
├── package.json
├── vite.config.ts
├── tsconfig.json
└── tailwind.config.ts
```

## 开发约定

| 约定 | 说明 |
|------|------|
| API 代理 | Vite dev 代理 `/api` → `http://localhost:8080` |
| 前端端口 | 5173 |
| 后端端口 | 8080 |
| 认证方案 | JWT Bearer Token |
| 响应格式 | `{ code, message, data }` 统一封装 |
| 数据库迁移 | GORM AutoMigrate |
