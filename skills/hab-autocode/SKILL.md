---
name: hab-autocode
description: "HAB AutoCode Skill — AI 自动化代码生成操作指南。通过 API 调用 HAB AutoCode 系统生成 CRUD 模块代码。触发条件：创建新的业务模块（如'创建一个订单管理模块'）、基于数据库表生成代码、查看/回滚已生成的代码、为已有模块添加新方法、autocode、代码生成、CRUD。"
---

# HAB AutoCode Skill

> AI 自动化代码生成操作指南 -- 通过 API 调用 HAB AutoCode 系统生成 CRUD 模块代码

## 概述

本 Skill 封装了 HAB 系统的 AutoCode API，支持:
- 创建业务包 (package)
- 生成完整 CRUD 模块代码 (model/api/router/service/前端)
- 预览代码再确认生成
- 查询数据库表结构
- 为已有模块添加方法
- 查看生成历史和回滚操作

### 触发条件

当用户需要:
- 创建新的业务模块 (如"创建一个订单管理模块")
- 基于数据库表生成代码
- 查看/回滚已生成的代码
- 为已有模块添加新方法

## 前置条件

1. HAB server 已启动并运行
2. 配置文件中已设置 `autocode.api-key`（优先读取 `config.local.yaml`，其次 `config.yaml`）
3. 数据库已初始化 (已执行 initdb)

### 配置 API Key

在 `server/config.local.yaml`（或 `config.yaml`）中添加:

```yaml
autocode:
  api-key: "your-random-api-key-here"  # 生成: uuidgen 或 openssl rand -hex 32
```

> `autocode` 的其他字段（web、server、module）均有代码级默认值（见 `config/defaults.go`），
> 可省略不写。`module` 会自动从 `go.mod` 读取。

重启 server 使配置生效。

## 辅助脚本

项目提供了辅助脚本简化 API 调用:

- `scripts/config.sh` -- 从 config.yaml 读取配置，导出环境变量
- `scripts/autocode.sh` -- 封装所有 API 的 curl 调用

### 使用方式

```bash
# 直接使用脚本
.claude/skills/hab-autocode/scripts/autocode.sh packages
.claude/skills/hab-autocode/scripts/autocode.sh get-db
.claude/skills/hab-autocode/scripts/autocode.sh preview examples/create-module.json
```

脚本会自动从 `server/config.local.yaml`（或 `config.yaml`）读取 API Key 和服务器地址。

## API 端点清单

所有请求需携带 `x-api-key` 请求头。基础 URL 默认为 `http://localhost:9688`（具体端口和前缀以 config.yaml 为准）。

### 通用 curl 格式

```bash
# POST 请求
curl -s -X POST "http://localhost:9688/autoCode/<endpoint>" \
  -H "Content-Type: application/json" \
  -H "x-api-key: <your-api-key>" \
  -d '<json-body>'

# GET 请求
curl -s -X GET "http://localhost:9688/autoCode/<endpoint>?param=value" \
  -H "x-api-key: <your-api-key>"
```

### 成功响应格式

所有 API 返回统一格式:
```json
{
  "code": 0,
  "data": { ... },
  "msg": "Success"
}
```

`code` 为 0 表示成功，非 0 表示失败，`msg` 包含错误信息。

---

## 操作流程

### 流程一: 创建包

包是模块的容器，创建模块前必须先确保包已存在。

**步骤 1: 查询已有包**

```bash
curl -s -X POST "http://localhost:9688/autoCode/getPackage" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d '{}'
```

响应:
```json
{
  "code": 0,
  "data": {
    "pkgs": [
      {
        "ID": 1,
        "packageName": "system",
        "template": "package",
        "label": "system包",
        "desc": "系统自动读取system包",
        "module": "hab"
      }
    ]
  },
  "msg": "Success"
}
```

**步骤 2: 创建新包 (如果不存在)**

```bash
curl -s -X POST "http://localhost:9688/autoCode/createPackage" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d '{
    "packageName": "order",
    "label": "订单管理",
    "desc": "订单相关业务模块",
    "template": "package"
  }'
```

参数说明:
| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| packageName | string | 是 | 包名 (小写英文，不含 / \ ..) |
| label | string | 否 | 展示名 |
| desc | string | 否 | 描述 |
| template | string | 是 | 模板类型: "package"（标准业务包）、"plugin"（插件包）或 "storage"（存储服务包，用于文件上传/存储相关模块） |

