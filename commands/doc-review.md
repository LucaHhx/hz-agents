---
description: 启动 PM + Tech Lead + UI 设计师团队协作完善文档设计并检查文档状态
argument-hint: [需求名称]
---

# 文档协作评审

启动 PM、Tech Lead 和 UI 设计师团队，协作评审文档完整性和一致性，完善 UI 设计。

## Implementation Steps

### 1. 扫描文档结构

使用 Glob 扫描 `docs/` 目录，确认存在且有内容。

If 提供了 `$ARGUMENTS` → 只检查该需求目录是否存在。

If `docs/` 不存在或为空 → 进入 **Phase 2: 用户驱动的文档初始化**。
If `docs/` 已存在且有需求目录 → 跳到 **Phase 3: 团队评审**。

### 2. 用户驱动的文档初始化 (docs/ 不存在时)

文档初始化不能自动完成——需要用户参与关键决策。分三步进行:

#### Step 2.1 — PM 与用户协作确定业务需求

使用 Task 工具启动 hz-pm agent，让 PM 通过 brainstorming skill 与用户交互:

```
Task tool:
  subagent_type: "hz-pm"
  prompt: |
    先读取 create-docs skill 的 SKILL.md (.claude/skills/create-docs/SKILL.md) 了解文档规范和 CLI 用法。

    项目中尚未初始化 docs/ 目录。你需要和用户协作完成文档初始化，而不是自动生成。

    ## 你的工作流程:

    1. **查找项目上下文**: 检查根目录是否有 PRD 文件 (*PRD*.md)、README、或其他说明文件
    2. **使用 brainstorming skill 与用户协作**:
       - 如果有 PRD，先读取内容，然后和用户确认:
         - 核心功能优先级（哪些是 MVP 必须的？）
         - 目标用户和使用场景是否准确
         - MVP 范围边界（什么不做？）
         - 是否有遗漏或需要调整的需求
       - 如果没有 PRD，通过 brainstorming 从零开始了解:
         - 项目要解决什么问题？
         - 目标用户是谁？
         - 核心功能有哪些？
         - MVP 范围是什么？
    3. **用户确认后，执行文档初始化**:
       - 运行 `python .claude/skills/create-docs/scripts/docs.py init` 初始化 docs/ 基础结构
       - 根据用户确认的内容完善 docs/project.md
       - 使用 `docs.py req <name>` 创建需求目录
       - 为每个需求填写 plan.md（目标、场景、验收标准）和 tasks.md（功能任务）

    **关键: 所有主要决策（功能范围、优先级、验收标准）必须由用户确认，不要自行假设。**
```

等待 PM 完成后，确认 docs/ 结构已创建，然后进入 Step 2.2。

#### Step 2.2 — Tech Lead 与用户协作确定技术选型

使用 Task 工具启动 hz-tech-lead agent，让 Tech Lead 通过 brainstorming skill 与用户讨论技术决策:

```
Task tool:
  subagent_type: "hz-tech-lead"
  prompt: |
    先读取 create-docs skill 的 SKILL.md (.claude/skills/create-docs/SKILL.md) 了解文档规范。
    再读取 docs/ 下已有的业务文档（project.md、各需求的 plan.md 和 tasks.md），了解业务需求。

    PM 已完成业务文档初始化。现在你需要和用户协作确定技术方案。

    ## 你的工作流程:

    1. **理解业务需求**: 阅读 docs/ 下所有 L2 文档
    2. **使用 brainstorming skill 与用户讨论关键技术决策**:
       - 项目整体架构方案（提出 2-3 个方案，说明各自的优缺点，给出推荐）
       - 基础技术选型确认（默认栈是否适合此项目，是否需要调整）
       - 关键技术问题（如: 数据同步策略、认证方案、离线支持等，根据具体需求而定）
       - 部署方式（桌面/移动/Web 优先级）
    3. **用户确认后，创建技术文档**:
       - 使用 `docs.py role <req> backend/frontend/qa/ui` 创建角色目录
       - 编写 backend/design.md 和 frontend/design.md 的初始技术方案
       - 在 log.md 记录技术决策及理由

    **关键: 技术选型不要直接拍板，提出选项让用户选择。特别是涉及架构级别的决策。**
```

等待 Tech Lead 完成后，继续进入 Phase 3。

### 3. 团队评审

#### 3.1 创建团队并分配任务

```
TeamCreate: team_name: "doc-review"
```

创建 4 个任务:

**任务 1 — PM 文档评审** (owner: pm):
- 评审 L1 + L2 业务文档完整性和质量
- 发现问题直接修复或记录建议
- 完成后发送结果给 tech-lead 和 ui-designer

**任务 2 — Tech Lead 文档评审** (owner: tech-lead):
- 评审 L3 技术文档完整性和质量
- 确保 ui 角色目录已创建（如未创建则创建）
- 发现问题直接修复或记录建议
- 完成后发送结果给 pm 和 ui-designer

