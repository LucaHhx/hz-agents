---
description: "[统一调度] 启动 PM + Tech Lead + UI 设计师团队协作完善文档设计并检查文档状态"
argument-hint: [需求名称]
---

# 文档协作评审

启动 PM、Tech Lead 和 UI 设计师团队，协作评审文档完整性和一致性，完善 UI 设计。

## Implementation Steps

### 1. 扫描文档结构

使用 Glob 扫描 `docs/` 目录，确认存在且有内容。

If 提供了 `$ARGUMENTS` → 只检查该需求目录是否存在。

判断进入哪个阶段:
1. If `docs/` 不存在或为空 → 进入 **Phase 2: 完整初始化**（PM + Tech Lead 顺序协作）
2. If `docs/` 存在，有需求目录，但 `docs/$REQ/tech/design.md` 不存在 → 进入 **Phase 2.5: Tech Lead 初始化**（PM 文档已就绪，仅需 Tech Lead 创建技术方案）
3. If `docs/` 存在，且 `docs/$REQ/tech/design.md` 已存在 → 跳到 **Phase 3: 团队评审**

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
       - 根据需求分析在 tech/design.md 写入角色规划表（## 角色规划），标注每个角色 ✅/❌
       - 只为活跃角色（✅）使用 `docs.py role <req> <role>` 创建角色目录
       - 为活跃的开发角色编写 design.md 的初始技术方案
       - 在 log.md 记录技术决策及理由

    **关键: 技术选型不要直接拍板，提出选项让用户选择。特别是涉及架构级别的决策。**
