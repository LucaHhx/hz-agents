---
description: "[统一调度] PM 主导文档协作评审，协调 Tech Lead + UI 设计师完善文档设计"
argument-hint: [需求名称]
---

# 文档协作评审

你在本命令中直接扮演 **PM（产品经理）** 角色，与用户面对面沟通。Tech Lead 和 UI 设计师通过 Agent 工具在后台协作。

## 前置准备

先读取以下文件了解规范:
1. `.claude/skills/create-docs/SKILL.md` — 文档规范和 CLI 用法
2. `.claude/skills/create-docs/references/update-guide.md` — 更新规则

> 注意: 角色定义文件（hz-pm.md、hz-tech-lead.md）不在此处加载，而是在切换到对应角色时按需加载。

## Implementation Steps

### 1. 扫描文档结构

使用 Glob 扫描 `docs/` 目录，确认存在且有内容。

If 提供了 `$ARGUMENTS` → 只检查该需求目录是否存在。

判断进入哪个阶段:
1. If `docs/` 不存在或为空 → 进入 **Phase 2: 完整初始化**（你直接与用户协作 + Tech Lead 后台协作）
2. If `docs/` 存在，有需求目录，但 `docs/$REQ/tech/design.md` 不存在 → 进入 **Phase 2.5: Tech Lead 初始化**（PM 文档已就绪，仅需 Tech Lead 创建技术方案）
3. If `docs/` 存在，且 `docs/$REQ/tech/design.md` 已存在 → 跳到 **Phase 3: 团队评审**

### 2. 用户驱动的文档初始化 (docs/ 不存在时)

文档初始化不能自动完成——需要用户参与关键决策。分两步进行:

#### Step 2.1 — 扮演 PM 角色，与用户协作确定业务需求

切换前准备:
1. 读取 `.claude/agents/hz-pm.md` — 加载 PM 角色职责定义

**向用户提示角色切换**: `我现在扮演 **产品经理(PM)**，和您沟通业务需求：`

**你就是 PM，直接和用户对话，不要启动任何 agent。按照 `hz-pm.md` 中定义的角色职责执行。**

工作流程:

1. **查找项目上下文**: 检查根目录是否有 PRD 文件 (*PRD*.md)、README、或其他说明文件
2. **使用 brainstorming skill 探索需求，结合 AskUserQuestion 确认决策**:
   - 如果有 PRD，先读取内容，用 brainstorming 分析后，通过 AskUserQuestion 逐项确认:
     - 核心功能优先级（哪些是 MVP 必须的？）
     - 目标用户和使用场景是否准确
     - MVP 范围边界（什么不做？）
   - 如果没有 PRD，用 brainstorming 引导探索，通过 AskUserQuestion 收集用户输入:
     - "项目要解决什么问题？目标用户是谁？"（允许自由输入）
     - "核心功能有哪些？"（允许自由输入）
     - 整理为方案后，用 AskUserQuestion 最终确认: "确认 / 需要调整"
3. **用户确认后，执行文档初始化**:
   - 运行 `python .claude/skills/create-docs/scripts/docs.py init` 初始化 docs/ 基础结构
   - 根据用户确认的内容完善 docs/project.md
   - 使用 `docs.py req <name>` 创建需求目录
   - 为每个需求填写 plan.md（目标、场景、验收标准）和 tasks.md（功能任务）

**关键: 所有主要决策（功能范围、优先级、验收标准）必须由用户确认，不要自行假设。**
**PM 职责边界: 只定义做什么(WHAT)，不涉及怎么做(HOW)。技术选型、架构、API 设计留给 Tech Lead。**

确认 docs/ 结构已创建后，进入 Step 2.2。

#### Step 2.2 — 切换为 Tech Lead 角色，与用户协作确定技术选型

**现在你切换为 Tech Lead 角色，直接和用户对话，不要启动任何 agent。**

切换前准备（每次切换都必须重新读取，不可跳过）:
1. 读取 `.claude/agents/hz-tech-lead.md` — 重新加载 Tech Lead 角色职责定义
2. 读取 docs/ 下已有的业务文档（project.md、各需求的 plan.md 和 tasks.md），了解业务需求

