---
description: "[统一调度] 启动开发团队（Tech Lead + UI + Frontend + Backend + QA）协作开发需求"
argument-hint: [需求名称]
---

# 启动开发团队

创建 Tech Lead 协调的完整开发团队，按 design.md 技术方案实现需求并验收。

## 流程概览

```
1. Tech Lead 文档检查 ── 不通过 → 暂停，提示用户先完善文档
                          ↓ 通过
2. Tech Lead AutoCode 预生成 ── 扫描 [autocode] 任务 → 生成 CRUD 基础代码 + 编译检查
                          ↓ 完成（或无 [autocode] 任务则跳过）
3. Frontend + Backend 并行开发（Backend 在 autocode 基础上补充自定义逻辑）
                          ↓
4. Tech Lead 代码审查 + UI 视觉审查 ── 不通过 → 回到步骤 3 修复
                          ↓ 通过
5. QA 测试（API 测试 + 浏览器有头模拟测试）
                          ↓
6. 汇总报告
```

## Usage

```bash
# 开发指定需求
/unify-dev 1-login-sync

# 带指令开发
/unify-dev 7 先实现后端API部分
/unify-dev 7 跳过UI审查

# 不指定需求（自动扫描待开发需求）
/unify-dev
```

## Implementation Steps

### 1. 参数解析 → 确定 REQ_NAME + USER_INSTRUCTIONS

读取 `$ARGUMENTS`，拆分为**需求标识**和**用户指令**两部分：

**拆分规则**: 取第一个 token（空格分隔）作为需求标识，剩余部分作为 `USER_INSTRUCTIONS`。

示例:
- `/unify-dev 7 先实现后端API` → 需求标识=`7`, USER_INSTRUCTIONS=`先实现后端API`
- `/unify-dev 7` → 需求标识=`7`, USER_INSTRUCTIONS=空
- `/unify-dev` → 需求标识=空, USER_INSTRUCTIONS=空

**需求匹配**（用需求标识部分）：

- **需求标识为空** → 扫描 `docs/` 下所有需求目录（排除 project.md, tasks.md, CHANGELOG.md, fixes/），读取每个需求的各角色 `tasks.md` 找出有待完成任务的需求，使用 AskUserQuestion 列出让用户选择
- **需求标识非空** → 按顺序尝试:
  1. 精确匹配: `docs/{需求标识}/` 存在？
  2. ID 匹配: `docs/{需求标识}-*/` 存在？
  3. 短名匹配: `docs/*-{需求标识}/` 存在？
  4. 全部失败 → 报错，列出可用需求目录，**停止执行**
- **匹配到多个** → 使用 AskUserQuestion 列出候选让用户选择

将确定的需求名称记为 `REQ_NAME`。

### 2. Tech Lead 文档检查（硬门槛）

使用 Task 工具启动 Tech Lead agent（非团队模式，独立检查）:

```
Task tool:
  subagent_type: "hz-tech-lead"
  prompt: |
    你是开发团队的 Tech Lead，负责检查需求 $REQ_NAME 的技术文档是否完善，可以进入开发阶段。

    先读取 create-docs skill 的 SKILL.md (.claude/skills/create-docs/SKILL.md) 了解文档规范。
    再读取 references/tech-stack.md (.claude/skills/create-docs/references/tech-stack.md) 了解项目技术栈。
    再读取 hz-project skill (.claude/skills/hz-project/SKILL.md) 了解项目全生命周期规范。

    检查以下文件是否存在且内容完整:
    - docs/$REQ_NAME/plan.md — 需求计划和验收标准
    - docs/$REQ_NAME/frontend/design.md — 前端技术方案
    - docs/$REQ_NAME/backend/design.md — 后端技术方案
    - docs/$REQ_NAME/qa/design.md — 测试方案
    - docs/$REQ_NAME/ui/design.md — UI 设计文档（如不存在记为警告，非阻塞）
    - docs/$REQ_NAME/frontend/tasks.md — 前端任务列表
    - docs/$REQ_NAME/backend/tasks.md — 后端任务列表
    - docs/$REQ_NAME/qa/tasks.md — QA 任务列表

    检查内容:
    1. 所有必需文件是否存在且非空
    2. 前后端 API 接口契约是否对齐（请求/响应格式一致）
    3. 技术方案是否完整可执行（不是占位符内容）
    4. 任务拆分是否合理、可执行
    5. **UI 资源完整性检查**（如果 ui/ 目录存在）:
       - merge.html 存在且可预览
       - merge.html 中无外部 URL 引用本地应有的资源（grep 检查 src="http 或 href="http 指向图片/图标的引用）
       - Resources/ 目录非空（不能只有 .gitkeep）
       - Resources/assets-manifest.md 存在且自检清单已填写
       - Resources/icons/ 下有 SVG 文件（如果 merge.html 中使用了图标）
       - 以上任一不满足 → pass: false

    最终输出一个 JSON 格式的检查结果:
    {
      "pass": true/false,
      "issues": ["问题1", "问题2", ...],
      "warnings": ["警告1（非阻塞）", ...],
      "summary": "一句话总结"
    }

    如果有小问题可以直接修复（如格式问题、小的遗漏），修复后视为通过。
    如果有结构性缺失（文件不存在、方案空白、接口未定义、UI 资源未交付），必须标记为不通过。
```