创建包会自动生成 `api/v1/<pkg>/enter.go`、`router/<pkg>/enter.go`、`service/<pkg>/enter.go` 等目录结构。

**获取可用模板类型:**

```bash
curl -s -X GET "http://localhost:9688/autoCode/getTemplates" \
  -H "x-api-key: $API_KEY"
```

**删除包:**

```bash
curl -s -X POST "http://localhost:9688/autoCode/delPackage" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d '{"id": 1}'
```

---

### 流程二: 创建模块 (代码生成)

**步骤 1: 构建请求体**

完整字段示例 (参见 `examples/create-module.json`):

```json
{
  "package": "order",
  "tableName": "orders",
  "structName": "Order",
  "packageName": "order",
  "abbreviation": "order",
  "humpPackageName": "order",
  "description": "订单管理",
  "businessDB": "",
  "gvaModel": true,
  "autoMigrate": true,
  "autoCreateApiToSql": true,
  "autoCreateMenuToSql": true,
  "autoCreateBtnAuth": true,
  "onlyTemplate": false,
  "generateServer": true,
  "generateWeb": true,
  "fields": [
    {
      "fieldName": "OrderNo",
      "fieldDesc": "订单号",
      "fieldType": "string",
      "fieldJson": "orderNo",
      "dataType": "varchar",
      "dataTypeLong": "64",
      "comment": "订单编号",
      "columnName": "order_no",
      "fieldSearchType": "=",
      "form": true,
      "table": true,
      "desc": true,
      "require": true
    }
  ]
}
```

**步骤 2: 预览代码 (推荐)**

```bash
curl -s -X POST "http://localhost:9688/autoCode/preview" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d @examples/create-module.json
```

响应包含所有将要生成的文件内容:
```json
{
  "code": 0,
  "data": {
    "autoCode": {
      "server/api/v1/order/order.go": "...",
      "server/model/order/order.go": "...",
      "server/router/order/order.go": "...",
      "server/service/order/order.go": "...",
      "web/src/api/order/order.js": "...",
      "web/src/view/order/order/order.vue": "..."
    }
  },
  "msg": "预览成功"
}
```

**步骤 3: 确认生成**

```bash
curl -s -X POST "http://localhost:9688/autoCode/createTemp" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d @examples/create-module.json
```

生成操作会:
- 创建所有代码文件
- 通过 AST 注入注册代码到 enter.go、router_biz.go 等
- 自动迁移数据库建表 (autoMigrate=true)
- 注册 API 路由 (autoCreateApiToSql=true)
- 创建菜单 (autoCreateMenuToSql=true)

**步骤 4: 验证**

检查生成的文件是否存在:
```bash
ls server/api/v1/order/ server/model/order/ server/router/order/ server/service/order/
```

---

### 流程三: 查询数据库结构

用于基于已有表生成代码，或了解当前数据库状态。

**获取数据库列表:**

```bash
curl -s -X GET "http://localhost:9688/autoCode/getDB" \
  -H "x-api-key: $API_KEY"
```

响应:
```json
{
  "code": 0,
  "data": {
    "dbs": ["hab"],
    "dbList": [
      {"aliasName": "...", "dbName": "...", "disable": false, "dbtype": "mysql"}
    ]
  },
  "msg": "Success"
}
```

**获取表列表:**

```bash
curl -s -X GET "http://localhost:9688/autoCode/getTables?dbName=hab" \
  -H "x-api-key: $API_KEY"
```

响应:
```json
{
  "code": 0,
  "data": {
    "tables": [
      {"tableName": "sys_users"}
    ]
  },
  "msg": "Success"
}
```

**获取表列信息:**

```bash
curl -s -X GET "http://localhost:9688/autoCode/getColumn?tableName=sys_users&dbName=hab" \
  -H "x-api-key: $API_KEY"
```

响应:
```json
{
  "code": 0,
  "data": {
    "columns": [
      {
        "columnName": "id",
        "dataType": "bigint",
        "dataTypeLong": "20",
        "columnComment": "主键ID",
        "fieldName": "Id",
        "fieldType": "int64",
        "fieldJson": "id"
      }
    ]
  },
  "msg": "Success"
}
```

---

### 流程四: 添加方法

为已有模块添加新的 API 方法。

