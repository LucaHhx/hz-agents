# API 契约

> 需求: {{REQ_NAME}} | 创建: {{DATE}}
>
> 本文件是前后端并行开发的接口契约。
> **前后端必须严格遵守本契约。** 任何接口变更需通过 Tech Lead 协调，同步更新本文件。
>
> **重要: 本文件仅定义自定义业务接口。** CRUD 接口（增删改查 + 列表分页）由 AutoCode 自动生成，不在此定义。
> 如需了解 CRUD 接口，请参考 AutoCode 生成的 router/api 代码。

## 通用约定

- 基础路径: `/api`
- 认证: `Authorization: Bearer <token>`

**标准响应格式:**

```json
{
  "code": 0,
  "data": {},
  "msg": ""
}
```

**分页请求:**

```json
{
  "page": 1,
  "pageSize": 10
}
```

**分页响应:**

```json
{
  "code": 0,
  "data": {
    "list": [],
    "total": 0,
    "page": 1,
    "pageSize": 10
  }
}
```

**错误响应:**

```json
{
  "code": 7,
  "msg": "错误说明"
}
```

## AutoCode 生成接口（不在此定义）

<!-- 以下模块的标准 CRUD 接口由 AutoCode 自动生成，无需手动定义:
- 创建 (POST /api/<module>/create<Model>)
- 删除 (DELETE /api/<module>/delete<Model>)
- 更新 (PUT /api/<module>/update<Model>)
- 查询 (GET /api/<module>/find<Model>)
- 列表 (POST /api/<module>/get<Model>List)

在此列出由 AutoCode 管理的模块名，便于查阅:
| 模块 | 模型 | 备注 |
|------|------|------|
-->

## 自定义业务接口

<!-- 按模块分组，每个接口使用以下格式:

### [METHOD] /api/xxx

- **描述**: 接口用途

**请求:**

```json
{
  "field": "value"
}
```

**响应 200:**

```json
{
  "code": 0,
  "data": {
    "id": 1
  }
}
```

**响应 4xx:**

```json
{
  "code": 7,
  "msg": "错误说明"
}
```

- **备注**: 补充说明
-->
