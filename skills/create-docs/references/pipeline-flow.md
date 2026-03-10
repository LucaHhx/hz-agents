# 流水线路径图

> 本文件定义完整的流水线路径和每个命令完成后的"下一步建议"。

## 完整流水线路径

```
hz-init (项目初始化)
  ↓
review-pm (PM 创建业务文档)
  ↓
review-tech (Tech Lead 创建技术方案)
  ↓
review-ui (UI 设计师产出设计稿) ←── 仅自定义页面需要
  ↓
review-all (三端文档对齐评审) ←── 可选，推荐
  ↓
cmd-autocode (生成 CRUD 基础代码) ←── 有 [autocode] 任务时
  ↓
unify-dev 或 dev-tech (团队开发)
  ↓
review-qa (QA 验收测试)
  ↓
unify-fix (修复 Bug) ←── 按需循环
  ↓
review-qa (回归测试) ←── 修复后重新验证
```

## 每个命令的下一步建议

### hz-init 完成后
```
下一步建议:
  1. /review-pm                    — PM 完善业务文档
  2. /review-tech                  — Tech Lead 做技术方案
  3. /unify-doc-review             — 从零开始的完整文档评审
```

### review-pm / unify-doc-review 完成后
```
下一步建议:
  1. /review-tech {REQ_NAME}       — Tech Lead 创建技术方案
  2. /review-all {REQ_NAME}        — 文档整体评审（如已有技术方案）
```

### review-tech 完成后
```
下一步建议:
  1. /review-ui {REQ_NAME}         — UI 设计师产出设计稿（自定义页面）
  2. /cmd-autocode                 — 生成 CRUD 模块代码（如有 [autocode] 任务）
  3. /review-all {REQ_NAME}        — 三端文档对齐评审
  4. /unify-dev {REQ_NAME}         — 直接进入开发（如文档已充分）
```

### review-ui 完成后
```
下一步建议:
  1. /review-all {REQ_NAME}        — 三端文档对齐评审
  2. /unify-dev {REQ_NAME}         — 直接进入开发
```

### review-all 完成后
```
下一步建议:
  1. /cmd-autocode                 — 生成 CRUD 模块代码（如有 [autocode] 任务）
  2. /unify-dev {REQ_NAME}         — 启动全团队开发
  3. /dev-tech {REQ_NAME}          — Tech Lead 带队精简开发
```

### cmd-autocode 完成后
```
下一步建议:
  1. /unify-dev {REQ_NAME}         — 启动全团队开发（含 QA）
  2. /dev-tech {REQ_NAME}          — Tech Lead 带队开发（无 QA）
```

### unify-dev / dev-tech 完成后
```
下一步建议:
  1. /review-qa {REQ_NAME}         — QA 验收测试
  2. git commit                    — 提交开发成果
```

### review-qa 完成后
```
下一步建议 (有 Bug 时):
  1. /unify-fix <问题描述>          — 修复发现的 Bug
  2. /review-qa {REQ_NAME}         — 修复后回归测试

下一步建议 (全部通过):
  1. git tag / release             — 发布版本
  2. 开始下一个需求                  — /review-pm
```

### unify-fix 完成后
```
下一步建议:
  1. /review-qa {REQ_NAME}         — 回归测试验证修复
```

## UI 设计范围判断

```
UI 设计范围:
  - AutoCode 标准 CRUD 页面        → 不需要 UI 设计（走 /cmd-autocode 生成前端模板）
  - 自定义页面/功能增强             → 需要 UI 设计（走 /review-ui 产出 merge.html）
  - CRUD 页面二次定制               → 需要 UI 设计（只设计定制部分）

merge.html 产出策略:
  - 当前框架默认 server + web（后台管理系统），merge.html 针对 web 端
  - 如果有 client 端，产出 merge-client.html 单独覆盖客户端设计
  - Tech Lead 在 review-tech 阶段标注哪些页面需要 UI 设计
```
