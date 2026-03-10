# 模块 07 — AutoCode 代码生成

## 概述

AutoCode 是 hz-admin-base（HAB）内置的代码生成系统，可通过 API 或管理后台 UI 生成完整的 CRUD 模块代码。

## 入口

- **Skill：** `hab-autocode` — 详细的 API 操作指南
- **Command：** `/cmd-autocode` — 交互式代码生成向导

## 能力

1. **创建业务包** — 生成包结构（api/router/service/model 的 enter.go）
2. **生成 CRUD 模块** — 完整的前后端代码（model/api/router/service/前端页面）
3. **预览代码** — 生成前预览所有文件内容
4. **查询数据库** — 基于已有表结构生成代码
5. **添加方法** — 为已有模块添加新 API 方法
6. **回滚** — 撤销已生成的代码

## 前置条件

1. HAB server 已启动运行
2. `server/config.yaml` 中配置了 `autocode.api-key`
3. 数据库已初始化（已执行 initdb）

## 使用场景

| 场景 | 推荐方式 |
|------|---------|
| 快速创建标准 CRUD 模块 | `/cmd-autocode` |
| 需要自定义生成逻辑 | 直接调用 `hab-autocode` skill 中的 API |
| 基于已有数据库表生成 | `/cmd-autocode` → 选择"从表生成" |
| 为已有模块添加方法 | `hab-autocode` skill → 流程四 |

## 限制

- AutoCode 生成的是标准 CRUD 代码，复杂业务逻辑需手动补充
- 前端代码生成到 `web/`（Vue 3），不支持生成 `client/`（React）代码
- 生成前建议先预览，确认文件列表和内容符合预期
- 回滚操作不可逆（但文件移到 rm_file/ 目录，可手动恢复）

## Tech Lead 集成工作流

### 何时必须使用 AutoCode

Tech Lead 在技术评审阶段（`/review-tech`）必须执行以下检测：

**检测条件（两者同时满足 → 强制使用 AutoCode）：**
1. **项目有后台管理页面** — `web/src/view/` 或 `web/src/api/` 存在，或 config.yaml 有 `autocode:` 配置段
2. **任务涉及创建数据库表** — backend/design.md 中有新数据模型定义（含表名、字段、需要 GORM AutoMigrate 建表）

**标记规则：**
- 标准 CRUD 模块（增删改查 + 分页列表） → 在 backend/tasks.md 加 `[autocode]` 前缀，AutoCode 同时生成后端代码 + 前端管理页面
- 复杂业务逻辑（登录、审批、第三方对接等） → 不标 `[autocode]`，开发者手写
- 标准 CRUD + 自定义方法 → `[autocode]` 生成基础 + addFunc 添加方法

**执行时机：**
1. `/review-tech` 阶段 → Tech Lead 检测并标记 `[autocode]` 任务
2. `/dev-tech` 或 `/unify-dev` 阶段 → Step 2.5 自动扫描并执行 AutoCode 预生成
3. Backend 开发者在生成代码基础上补充自定义业务逻辑

| 场景 | 推荐方式 |
|------|---------|
| Tech Lead 评审标注 CRUD 模块 | 在 backend/tasks.md 加 `[autocode]` 前缀 |
| 开发阶段预生成（自动） | `/dev-tech` 或 `/unify-dev` 的 Step 2.5 自动执行 |
| 手动预生成 | `/cmd-autocode` 或直接调用 hab-autocode API |
| 独立快速原型 | `/cmd-autocode` |

## 快速开始

```bash
# 1. 确保 server 运行中
cd server && go run . &

# 2. 使用交互式向导
/cmd-autocode

# 3. 或直接使用脚本
.claude/skills/hab-autocode/scripts/autocode.sh packages
.claude/skills/hab-autocode/scripts/autocode.sh get-db
```