**处理检查结果:**
- If `pass: false` → 输出问题列表，建议运行 `/doc-review $REQ_NAME` 完善文档，**停止执行，不创建团队**
- If `pass: true` → 继续下一步

### 2.5. Tech Lead AutoCode 预生成（文档检查通过后、创建团队前）

**此步骤在创建开发团队之前执行**，由 Tech Lead 独立完成 CRUD 代码生成，为后续开发奠定基础。

使用 Agent 工具启动 Tech Lead agent（非团队模式，独立执行）:

```
Agent tool:
  subagent_type: "hz-tech-lead"
  prompt: |
    你是开发团队的 Tech Lead，负责需求 $REQ_NAME 的 AutoCode 预生成。

    先读取 create-docs skill 的 SKILL.md (.claude/skills/create-docs/SKILL.md) 了解文档规范。
    再读取 hab-autocode skill 的 SKILL.md (.claude/skills/hab-autocode/SKILL.md) 了解 AutoCode API 用法。

    ## 你的任务

    1. 读取 docs/$REQ_NAME/tech/tasks.md，扫描所有标注 [autocode] 的待办任务
    2. 如果没有 [autocode] 任务 → 输出 {"autocode": false, "summary": "无 [autocode] 任务，跳过"} 并结束
    3. 如果有 [autocode] 任务 → 按以下流程执行:

    ### AutoCode 执行流程
    a. 启动 HAB server（必须通过 process-manager）:
       PM=.claude/skills/process-manager/scripts
       $PM/list.sh
       $PM/start.sh backend "go run ." --cwd ./server --env "HAB_CONFIG=config.local.yaml"
       sleep 3
       $PM/search.sh backend "listening on|server run success"
    b. 调用 getPackage 查看已有包，确认目标包是否存在
    c. 如需创建新包，调用 createPackage
    d. 读取 backend/design.md 中的数据模型定义，构建 AutoCode 请求 JSON:
       - structName、tableName、packageName、description、fields
       - 设置 gvaModel: true, autoMigrate: true, autoCreateApiToSql: true, autoCreateMenuToSql: true
    e. 调用 preview 预览生成文件列表
    f. 调用 createTemp 正式生成代码
    g. 执行 `cd server && go build ./...` 编译检查
    h. 如果编译失败，分析并修复问题，循环直到编译通过
    i. 使用 docs.py done 标记 [autocode] 任务为已完成:
       python3 .claude/skills/create-docs/scripts/docs.py done <req> <task-number> --role tech
    j. 使用 docs.py log 记录 AutoCode 生成信息
    k. 清理服务:
       $PM/stop.sh backend
       $PM/clean.sh
    l. 在 backend/design.md 末尾追加「AutoCode 已生成模块」段落（含模块名和文件路径）
    m. 在 frontend/design.md 末尾追加「AutoCode 已生成页面」段落（含模块名和文件路径）

    4. 输出结果:
    {
      "autocode": true,
      "generated_modules": ["模块1", "模块2", ...],
      "generated_files": ["文件路径1", "文件路径2", ...],
      "synced_to": ["backend/design.md", "frontend/design.md"],
      "remaining_tasks": ["非 autocode 的待办任务描述", ...],
      "summary": "一句话总结"
    }
```

**处理 AutoCode 结果:**
- `autocode: false` → 无 [autocode] 任务，直接进入创建团队
- `autocode: true` → 记录生成信息，进入创建团队。Backend agent 将基于生成的代码补充自定义逻辑

