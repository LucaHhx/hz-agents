# 已知问题库

> 从供应商管理项目的实际测试中提炼的已知问题，每个问题包含症状、根因和解决方案。

## BUG-001: AutoMigrate 建表失败

**症状**：服务启动后数据库中没有新表，或建表 SQL 报错。
**根因**：新 model 未在 `server/initialize/gorm.go` 的 `RegisterTables()` 中注册（业务 model 在其调用的 `bizModel()` 函数中添加）。
**解决方案**：在 `bizModel()` 函数中添加新 model 的注册。

## BUG-002: 建表 SQL 语法错误 (varchar)

**症状**：MySQL 建表报 SQL 语法错误，错误信息指向 `varchar` 类型定义。
**根因**：GORM tag 中 `type:varchar` 未指定长度，MySQL 要求 varchar 必须有长度。
**解决方案**：将 `type:varchar` 改为 `type:varchar(200)` 或使用 `size:200`。

```go
// 修复前
Name string `gorm:"type:varchar"`
// 修复后
Name string `gorm:"size:200"`
```

## BUG-003: API 调用返回 404 (Api group 未注册)

**症状**：curl 调用新 API 返回 404 Not Found。
**根因**：`server/api/v1/enter.go` 中未注册新模块的 Api group。
**解决方案**：在 enter.go 的 ApiGroup struct 中添加新模块的 Api group 字段。

## BUG-004: API 调用返回 404 (Router 未注册)

**症状**：curl 调用新 API 返回 404 Not Found（enter.go 已注册）。
**根因**：`server/initialize/router_biz.go` 中未调用 `InitXxxRouter`。
**解决方案**：在 router_biz.go 中添加 `InitXxxRouter(PrivateGroup, PublicGroup)` 调用。

## BUG-005: 列表页列配置异常

**症状**：前端列表页的列显示异常（缺列、多出虚拟列、列宽不合理）。
**根因**：`sys_table_columns` 中的虚拟列配置不正确，或列排序/显示属性未设置。
**解决方案**：检查 sys_table_columns 表数据，修正列配置。

## BUG-006: Update API 清空未传字段

**症状**：编辑保存后，未修改的字段被清空为零值（空字符串、0、false）。
**根因**：后端使用 `Save()` 做更新，Save 会覆盖全部字段。
**解决方案**：将 `Save()` 改为 `Updates()`，只更新传入的字段。

```go
// 修复前
db.Save(&model)
// 修复后
db.Model(&model).Where("id = ?", id).Updates(updateData)
```

## BUG-007: Switch toggle 返回 400 错误

**症状**：前端 Switch 组件切换时返回 400 Bad Request。
**根因**：Create 和 Update 共用 struct，Update struct 中有 `binding:"required"` 字段。Switch 只传 `{ID, enabled}`，缺少 required 字段导致校验失败。
**解决方案**：Create 和 Update 使用分离的 struct，Update struct 中只有 ID 是 required。

## BUG-008: 分页列表排序失效

**症状**：列表页数据没有按预期排序（如不是按创建时间倒序）。
**根因**：GORM 的 `Count()` 会清除之前的 `Order()` 设置。
**解决方案**：将 Count 查询和带 Order 的数据查询分离为两条独立查询。

```go
// 修复前
db.Order("created_at DESC").Count(&total).Offset(offset).Find(&list)
// 修复后
db.Model(&Model{}).Count(&total)
db.Order("created_at DESC").Offset(offset).Find(&list)
```

## BUG-009: 布尔字段 false 无法保存

**症状**：将开关切换为"关闭"（false）后保存，刷新页面发现仍然是"开启"。
**根因**：`Updates(struct)` 跳过零值，`bool` 的零值是 `false`，因此 `false` 被跳过。
**解决方案**：使用 `*bool` 指针类型，或使用 `map[string]interface{}` 传递更新数据。

## BUG-010: 编辑时必填校验阻塞

**症状**：编辑表单只修改一个字段时，提交被"name is required"等错误拦截。
**根因**：与 BUG-007 同根因 — Create/Update 共用 struct。
**解决方案**：同 BUG-007，分离 Create 和 Update struct。