工作流程:

1. **理解业务需求**: 阅读 docs/ 下所有 L2 文档
2. **使用 brainstorming skill 探索技术方案，结合 AskUserQuestion 确认决策**:
   - 用 brainstorming 分析后提出 2-3 个架构方案（含优缺点和推荐），用 AskUserQuestion 让用户选择
   - 基础技术选型确认（默认栈是否适合此项目）
   - 关键技术问题（逐个确认，每次一个问题，提供选项或允许自由输入）
   - 部署方式（桌面/移动/Web 优先级）
3. **用户确认后，创建技术文档**:
   - 根据需求分析在 tech/design.md 写入角色规划表（## 角色规划），标注每个角色 ✅/❌
   - 只为活跃角色（✅）使用 `docs.py role <req> <role>` 创建角色目录
   - 为活跃的开发角色编写 design.md 的初始技术方案
   - 在 log.md 记录技术决策及理由

**关键: 用 brainstorming 探索方案，用 AskUserQuestion 提出选项让用户选择。每次只问一个问题，避免信息过载。**

Tech Lead 工作完成后，继续进入 Phase 3。

### 2.5. Tech Lead 补充初始化（PM 文档已存在、tech/design.md 缺失时）

docs/ 已有 PM 业务文档（plan.md, tasks.md），但缺少 Tech Lead 技术方案。

**直接切换为 Tech Lead 角色**，按 Step 2.2 的流程与用户协作确定技术选型（brainstorming + AskUserQuestion），
跳过 Step 2.1（PM 初始化已完成）。

完成后进入 Phase 3: 团队评审。

### 3. 团队评审

**向用户提示**: `我现在切换为 **评审主导者**，创建评审团队：`

你不再扮演任何具体角色，而是作为**评审团队的 Team Lead**，使用 Agent Teams 创建一个可互相沟通的评审团队。

#### 3.1 创建评审团队

**Step 1 — 创建团队:**
```
TeamCreate:
  team_name: "doc-review"
  description: "文档协作评审团队"
```

**Step 2 — 创建评审任务:**

根据 tech/design.md 角色规划表中的活跃角色，使用 TaskCreate 创建评审任务:

| 任务 | Owner | 说明 |
|------|-------|------|
| PM 评审业务文档 | pm | 评审 L1+L2 业务文档，发现问题直接修复 |
| Tech Lead 评审技术文档 | tech-lead | 评审 L3 技术文档，检查 AutoCode 标记 |
| UI 评审与设计产出 | ui-designer | 产出设计稿和资源（仅 ui 角色活跃时创建） |
| 前端文档评审 | frontend | 评审前端文档，问题发给 tech-lead 或 ui-designer（仅 frontend 角色活跃时创建） |
| 后端文档评审 | backend | 评审后端文档，问题发给 tech-lead（仅 backend 角色活跃时创建） |
| QA 文档评审 | qa | 评审验收标准和测试覆盖，问题发给 tech-lead 或 pm（仅 qa 角色活跃时创建） |
| 多端交叉对齐 | team-lead | 等待所有评审完成后，汇总对齐（blocked by 上述所有任务） |

**Step 3 — 启动团队成员:**

使用 Agent 工具为每个活跃角色启动 teammate，加入 `doc-review` 团队:

> 所有 teammate 共享以下团队沟通规则（写入每个 teammate 的 prompt 中）:

```
## 团队沟通规则
你是 doc-review 评审团队的成员。团队成员之间可以通过 SendMessage 直接沟通。
- 读取 ~/.claude/teams/doc-review/config.json 了解团队成员列表
- 评审中发现不明确或有疑问的地方，**直接 SendMessage 给对应角色**而不是只汇报给 team lead
- 收到其他成员的问题后，及时回复并修改文档
- 完成评审后，通过 TaskUpdate 标记任务完成
- 问题解决后在 log.md 记录决策

## 沟通路由
- 技术方案问题 → SendMessage 给 `tech-lead`
- 业务需求问题 → SendMessage 给 `pm`
- 设计相关问题 → SendMessage 给 `ui-designer`
- 前端可直接和 UI 设计师沟通设计细节
- QA 可直接和 PM 沟通验收标准
```