### 3. 创建团队与任务

```
TeamCreate: team_name: "dev-$REQ_NAME"
```

创建以下任务:

**任务 1 — Frontend 开发** (owner: frontend):
- 读取 frontend/design.md 和 frontend/tasks.md
- 参考 ui/ 设计稿实现视觉效果
- 按任务列表逐项实现前端代码
- 完成后通知 tech-lead

**任务 2 — Backend 开发** (owner: backend):
- 读取 backend/design.md 和 backend/tasks.md
- [autocode] 标注的任务已由 Tech Lead 预生成完成，**不要重复创建**
- 在 autocode 生成的基础代码上补充自定义业务逻辑（如非标准 CRUD 的 API）
- 按 tasks.md 中剩余的非 [autocode] 任务逐项实现
- 完成后通知 tech-lead

**任务 3 — Tech Lead 代码审查 + UI 视觉审查** (owner: tech-lead, blockedBy: 任务1, 任务2):
- Tech Lead 审查前后端代码质量和接口对齐
- UI 设计师审查前端视觉还原度（代码级 + 截图对比）
- 两者并行，任一不通过 → 创建修复任务，通知开发者修复
- 都通过 → 通知 QA 开始测试

**任务 4 — QA 验收测试** (owner: qa, blockedBy: 任务3):
- 后端 API 接口测试
- 浏览器有头模式模拟用户操作测试
- 记录测试结果

### 4. 启动团队成员

并行启动 5 个 agent，使用 Task 工具:

**Frontend agent:**
```
Task tool:
  subagent_type: "hz-frontend"
  team_name: "dev-$REQ_NAME"
  name: "frontend"
  prompt: |
    你是开发团队的前端工程师，负责实现需求 $REQ_NAME 的前端功能。

    先读取 create-docs skill 的 SKILL.md (.claude/skills/create-docs/SKILL.md) 了解文档规范和 CLI 用法。

    {如果 USER_INSTRUCTIONS 非空，追加以下段落}
    ## 用户指令（优先级最高）
    $USER_INSTRUCTIONS

    你的工作流程:
    1. 从 TaskList 获取你的任务，标记为 in_progress
    2. 读取 docs/$REQ_NAME/frontend/design.md 了解技术方案
    3. 读取 docs/$REQ_NAME/frontend/tasks.md 获取任务列表
    3.5. 读取 docs/$REQ_NAME/tech/api-contracts.md — API 契约，实现接口时严格遵守。如发现接口需要变更，必须通知 tech-lead 更新契约，不能自行修改。
    4. 读取 docs/$REQ_NAME/ui/ 下的设计稿作为视觉参考（如存在）:
       - ui/merge.html — 响应式效果图（主要参考）
       - ui/Introduction.md — UI 设计说明
       - ui/design.md — 设计系统（配色、字体、间距）
       - ui/Resources/ — 可复用的资源文件
    4.5. **资源可用性验证**（实现代码前必须执行）:
       - 检查 ui/Resources/icons/ 中有哪些可用 SVG 图标
       - 检查 ui/Resources/tokens.css 和 tailwind.config.js 是否存在
       - 阅读 ui/Resources/assets-manifest.md 了解资源交付状态
       - **如发现设计稿中引用但 Resources/ 中缺失的资源**: 在 log.md 记录（类型: 变更），通知 tech-lead 协调补充，使用占位方案暂时处理，**禁止用外部 URL 替代**
    5. 按任务列表逐项实现前端代码，优先以 UI 设计稿为视觉标准，优先使用 ui/Resources/ 中的本地资源
    6. 每完成一个子任务，使用 docs.py CLI 更新 tasks.md 状态
    7. 全部完成后标记团队任务为 completed
    8. 发送消息给 tech-lead 报告完成状态

    需求目录: docs/$REQ_NAME/
```

