# CRUD 模块审阅规范

## 审阅时机

| 时机 | 执行者 | 触发点 | 侧重 |
|------|--------|--------|------|
| A. AutoCode 后审阅 | Tech Lead | AutoCode 生成代码后 | 生成质量、注册完整性 |
| B. 开发完成审阅 | Backend 自验 | 标记任务完成前 | 业务逻辑、struct 设计 |
| C. 代码审查 | Tech Lead | 代码审查阶段 | 全量检查 |
| D. QA 前置检查 | QA | API 测试前 | 结构性缺陷拦截 |

## 检查项目录

### 一、注册完整性（审阅时机: A/C/D）

| ID | 检查项 | 检查方法 | 失败案例 |
|----|--------|---------|---------|
| REG-1 | model 在 gorm_biz.go 注册 | 读取 server/initialize/gorm_biz.go，确认 bizModel() 中有 &{pkg}.{Struct}{} | model 没 AutoMigrate，表不存在 |
| REG-2 | enter.go Api group 注册 | 读取 server/api/v1/{pkg}/enter.go，确认有 {Struct}Api 字段 | API 路由 404 |
| REG-3 | enter.go Service group 注册 | 读取 server/service/{pkg}/enter.go，确认有 {Struct}Service 字段 | 编译失败 |
| REG-4 | router_biz.go 初始化 | 读取 server/initialize/router_biz.go，确认有 Init{Struct}Router 调用 | 路由未加载 |

### 二、Model & Struct 设计（审阅时机: A/B/C）

| ID | 检查项 | 检查方法 | 失败案例 |
|----|--------|---------|---------|
| STR-1 | Create/Update struct 分离 | 读取 server/model/{pkg}/request/，确认存在 Create{Struct}Request 和 Update{Struct}Request 两个独立 struct | BUG-001: Update 零值覆盖 |
| STR-2 | Create struct 必填字段有 binding:"required" | 读取 Create{Struct}Request，检查业务必填字段有 binding:"required" tag | BUG-003: 缺少 required 校验 |
| STR-3 | Update struct 仅 ID 是 required | 读取 Update{Struct}Request，确认只有 ID 字段有 binding:"required" | 部分更新失败 |
| STR-4 | 布尔字段使用 *bool 指针 | 在 Update struct 中，布尔类型字段必须是 *bool | Switch toggle false 无法保存 |
| STR-5 | GORM tag 无裸 varchar | 读取 model 文件，确认无 type:varchar（应使用 size:N） | GORM 迁移不确定长度 |
| STR-6 | design.md 唯一字段有 uniqueIndex | 对比 design.md 唯一约束 vs model GORM tag | BUG-002: 重复数据可插入 |

### 三、Service 层逻辑（审阅时机: B/C）

| ID | 检查项 | 检查方法 | 失败案例 |
|----|--------|---------|---------|
| SVC-1 | Update 使用 Updates() 不用 Save() | 读取 service 文件，确认更新操作用 db.Updates() | BUG-001: 零值覆盖 |
| SVC-2 | Count() 和 Order() 查询分离 | 确认分页查询中 Count 和 Order 不在同一个 DB chain | Count 结果受 Order 影响出错 |
| SVC-3 | 唯一性校验在 Create 和 Update 中都有 | 读取 service，确认两个方法都有查重逻辑 | 重复数据可创建/更新 |
| SVC-4 | 唯一性校验 Update 时跳过零值 | 确认 Update 查重时排除零值字段 | 空字段也触发唯一性报错 |

### 四、sys_table_columns 配置（审阅时机: A/B/C/D）

| ID | 检查项 | 检查方法 | 失败案例 |
|----|--------|---------|---------|
| COL-1 | 虚拟列 vs model 字段对齐 | 如果 model 用 HAB_MODEL（无 CreatedBy/UpdatedBy/DeletedBy），确认 sys_table_columns 中没有注册 created_by/updated_by/deleted_by | BUG-004: Unknown column 错误 |
| COL-2 | type 值在 DiyForm 支持列表内 | 检查所有字段的 type，禁止裸 int（改用 int32） | 表单渲染为 textarea |
| COL-3 | 必填字段 formMust = true | 业务必填字段的 formMust 配置正确 | 前端无必填星号提示 |
| COL-4 | 枚举字段 type 为 enum | 枚举字段配置正确，enum 数组包含所有值 | 下拉框为空 |

