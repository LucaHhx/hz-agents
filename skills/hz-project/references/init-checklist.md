# 项目初始化定制清单

从 hz-admin-base 模板创建项目后，必须修改以下项目完成定制化。

> **注意**: Go module（`hab`）、import 路径（`"hab/`）、全局变量前缀（`HAB_`）**保持不变**，所有项目统一使用 hab 作为基础框架标识。

## 后端定制（config.yaml）

| # | 项目 | 配置路径 | 修改内容 |
|---|------|---------|---------|
| 1 | 数据库类型 | `system.db-type` | `sqlite` / `mysql` / `pgsql` |
| 2 | 数据库名 | `mysql.db-name` 或 SQLite 路径 | 改为项目名 |
| 3 | JWT 签名 | `jwt.signing-key` | 新生成的 UUID（`uuidgen`） |
| 4 | AutoCode module | `autocode.module` | 改为项目名（影响代码生成路径） |
| 5 | 日志前缀 | `zap.prefix` | `'[hab]'` → `'[<project>]'` |

## Dockerfile 定制

| # | 项目 | 修改内容 |
|---|------|---------|
| 6 | 工作目录 | `/srv/hab` → `/srv/<project>` |
| 7 | 二进制名 | 按项目命名 |

## 前端定制（web/）

| # | 项目 | 文件 | 修改内容 |
|---|------|------|---------|
| 8 | 页面标题 | `web/index.html` | `<title>` 改为项目名称 |
| 9 | 开发端口 | `web/.env` | `VITE_CLI_PORT`（默认 8091） |
| 10 | API 端口 | `web/.env` | `VITE_SERVER_PORT`（默认 9688） |

## 项目配置

| # | 项目 | 文件 | 修改内容 |
|---|------|------|---------|
| 11 | hz-agents 链接 | `.claude/link.sh` | `HZ_AGENTS` 路径指向实际 hz-agents 位置 |
| 12 | Claude 设置 | `.claude/settings.local.json` | 权限和 agent 配置 |

## 验证清单

完成定制化后验证：

```bash
# 1. 编译检查
cd server && go build ./...

# 2. 前端检查
cd web && npm install && npm run serve
```
