# 模块 03 — 开发迭代流程

## 概述

标准开发流程分为**评审类**和**开发类**两大阶段，通过 command 驱动。

## 标准流程

```
需求输入
  │
  ▼
/review-pm          PM 评审/完善业务文档
  │
  ▼
/review-tech        Tech Lead 创建技术方案和任务
  │
  ▼
/review-ui          UI 设计师产出设计稿
  │
  ▼
/dev-tech           Tech Lead 带队前后端开发
  │
  ▼
/review-qa          QA 执行验收测试
  │
  ▼
完成 ✓
```

## 统一入口命令

### /review-all — 文档整体评审

启动 PM + Tech Lead + UI 团队**并行**评审：
- PM 评审业务文档
- Tech Lead 评审技术文档
- UI 设计师产出设计稿
- 三端交叉对齐

适用：项目初期或需要全面评审时。

### /unify-doc-review — 文档协作评审

与 `/review-all` 类似，但额外包含初始化流程（docs/ 不存在时）。

### /unify-dev — 统一开发

启动 Tech Lead + UI + Frontend + Backend + QA **协作开发**：
- Tech Lead 分配和监督任务
- 前后端并行开发
- QA 跟进测试

### /unify-fix — 统一修复

诊断并修复 bug，自动组建修复团队。

## 评审类 vs 开发类

| 类型 | 命令 | 角色 | 产出 |
|------|------|------|------|
| 评审 | /review-pm | PM | plan.md, tasks.md |
| 评审 | /review-tech | Tech Lead | design.md, L3 tasks.md |
| 评审 | /review-ui | UI 设计师 | merge.html, design.md |
| 评审 | /review-qa | QA | 测试报告 |
| 评审 | /review-all | PM+TL+UI | 全面评审 |
| 开发 | /dev-tech | TL+FE+BE | 代码实现 |
| 开发 | /dev-frontend | Frontend | 前端代码 |
| 开发 | /dev-backend | Backend | 后端代码 |
| 开发 | /unify-dev | 全团队 | 完整功能 |
| 修复 | /unify-fix | 按需 | bug 修复 |

## 场景示例

### 场景 1：新项目从零开始

```
/hz-init                    # 初始化项目
/unify-doc-review           # PM + Tech Lead + UI 协作完善文档
/unify-dev 用户系统          # 全团队协作开发第一个需求
```

### 场景 2：新增需求

```
/review-pm                  # PM 创建新需求文档
/review-tech 新需求名        # Tech Lead 做技术方案
/review-ui 新需求名          # UI 出设计稿
/dev-tech 新需求名           # 开发实现
/review-qa 新需求名          # QA 验收
```

### 场景 3：修复 bug

```
/unify-fix 用户无法登录      # 自动诊断并修复
```

### 场景 4：只做前端开发

```
/dev-frontend               # 单独启动前端开发
```