```

等待 Tech Lead 完成后，继续进入 Phase 3。

### 2.5. Tech Lead 补充初始化（PM 文档已存在、tech/design.md 缺失时）

docs/ 已有 PM 业务文档（plan.md, tasks.md），但缺少 Tech Lead 技术方案。
直接启动 Step 2.2 的 Tech Lead 初始化流程（与用户 brainstorming 确定技术选型），
跳过 Step 2.1（PM 初始化已完成）。

完成后进入 Phase 3: 团队评审。

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

**任务 3 — UI 设计产出** (owner: ui-designer, blockedBy: 任务1, **仅当 ui 角色活跃时创建**):
- 阅读 plan.md 用户场景，创建 UI 设计稿
- 产出: merge.html（响应式效果图，覆盖所有断点，禁止使用外部 URL 引用本地资源）
- 编写 design.md 设计系统文档和 Introduction.md 设计说明
- **强制交付 Resources/**:
  - `Resources/icons/*.svg` — 设计稿中使用的所有 SVG 图标（必须交付）
  - `Resources/tokens.css` — CSS 变量（必须交付）
  - `Resources/tailwind.config.js` — Tailwind 扩展配置（必须交付）
  - `Resources/assets-manifest.md` — 资源交付清单，自检清单全部通过
- 需人工提供的资源记录到 assets-manifest.md 并在 merge.html 中使用占位方案
- **交付自检**: 10 项检查清单全部通过才可标记完成（见 hz-ui agent 定义）
- 完成后发送结果给 tech-lead 和 pm

**任务 4 — 三端交叉对齐** (pm + tech-lead + ui-designer 协作):
- 汇总各端独立评审发现的问题
- 检查一致性（根据活跃角色动态调整）：
  - **业务 ↔ 技术**: 每个业务场景是否有对应技术实现路径
  - **业务 ↔ UI** (如有 ui): 设计稿是否覆盖所有用户场景
  - **技术 ↔ UI** (如有 ui): 前端技术方案与设计系统是否对齐（组件命名、样式变量、资源引用），Resources/ 资源是否满足前端实现需求
- **发现分歧或不一致 → 使用 brainstorming skill 与用户讨论，以用户决策为准修改文档**
- Tech Lead 验证 UI 资源完整性: Resources/ 非空、assets-manifest.md 自检通过、merge.html 无外部 URL。不完整则退回 UI 设计师补充
- 按决策结果修改对应文档，在 log.md 记录用户决策

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

    ## 阶段二：三端对齐
    等待收到 tech-lead 和 ui-designer 的评审报告后：
    1. 汇总三端问题，识别不一致之处
    2. 重点关注：
       - 业务场景是否每个都有技术实现路径和 UI 设计覆盖
       - 验收标准是否与技术任务和设计页面匹配
    3. 发现分歧时：使用 brainstorming skill 与用户讨论，清晰呈现各端差异，请用户决策
    4. 按用户决策修改 plan.md 和 tasks.md
    5. 完成后将最终对齐结果发送给 tech-lead 和 ui-designer

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
    - 读取 tech/design.md 的角色规划表，确认活跃角色
    - 只检查活跃角色的目录和文件
    - 如果活跃角色的目录不存在，使用 docs.py role <req> <role> 创建
    - design.md: 技术方案、架构、接口完整性
    - tasks.md: 技术任务具体可执行性
    - 业务需求是否有对应技术方案
    - **AutoCode 标记检查**: 如果项目有后台管理页面（web/src/view/ 存在）且 backend/design.md 中有新数据模型需要建表，确认 tech/tasks.md 中对应的标准 CRUD 任务已加 [autocode] 前缀。缺失则补充标记。

    发现问题直接修复。完成后将结果发送给 pm 和 ui-designer。

    ## 阶段二：三端对齐
    等待收到 pm 和 ui-designer 的评审报告后：
    1. 汇总技术视角的不一致问题
    2. 重点关注：
       - 前端技术方案是否与 UI 设计系统对齐（组件命名、样式变量、资源引用）
       - UI Resources/ 中提供的资源是否满足前端实现需求
       - 后端接口设计是否满足所有业务场景
    3. 发现分歧时：使用 brainstorming skill 与用户讨论，提出技术方案选项，请用户决策
    4. 按用户决策修改 backend/design.md、frontend/design.md 和对应 tasks.md
    5. 完成后将最终对齐结果发送给 pm 和 ui-designer

    [如有需求参数: 只评审需求: $ARGUMENTS]
```

**UI Designer agent（仅当 ui 角色活跃时启动）:**
```
Task tool:
  subagent_type: "hz-ui"
  team_name: "doc-review"
  name: "ui-designer"
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
    1. 等待 PM 完成文档评审（确保 plan.md 内容稳定）
    2. 阅读 docs/ 下的需求 plan.md，了解用户场景和验收标准
    3. 按照你的 agent 职责，为每个需求创建 UI 设计:
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
    4. 完成前对照 10 项交付检查清单逐项自检（见你的 agent 定义）
    5. 使用 docs.py CLI 更新 ui/tasks.md 任务状态
    6. 完成后将设计成果发送给 tech-lead 和 pm

    ## 阶段二：三端对齐
    等待收到 pm 和 tech-lead 的评审报告后：
    1. 汇总设计视角的不一致问题
    2. 重点关注：
       - 设计稿是否覆盖所有业务用户场景（对照 plan.md）
       - 设计系统是否与前端 design.md 的组件方案一致
       - Resources/ 资源是否满足前端实现需求
    3. 发现分歧时：使用 brainstorming skill 与用户讨论，展示设计方案选项，请用户决策
    4. 按用户决策更新 merge.html、design.md、Resources/ 等设计文档
    5. 完成后将最终对齐结果发送给 tech-lead 和 pm

    [如有需求参数: 只处理需求: $ARGUMENTS]
```

### 4. 等待完成并汇总

等待三个 agent 完成两个阶段（独立评审 + 三端对齐）后，汇总评审报告:
- 文档结构状态
- PM 评审结果
- Tech Lead 评审结果
- UI 设计产出状态
- 三端对齐结果:
  - 业务 ↔ 技术: [对齐状态，解决的分歧]
  - 业务 ↔ UI: [对齐状态]（如有 ui 角色）
  - 技术 ↔ UI: [对齐状态]（如有 ui 角色）
- 用户决策记录: [brainstorming 中用户的关键决策]
- 改进建议

### 5. 清理团队

发送 shutdown_request → TeamDelete

### 6. Git 提交

1. 运行 `git status` + `git diff --stat` 展示变更概要
2. 使用 AskUserQuestion 询问用户是否提交 git:
   - 选项: 提交 / 不提交 / 修改后再提交
3. 用户批准后提交:
   - commit message: `docs($REQ_NAME): doc-review 文档协作评审完成`
   - 如果是初始化（Phase 2），commit message: `docs: doc-review 初始化项目文档`
4. **绝不自动提交**，必须等待用户明确批准

### 7. 后续建议

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

- **Phase 2 (初始化) 是顺序执行的**: 先 PM 与用户确定业务需求 → 再 Tech Lead 与用户确定技术方案 → 最后进入团队评审
- **Phase 3 (评审) 是并行执行的**: 三个 agent 同时启动（UI 设计师等 PM 评审完成后再开始设计）
- **用户参与是核心**: 初始化阶段的所有关键决策（功能范围、优先级、技术选型）都通过 brainstorming 由用户确认
- **鼓励直接修复** 而非仅列出问题
- **DO NOT** 修改代码文件，仅涉及 docs/
- **DO NOT** 创建新需求，仅评审已有文档（Phase 3 阶段）
- Agent 自身已有完整的角色职责定义，prompt 只需指明评审任务和 skill 规范位置
- UI 设计师在此阶段完成所有设计稿产出，确保进入开发阶段前设计方案已就绪