**任务 3 — UI 设计产出** (owner: ui-designer, blockedBy: 任务1):
- 阅读 plan.md 用户场景，创建 UI 设计稿
- 产出: merge.html（响应式效果图，覆盖所有断点）
- 编写 design.md 设计系统文档和 Introduction.md 设计说明
- 按需产出 Resources/ 资源
- 完成后发送结果给 tech-lead 和 pm

**任务 4 — 交叉评审与对齐** (pm + tech-lead + ui-designer 协作):
- 确认需求、技术方案、UI 设计三方对齐
- 解决不一致问题

#### 3.2 启动团队成员

并行启动三个 agent，使用 Task 工具:

**PM agent:**
```
Task tool:
  subagent_type: "hz-pm"
  team_name: "doc-review"
  name: "pm"
  prompt: |
    你是文档评审团队的 PM。

    先读取 create-docs skill 的 SKILL.md (.claude/skills/create-docs/SKILL.md) 了解文档规范。
    再读取 references/update-guide.md 了解更新规则。

    然后按照你的 agent 职责，评审 docs/ 下的 L1 + L2 业务文档:
    - project.md 业务信息完整性
    - 各需求 plan.md: 目标、场景、验收标准
    - 各需求 tasks.md: 功能任务清晰度
    - log.md 变更记录

    发现问题直接修复。完成后将结果发送给 tech-lead 和 ui-designer。
    [如有需求参数: 只评审需求: $ARGUMENTS]
```

**Tech Lead agent:**
```
Task tool:
  subagent_type: "hz-tech-lead"
  team_name: "doc-review"
  name: "tech-lead"
  prompt: |
    你是文档评审团队的 Tech Lead。

    先读取 create-docs skill 的 SKILL.md (.claude/skills/create-docs/SKILL.md) 了解文档规范。
    再读取 references/update-guide.md 了解更新规则。

    然后按照你的 agent 职责，评审 docs/ 下的 L3 技术文档:
    - 角色目录是否已创建（包括 backend, frontend, qa, ui）
    - 如果 ui 角色目录不存在，使用 docs.py role <req> ui 创建
    - design.md: 技术方案、架构、接口完整性
    - tasks.md: 技术任务具体可执行性
    - 业务需求是否有对应技术方案

    发现问题直接修复。完成后将结果发送给 pm 和 ui-designer。
    [如有需求参数: 只评审需求: $ARGUMENTS]
```

**UI Designer agent:**
```
Task tool:
  subagent_type: "hz-ui"
  team_name: "doc-review"
  name: "ui-designer"
  prompt: |
    你是文档评审团队的 UI 设计师。

    先读取 create-docs skill 的 SKILL.md (.claude/skills/create-docs/SKILL.md) 了解文档规范和 CLI 用法。

    你的工作流程:
    1. 等待 PM 完成文档评审（确保 plan.md 内容稳定）
    2. 阅读 docs/ 下的需求 plan.md，了解用户场景和验收标准
    3. 按照你的 agent 职责，为每个需求创建 UI 设计:
       - 使用 ui-ux-pro-max skill 生成设计系统
       - 制作 merge.html 响应式效果图（覆盖所有断点）
       - 编写 design.md 设计系统文档
       - 编写 Introduction.md 给前端的设计说明
       - 按需产出 Resources/ 资源
    4. 使用 docs.py CLI 更新 ui/tasks.md 任务状态
    5. 完成后将设计成果发送给 tech-lead 和 pm

    [如有需求参数: 只处理需求: $ARGUMENTS]
```

### 4. 等待完成并汇总

等待三个 agent 完成后，汇总评审报告:
- 文档结构状态
- PM 评审结果
- Tech Lead 评审结果
- UI 设计产出状态
- 交叉评审对齐情况
- 改进建议

### 5. 清理团队

发送 shutdown_request → TeamDelete

## Important Notes

- **Phase 2 (初始化) 是顺序执行的**: 先 PM 与用户确定业务需求 → 再 Tech Lead 与用户确定技术方案 → 最后进入团队评审
- **Phase 3 (评审) 是并行执行的**: 三个 agent 同时启动（UI 设计师等 PM 评审完成后再开始设计）
- **用户参与是核心**: 初始化阶段的所有关键决策（功能范围、优先级、技术选型）都通过 brainstorming 由用户确认
- **鼓励直接修复** 而非仅列出问题
- **DO NOT** 修改代码文件，仅涉及 docs/
- **DO NOT** 创建新需求，仅评审已有文档（Phase 3 阶段）
- Agent 自身已有完整的角色职责定义，prompt 只需指明评审任务和 skill 规范位置
- UI 设计师在此阶段完成所有设计稿产出，确保进入开发阶段前设计方案已就绪
