# API 测试记录 — {{REQ_NAME}}

> 创建日期: {{DATE}} | 当前轮次: 第 1 轮

## 测试环境

| 项目 | 值 |
|------|-----|
| 后端基准地址 | http://localhost:8080 |
| API 前缀 | /api/v1 |
| 认证方式 | Bearer Token (JWT) |
| Content-Type | application/json |
| 数据库 | _MySQL / SQLite_ |
| 测试数据准备 | _描述测试数据来源和准备方式_ |

## 认证 Token

_测试前先获取 Token:_

**请求**:
```json
{
  "method": "POST",
  "url": "http://localhost:8080/base/login",
  "headers": {
    "Content-Type": "application/json"
  },
  "body": {
    "username": "admin",
    "password": "123456",
    "captcha": "",
    "captchaId": ""
  }
}
```

**响应**:
```json
{
  "status": 200,
  "headers": {
    "Content-Type": "application/json; charset=utf-8"
  },
  "body": {
    "code": 0,
    "data": {
      "token": "<JWT_TOKEN>",
      "expiresAt": 1234567890
    },
    "msg": "登录成功"
  }
}
```

_后续请求使用此 Token: `Authorization: Bearer <JWT_TOKEN>`_

---

## API-001: _接口名称_

> 对应 design.md 接口: _引用_
> 测试轮次: 第 N 轮 | 结论: 通过 / 失败

### TC-001-1: 正常流程

**请求**:
```json
{
  "method": "POST",
  "url": "http://localhost:8080/api/v1/resource",
  "headers": {
    "Content-Type": "application/json",
    "Authorization": "Bearer <token>",
    "x-user-id": "1"
  },
  "body": {
    "field1": "value1",
    "field2": 100
  }
}
```

**预期**: 状态码 `200`，返回创建的资源数据

**实际响应**:
```json
{
  "status": 200,
  "headers": {
    "Content-Type": "application/json; charset=utf-8"
  },
  "body": {
    "code": 0,
    "data": {
      "id": 1,
      "field1": "value1",
      "field2": 100,
      "createdAt": "2024-01-01T00:00:00Z"
    },
    "msg": "创建成功"
  }
}
```

**结论**: ✅ 通过

---

### TC-001-2: 异常 — 无效参数

**请求**:
```json
{
  "method": "POST",
  "url": "http://localhost:8080/api/v1/resource",
  "headers": {
    "Content-Type": "application/json",
    "Authorization": "Bearer <token>"
  },
  "body": {
    "field1": "",
    "field2": -1
  }
}
```

**预期**: 状态码 `400`，返回字段校验错误

**实际响应**:
```json
{
  "status": 400,
  "body": {
    "code": 7,
    "data": {},
    "msg": "field1 不能为空"
  }
}
```

**结论**: ✅ 通过

---

### TC-001-3: 异常 — 未授权

**请求**:
```json
{
  "method": "POST",
  "url": "http://localhost:8080/api/v1/resource",
  "headers": {
    "Content-Type": "application/json"
  },
  "body": {
    "field1": "value1"
  }
}
```

**预期**: 状态码 `401`

**实际响应**:
```json
{
  "status": 401,
  "body": {
    "code": 7,
    "data": {},
    "msg": "未登录或非法访问"
  }
}
```

**结论**: ✅ 通过

---

### 数据验证

```sql
SELECT id, field1, field2, created_at FROM resource ORDER BY id DESC LIMIT 5;
```

| id | field1 | field2 | created_at |
|----|--------|--------|------------|

**结论**: _数据持久化正确 / 异常_

---

_<!-- 为每个 API 接口复制以上完整块，编号递增: API-002, API-003... -->_
_<!-- 测试用例编号规则: TC-{API编号}-{用例序号}，如 TC-002-1 -->_