### 五、翻译文件（审阅时机: B/C）

| ID | 检查项 | 检查方法 | 失败案例 |
|----|--------|---------|---------|
| I18N-1 | 翻译文件存在 | 确认 server/translation/zh-CN/business/{pkg}.json 存在 | 页面显示 key 不显示中文 |
| I18N-2 | enum 占位符已替换 | 检查 enums 段没有 "Status-1" 等占位符 | 状态显示为 Status-1 |
| I18N-3 | en-US 同步 | 确认 en-US 翻译文件存在且内容完整 | 英文环境报错 |

### 六、编译（审阅时机: A/B/C/D）

| ID | 检查项 | 检查方法 | 失败案例 |
|----|--------|---------|---------|
| BUILD-1 | go build 通过 | 执行 cd server && go build ./... | 编译失败 |

## 审阅输出模板

agent 完成审阅后，必须输出以下格式的审阅结果：

| ID | 检查项 | 结果 | 备注 |
|----|--------|------|------|
| REG-1 | gorm_biz.go 注册 | ✅ PASS | |
| STR-1 | Create/Update 分离 | ❌ FAIL | 共用 AiModelConfig struct |
| COL-1 | 虚拟列对齐 | ⚠️ WARN | HAB_MODEL 无 created_by，需确认 |
| ... | ... | ... | ... |

**审阅结论**: PASS / FAIL（附 FAIL 项数量和具体问题）

- ❌ FAIL 项必须修复后重新审阅
- ⚠️ WARN 项需评估，记录决策理由
- 审阅结果表格写入对应文档（log.md 或 test-report.md）

## 常见问题排查指南

遇到问题时按以下决策树逐步排查，每步给出具体的检查命令和文件路径。

---

### FAQ-1: 服务启动后数据库表没有同步

**现象**: 启动服务后访问 API 报 "Error 1146: Table doesn't exist" 或 SQLite "no such table"

**排查步骤**:
1. **检查配置是否开启自动同步**
   - 读取 server/config.local.yaml（或 config.yaml），确认 `system.migration: true`
   - 如果为 false → 改为 true 并重启服务
2. **检查 model 是否注册到同步位置**
   - 读取 server/initialize/gorm_biz.go，确认 bizModel() 中有 `db.AutoMigrate(&{pkg}.{Struct}{})`
   - 如果缺失 → 添加注册
3. **检查 model import 是否正确**
   - gorm_biz.go 的 import 段是否导入了 model 包
   - 包路径拼写是否正确
4. **检查 model struct 的 GORM tag**
   - 是否有 `gorm:"table:xxx"` 指定表名
   - 字段类型是否与数据库兼容

---

### FAQ-2: 页面没有翻译（显示 key 或英文占位符）

**现象**: 页面字段显示为 `business.aiModelConfig.columns.name` 或 `Status-1`

**排查步骤**:
1. **检查前端是否写死了文字**
   - 读取对应的 .vue 文件，确认 label 使用 `$t('business.xxx.columns.yyy')` 而非硬编码中文
   - AutoCode 生成的标准 CRUD 页面由 DiyTable/DiyForm 驱动，翻译由后端 sys_table_columns 配置自动处理，不需要前端写 $t()
   - **如果是标准 CRUD 页面但没翻译** → 检查 sys_table_columns 的 structName 是否正确（DiyForm 用 `business.{structName}.columns.{jsonName}` 作为翻译 key）
2. **检查后端翻译文件是否存在**
   - 确认 `server/translation/zh-CN/business/{packageName}.json` 存在
   - 文件名必须与 packageName（小写驼峰）一致
3. **检查翻译文件内容是否完整**
   - columns 段：每个字段都有对应的中文翻译
   - enums 段：占位符 "Status-1" 等已替换为真实业务含义（"启用"/"禁用"）
   - messages 段：业务提示消息已填写
4. **检查 en-US 翻译文件是否同步**
   - `server/translation/en-US/business/{packageName}.json` 存在且 key 结构与 zh-CN 一致
5. **检查翻译文件 JSON 格式**
   - JSON 语法是否正确（可 `cat server/translation/zh-CN/business/{pkg}.json | python3 -m json.tool` 验证）