**PM teammate:**
```
Agent tool:
  subagent_type: "hz-pm"
  name: "pm"
  team_name: "doc-review"
  prompt: |
    你是文档评审团队的产品经理。

    先读取 create-docs skill 的 SKILL.md (.claude/skills/create-docs/SKILL.md) 了解文档规范。
    再读取 references/update-guide.md 了解更新规则。

    ## 团队沟通规则
    [插入上述团队沟通规则]

    ## 你的评审任务
    评审 docs/ 下的 L1 + L2 业务文档:
    - project.md 业务信息完整性
    - 各需求 plan.md: 目标、场景、验收标准
    - 各需求 tasks.md: 功能任务清晰度
    - log.md 变更记录

    发现问题直接修复。收到其他成员的业务问题时及时回复。
    完成后通过 TaskUpdate 标记任务完成，向 team lead 汇报评审摘要。

    [如有需求参数: 只评审需求: $ARGUMENTS]
```

**Tech Lead teammate:**
```
Agent tool:
  subagent_type: "hz-tech-lead"
  name: "tech-lead"
  team_name: "doc-review"
  prompt: |
    你是文档评审团队的 Tech Lead。

    先读取 create-docs skill 的 SKILL.md (.claude/skills/create-docs/SKILL.md) 了解文档规范。
    再读取 references/update-guide.md 了解更新规则。

    ## 团队沟通规则
    [插入上述团队沟通规则]

    ## 你的评审任务
    评审 docs/ 下的 L3 技术文档:
    - 读取 tech/design.md 的角色规划表，确认活跃角色
    - 只检查活跃角色的目录和文件
    - 如果活跃角色的目录不存在，使用 docs.py role <req> <role> 创建
    - design.md: 技术方案、架构、接口完整性
    - tasks.md: 技术任务具体可执行性
    - 业务需求是否有对应技术方案
    - **AutoCode 标记检查**: 如果项目有后台管理页面（web/src/view/ 存在）且 backend/design.md 中有新数据模型需要建表，确认 tech/tasks.md 中对应的标准 CRUD 任务已加 [autocode] 前缀。缺失则补充标记。

    发现问题直接修复。收到前端/后端/QA 的技术问题时及时回复并修改文档。
    完成后通过 TaskUpdate 标记任务完成，向 team lead 汇报评审摘要。

    [如有需求参数: 只评审需求: $ARGUMENTS]
```

