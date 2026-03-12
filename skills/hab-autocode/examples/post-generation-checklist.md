# 生成后完善检查清单 — 以"订单模块"为例

> 本文档以订单管理模块为实例，展示 autocode 生成后的完整完善流程。

## 1. AutoCode 已生成的文件

假设通过 `/cmd-autocode` 生成了 `order` 包下的 `Order` 模块：

```
后端文件:
  server/model/order/order.go          # 数据模型
  server/api/v1/order/order.go         # API handler
  server/router/order/order.go         # 路由注册
  server/service/order/order.go        # 业务逻辑

前端文件:
  web/src/api/order/order.js           # API 调用
  web/src/view/order/order/order.vue   # 页面组件

翻译文件:
  server/translation/zh-CN/business/order.json
  server/translation/en-US/business/order.json

自动操作:
  ✅ 数据库表 orders 已创建 (autoMigrate)
  ✅ API 路由已注册 (autoCreateApiToSql)
  ✅ 菜单已创建 (autoCreateMenuToSql)
  ✅ 9个标准按钮权限已分配给 authority=1 (autoCreateBtnAuth)
  ✅ SysTableColumns 条目已创建（按类型设默认列宽）
```

## 2. 翻译完善

### zh-CN (Before → After)

**Before** (`server/translation/zh-CN/business/order.json`):
```json
{
  "columns": {
    "ID": "ID",
    "orderNo": "订单号",
    "status": "状态",
    "totalAmount": "总金额",
    "customerName": "客户名称",
    "remark": "备注"
  },
  "enums": {
    "status": {
      "1": "Status-1",
      "2": "Status-2",
      "3": "Status-3"
    }
  },
  "messages": {}
}
```

**After**:
```json
{
  "columns": {
    "ID": "ID",
    "orderNo": "订单号",
    "status": "状态",
    "totalAmount": "总金额",
    "customerName": "客户名称",
    "remark": "备注"
  },
  "enums": {
    "status": {
      "1": "待处理",
      "2": "处理中",
      "3": "已完成"
    }
  },
  "messages": {
    "confirmComplete": "确认将此订单标记为已完成？",
    "cannotDeleteProcessing": "处理中的订单不可删除"
  }
}
```

### en-US 同步

`server/translation/en-US/business/order.json`:
```json
{
  "columns": {
    "ID": "ID",
    "orderNo": "Order No.",
    "status": "Status",
    "totalAmount": "Total Amount",
    "customerName": "Customer",
    "remark": "Remark"
  },
  "enums": {
    "status": {
      "1": "Pending",
      "2": "Processing",
      "3": "Completed"
    }
  },
  "messages": {
    "confirmComplete": "Confirm marking this order as completed?",
    "cannotDeleteProcessing": "Cannot delete orders in processing status"
  }
}
```

## 3. SysTableColumns 调整

### 需要调整的字段

| 字段 | 调整项 | Before | After | 原因 |
|------|--------|--------|-------|------|
| orderNo | formMust | false | **true** | 订单号为业务必填 |
| orderNo | fixed | "" | **"left"** | 关键标识列固定左侧 |
| orderNo | isAddSearch | false | **true** | 常用搜索条件 |
| orderNo | with | 120 | **150** | 订单号较长（如 ORD-20240101-001） |
| status | formMust | false | **true** | 状态为业务必填 |
| status | with | 100 | **80** | 枚举文本较短 |
| status | isAddSearch | false | **true** | 常用搜索条件 |
| totalAmount | with | 100 | **120** | 金额需要更宽显示 |
| totalAmount | formMust | false | **true** | 金额为业务必填 |
| customerName | isAddSearch | false | **true** | 常用搜索条件 |
| remark | with | 120 | **200** | 备注文本较长 |
| remark | formWith | 45 | **93** | 备注需要全行宽度 |

### 通过 API 逐条更新示例

```bash
# 更新 orderNo 字段
curl -s -X PUT "http://localhost:9688/sysTableColumns/updateSysTableColumns" \
  -H "Content-Type: application/json" \
  -H "x-token: <admin-token>" \
  -d '{
    "ID": <column_id>,
    "formMust": true,
    "fixed": "left",
    "isAddSearch": true,
    "with": 150
  }'
```

## 4. 权限确认（仅 authority=1）

### 标准按钮权限检查

autocode 已为 authority=1 创建以下按钮权限：

```
✅ add          - 新增订单
✅ edit         - 编辑订单
✅ delete       - 删除订单
✅ batchDelete  - 批量删除
✅ info         - 订单详情
✅ exportTemplate - 导出模板
✅ exportExcel  - 导出 Excel
✅ importExcel  - 导入 Excel
✅ columnConfig - 列配置
```

如需添加自定义按钮（如"复制订单"）：
1. 在 `SysBaseMenuBtn` 中添加 `copy` 按钮记录
2. 前端使用 `v-auth="btnAuth.copy"` 控制显示

> **注意**：其他角色（如 authority=2 普通用户）的按钮/列权限由管理员通过管理界面手动分配，AI 不做任何修改。

## 5. 业务逻辑补充示例

### 前端校验（order.vue）

```javascript
// 订单号格式校验
const orderNoRule = {
  pattern: /^ORD-\d{8}-\d{3}$/,
  message: '订单号格式：ORD-YYYYMMDD-NNN',
  trigger: 'blur'
}

// 金额校验
const amountRule = {
  validator: (rule, value, callback) => {
    if (value <= 0) callback(new Error('金额必须大于0'))
    else callback()
  },
  trigger: 'blur'
}
```

### 后端逻辑（service/order/order.go）

```go
// 删除前检查状态
func (s *OrderService) DeleteOrder(id uint) error {
    var order order.Order
    if err := global.HAB_DB.First(&order, id).Error; err != nil {
        return err
    }
    if order.Status == 2 { // 处理中
        return errors.New("处理中的订单不可删除")
    }
    return global.HAB_DB.Delete(&order).Error
}
```

## 完善检查清单

```
[x] 翻译：enum 值替换为真实业务含义（待处理/处理中/已完成）
[x] 翻译：en-US 文件同步更新
[x] 列配置：FormMust 设置必填字段（orderNo, status, totalAmount）
[x] 列配置：列宽根据数据内容调整
[x] 列配置：orderNo 设 Fixed("left")
[x] 列配置：常用搜索字段设 IsAddSearch（orderNo, status, customerName）
[x] 权限：确认 authority=1 的 9 个标准按钮权限正确
[ ] 前端：订单号格式校验、金额校验
[ ] 后端：删除前状态检查逻辑
[ ] 业务逻辑：需人工审查是否有更多场景
```
