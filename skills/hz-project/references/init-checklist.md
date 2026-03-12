# 项目初始化定制清单

从 hz-admin-base 模板创建项目后，必须修改以下项目完成定制化。

> **注意**: Go module（`hab`）、import 路径（`"hab/`）、全局变量前缀（`HAB_`）**保持不变**，所有项目统一使用 hab 作为基础框架标识。

## 配置文件结构

| 文件 | 用途 | Git |
|------|------|-----|
| `server/config.example.yaml` | 模板参考（非敏感配置） | 提交 |
| `server/config.local.yaml` | 实际运行配置（含密码） | .gitignore |
| `server/config.yaml` | 默认运行配置（可选） | .gitignore |

## 步骤 4：项目定制化（config.example.yaml + 其他文件）

这些在模板文件中修改，会提交到 git：

| # | 项目 | 文件 | 修改内容 |
|---|------|------|---------|
| 1 | AutoCode module | `server/config.example.yaml` | `autocode.module` → 项目名 |
| 2 | 日志前缀 | `server/config.example.yaml` | `zap.prefix` → `'[<project>]'` |
| 3 | Dockerfile 工作目录 | `Dockerfile` | `/srv/hab` → `/srv/<project>` |
| 4 | Dockerfile 二进制名 | `Dockerfile` | 按项目命名（默认为 `hab`） |
| 5 | 页面标题 | `web/index.html` | `<title>` 改为项目名称 |
| 6 | 前端端口 | `web/.env.example` | 按需调整 `VITE_CLI_PORT` |

## 步骤 6：生成 config.local.yaml（含敏感配置）

基于 `config.example.yaml` 复制，额外覆盖以下敏感字段：

| # | 项目 | 配置路径 | 修改内容 |
|---|------|---------|---------|
| 7 | 数据库类型 | `system.db-type` | `sqlite` / `mysql` |
| 8 | 数据库连接 | `mysql.*` | host, port, db-name, user, password（MySQL 时） |
| 9 | JWT 签名 | `jwt.signing-key` | 新生成的 UUID（`uuidgen`） |

> config.local.yaml 不入库，含敏感信息。启动时使用 `HAB_CONFIG=config.local.yaml go run .`

## 前端 .env 文件

| 文件 | 说明 |
|------|------|
| `web/.env.example` | 开发配置模板（mode=development 时加载） |
| `web/.env.dev` | dev 模式配置（mode=dev 时加载） |

如需自定义，复制 `.env.example` 为对应环境文件：
```bash
cp web/.env.example web/.env.development
```

## 验证清单

完成定制化后验证：

```bash
# 1. 后端编译检查
cd server && go build ./...

# 2. 后端启动
HAB_CONFIG=config.local.yaml go run .

# 3. 前端启动
cd web && npm install && npm run serve

# 4. 浏览器验证
# 打开 http://localhost:8091 → 用 admin 登录
```