**Backend agent:**
```
Task tool:
  subagent_type: "hz-backend"
  team_name: "dev-$REQ_NAME"
  name: "backend"
  prompt: |
    你是开发团队的后端工程师，负责实现需求 $REQ_NAME 的后端功能。

    先读取 create-docs skill 的 SKILL.md (.claude/skills/create-docs/SKILL.md) 了解文档规范和 CLI 用法。

    {如果 USER_INSTRUCTIONS 非空，追加以下段落}
    ## 用户指令（优先级最高）
    $USER_INSTRUCTIONS

    ## 重要: AutoCode 预生成说明
    Tech Lead 已在开发阶段之前使用 hab-autocode 预生成了标注 [autocode] 的 CRUD 模块基础代码。
    这些模块的 model、api handler、router、service、前端页面已经自动生成并编译通过。

    **你必须遵守以下规则:**
    - **绝对不要重新创建** [autocode] 任务中已生成的 model 结构体、api handler、router、service 文件
    - **不要修改** autocode 生成文件的基础结构（如字段定义、标准 CRUD 方法）
    - 你的职责是在已生成的代码基础上 **补充自定义业务逻辑**:
      - 非标准 CRUD 的 API（如 login、register 等需要特殊逻辑的接口）
      - 在已有 service 中添加自定义方法（如 addFunc）
      - 业务校验、权限控制、数据处理等自定义逻辑
    - tasks.md 中标注 [autocode] 且状态为「已完成」的任务 **跳过不做**
    - 只实现 tasks.md 中 **非 [autocode] 的待办任务**

    你的工作流程:
    1. 从 TaskList 获取你的任务，标记为 in_progress
    2. 读取 docs/$REQ_NAME/backend/design.md 了解技术方案
    3. 读取 docs/$REQ_NAME/backend/tasks.md 获取任务列表
    3.5. 读取 docs/$REQ_NAME/tech/api-contracts.md — API 契约，实现接口时严格遵守。如发现接口需要变更，必须通知 tech-lead 更新契约，不能自行修改。
    4. **先检查哪些任务已标记 [autocode] 已完成** — 这些已由 Tech Lead 预生成，跳过
    5. **浏览已生成的代码**，了解 autocode 产出的文件结构和内容
    6. 在已有代码基础上，按 tasks.md 中剩余的非 [autocode] 任务逐项实现
    7. 每完成一个子任务，使用 docs.py CLI 更新 tasks.md 状态
    8. 全部完成后标记团队任务为 completed
    9. 发送消息给 tech-lead 报告完成状态

    需求目录: docs/$REQ_NAME/
```

**Tech Lead agent:**
```
Task tool:
  subagent_type: "hz-tech-lead"
  team_name: "dev-$REQ_NAME"
  name: "tech-lead"
  prompt: |
    你是开发团队的 Tech Lead，负责需求 $REQ_NAME 的代码质量审查和团队协调。

    先读取 create-docs skill 的 SKILL.md (.claude/skills/create-docs/SKILL.md) 了解文档规范。
    再读取 references/tech-stack.md (.claude/skills/create-docs/references/tech-stack.md) 了解项目技术栈。
    再读取 hz-project skill (.claude/skills/hz-project/SKILL.md) 了解项目全生命周期规范。

    {如果 USER_INSTRUCTIONS 非空，追加以下段落}
    ## 用户指令（优先级最高）
    $USER_INSTRUCTIONS
    将此指令传达给相关开发者，确保按用户要求调整开发优先级或方式。

    ## 说明
    AutoCode 预生成已在创建团队前由 Step 2.5 独立完成。[autocode] 标注的任务已生成并编译通过。
    你的职责聚焦于代码审查和团队协调。

    你的工作流程:

    ## 阶段一: 等待开发完成
    1. 从 TaskList 获取你的任务（代码审查任务，blockedBy 前后端开发）
    2. 等待 frontend 和 backend 完成开发

    ## 阶段二: 代码质量审查（与 UI 视觉审查并行）
    3. 标记代码审查任务为 in_progress
    4. 通知 ui-designer 开始视觉审查
    5. 读取 docs/$REQ_NAME/ 下的 design.md 文件，对照检查代码实现:
       - 代码结构是否符合 design.md 中的架构设计
       - 前后端 API 接口是否对齐（路由、参数、响应格式）
       - 代码质量: 错误处理、类型安全、安全性
       - 是否有明显遗漏或偏离设计的实现
    6. 等待 ui-designer 的视觉审查结果
    7. 综合审查结果处理:
       - **不通过**: 合并代码问题和视觉问题，创建修复任务（TaskCreate），详细描述需要修复的问题，指定 owner 为对应开发者（frontend/backend）。发送消息通知开发者修复。等待修复完成后重新审查。
       - **通过**: 标记审查任务为 completed，通知 QA 可以开始测试。

    ## 阶段三: 汇总
    8. 等待 QA 完成测试
    9. 汇总所有角色的完成状态，发送给团队 leader

    需求目录: docs/$REQ_NAME/
```

