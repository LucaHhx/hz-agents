# AutoCode API 参考

所有请求需携带 `x-api-key` 请求头。基础 URL 默认 `http://localhost:9688`（端口以 config.yaml 为准）。

## 通用格式

```bash
# POST
curl -s -X POST "http://localhost:9688/autoCode/<endpoint>" \
  -H "Content-Type: application/json" \
  -H "x-api-key: <your-api-key>" \
  -d '<json-body>'

# GET
curl -s -X GET "http://localhost:9688/autoCode/<endpoint>?param=value" \
  -H "x-api-key: <your-api-key>"
```

成功响应: `{"code": 0, "data": {...}, "msg": "Success"}`。`code` 非 0 表示失败。

---

## 包管理

### 查询已有包

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
      {"ID": 1, "packageName": "system", "template": "package", "label": "system包", "desc": "系统自动读取system包", "module": "hab"}
    ]
  }
}
```

### 创建包

```bash
curl -s -X POST "http://localhost:9688/autoCode/createPackage" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d '{"packageName": "order", "label": "订单管理", "desc": "订单相关业务模块", "template": "package"}'
```

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| packageName | string | 是 | 包名（小写英文，不含 / \ ..） |
| label | string | 否 | 展示名 |
| desc | string | 否 | 描述 |
| template | string | 是 | 模板类型: `package`（标准）、`plugin`（插件）、`storage`（存储服务） |

创建包会自动生成 `api/v1/<pkg>/enter.go`、`router/<pkg>/enter.go`、`service/<pkg>/enter.go` 等目录结构。

### 其他包操作

```bash
# 获取可用模板类型
curl -s -X GET "http://localhost:9688/autoCode/getTemplates" -H "x-api-key: $API_KEY"

# 删除包
curl -s -X POST "http://localhost:9688/autoCode/delPackage" \
  -H "Content-Type: application/json" -H "x-api-key: $API_KEY" -d '{"id": 1}'
```

---

## 代码生成

### 预览代码（推荐先预览再生成）

```bash
curl -s -X POST "http://localhost:9688/autoCode/preview" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d @examples/create-module.json
```

响应包含所有将要生成的文件路径和代码内容。

### 确认生成

```bash
curl -s -X POST "http://localhost:9688/autoCode/createTemp" \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d @examples/create-module.json
```

生成操作会：创建代码文件 → AST 注入注册到 enter.go/router_biz.go → 自动迁移建表 → 注册 API 路由 → 创建菜单。

---

## 数据库查询

```bash
# 获取数据库列表
curl -s -X GET "http://localhost:9688/autoCode/getDB" -H "x-api-key: $API_KEY"

# 获取表列表
curl -s -X GET "http://localhost:9688/autoCode/getTables?dbName=hab" -H "x-api-key: $API_KEY"

# 获取表列信息
curl -s -X GET "http://localhost:9688/autoCode/getColumn?tableName=sys_users&dbName=hab" -H "x-api-key: $API_KEY"
```

列信息响应示例:
```json
{
  "columns": [
    {"columnName": "id", "dataType": "bigint", "dataTypeLong": "20", "columnComment": "主键ID", "fieldName": "Id", "fieldType": "int64", "fieldJson": "id"}
  ]
}
```

---

## 回滚

```bash
# 查询生成历史（flag: 0=未回滚, 1=已回滚）
curl -s -X POST "http://localhost:9688/autoCode/getSysHistory" \
  -H "Content-Type: application/json" -H "x-api-key: $API_KEY" \
  -d '{"page": 1, "pageSize": 10}'

# 查看详情
curl -s -X POST "http://localhost:9688/autoCode/getMeta" \
  -H "Content-Type: application/json" -H "x-api-key: $API_KEY" \
  -d '{"id": 1}'

# 执行回滚（移除文件+撤回注入+删除API/菜单/表）
curl -s -X POST "http://localhost:9688/autoCode/rollback" \
  -H "Content-Type: application/json" -H "x-api-key: $API_KEY" \
  -d '{"id": 1, "deleteApi": true, "deleteMenu": true, "deleteTable": true}'

# 只回滚代码但保留数据库表 → "deleteTable": false
# 删除历史记录
curl -s -X POST "http://localhost:9688/autoCode/delSysHistory" \
  -H "Content-Type: application/json" -H "x-api-key: $API_KEY" \
  -d '{"id": 1}'
```

回滚操作: 移除生成文件（到 `rm_file/`，非永久删除）→ 撤回 AST 注入 → 可选删除 API/菜单/表 → 标记 flag=1。

---

## 错误处理

| 错误场景 | 错误信息 | 解决方案 |
|----------|----------|----------|
| 包名重复 | "存在相同PackageName" | 先 getPackage 查询 |
| 包名是 Go 关键字 | "\<name\>为go的关键字!" | 改用其他名称 |
| 结构体重复 | "已经创建过此数据结构" | 先查历史，必要时 rollback 再创建 |
| 包结构异常 | "package结构异常,缺少..." | 检查 enter.go 是否存在 |
| API Key 无效 | 401 "invalid api key" | 检查 config.yaml 中的 api-key |
| 未认证 | 401 "未登录或非法访问" | 确认请求头携带 x-api-key |