---

### FAQ-3: 修改保存后没有更新到数据库

**现象**: 编辑表单提交后显示成功，但数据库中的值未变化或被清空

**排查步骤**:
1. **检查 Service 层 Update 方法使用的是 Updates() 还是 Save()**
   - 读取 server/service/{pkg}/{module}.go 的 Update 方法
   - 如果用了 `db.Save(&model)` → 改为 `db.Updates(updates)` 模式
   - Save() 会将零值字段也写入数据库，导致未传的字段被清空（BUG-001 根因）
2. **检查 Create/Update 是否使用分离的 Request struct**
   - 共用 struct 时，Update 请求只传了部分字段，其他字段为零值
   - 如果只有一个 struct → 分离为 CreateXxxRequest 和 UpdateXxxRequest
3. **检查 Update struct 的必填设置**
   - UpdateXxxRequest 中只有 ID 应该是 `binding:"required"`
   - 其他字段不应有 required，否则部分更新时会校验失败
4. **检查布尔字段类型**
   - Update struct 中的布尔字段是否用了 `*bool` 指针类型
   - 非指针 bool 的零值是 false，Updates() 会跳过零值，导致无法将字段改为 false
5. **检查前端请求格式**
   - 打开浏览器 DevTools Network，查看 PUT 请求的 Body
   - 确认 JSON 字段名与后端 struct 的 json tag 一致
   - 特别注意：Switch toggle 场景只传 `{ID, status}` 时，后端需要能正确处理

---

### FAQ-4: 更新列设置（sys_table_columns）后前端没有生效

**现象**: 在后台修改了 sys_table_columns 配置（如 formMust、type、列宽），但前端页面看不到变化

**排查步骤**:
1. **检查列设置是否已保存到数据库**
   - 用 mysql-operator 查询：`SELECT * FROM sys_table_columns WHERE struct_name = 'XxxStruct' AND json_name = 'fieldName'`
   - 确认修改的字段值已持久化（如 form_must、type、with 等）
   - 如果值未更新 → API 调用有问题，检查请求是否成功
2. **检查服务端缓存是否已清除**
   - **关键**: 列配置有服务端内存缓存 `utils.ColumnsCache`（见 server/utils/table_query.go:22）
   - 通过**管理后台界面**修改列配置时，API 会自动调用 `ColumnsCache.Clear()` 或 `ColumnsCache.Remove(authorityId)` 清除缓存
   - 但**直接操作数据库**（如 mysql-operator SQL）修改列配置时，缓存不会被清除！
   - 解决方案：直接操作数据库后**必须重启服务**才能生效，或通过 API 调用 update 接口触发缓存清除
   - 注意 `UpdateSysTableColumnsInfo`（批量更新）只清除**当前用户角色**的缓存（`Remove(authorityId)`），不是全量清除。如果其他角色也需要看到变化，需要那个角色重新登录或重启服务
3. **检查前端页面是否需要刷新**
   - sys_table_columns 数据在页面加载时通过 `getColumns()` API 获取
   - 服务端缓存清除后，前端还需要**刷新页面**（F5），不是简单切换路由
4. **检查列权限（authority_cols）**
   - 列配置生效依赖 `sys_authority_cols` 中的权限关联
   - 确认当前用户的 authority_id 在 sys_authority_cols 中有对应的 column_id 记录
   - 用 mysql-operator 查询：`SELECT * FROM sys_authority_cols WHERE authority_id = 1 AND sys_table_columns_id = <column_id>`
5. **检查 is_show 字段**
   - sys_table_columns 的 `is_show` 必须为 1（或 true），否则该列不会返回给前端
6. **检查 struct_name 和 table_name 是否匹配**
   - sys_table_columns 的 `struct_name` 必须与路由 meta 中的 structName 一致
   - 前端通过当前路由的 structName 查询对应的列配置
7. **检查虚拟列问题（COL-1）**
   - 如果 model 用的是 HAB_MODEL（不含 created_by/updated_by/deleted_by），但 sys_table_columns 中注册了这些字段
   - 查询时 SELECT 会包含不存在的列，导致 SQL 错误
   - 解决：删除 sys_table_columns 和 sys_authority_cols 中多余的列记录

---

### FAQ-5: API 路由 404