**UI Designer agent:**
```
Task tool:
  subagent_type: "hz-ui"
  team_name: "dev-$REQ_NAME"
  name: "ui-designer"
  prompt: |
    你是开发团队的 UI 设计师，负责需求 $REQ_NAME 的视觉还原度审查。

    你的工作流程:

    ## 等待代码审查阶段
    1. 等待 tech-lead 通知你开始视觉审查
    2. 收到通知后开始审查

    ## 视觉审查
    3. 代码级审查:
       - 读取前端源码，检查 Tailwind class 使用是否与 ui/design.md 一致
       - 检查响应式断点是否正确
       - 检查间距、颜色、字号是否与设计系统一致
    4. **资源使用审查**:
       - 对比前端代码中引用的资源 vs ui/Resources/ 中提供的资源
       - 检查前端是否使用了外部 URL 替代本地应有的资源（grep 检查图片/图标的 src/href 是否指向外部域名）
       - 检查 ui/Resources/icons/ 中的 SVG 图标是否被前端正确引用
       - 检查 ui/Resources/tokens.css 和 tailwind.config.js 是否被前端项目集成
       - **缺失资源或使用外部 URL 替代标记为 P0**
    5. 视觉对比审查:
       - 使用 process-manager scripts 启动前后端服务
       - 使用 agent-browser --headed 打开页面进行实时视觉检查
       - 与 ui/ 目录下的 HTML 设计稿对比
       - **仅在发现视觉问题时截图留证，正常通过的页面不截图**
    6. 输出审查报告发送给 tech-lead:
       - 视觉一致性评分
       - 具体问题清单（布局差异、颜色不一致、间距问题、**资源缺失**等）
       - 每个问题标注严重程度（P0/P1/P2）和建议修复方式
       - **资源缺失问题单独列出**，说明缺失的资源名称和前端当前使用的替代方案
    7. 审查完成后清理: 关闭浏览器, 停止服务, 清理进程

    需求目录: docs/$REQ_NAME/
```

**QA agent:**
```
Task tool:
  subagent_type: "hz-qa"
  team_name: "dev-$REQ_NAME"
  name: "qa"
  prompt: |
    你是开发团队的 QA 工程师，负责验收需求 $REQ_NAME 的实现质量。

    先读取 create-docs skill 的 SKILL.md (.claude/skills/create-docs/SKILL.md) 了解文档规范和 CLI 用法。

    {如果 USER_INSTRUCTIONS 非空，追加以下段落}
    ## 用户指令（优先级最高）
    $USER_INSTRUCTIONS

    你的工作流程:
    1. 从 TaskList 获取你的任务（等待代码审查通过后开始）
    2. 标记任务为 in_progress
    3. 读取 docs/$REQ_NAME/plan.md 获取验收标准
    4. 读取 docs/$REQ_NAME/qa/design.md 获取测试方案
    5. 读取 docs/$REQ_NAME/qa/tasks.md 获取测试任务

    ## 测试执行（两阶段）

    ### 阶段 A: 后端 API 测试
    - 根据 backend/design.md 中的接口定义，逐个测试 API 端点
    - 使用 curl 或编写测试脚本验证:
      - 请求/响应格式是否符合设计
      - 正常流程是否正确
      - 错误处理（无效参数、未授权等）
      - 边界条件
    - 记录每个 API 的测试结果

    ### 阶段 B: 浏览器有头模式用户模拟测试
    - 使用 agent-browser skill 进行有头 (headed) 浏览器测试
    - 启动前后端服务（使用 process-manager scripts 管理进程）
    - 模拟真实用户操作流程:
      - 按 plan.md 中的用户场景逐步操作
      - 验证页面展示、交互、数据一致性
      - **仅在发现 Bug 时截图留证，正常通过的步骤不截图**
    - 发现 bug 记录到 log.md（附截图），严重问题通知 tech-lead

    6. 全部完成后标记团队任务为 completed
    7. 发送消息给 tech-lead 报告验收结果，包括:
       - API 测试通过率
       - 用户场景测试结果
       - 发现的问题列表（如有）

    ## 测试产物
    测试过程中必须写入以下文档:
    - `qa/test-report.md` — 每轮测试追加「第 N 轮测试结果」段落（按模板格式填写）
    - `qa/api-tests.md` — 记录每个 API 的完整请求/响应（按模板格式）
    - `qa/bugs.md` — 发现 Bug 时追加 Bug 详情块（含复现步骤、证据）
    使用 `docs.py log` 在 log.md 记录测试摘要。

    需求目录: docs/$REQ_NAME/
```

