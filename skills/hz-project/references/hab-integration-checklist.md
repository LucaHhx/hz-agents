# AutoCode 后集成检查清单

> 每次 AutoCode 生成代码后，**必须**按此清单逐项检查，全部通过后才能标记任务完成。

## 检查项

### 1. RegisterTables() 中注册新 model

确认新模块的 model 已添加到 `server/initialize/gorm.go` 的 `RegisterTables()` 函数中（或其调用的 `bizModel()` 函数中）。

```bash
# 检查 RegisterTables / bizModel 中是否包含新模块的 model
grep -rn "bizModel\|RegisterTables" server/initialize/gorm.go
```

### 2. enter.go Api/Service group 注册

确认新模块的 Api group 和 Service group 已在**包级** enter.go 中注册。

> **注意**：顶层 `server/api/v1/enter.go` 只做包聚合（如 `BusinessApiGroup business.ApiGroup`），
> 具体模块的 Api/Service struct 注册在对应包的 enter.go 中。

```bash
# 检查 Api group 注册（替换 <package> 为实际包名，如 business）
grep -rn "XxxApi\|新模块Api" server/api/v1/<package>/enter.go

# 检查 Service group 注册
grep -rn "XxxService\|新模块Service" server/service/<package>/enter.go
```

**典型错误**：AutoCode 生成了 api handler 和 service 文件，但忘记在包级 enter.go 中注册 group，导致路由无法挂载。

### 3. router_biz.go InitXxxRouter 调用

确认新模块的 router 初始化函数已在 router_biz.go 中调用。

```bash
# 检查 router 注册
grep -rn "InitXxx\|Init新模块" server/initialize/router_biz.go
```

**典型错误**：router 文件已生成，但 router_biz.go 中未调用 `InitXxxRouter`，导致 API 返回 404。

### 4. sys_table_columns 虚拟列检查

如果模块使用了 sys_table_columns 动态列配置，确认虚拟列（如操作列）的配置正确。

```bash
# 检查是否有自动生成的 SQL 插入 sys_table_columns
grep -rn "sys_table_columns" server/source/
```

### 5. 编译验证

```bash
cd server && go build ./...
```

**编译不通过 = 禁止标记完成。** 常见编译问题：
- import 路径错误（module path 与实际不匹配）
- 缺少依赖包
- 类型不匹配
- 未使用的 import

### 6. curl 冒烟测试

编译通过后，启动服务执行基本的 API 冒烟测试：

```bash
# 获取 token（使用管理员账号）
TOKEN=$(curl -s -X POST http://localhost:9688/base/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"123456"}' | jq -r '.data.token')

# 测试列表接口
curl -s http://localhost:9688/api/xxx/getXxxList \
  -H "x-token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"page":1,"pageSize":10}' | jq .
```

如果返回 404 → 回到检查项 2 和 3。

## 快速检查脚本

```bash
# 一键检查（替换 Xxx 为实际模块名）
MODULE=Xxx
PKG=business  # 替换为实际包名
echo "=== 1. enter.go Api group ==="
grep -rn "${MODULE}" server/api/v1/${PKG}/enter.go
echo "=== 2. enter.go Service group ==="
grep -rn "${MODULE}" server/service/${PKG}/enter.go
echo "=== 3. router_biz.go ==="
grep -rn "Init${MODULE}" server/initialize/router_biz.go
echo "=== 4. GORM varchar check ==="
grep -rn 'type:varchar[^(]' server/model/
echo "=== 5. Compile ==="
cd server && go build ./...
```
