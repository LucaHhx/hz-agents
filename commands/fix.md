---
description: 诊断并修复 bug，自动组建修复团队，记录修复日志到 docs/fixes/
argument-hint: <问题描述>
---

# 智能修复流程

针对 bug / 样式问题 / 兼容性问题等非需求性修复，根据复杂度选择直接修复或组建团队。

## 流程概览

```
1. Explore agent 定位问题 → 判断分类 + 严重程度 + 复杂度
2. 简单问题 → 直接修复 + 记录
   复杂问题 → 组建团队修复 + 记录
3. 输出修复报告（必须包含 docs/fixes/ 记录）
```

## Implementation Steps

### 1. 分析问题并分类

读取用户提供的 `$ARGUMENTS` 问题描述。

**用 Explore agent 快速定位问题**（搜索相关代码、日志、配置），然后判断三个维度：

**问题分类:**

| 分类 | 关键词/特征 |
|------|-------------|
| **前端 UI/样式** | CSS、布局、滚动、响应式、动画、组件显示异常 |
| **后端 API/逻辑** | 接口报错、数据异常、服务崩溃、数据库 |
| **全栈联调** | 前后端不一致、接口对接、数据流问题 |
| **构建/配置** | 编译失败、打包错误、环境配置、连接问题 |
| **性能问题** | 卡顿、慢、内存泄漏 |

**严重程度:**
- **P0**: 应用崩溃、数据丢失、核心功能不可用
- **P1**: 功能异常、UI 严重错位
- **P2**: 样式微调、非核心体验

**复杂度判断 → 决定修复路径:**

| 复杂度 | 判断条件 | 修复路径 |
|--------|----------|----------|
| **简单** | 改动 ≤3 个文件、单端问题、根因明确、配置/构建类 | → 步骤 2A: 直接修复 |
| **复杂** | 改动 >3 个文件、需多端协调、根因需深入排查、涉及架构 | → 步骤 2B: 组建团队 |

### 2A. 直接修复（简单问题）

当 Explore agent 已定位根因且修复方案明确时，**主 agent 直接实施修复**：

1. 读取需要修改的文件
2. 实施代码修改
3. 验证修改正确性（TypeScript 编译、基本逻辑检查）
4. **创建修复记录**（必须）：
   ```
   python3 .claude/skills/create-docs/scripts/docs.py fix "<修复标题>" --severity <P0|P1|P2>
   ```
   然后编辑生成的文件，填写完整内容（现象/根因/方案/变更文件/验收标准）
5. 输出修复报告（→ 步骤 3）

### 2B. 组建团队修复（复杂问题）

**团队组成规则:**

| 分类 | 团队成员 |
|------|----------|
| 前端 UI/样式 | tech-lead + frontend |
| 后端 API/逻辑 | tech-lead + backend |
| 全栈联调 | tech-lead + frontend + backend |
| 性能问题 | tech-lead + 相关端（前端/后端） |

**QA 加入规则:**
- P0 → 强制加入 QA
- 涉及数据/API 变更 → 加入 QA
- 纯样式/配置修复 → 不需要 QA

```
TeamCreate: team_name: "fix-<简短描述>"
```

**创建任务:**

- **任务 1 — 诊断与修复方案**（owner: tech-lead）: 定位根因、制定方案、分配任务
- **任务 2 — 实施修复**（owner: frontend/backend，按需）: 按方案实施代码修改
- **任务 3 — 验证修复**（owner: qa，仅 P0 或涉及数据变更时）: 验证修复效果
- **任务 4 — 记录修复**（owner: tech-lead）: 使用 `docs.py fix` 创建修复记录

**启动团队成员（仅启动需要的角色，并行启动）:**

