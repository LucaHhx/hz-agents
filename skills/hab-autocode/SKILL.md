---
name: hab-autocode
description: "HAB AutoCode Skill — AI 自动化代码生成操作指南。通过 API 调用 HAB AutoCode 系统生成 CRUD 模块代码。触发条件：创建新的业务模块（如'创建一个订单管理模块'）、基于数据库表生成代码、查看/回滚已生成的代码、autocode、代码生成、CRUD。"
---

# HAB AutoCode Skill

通过 API 调用 HAB AutoCode 系统，生成完整 CRUD 模块代码（model/api/router/service/前端页面）。

## 资源清单

### scripts/ — 可执行脚本

| 脚本 | 用途 |
|------|------|
| `scripts/autocode.sh` | AutoCode API 封装，所有操作通过此脚本调用 |
| `scripts/config.sh` | 从 config.yaml 读取 API Key 和服务器地址，导出环境变量 |

### references/ — 按需加载的参考文档

| 文件 | 内容 | 何时读取 |
|------|------|---------|
| `references/api-reference.md` | 完整 API 端点、curl 示例、请求/响应格式、错误处理 | 需要手动调用 API 或调试时 |
| `references/field-reference.md` | AutoCode/AutoCodeField 完整字段定义 + fieldType→DiyForm 组件映射 | 构建请求体时查阅字段类型和选项 |
| `references/post-generation-guide.md` | 生成后业务完善指南：SysTableColumns 配置、翻译文件、按钮/列权限 | 代码生成完成后进行业务定制化 |
| `references/post-generation-checklist.md` | 以"订单模块"为实例的完整完善流程示例 | 首次执行生成后完善时参考 |

### examples/ — 请求体模板

| 文件 | 用途 |
|------|------|
| `examples/create-module.json` | 完整字段的模块创建请求示例 |
| `examples/create-module-simple.json` | 最简模块创建请求示例 |
| `examples/create-package.json` | 包创建请求示例 |
| `examples/rollback.json` | 回滚请求示例 |

## 前置条件

1. HAB server 已启动并运行
2. `server/config.local.yaml`（或 `config.yaml`）已配置 API Key
3. 数据库已初始化

### API Key 配置（两种形态，`scripts/config.sh` 两者都兼容）

**新版（推荐，pp-game 等现行项目）—— 顶级 `api-key` 段**

项目把 AutoCode 路由并入统一的 `ApiKeyOrJWT` 中间件鉴权（见 `server/middleware/api_key.go`），
所有后台 API 共享同一把 key：

```yaml
# server/config.local.yaml
api-key:
  enabled: true
  key: "your-random-api-key-here"   # uuidgen 或 openssl rand -hex 32
  mode: "write"                      # ⚠️ autocode 写操作期间必须是 write
```

> **⚠️ mode 影响 autocode 可用性**
> - `mode: "read"` — 中间件只放行 `get*/find*/list*/search*/preview/export*/count*/check*/page*` 前缀的路径。`preview` 能跑，但 `createTemp` / `createPackage` / `rollback` 会被拒 401。
> - `mode: "write"` — 全放行。autocode 生成操作必须在此模式下。
> - 生成完成后建议改回 `"read"` 以保持安全边界。改完需重启 server。

**旧版（hz-admin-base 原始模板）—— `autocode.api-key` 子字段**

```yaml
autocode:
  api-key: "your-random-api-key-here"
```

> `scripts/config.sh` 优先读新版（顶级 `api-key.key`），读不到时 fallback 到旧版。
> `autocode` 的其他字段（web、server、module）均有代码级默认值，可省略。`module` 会自动从 `go.mod` 读取。

## 辅助脚本用法

优先使用辅助脚本，自动读取配置。脚本位于本 skill 的 `scripts/autocode.sh`，使用前需定位实际路径:

```bash
# 定位 autocode.sh（根据项目实际 skills 安装位置）
AC=$(find . -path "*/hab-autocode/scripts/autocode.sh" -maxdepth 5 2>/dev/null | head -1)

$AC packages                          # 查询已有包
$AC create-package '{"packageName":"order","label":"订单管理","desc":"订单相关","template":"package"}'
$AC get-db                            # 数据库列表
$AC get-tables hab                    # 表列表
$AC get-columns sys_users             # 表字段
$AC preview examples/create-module.json   # 预览代码
$AC create examples/create-module.json    # 生成代码
$AC history                           # 生成历史
$AC rollback 1                        # 回滚（删除所有）
$AC rollback 1 keep-table             # 回滚但保留数据库表
```