### 5. 监控团队进度

等待团队成员消息:
- Frontend + Backend 完成 → Tech Lead 开始代码审查 + 通知 UI 设计师视觉审查
- Tech Lead + UI 审查不通过 → 开发者修复 → 重新审查（循环直到通过）
- 审查通过 → QA 开始测试
- QA 完成 → Tech Lead 汇总报告

### 6. 汇总开发报告

所有任务完成后，输出报告:

```
## 开发报告: $REQ_NAME

**状态**: [SUCCESS/PARTIAL/BLOCKED]

### 1. 文档检查
- [通过/不通过，检查摘要]

### 1.5 AutoCode 预生成
- [有/无 [autocode] 任务]
- [生成的模块列表（如有）]
- [编译状态]

### 2. 开发实现
**Frontend**:
- [完成任务数/总任务数]
- [关键实现摘要]

**Backend**:
- [完成任务数/总任务数]
- [关键实现摘要]

### 3. 代码审查 + 视觉审查
- [审查轮次: 第 N 轮通过]
- [Tech Lead 代码审查意见摘要]
- [UI 视觉审查结果摘要]

### 4. QA 测试
**API 测试**:
- [通过数/总数]
- [失败项（如有）]

**浏览器用户模拟测试**:
- [场景通过数/总数]
- [发现问题（如有）]

### 后续待办
- [如有未完成项或问题，列出]

### 后续建议
- 运行 `/review-qa $REQ_NAME` 进行独立验收测试（如需更全面的测试）
- 运行 `/unify-fix <问题描述>` 修复发现的 Bug
- 查看流水线状态: `python3 .claude/skills/create-docs/scripts/docs.py pipeline $REQ_NAME`
```

### 7. Git 提交

1. 运行 `git status` + `git diff --stat` 展示变更概要
2. 使用 AskUserQuestion 询问用户是否提交 git:
   - 选项: 提交 / 不提交 / 修改后再提交
3. 用户批准后提交:
   - commit message: `feat($REQ_NAME): unify-dev 完成全团队协作开发`
4. **绝不自动提交**，必须等待用户明确批准

### 8. 清理团队

发送 shutdown_request 给所有成员 → 等待确认 → TeamDelete

## Important Notes

- **文档检查是硬门槛** — 不通过直接停止，不创建团队，不开始开发
- **AutoCode 预生成在创建团队前完成** — Tech Lead 独立执行，生成 CRUD 基础代码（model/api/router/service/前端页面），Backend 开发者在此基础上补充自定义逻辑，**不得重复创建已生成的文件**
- **代码审查 + UI 视觉审查是质量关卡** — 不通过必须修复后重新审查，不能跳过直接进 QA
- **Frontend 和 Backend 并行开发**，互不阻塞
- **Tech Lead 代码审查与 UI 视觉审查并行**，综合结果后决定是否通过
- **QA 测试两阶段** — 先 API 测试确保接口正确，再浏览器测试验证用户体验
- **DO NOT** 跳过文档检查直接开发
- **DO NOT** 跳过代码审查直接进 QA
- **DO NOT** 在没有 design.md 的情况下开始编码
- 每个 agent 使用 docs.py CLI 更新自己角色的 tasks.md 状态
- 所有变更记录到 docs/$REQ_NAME/log.md

## Error Handling

If 文档检查不通过:
- 输出具体缺失/问题列表
- 提示: `建议先运行 /doc-review $REQ_NAME 完善文档`
- **停止执行**

If 代码审查不通过:
- Tech Lead 合并代码问题和 UI 视觉问题，创建修复任务，指定给对应开发者
- 开发者修复后 Tech Lead + UI 重新审查
- 如果连续 3 轮不通过，使用 AskUserQuestion 上报给用户，提供明确选项:
  - 继续修复（再给 2 轮机会）
  - 回退到文档阶段（重新审查 design.md）
  - 接受当前状态（标记为 PARTIAL，记录遗留问题）

If QA 发现严重 bug:
- 通知 Tech Lead
- Tech Lead 决定是否需要回退修复
- 严重问题阻塞发布时，报告给用户