**现象**: curl 调用 API 返回 404 Not Found

**排查步骤**:
1. **检查路由是否注册**
   - 读取 server/initialize/router_biz.go，确认有 `Init{Struct}Router()` 调用
2. **检查 enter.go 注册链**
   - server/router/{pkg}/enter.go 中 RouterGroup 是否嵌入了 {Struct}Router
   - server/api/v1/{pkg}/enter.go 中 ApiGroup 是否嵌入了 {Struct}Api
   - server/service/{pkg}/enter.go 中 ServiceGroup 是否嵌入了 {Struct}Service
3. **检查路由路径**
   - 读取 server/router/{pkg}/{module}.go，确认路由 URL 路径是否正确
   - 注意 config 中的 `system.router-prefix`，前端请求路径是否包含了前缀
4. **检查中间件分组**
   - 路由注册到 PrivateGroup（需要 JWT）还是 PublicGroup（不需要）
   - 如果在 PrivateGroup 但请求没带 token → 返回 401 而非 404

---

### FAQ-6: Switch toggle 保存异常

**现象**: 在列表页点击 Switch 开关切换状态后，该行其他字段被清空

**排查步骤**:
1. **前端检查**
   - Switch 的 @change 事件是否只发送了 `{ID, status}` 还是发送了整行数据
   - 如果只发送了部分字段，后端必须支持部分更新
   - 前端 Switch 的 active-value/inactive-value 类型是否与后端一致（数字 vs 布尔）
2. **后端检查**
   - Update 方法是否使用 `Updates()` 而非 `Save()`
   - Update struct 中 status 是否为 `*bool` 或 `*int` 指针类型
   - Update struct 中其他字段是否有 `binding:"required"`（不应该有）

---

### FAQ-7: 编译通过但运行时 panic

**现象**: `go build` 成功，但启动服务时 panic: nil pointer

**排查步骤**:
1. **检查全局变量初始化顺序**
   - global.HAB_DB 是否在使用前初始化
   - service 中引用的其他 service 是否已注册
2. **检查 enter.go 的 struct 嵌入**
   - 确认所有嵌入的 struct 已定义且导出
   - 确认 import 路径正确

---

### FAQ-8: API 端口和登录路由不对

**现象**: curl 测试 API 返回 404，尝试多个路径都不通

**排查步骤**:
1. **确认正确的端口**
   - HAB 项目有**两个 HTTP 端口**：
     - **后台管理端口**（如 9688）：所有 CRUD 管理 API、登录、菜单等
     - **客户端 API 端口**（如 9689）：面向客户端的业务 API
   - 读取 `server/config.local.yaml`，查看 `system.addr`（管理端口）和 `client-api.addr`（客户端端口）
   - **CRUD 模块的 API 全部在管理端口上**，不要用客户端端口测试
2. **确认登录路由**
   - HAB 登录接口不是 `/base/login`，而是 `/auth/password/login`
   - 完整登录流程：
     1. 查询安全状态：`POST /auth/security-state` body: `{"username":"admin"}`
     2. 密码登录：`POST /auth/password/login` body: `{"username":"admin","password":"123456"}`
   - 登录成功后从响应 `data.token` 取得 JWT token
3. **确认 GIN 调试日志的路由前缀**
   - GIN 的 `[GIN-debug]` 日志中打印的路由**不包含 router-prefix**
   - 实际请求路径 = `router-prefix`（如果有）+ GIN 调试日志中的路径
   - 用 `curl http://localhost:{管理端口}/api/health` 测试是否有 `/api` 前缀
   - 如果 `/api/health` 返回 `"ok"` → 所有路由都需要加 `/api` 前缀
   - 如果 `/health` 直接返回 → 无前缀
4. **正确的 CRUD API 测试模板**
   ```bash
   # 1. 获取 token
   TOKEN=$(curl -s -X POST http://localhost:9688/auth/password/login \
     -H "Content-Type: application/json" \
     -d '{"username":"admin","password":"123456"}' | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['token'])")

   # 2. 测试 CRUD API（以 aiModelConfig 为例）
   curl -s http://localhost:9688/aiModelConfig/getAiModelConfigList \
     -H "Content-Type: application/json" \
     -H "x-token: $TOKEN" \
     -d '{"page":1,"pageSize":10}'
   ```
