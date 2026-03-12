# GORM 常见陷阱与正确用法

> 从实际项目 Bug 中总结的 GORM 硬性规则。违反任何一条都会导致生产 Bug。

## 1. Save() vs Updates()：部分更新必须用 Updates

**陷阱**：`Save()` 会覆盖**全部字段**（包括未传的字段会被设为零值），导致更新 API 清空未传字段。

```go
// ❌ 错误：Save 覆盖全字段
db.Save(&model)  // 未传的字段被设为 ""、0、false

// ✅ 正确：Updates 只更新传入的字段
db.Model(&model).Where("id = ?", id).Updates(updateData)
```

**规则**：`Save()` 只用于"创建或完整替换"场景。部分更新**必须**使用 `Updates()`。

## 2. varchar 必须带长度

**陷阱**：`type:varchar` 不带长度，在 MySQL 中会报 SQL 语法错误。

```go
// ❌ 错误：varchar 缺长度
Name string `gorm:"column:name;type:varchar;comment:名称"`

// ✅ 正确：varchar 带 size
Name string `gorm:"column:name;type:varchar(200);comment:名称"`
// 或使用 size tag
Name string `gorm:"column:name;size:200;comment:名称"`
```

**规则**：所有 varchar 字段必须指定长度。推荐用 `size:N` 替代 `type:varchar(N)`。

**常见长度参考**：
| 场景 | 推荐长度 |
|------|---------|
| 名称、标题 | 200 |
| 描述、备注 | 500 |
| URL、路径 | 500 |
| 短标识 (code) | 50 |
| 长文本 | 用 text 类型 |

## 3. Count() 清除 Order()

**陷阱**：GORM 的 `Count()` 会清除之前设置的 `Order()`，导致分页查询中排序失效。

```go
// ❌ 错误：Count 清除了 Order
db.Order("created_at DESC").Count(&total).Offset(offset).Limit(limit).Find(&list)
// 实际效果：list 没有按 created_at 排序

// ✅ 正确：Count 和查询分离
db.Model(&Model{}).Where(conditions).Count(&total)
db.Where(conditions).Order("created_at DESC").Offset(offset).Limit(limit).Find(&list)
```

**规则**：分页查询中，`Count()` 和带 `Order()` 的查询**必须分离**为两条独立查询。

## 4. 零值更新问题

**陷阱**：`Updates(struct)` 会跳过零值字段（`""`、`0`、`false`），无法将字段更新为零值。

```go
// ❌ 错误：Updates(struct) 跳过 false
db.Updates(Model{Enabled: false})  // enabled 字段不会被更新

// ✅ 正确方案一：使用 map
db.Updates(map[string]interface{}{"enabled": false})

// ✅ 正确方案二：使用指针类型
type Model struct {
    Enabled *bool `json:"enabled"`
}
```

**规则**：布尔开关字段（如 enabled/disabled）使用 `*bool` 指针类型。

## 5. 布尔字段使用指针类型

**陷阱**：Go 的 `bool` 零值是 `false`，JSON 反序列化时"未传"和"传 false"无法区分。

```go
// ❌ 错误：bool 无法区分未传和 false
type UpdateReq struct {
    Enabled bool `json:"enabled"`
}

// ✅ 正确：*bool 区分 nil（未传）和 false
type UpdateReq struct {
    Enabled *bool `json:"enabled"`
}
```

**规则**：所有布尔开关字段在 Update struct 中使用 `*bool`。

## 检查命令

```bash
# 检查是否有 type:varchar 缺长度
grep -rn 'type:varchar[^(]' server/model/

# 检查是否有 Save() 用于更新
grep -rn '\.Save(' server/service/

# 检查分页查询中 Count 和 Order 是否分离
grep -A5 '\.Count(' server/service/ | grep '\.Order('
```