> 需要完整 curl 命令或调试 → 读取 `references/api-reference.md`

## 核心工作流

### 流程一: 创建包 → 生成模块

```
1. 查询已有包: $AC packages
2. 创建新包（如不存在）: $AC create-package '<json>'
3. 构建请求 JSON（参考 examples/ 和 references/field-reference.md）
4. 预览: $AC preview <json_file>
5. 确认生成: $AC create <json_file>
6. 编译检查: cd server && go build ./...
7. 业务完善: 读取 references/post-generation-guide.md
```

### 请求体关键字段

构建模块请求时的必填和推荐字段:

```json
{
  "package": "order",           // 包名（需已存在）
  "tableName": "orders",        // 数据库表名
  "structName": "Order",        // Go 结构体名（首字母大写）
  "packageName": "order",       // 文件名（小写）
  "abbreviation": "order",      // 简称（路由前缀）
  "humpPackageName": "order",   // 驼峰文件名
  "description": "订单管理",     // 中文描述
  "gvaModel": true,             // 使用默认 Model（ID, CreatedAt 等）
  "autoMigrate": true,          // 自动迁移建表
  "autoCreateApiToSql": true,   // 自动注册 API 路由
  "autoCreateMenuToSql": true,  // 自动创建菜单
  "autoCreateBtnAuth": true,    // 自动创建按钮权限
  "generateServer": true,       // 生成后端代码
  "generateWeb": true,          // 生成前端代码
  "fields": [...]               // 字段定义（见下方）
}
```

### 字段定义要点

```json
{
  "fieldName": "OrderNo",       // Go 字段名（大驼峰）
  "fieldDesc": "订单号",         // 中文描述
  "fieldType": "string",        // Go 类型（见映射表）
  "fieldJson": "orderNo",       // JSON 名（小驼峰）
  "dataType": "varchar",        // 数据库类型
  "dataTypeLong": "64",         // 长度
  "columnName": "order_no",     // 数据库列名（下划线）
  "fieldSearchType": "=",       // 搜索条件（可选）
  "form": true, "table": true, "desc": true,
  "require": true               // 必填
}
```

**fieldType 常用映射**（完整映射见 `references/field-reference.md`）:

| fieldType | DiyForm 组件 | 注意 |
|-----------|-------------|------|
| string | el-input | |
| int | **⚠️ 需改为 int32** | DiyForm 不识别裸 int，会渲染为 textarea |
| float64 | el-input-number | |
| bool | el-switch | |
| time.Time | el-date-picker | |
| enum | el-select | 需翻译文件 enums 段 |

### 流程二: 回滚

```bash
$AC history              # 查看生成历史（flag: 0=未回滚, 1=已回滚）
$AC rollback <id>        # 完整回滚（代码+API+菜单+表）
$AC rollback <id> keep-table  # 回滚但保留数据库表
```

### 流程三: 查询数据库结构

用于基于已有表生成代码: `$AC get-db` → `$AC get-tables <db>` → `$AC get-columns <table>`

## 生成后完善（必读）

代码生成后需进行业务定制化，详见 **[references/post-generation-guide.md](references/post-generation-guide.md)**:

1. **SysTableColumns 配置** — type 值检查（⚠️ 裸 int 改 int32）、列宽、必填标记、搜索配置
2. **翻译文件** — enum 占位符替换为真实业务含义，en-US 同步
3. **按钮/列权限** — 确认 authority=1 的 9 个标准按钮权限完整
4. **业务逻辑** — 自定义校验、状态流转、关联操作等

> 首次操作可参考实例 → `references/post-generation-checklist.md`

## 安全注意事项

- API Key 存储在 `config.local.yaml`（.gitignore 中），建议 `chmod 600`
- **新版顶级 `api-key` 段**注入的是超管 claims（`authorityId=1`），**可访问所有后台 API**，不仅限 AutoCode。使用期间要意识到这把 key 等同于超管凭证。
  - 旧版 `autocode.api-key` 子字段仅对 AutoCode 路由生效（如果项目模板还保留该独立机制）。
- **生成完成后建议把 `api-key.mode` 改回 `"read"`**，把写权限收回；这样这把 key 只能做查询，泄露风险降一档。
- 操作日志中 Username 为 "api-key"，与人工操作可区分
- 所有生成操作有历史记录，支持回滚
