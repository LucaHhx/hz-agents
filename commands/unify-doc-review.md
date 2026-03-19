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

**向用户提示**: `我现在切换为 **评审主导者**，启动评审团队并行工作：`

你不再扮演任何具体角色，而是作为**评审主导者**，同时启动 PM、Tech Lead、UI 设计师作为后台 agent 并行评审。

#### 3.1 启动评审团队（全部后台 Agent 并行）

同时启动以下 agent:

**PM agent:**
```
Agent tool:
  subagent_type: "hz-pm"
  name: "pm-reviewer"
  run_in_background: true
  prompt: |
    你是文档评审团队的产品经理。

    先读取 create-docs skill 的 SKILL.md (.claude/skills/create-docs/SKILL.md) 了解文档规范。
    再读取 references/update-guide.md 了解更新规则。

    评审 docs/ 下的 L1 + L2 业务文档:
    - project.md 业务信息完整性
    - 各需求 plan.md: 目标、场景、验收标准
    - 各需求 tasks.md: 功能任务清晰度
    - log.md 变更记录

    发现问题直接修复。完成后输出评审摘要。

    [如有需求参数: 只评审需求: $ARGUMENTS]
```

**Tech Lead agent:**
```
Agent tool:
  subagent_type: "hz-tech-lead"
  name: "tech-lead"
  run_in_background: true
  prompt: |
    你是文档评审团队的 Tech Lead。

    先读取 create-docs skill 的 SKILL.md (.claude/skills/create-docs/SKILL.md) 了解文档规范。
    再读取 references/update-guide.md 了解更新规则。

    然后按照你的 agent 职责，评审 docs/ 下的 L3 技术文档:
    - 读取 tech/design.md 的角色规划表，确认活跃角色
    - 只检查活跃角色的目录和文件
    - 如果活跃角色的目录不存在，使用 docs.py role <req> <role> 创建
    - design.md: 技术方案、架构、接口完整性
    - tasks.md: 技术任务具体可执行性
    - 业务需求是否有对应技术方案
    - **AutoCode 标记检查**: 如果项目有后台管理页面（web/src/view/ 存在）且 backend/design.md 中有新数据模型需要建表，确认 tech/tasks.md 中对应的标准 CRUD 任务已加 [autocode] 前缀。缺失则补充标记。

    发现问题直接修复。完成后输出评审摘要。

    [如有需求参数: 只评审需求: $ARGUMENTS]
```

**UI Designer agent（仅当 ui 角色活跃时启动）:**
```
Agent tool:
  subagent_type: "hz-ui"
  name: "ui-designer"
  run_in_background: true
  prompt: |
    你是文档评审团队的 UI 设计师。

    先读取 create-docs skill 的 SKILL.md (.claude/skills/create-docs/SKILL.md) 了解文档规范和 CLI 用法。

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
    5. 完成后输出设计成果摘要

    [如有需求参数: 只处理需求: $ARGUMENTS]
```

#### 3.2 三端交叉对齐

等待所有 agent 完成后，你作为评审主导者执行对齐:

1. **汇总三端评审结果**: 收集 PM 评审报告 + Tech Lead 评审报告 + UI 设计师报告
2. **检查一致性**（根据活跃角色动态调整）：
   - **业务 ↔ 技术**: 每个业务场景是否有对应技术实现路径
   - **业务 ↔ UI** (如有 ui): 设计稿是否覆盖所有用户场景
   - **技术 ↔ UI** (如有 ui): 前端技术方案与设计系统是否对齐（组件命名、样式变量、资源引用），Resources/ 资源是否满足前端实现需求
3. **发现分歧或不一致 → 用 brainstorming 分析分歧原因和可选方案，再用 AskUserQuestion 让用户选择或输入想法，以用户决策为准修改文档**
4. 验证 UI 资源完整性（如有 ui 角色）: Resources/ 非空、assets-manifest.md 自检通过、merge.html 无外部 URL
5. 按决策结果修改对应文档，在 log.md 记录用户决策

#### 3.3 用户确认与团队关闭

在对齐完成后，**必须与用户沟通确认**，不可直接关闭评审团队:

1. **汇报完整方案**: 向用户呈现三端对齐后的完整方案摘要（业务需求、技术方案、UI 设计），让用户全面了解当前状态
2. **询问是否有补充**: 使用 AskUserQuestion 询问用户是否有需要补充或修改的内容
   - 如果用户有补充 → 通过 SendMessage 将补充内容发送给对应的 agent 处理，然后重新对齐
   - 如果用户无补充 → 继续下一步
3. **确认关闭评审团队**: 使用 AskUserQuestion 确认是否关闭评审团队
   - 用户确认后，评审团队结束工作，进入 Phase 4

**绝不自动关闭评审团队**，必须等待用户明确确认。

### 4. 汇总评审报告

汇总评审报告:
- 文档结构状态
- PM 评审结果
- Tech Lead 评审结果
- UI 设计产出状态
- 三端对齐结果:
  - 业务 ↔ 技术: [对齐状态，解决的分歧]
  - 业务 ↔ UI: [对齐状态]（如有 ui 角色）
  - 技术 ↔ UI: [对齐状态]（如有 ui 角色）
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
  2. /unify-dev $REQ_NAME         — 直接进入全团队开发（推荐下一步）
  3. /dev-tech $REQ_NAME          — Tech Lead 带队精简开发
```

## Important Notes

- **角色切换机制**: 你在整个流程中直接扮演 PM 和 Tech Lead 两个角色，不启动对应的 agent。每次切换角色时必须:
  1. **重新读取对应角色定义文件**（即使之前已读取过，也必须重新加载，确保角色职责清晰）
  2. **明确告知用户角色切换**，格式: `我现在切换为 **[角色名]**，和您沟通[具体事项]：`
  - 进入 Step 2.1: 读取 `hz-pm.md` → `我现在扮演 **产品经理(PM)**，和您沟通业务需求：`
  - 进入 Step 2.2: 读取 `hz-tech-lead.md` → `我现在切换为 **Tech Lead(开发总管)**，和您沟通技术选型：`
  - 进入 Phase 3: 不扮演具体角色 → `我现在切换为 **评审主导者**，启动评审团队并行工作：`
- **Phase 2 (初始化) 是顺序执行的**: 你先扮演 PM 与用户确定业务需求 → 再切换为 Tech Lead 与用户确定技术方案 → 最后进入评审
- **Phase 3 (评审) 是全并行的**: PM、Tech Lead、UI 设计师全部作为后台 agent 并行工作，你作为评审主导者协调和对齐
- **用户参与是核心**: 用 brainstorming 探索和分析，用 AskUserQuestion 让用户做决策（提供选项或允许自由输入），每次只问一个问题，避免信息过载
- **三端对齐由评审主导者执行**: 收集各端结果后，用 brainstorming 分析分歧，用 AskUserQuestion 向用户展示可选方案让用户做决策
- **评审团队关闭须用户确认**: 对齐完成后必须向用户汇报完整方案、询问是否有补充、确认关闭团队后才进入下一步
- **鼓励直接修复** 而非仅列出问题
- **DO NOT** 修改代码文件，仅涉及 docs/
- **DO NOT** 创建新需求，仅评审已有文档（Phase 3 阶段）
- Agent 自身已有完整的角色职责定义，prompt 只需指明评审任务和 skill 规范位置
- UI 设计师在此阶段完成所有设计稿产出，确保进入开发阶段前设计方案已就绪