```bash
curl -s -X POST "http://localhost:9688/autoCode/addFunc" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d '{
    "package": "order",
    "structName": "Order",
    "packageName": "order",
    "humpPackageName": "order",
    "abbreviation": "order",
    "funcName": "ExportOrder",
    "router": "exportOrder",
    "method": "GET",
    "description": "导出订单",
    "funcDesc": "导出订单数据",
    "isAuth": true,
    "isPreview": false,
    "isAi": false
  }'
```

预览模式: 设置 `"isPreview": true`，返回预览代码而不写入文件。

AI 模式: 设置 `"isAi": true`，可通过 `apiFunc`、`serverFunc`、`jsFunc` 字段自定义生成的代码内容。

---

### 流程五: 回滚

**步骤 1: 查询生成历史**

```bash
curl -s -X POST "http://localhost:9688/autoCode/getSysHistory" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d '{"page": 1, "pageSize": 10}'
```

响应:
```json
{
  "code": 0,
  "data": {
    "list": [
      {
        "ID": 1,
        "table": "orders",
        "package": "order",
        "structName": "Order",
        "description": "订单管理",
        "flag": 0
      }
    ],
    "total": 1,
    "page": 1,
    "pageSize": 10
  },
  "msg": "Success"
}
```

`flag`: 0 = 未回滚, 1 = 已回滚

**步骤 2: 查看详情 (可选)**

```bash
curl -s -X POST "http://localhost:9688/autoCode/getMeta" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d '{"id": 1}'
```

**步骤 3: 执行回滚**

```bash
curl -s -X POST "http://localhost:9688/autoCode/rollback" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d '{
    "id": 1,
    "deleteApi": true,
    "deleteMenu": true,
    "deleteTable": true
  }'
```

回滚操作包括:
- 移除生成的文件 (移动到 `rm_file/` 目录，非永久删除)
- 撤回 AST 注入的代码 (enter.go, router_biz.go 等)
- 删除自动创建的 API 记录 (`deleteApi: true`)
- 删除自动创建的菜单 (`deleteMenu: true`)
- 删除数据库表 (`deleteTable: true`)
- 将历史记录标记为 `flag = 1`

如果只想回滚代码但保留数据库表，设置 `"deleteTable": false`。

**步骤 4: 删除历史记录 (可选)**

```bash
curl -s -X POST "http://localhost:9688/autoCode/delSysHistory" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d '{"id": 1}'
```

---

## 字段参考

构建请求体时查阅完整字段定义：**[references/field-reference.md](references/field-reference.md)**

包含 AutoCode 结构体字段、AutoCodeField 字段、AutoFunc 字段的完整说明。

---

## 错误处理与常见问题

| 错误场景 | 错误信息 | 解决方案 |
|----------|----------|----------|
| 包名重复 | "存在相同PackageName" | 先 getPackage 查询，不重复创建 |
| 包名是 Go 关键字 | "\<name\>为go的关键字!" | 改用其他名称 |
| 结构体重复 | "已经创建过此数据结构,请勿重复创建!" | 先查历史，必要时先 rollback 再重新创建 |
| 包结构异常 | "package结构异常,缺少..." | 检查对应 enter.go 文件是否存在 |
| 包名含非法字符 | "包名不合法" | 不要在包名中使用 / \ .. |
| API Key 无效 | 401 "invalid api key" | 检查 config.yaml 中的 api-key 配置 |
| 未认证 | 401 "未登录或非法访问" | 确认请求头中携带了 x-api-key |

---

## 生成后完善指南

代码生成后的业务定制化完善流程：**[references/post-generation-guide.md](references/post-generation-guide.md)**

包含 SysTableColumns 配置、翻译文件完善、按钮/列权限配置、业务完善检查清单。

---

## 安全注意事项

1. **API Key 安全**: API Key 存储在 `config.yaml` 中，该文件已在 `.gitignore` 中，不会提交到版本控制。建议使用 `uuidgen` 或 `openssl rand -hex 32` 生成高强度密钥。
2. **访问范围**: API Key 仅对 AutoCode 相关路由生效，不能用于访问用户管理、权限管理等其他接口。
3. **审计追溯**: API Key 请求的操作日志中 Username 为 "api-key"，可与人工操作区分。所有生成操作都有历史记录，支持回滚。
4. **文件权限**: 建议设置 `config.yaml` 文件权限为 600 (`chmod 600 server/config.yaml`)。
5. **生产环境**: 生产环境必须使用 HTTPS 传输 API Key。
