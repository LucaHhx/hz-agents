---
description: HAB AutoCode 交互式代码生成向导 - 创建包、生成CRUD模块、编译检查
argument-hint: [操作描述，如"创建订单模块"或"查看包列表"]
---

# HAB AutoCode 交互式代码生成向导

> **推荐使用方式**: Tech Lead 完成技术评审 (`/review-tech`) 后，
> 对标注 `[autocode]` 的 CRUD 模块使用本命令生成基础代码。
> 也可独立使用进行快速原型开发。

本命令分为两个阶段：
1. **探索阶段**：使用 `brainstorming` skill 结合 `hab-autocode` 的查询 API，与用户沟通并完善需求
2. **执行阶段**：使用 `hab-autocode` skill 的生成 API 执行代码生成，并完成编译检查

---

## Step 0：扫描 [autocode] 标注任务（快捷入口）

如果 `docs/` 目录存在，先扫描所有需求的 `tech/tasks.md`，找出标注 `[autocode]` 的待办任务:

```bash
# 搜索所有 [autocode] 标注的待办任务
grep -r "\[autocode\]" docs/*/tech/tasks.md 2>/dev/null | grep "待办"
```

如果找到 [autocode] 任务:
- 列出这些任务及对应需求
- 直接使用任务中的模块信息进入执行阶段（跳过 brainstorming 探索）
- 如果用户未指定具体模块，使用 AskUserQuestion 让用户选择

如果没有找到或 docs/ 不存在 → 继续正常流程。

---

## 阶段一：探索与需求确认（brainstorming + hab-autocode 查询）

使用 `brainstorming` skill 引导用户明确意图。在 brainstorming 过程中，调用 hab-autocode 的**只读 API** 获取真实数据辅助沟通。

### 1. 了解用户意图

根据 `$ARGUMENTS` 和对话，判断用户想做什么：
- 创建业务包 (package)
- 生成 CRUD 模块
- 为已有模块添加方法
- 查看/回滚生成历史
- 基于已有数据库表生成代码

### 2. 获取当前项目状态

调用 hab-autocode 的查询 API 获取真实数据，展示给用户：
- `getPackage` — 查询当前已有的包列表（包名、描述），格式化为表格
- `getDB` / `getTables` / `getColumn` — 如需了解已有表结构
- `getSysHistory` — 如需查看已生成的模块历史

让用户基于真实项目状态做决策，而非凭空猜测。

### 3. 确定目标包

与用户沟通：
- 模块应该放在哪个包下？
- 是否需要创建新包？
- 包名、展示名、描述是什么？

### 4. 理解模块需求

深入了解用户想创建的业务模块：
- 模块的业务场景和用途
- 核心字段（字段名、类型、用途）
- 如果用户不确定字段，用 `getColumn` 查询已有表结构作为参考

收集的关键信息：
- structName（Go 结构体名，首字母大写）
- tableName（数据库表名，下划线命名）
- packageName（文件名，小写）
- description（中文描述）
- fields（字段列表及其属性）

### 5. 给出优化建议

审查模块设计，向用户提出建议：

1. **字段设计**：类型是否合理（如金额用 decimal 而非 float）、长度是否恰当、是否需要索引
2. **搜索条件**：哪些字段适合精确搜索（=）、模糊搜索（LIKE）、范围搜索（BETWEEN）
3. **表单/列表**：哪些字段应出现在表单（form）、列表（table）、详情（desc）中
4. **命名规范**：fieldName 大驼峰、columnName 下划线、fieldJson 小驼峰
5. **必填校验**：哪些字段应标记为 require
6. **默认值**：是否需要设置 defaultValue

将完整的模块设计方案展示给用户，**等用户明确确认后**才进入执行阶段。

---

## 阶段二：执行代码生成（hab-autocode 执行）

用户确认需求后，使用 `hab-autocode` skill 执行写操作。

### 6. 创建包（如需要）

如果目标包不存在，调用 `createPackage` 创建。

### 7. 预览并生成代码

1. 构建完整的请求 JSON（参考 hab-autocode skill 文档中的字段说明）
2. 调用 `preview` 接口预览生成的代码
3. 将预览结果中的**文件列表**（不是完整代码）展示给用户
4. 等用户确认后，调用 `createTemp` 接口正式生成
5. 用 `ls` 验证文件已生成

### 8. 编译检查与修复

生成代码后立即执行编译检查：

```bash
cd server && go build ./...
```

如果编译失败：
1. 分析错误信息，判断问题类型（import 路径错误、缺少依赖、类型不匹配等）
2. 直接修复生成的代码文件（使用 Edit 工具）
3. 重新编译验证，循环直到编译通过
4. 如果是模板问题（如 .tpl 文件中的硬编码路径），同时修复模板文件防止后续复现

常见问题及修复：
- `forge-basic/` import 路径 → 替换为正确的 module 路径（检查 go.mod）
- 缺少 `gorm.io/gorm` 导入 → 添加到 import
- 未使用的 import → 移除

### 9. 更新文档状态

如果 `docs/` 目录存在且有对应需求:
- 使用 `docs.py done` 标记 [autocode] 任务为已完成:
  ```bash
  python3 .claude/skills/create-docs/scripts/docs.py done <req> <task-number> --role tech
  ```
- 使用 `docs.py log` 在 log.md 记录生成信息:
  ```bash
  python3 .claude/skills/create-docs/scripts/docs.py log <req> 新增 "AutoCode 生成模块: <模块名>, 文件: <文件列表摘要>"
  ```
- 在 backend/design.md 末尾追加「AutoCode 已生成模块」段落（含模块名和文件路径）
- 在 frontend/design.md 末尾追加「AutoCode 已生成页面」段落（含模块名和文件路径）

### 10. 输出总结

编译通过后，输出：
- 生成的文件清单（后端 + 前端）
- 自动完成的操作（建表、API 注册、菜单创建等）
- 如果修复了编译问题，说明修复内容
- **后续建议**:
  ```
  后续建议:
    1. /unify-dev <REQ_NAME>       — 启动全团队开发（含 QA）
    2. /dev-tech <REQ_NAME>        — Tech Lead 带队开发（无 QA）
  ```

---

## 注意事项

- 使用辅助脚本 `.claude/skills/hab-autocode/scripts/autocode.sh` 或直接用 curl 调用 API
- API Key 和端口从 `server/config.local.yaml`（或 `server/config.yaml`）读取
- 默认设置 `gvaModel: true`、`autoMigrate: true`、`autoCreateApiToSql: true`、`autoCreateMenuToSql: true`
- 阶段一只使用查询类 API（getPackage/getDB/getTables/getColumn/getSysHistory），不做任何写操作
- 阶段二的预览（preview）是非破坏性的，始终先预览再生成
- 如果用户要回滚，调用 `getSysHistory` 查历史后执行 `rollback`