**Tech Lead（必有）:**
```
Agent tool:
  subagent_type: "hz-tech-lead"
  team_name: "fix-<name>"
  name: "tech-lead"
  prompt: |
    你是修复团队的 Tech Lead，负责协调本次 bug 修复。

    ## 问题描述
    $ARGUMENTS

    ## 你的职责
    1. 从 TaskList 获取你的任务
    2. 定位问题根因（读代码、查日志、分析配置）
    3. 制定修复方案
    4. If 团队中有开发者 → 创建具体修复任务（TaskCreate），分配给对应开发者
    5. If 只有你 → 直接实施修复
    6. 修复完成后，创建修复记录：
       python3 .claude/skills/create-docs/scripts/docs.py fix "<修复标题>" --severity <P0|P1|P2>
       然后编辑生成的文件，填写完整内容（现象/根因/方案/变更文件/验收标准）
    7. If 有 QA → 通知 QA 验证；否则自行验证
    8. 汇总修复结果，标记任务 completed
```

**Frontend（仅前端/全栈问题时启动）:**
```
Agent tool:
  subagent_type: "hz-frontend"
  team_name: "fix-<name>"
  name: "frontend"
  prompt: |
    你是修复团队的前端工程师。

    ## 问题背景
    $ARGUMENTS

    ## 你的职责
    1. 从 TaskList 获取 tech-lead 分配给你的修复任务
    2. 标记任务为 in_progress，按描述实施代码修改
    3. 确保修复不引入新问题
    4. 完成后标记任务 completed，发送消息给 tech-lead
```

**Backend（仅后端/全栈问题时启动）:**
```
Agent tool:
  subagent_type: "hz-backend"
  team_name: "fix-<name>"
  name: "backend"
  prompt: |
    你是修复团队的后端工程师。

    ## 问题背景
    $ARGUMENTS

    ## 你的职责
    1. 从 TaskList 获取 tech-lead 分配给你的修复任务
    2. 标记任务为 in_progress，按描述实施代码修改
    3. 确保修复不破坏现有 API 契约和数据一致性
    4. 完成后标记任务 completed，发送消息给 tech-lead
```

**QA（仅 P0 或涉及数据变更时启动）:**
```
Agent tool:
  subagent_type: "hz-qa"
  team_name: "fix-<name>"
  name: "qa"
  prompt: |
    你是修复团队的 QA 工程师。

    ## 问题背景
    $ARGUMENTS

    ## 你的职责
    1. 等待 tech-lead 通知你开始验证
    2. 验证修复是否解决了原始问题，检查回归问题
    3. 如果涉及 API → 用 curl 测试接口
    4. 如果涉及 UI → 使用 agent-browser 截图验证
    5. 发送验证结果给 tech-lead，标记任务 completed
```

**团队监控：** 等待消息直至所有任务完成，然后发送 shutdown_request → TeamDelete。

### 3. 输出修复报告（两条路径共用）

```
## 修复报告

**严重程度**: P0/P1/P2
**分类**: 前端UI / 后端API / 全栈联调 / 构建配置
**修复方式**: 直接修复 / 团队修复 [参与角色]
**状态**: 已修复 / 部分修复 / 需要进一步处理

### 问题
<简述>

### 根因
<技术分析>

### 修复
<改动摘要>

### 变更文件
- `file1` — 改动说明

### 验证结果
<验证方式和结果>

### 修复记录
已记录到 docs/fixes/<N>-<slug>.md
```

## 路径选择示例

```
/fix 登录页在 iOS 上有滚动条
→ 分类: 前端UI, P1, 简单(1文件) → 直接修复

/fix 记账接口返回 500 错误
→ 分类: 后端API, P0, 复杂(需排查) → 团队: tech-lead + backend + qa

/fix 前端显示金额与后端不一致
→ 分类: 全栈联调, P1, 复杂(多端) → 团队: tech-lead + frontend + backend

/fix iOS 编译失败
→ 分类: 构建配置, P1, 简单(配置) → 直接修复

/fix 用户数据同步后丢失
→ 分类: 后端API, P0, 复杂(数据) → 团队: tech-lead + backend + qa
```

## Important Notes

- **记录必须生成** — 无论直接修复还是团队修复，都必须用 `docs.py fix` 生成 `docs/fixes/` 记录
- **最小开销原则** — 简单问题直接修，复杂问题才组建团队
- **QA 按需参与** — P0 强制，涉及数据变更时加入，其他情况不需要
- 修复要针对根因，不要只修表象
- 如果问题复杂度超出修复范围（需要架构变更），建议改用 `/dev-team`