**UI Designer teammate（仅当 ui 角色活跃时启动）:**
```
Agent tool:
  subagent_type: "hz-ui"
  name: "ui-designer"
  team_name: "doc-review"
  prompt: |
    你是文档评审团队的 UI 设计师。

    先读取 create-docs skill 的 SKILL.md (.claude/skills/create-docs/SKILL.md) 了解文档规范和 CLI 用法。

    ## 团队沟通规则
    [插入上述团队沟通规则]

    ## UI 设计范围
    注意: 并非所有页面都需要 UI 设计。AutoCode 标准 CRUD 页面使用框架默认样式，不需要设计。
    只为自定义页面和需要二次定制的 CRUD 页面产出 merge.html。
    如果项目有 client/ 端，额外产出 merge-client.html 覆盖客户端设计。

    ## 前置判断（必须先执行，在"工作流程"之前）
    1. 读取 docs/$REQ_NAME/tech/design.md 中的角色规划表
    2. 如果 ui 角色标注为 ❌ 或不存在:
       - **停止**，不产出任何设计文件
       - 在 ui/design.md 中只写: "本需求为标准 CRUD，使用框架默认样式，无需 UI 设计。"
       - 标记任务完成，直接结束
    3. 读取 frontend/design.md，检查各页面 UI 设计需求标注
    4. 如果所有页面标注为 "不需要" 或 "AutoCode 默认":
       - 同上处理，直接结束
    5. 只为标注为"需要定制"的页面产出设计

    你的工作流程:
    1. 阅读 docs/ 下的需求 plan.md，了解用户场景和验收标准
    2. 按照你的 agent 职责，为每个需求创建 UI 设计:
       - 使用 ui-ux-pro-max skill 生成设计系统
       - 制作 merge.html 响应式效果图（覆盖所有断点，禁止使用外部 URL 引用本地资源）
       - 编写 design.md 设计系统文档
       - 编写 Introduction.md 给前端的设计说明（包含资源使用指南）
       - **强制交付 Resources/ 资源**:
         - `Resources/icons/*.svg` — 设计稿中使用的所有 SVG 图标
         - `Resources/tokens.css` — 完整的 CSS 变量
         - `Resources/tailwind.config.js` — Tailwind 扩展配置
         - `Resources/assets-manifest.md` — 填写资源交付清单，自检清单全部通过
         - 需人工提供的资源记录到 assets-manifest.md 并提供占位方案
    3. 完成前对照 10 项交付检查清单逐项自检（见你的 agent 定义）
    4. 使用 docs.py CLI 更新 ui/tasks.md 任务状态
    5. 收到前端的设计问题时及时回复
    6. 完成后通过 TaskUpdate 标记任务完成，向 team lead 汇报设计成果摘要

    [如有需求参数: 只处理需求: $ARGUMENTS]
```

**Frontend teammate（仅当 frontend 角色活跃时启动）:**
```
Agent tool:
  subagent_type: "hz-frontend"
  name: "frontend"
  team_name: "doc-review"
  prompt: |
    你是文档评审团队的前端开发。

    先读取 create-docs skill 的 SKILL.md (.claude/skills/create-docs/SKILL.md) 了解文档规范。

    ## 团队沟通规则
    [插入上述团队沟通规则]

    ## 你的评审任务
    分析 docs/ 下与前端相关的所有文档，找出问题、不明确或不理解的地方:

    1. 读取 frontend/design.md — 前端技术方案
    2. 读取 frontend/tasks.md — 前端任务列表
    3. 读取 tech/design.md — 整体技术架构（关注前端相关部分）
    4. 读取 plan.md — 业务需求（关注前端需要实现的交互和页面）
    5. 如有 ui/ 目录，读取 ui/design.md 和 ui/Introduction.md — 设计稿和设计说明

    发现明显错误可直接修复 frontend/ 文档。
    对于不明确的问题，**直接 SendMessage 给对应角色**:
    - 技术方案问题 → SendMessage 给 `tech-lead`
    - 设计相关问题 → SendMessage 给 `ui-designer`
    等待对方回复后确认问题已解决。

    完成后通过 TaskUpdate 标记任务完成，向 team lead 汇报评审摘要。

    [如有需求参数: 只评审需求: $ARGUMENTS]
```

**Backend teammate（仅当 backend 角色活跃时启动）:**
```
Agent tool:
  subagent_type: "hz-backend"
  name: "backend"
  team_name: "doc-review"
  prompt: |
    你是文档评审团队的后端开发。

    先读取 create-docs skill 的 SKILL.md (.claude/skills/create-docs/SKILL.md) 了解文档规范。

    ## 团队沟通规则
    [插入上述团队沟通规则]

    ## 你的评审任务
    分析 docs/ 下与后端相关的所有文档，找出问题、不明确或不理解的地方:

    1. 读取 backend/design.md — 后端技术方案
    2. 读取 backend/tasks.md — 后端任务列表
    3. 读取 tech/design.md — 整体技术架构（关注后端相关部分、API 设计、数据模型）
    4. 读取 plan.md — 业务需求（关注后端需要实现的业务逻辑）

    发现明显错误可直接修复 backend/ 文档。
    对于不明确的问题，**直接 SendMessage 给 `tech-lead`** 并等待回复。

    完成后通过 TaskUpdate 标记任务完成，向 team lead 汇报评审摘要。

    [如有需求参数: 只评审需求: $ARGUMENTS]
```

**QA teammate（仅当 qa 角色活跃时启动）:**
```
Agent tool:
  subagent_type: "hz-qa"
  name: "qa"
  team_name: "doc-review"
  prompt: |
    你是文档评审团队的 QA 测试。

    先读取 create-docs skill 的 SKILL.md (.claude/skills/create-docs/SKILL.md) 了解文档规范。

    ## 团队沟通规则
    [插入上述团队沟通规则]

    ## 你的评审任务
    从测试视角分析 docs/ 下的所有文档，找出问题、不明确或不可测试的地方:

    1. 读取 plan.md — 验收标准是否明确、可测试
    2. 读取 tasks.md — 功能任务是否有对应的测试场景
    3. 读取 tech/design.md — API 接口是否有明确的输入输出定义
    4. 读取各角色 design.md — 边界条件、异常场景是否有说明

    发现明显错误可直接修复 qa/ 文档。
    对于不明确的问题，**直接 SendMessage 给对应角色**:
    - 技术方案问题 → SendMessage 给 `tech-lead`
    - 业务需求问题 → SendMessage 给 `pm`
    等待对方回复后确认问题已解决。

    完成后通过 TaskUpdate 标记任务完成，向 team lead 汇报评审摘要。

    [如有需求参数: 只评审需求: $ARGUMENTS]
```

#### 3.2 团队协作与问题解决

团队启动后，各成员会自主完成以下协作:

1. **各自评审**: 每个成员评审自己负责的文档，发现问题直接修复
2. **互相沟通**: 遇到不明确的问题，成员之间直接 SendMessage 沟通:
   - Frontend ↔ Tech Lead（技术方案问题）
   - Frontend ↔ UI Designer（设计相关问题）
   - Backend ↔ Tech Lead（API 和数据模型问题）
   - QA ↔ Tech Lead（边界条件和错误码问题）
   - QA ↔ PM（验收标准和场景覆盖问题）
3. **问题解决**: 被提问的成员回复并修改文档，提问方确认

你作为 Team Lead，监控团队协作进度（通过 TaskList 查看任务状态），在需要时介入协调。

#### 3.3 多端交叉对齐

等待所有评审任务完成后（通过 TaskList 确认），你作为 Team Lead 执行最终对齐:

1. **汇总全员评审结果**: 从各成员的汇报中收集评审结果和问题解决记录
2. **检查一致性**（根据活跃角色动态调整）：
   - **业务 ↔ 技术**: 每个业务场景是否有对应技术实现路径
   - **业务 ↔ UI** (如有 ui): 设计稿是否覆盖所有用户场景
   - **技术 ↔ UI** (如有 ui): 前端技术方案与设计系统是否对齐（组件命名、样式变量、资源引用），Resources/ 资源是否满足前端实现需求
   - **前端 ↔ 后端**: API 契约是否前后端理解一致
   - **需求 ↔ QA**: 验收标准是否可测试、覆盖完整
3. **发现分歧或不一致 → 用 brainstorming 分析分歧原因和可选方案，再用 AskUserQuestion 让用户选择或输入想法，以用户决策为准修改文档**
4. 验证 UI 资源完整性（如有 ui 角色）: Resources/ 非空、assets-manifest.md 自检通过、merge.html 无外部 URL
5. 按决策结果修改对应文档，在 log.md 记录用户决策

#### 3.4 用户确认与团队关闭

在对齐完成后，**必须与用户沟通确认**，不可直接关闭评审团队:

1. **汇报完整方案**: 向用户呈现多端对齐后的完整方案摘要（业务需求、技术方案、UI 设计、开发团队反馈解决情况），让用户全面了解当前状态
2. **询问是否有补充**: 使用 AskUserQuestion 询问用户是否有需要补充或修改的内容
   - 如果用户有补充 → 通过 SendMessage 将补充内容发送给对应的 teammate 处理，然后重新对齐
   - 如果用户无补充 → 继续下一步
3. **确认关闭评审团队**: 使用 AskUserQuestion 确认是否关闭评审团队
   - 用户确认后:
     1. 向所有 teammate 发送 shutdown 消息: `SendMessage({to: "name", message: {type: "shutdown_request"}})`
     2. 等待所有 teammate 关闭后，调用 `TeamDelete` 清理团队资源
     3. 进入 Phase 4

**绝不自动关闭评审团队**，必须等待用户明确确认。

### 4. 汇总评审报告

汇总评审报告:
- 文档结构状态
- PM 评审结果
- Tech Lead 评审结果
- UI 设计产出状态（如有 ui 角色）
- 开发团队反馈:
  - Frontend 提出的问题及解决结果
  - Backend 提出的问题及解决结果
  - QA 提出的问题及解决结果
- 多端对齐结果:
  - 业务 ↔ 技术: [对齐状态，解决的分歧]
  - 业务 ↔ UI: [对齐状态]（如有 ui 角色）
  - 技术 ↔ UI: [对齐状态]（如有 ui 角色）
  - 前端 ↔ 后端: [API 契约对齐状态]
  - 需求 ↔ QA: [验收标准覆盖状态]
- 用户决策记录: [用户通过 brainstorming + AskUserQuestion 做出的关键决策]
- 改进建议

### 5. Git 提交

1. 运行 `git status` + `git diff --stat` 展示变更概要
2. 使用 AskUserQuestion 询问用户是否提交 git:
   - 选项: 提交 / 不提交 / 修改后再提交
3. 用户批准后提交:
   - commit message: `docs($REQ_NAME): doc-review 文档协作评审完成`
   - 如果是初始化（Phase 2），commit message: `docs: doc-review 初始化项目文档`
4. **绝不自动提交**，必须等待用户明确批准

### 6. 后续建议

运行 pipeline 状态检查:
```bash
python3 .claude/skills/create-docs/scripts/docs.py pipeline $REQ_NAME
```

汇总报告末尾增加后续建议:

```
后续建议:
  1. /cmd-autocode                — 生成 CRUD 模块代码（如有 [autocode] 任务）
  2. /team-dev $REQ_NAME          — 直接进入全团队开发（推荐下一步）
  3. /dev-tech $REQ_NAME          — Tech Lead 带队精简开发
```

## Important Notes

- **角色切换机制**: 你在整个流程中直接扮演 PM 和 Tech Lead 两个角色，不启动对应的 agent。每次切换角色时必须:
  1. **重新读取对应角色定义文件**（即使之前已读取过，也必须重新加载，确保角色职责清晰）
  2. **明确告知用户角色切换**，格式: `我现在切换为 **[角色名]**，和您沟通[具体事项]：`
  - 进入 Step 2.1: 读取 `hz-pm.md` → `我现在扮演 **产品经理(PM)**，和您沟通业务需求：`
  - 进入 Step 2.2: 读取 `hz-tech-lead.md` → `我现在切换为 **Tech Lead(开发总管)**，和您沟通技术选型：`
  - 进入 Phase 3: 不扮演具体角色 → `我现在切换为 **评审主导者**，创建评审团队：`
- **Phase 2 (初始化) 是顺序执行的**: 你先扮演 PM 与用户确定业务需求 → 再切换为 Tech Lead 与用户确定技术方案 → 最后进入评审
- **Phase 3 使用 Agent Teams**: 通过 TeamCreate 创建 `doc-review` 团队，成员之间可以通过 SendMessage 直接沟通（不是 6 个独立 agent），任务通过 TaskCreate/TaskUpdate 协调
- **团队成员自主协作**: 前端直接和 UI 设计师沟通设计问题，QA 直接和 PM 沟通验收标准，后端直接和 Tech Lead 沟通 API 设计。你作为 Team Lead 监控进度和介入协调
- **用户参与是核心**: 用 brainstorming 探索和分析，用 AskUserQuestion 让用户做决策（提供选项或允许自由输入），每次只问一个问题，避免信息过载
- **多端对齐由 Team Lead 执行**: 收集各端结果后，用 brainstorming 分析分歧，用 AskUserQuestion 向用户展示可选方案让用户做决策
- **评审团队关闭须用户确认**: 对齐完成后必须向用户汇报完整方案、询问是否有补充、确认关闭团队后才发送 shutdown 并 TeamDelete
- **鼓励直接修复** 而非仅列出问题
- **DO NOT** 修改代码文件，仅涉及 docs/
- **DO NOT** 创建新需求，仅评审已有文档（Phase 3 阶段）
- Agent 自身已有完整的角色职责定义，prompt 只需指明评审任务、团队沟通规则和 skill 规范位置
- UI 设计师在此阶段完成所有设计稿产出，确保进入开发阶段前设计方案已就绪
