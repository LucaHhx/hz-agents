---
description: "[团队调度] Tech Lead 带队前后端开发，含指导和代码审查"
argument-hint: [需求名称或ID] [用户指令]
---

# Tech Lead 带队开发

启动 Tech Lead 协调的开发团队（Tech Lead + Frontend + Backend），按 design.md 技术方案实现需求。Tech Lead 负责开发指导和代码审查。

## 流程概览

```
1. 前置文档检查 ── 不通过 → 暂停，提示用户先完善文档
                     ↓ 通过
2. Tech Lead AutoCode 预生成 ── 扫描 [autocode] 任务 → 生成 CRUD 基础代码 + 编译检查
                     ↓ 完成（或无 [autocode] 任务则跳过）
3. 创建团队，Frontend + Backend 并行开发（Backend 在 autocode 基础上补充自定义逻辑）
                     ↓
4. Tech Lead 代码审查 ── 不通过 → 创建修复任务，回到步骤 3
                     ↓ 通过       （最多 3 轮，超过上报用户）
5. 汇总报告 + Git 提交
```

## Usage

```bash
# 开发指定需求
/dev-tech 7

# 带指令开发
/dev-tech 7 先实现登录模块
/dev-tech 7 只做后端API部分

# 不指定需求（自动列表选择）
/dev-tech
```

## Implementation Steps

### 1. 参数解析 → 确定 REQ_NAME + USER_INSTRUCTIONS

读取 `$ARGUMENTS`，拆分为**需求标识**和**用户指令**两部分：

**拆分规则**: 取第一个 token（空格分隔）作为需求标识，剩余部分作为 `USER_INSTRUCTIONS`。

示例:
- `/dev-tech 7 先实现登录模块` → 需求标识=`7`, USER_INSTRUCTIONS=`先实现登录模块`
- `/dev-tech 7` → 需求标识=`7`, USER_INSTRUCTIONS=空
- `/dev-tech` → 需求标识=空, USER_INSTRUCTIONS=空

**需求匹配**（用需求标识部分）：

- **需求标识为空** → 扫描 `docs/` 下所有需求目录（排除 project.md, tasks.md, CHANGELOG.md, fixes/），使用 AskUserQuestion 列出需求列表让用户选择
- **需求标识非空** → 按顺序尝试:
  1. 精确匹配: `docs/{需求标识}/` 存在？
  2. ID 匹配: `docs/{需求标识}-*/` 存在？
  3. 短名匹配: `docs/*-{需求标识}/` 存在？
  4. 全部失败 → 报错，列出可用需求目录，**停止执行**
- **匹配到多个** → 使用 AskUserQuestion 列出候选让用户选择

将确定的需求名称记为 `REQ_NAME`。

### 2. 前置检查（硬门槛）

逐项检查以下条件，**任一不满足 → 严格拒绝执行**:

| 检查项 | 条件 | 不满足时提示 |
|--------|------|-------------|
| plan.md | `docs/{REQ_NAME}/plan.md` 存在且非空 | "请先运行 `/review-pm {REQ_NAME}` 完善业务文档" |
| frontend/design.md | `docs/{REQ_NAME}/frontend/design.md` 存在且非空 | "请先运行 `/review-tech {REQ_NAME}` 创建技术方案" |
| backend/design.md | `docs/{REQ_NAME}/backend/design.md` 存在且非空 | "请先运行 `/review-tech {REQ_NAME}` 创建技术方案" |
| frontend/tasks.md | `docs/{REQ_NAME}/frontend/tasks.md` 存在且有待办任务 | "前端无待办任务，请检查任务列表" |
| backend/tasks.md | `docs/{REQ_NAME}/backend/tasks.md` 存在且有待办任务 | "后端无待办任务，请检查任务列表" |

如有不满足项 → 列出缺失项 + 对应前置命令，**停止执行**。

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
TeamCreate: team_name: "dev-tech-$REQ_NAME"
```

创建以下任务:

**任务 1 — Frontend 开发** (owner: frontend):
- 读取 frontend/design.md 和 frontend/tasks.md
- 参考 ui/ 设计稿实现视觉效果（如存在）
- 按任务列表逐项实现前端代码
- 完成后通知 tech-lead

**任务 2 — Backend 开发** (owner: backend):
- 读取 backend/design.md 和 backend/tasks.md
- 按任务列表逐项实现后端代码
- 完成后通知 tech-lead

**任务 3 — Tech Lead 代码审查** (owner: tech-lead, blockedBy: 任务1, 任务2):
- 审查前后端代码质量、架构一致性、接口对齐
- 不通过 → 创建修复任务，通知开发者修复，重新审查
- 通过 → 标记完成，汇总报告

### 4. 启动团队成员

并行启动 3 个 agent:

**Tech Lead agent (team leader):**
```
Task tool:
  subagent_type: "hz-tech-lead"
  team_name: "dev-tech-$REQ_NAME"
  name: "tech-lead"
  prompt: |
    你是开发团队的 Tech Lead（团队负责人），负责需求 {REQ_NAME} 的开发指导和代码审查。

    先读取 create-docs skill 的 SKILL.md (.claude/skills/create-docs/SKILL.md) 了解文档规范。
    再读取 references/tech-stack.md (.claude/skills/create-docs/references/tech-stack.md) 了解项目技术栈。
    再读取 hz-project skill (.claude/skills/hz-project/SKILL.md) 了解项目全生命周期规范。

    {如果 USER_INSTRUCTIONS 非空，追加以下段落}
    ## 用户指令（优先级最高）
    {USER_INSTRUCTIONS}
    将此指令传达给相关开发者，确保按用户要求调整开发优先级或方式。

    ## 说明
    AutoCode 预生成已在创建团队前由 Step 2.5 独立完成。[autocode] 标注的任务已生成并编译通过。
    你的职责聚焦于开发指导和代码审查。

    ## 链接浏览
    如果用户指令中包含 URL 链接，使用 agent-browser 浏览这些链接，提取技术细节后传达给开发者。

    你的工作流程:

    ## 阶段一: 开发指导
    1. 从 TaskList 获取任务概览
    2. 读取 docs/{REQ_NAME}/ 下所有 design.md 文件，掌握完整技术方案
    3. 读取 docs/{REQ_NAME}/plan.md 了解业务需求
    4. 等待 frontend 和 backend 完成开发
    5. 期间如收到开发者的技术疑问，及时回复指导:
       - 参照 design.md 解答架构疑问
       - 确认接口变更是否合理
       - 协调前后端接口对齐问题
       - 如有需要，使用 brainstorming skill 与用户探讨方案

    ## 阶段二: 代码审查
    6. 前后端都完成后，标记代码审查任务为 in_progress
    7. 审查前端代码:
       - 读取前端源码，对照 frontend/design.md 检查
       - 组件结构、状态管理是否合理
       - 是否正确使用了 ui/Resources/ 中的本地资源
       - 有无外部 URL 替代本地资源的情况
    8. 审查后端代码:
       - 读取后端源码，对照 backend/design.md 检查
       - API 接口实现是否与约定一致
       - 数据模型、错误处理、安全性
    9. 交叉检查:
       - 前后端 API 接口是否对齐（路由、参数、响应格式）
       - 认证/鉴权流程一致性
    10. 审查结果处理:
        - **不通过**: 创建修复任务（TaskCreate），详细描述问题和修复建议，指定 owner 为对应开发者。发送消息通知开发者修复。等待修复完成后重新审查。最多 3 轮，超过上报用户。
        - **通过**: 标记审查任务为 completed。

    ## 阶段三: 汇总
    11. 输出开发报告，包括:
        - 前后端完成情况
        - 代码审查结果（通过/修复轮次）
        - 技术债务或后续优化建议

    需求目录: docs/{REQ_NAME}/
```

**Frontend agent:**
```
Task tool:
  subagent_type: "hz-frontend"
  team_name: "dev-tech-$REQ_NAME"
  name: "frontend"
  prompt: |
    你是开发团队的前端工程师，负责实现需求 {REQ_NAME} 的前端功能。
    团队中有 Tech Lead (tech-lead) 和后端工程师 (backend)，遇到技术疑问可以发消息给 tech-lead。

    先读取 create-docs skill 的 SKILL.md (.claude/skills/create-docs/SKILL.md) 了解文档规范和 CLI 用法。

    {如果 USER_INSTRUCTIONS 非空，追加以下段落}
    ## 用户指令（优先级最高）
    {USER_INSTRUCTIONS}

    ## 链接浏览
    如果用户指令中包含 URL 链接，使用 agent-browser 浏览这些链接，提取实现参考。

    你的工作流程:
    1. 从 TaskList 获取你的任务，标记为 in_progress
    2. 读取 docs/{REQ_NAME}/frontend/design.md 了解技术方案
    3. 读取 docs/{REQ_NAME}/frontend/tasks.md 获取任务列表
    3.5. 读取 docs/{REQ_NAME}/tech/api-contracts.md — API 契约，实现接口时严格遵守。如发现接口需要变更，必须通知 tech-lead 更新契约，不能自行修改。
    4. 读取 docs/{REQ_NAME}/ui/ 下的设计稿作为视觉参考（如存在）:
       - ui/merge.html — 响应式效果图（主要参考）
       - ui/Introduction.md — UI 设计说明
       - ui/design.md — 设计系统（配色、字体、间距）
       - ui/Resources/ — 可复用的资源文件
    5. 资源可用性验证（编码前必须执行）:
       - 检查 ui/Resources/ 中有哪些可用资源
       - 如发现设计稿引用但 Resources/ 中缺失的资源: 在 log.md 记录，通知 tech-lead 协调，使用占位方案，禁止用外部 URL 替代
    6. 按任务列表逐项实现前端代码
    7. 遇到接口定义不清或技术疑问时，发消息给 tech-lead 咨询
    8. 每完成一个任务，使用 docs.py CLI 更新 tasks.md 状态
    9. 全部完成后标记团队任务为 completed
    10. 发送消息给 tech-lead 报告完成状态

    需求目录: docs/{REQ_NAME}/
```

**Backend agent:**
```
Task tool:
  subagent_type: "hz-backend"
  team_name: "dev-tech-$REQ_NAME"
  name: "backend"
  prompt: |
    你是开发团队的后端工程师，负责实现需求 {REQ_NAME} 的后端功能。
    团队中有 Tech Lead (tech-lead) 和前端工程师 (frontend)，遇到技术疑问可以发消息给 tech-lead。

    先读取 create-docs skill 的 SKILL.md (.claude/skills/create-docs/SKILL.md) 了解文档规范和 CLI 用法。

    {如果 USER_INSTRUCTIONS 非空，追加以下段落}
    ## 用户指令（优先级最高）
    {USER_INSTRUCTIONS}

    ## 链接浏览
    如果用户指令中包含 URL 链接，使用 agent-browser 浏览这些链接，提取 API 文档或技术参考。

    ## 重要: AutoCode 预生成说明
    Tech Lead 已在开发阶段之前使用 hab-autocode 预生成了标注 [autocode] 的 CRUD 模块基础代码。
    这些模块的 model、api handler、router、service、前端页面已经自动生成并编译通过。

    **你必须遵守以下规则:**
    - **绝对不要重新创建** [autocode] 任务中已生成的 model 结构体、api handler、router、service 文件
    - **不要修改** autocode 生成文件的基础结构（如字段定义、标准 CRUD 方法）
    - 你的职责是在已生成的代码基础上 **补充自定义业务逻辑**:
      - 非标准 CRUD 的 API（如 login、register 等需要特殊逻辑的接口）
      - 在已有 service 中添加自定义方法
      - 业务校验、权限控制、数据处理等自定义逻辑
    - tasks.md 中标注 [autocode] 且状态为「已完成」的任务 **跳过不做**
    - 只实现 tasks.md 中 **非 [autocode] 的待办任务**

    你的工作流程:
    1. 从 TaskList 获取你的任务，标记为 in_progress
    2. 读取 docs/{REQ_NAME}/backend/design.md 了解技术方案
    3. 读取 docs/{REQ_NAME}/backend/tasks.md 获取任务列表
    3.5. 读取 docs/{REQ_NAME}/tech/api-contracts.md — API 契约，实现接口时严格遵守。如发现接口需要变更，必须通知 tech-lead 更新契约，不能自行修改。
    4. **先检查哪些任务已标记 [autocode] 已完成** — 这些已由 Tech Lead 预生成，跳过
    5. **浏览已生成的代码**，了解 autocode 产出的文件结构和内容
    6. 在已有代码基础上，按 tasks.md 中剩余的非 [autocode] 任务逐项实现
    7. 遇到接口定义不清或技术疑问时，发消息给 tech-lead 咨询
    8. 每完成一个任务，使用 docs.py CLI 更新 tasks.md 状态
    9. 全部完成后标记团队任务为 completed
    10. 发送消息给 tech-lead 报告完成状态

    需求目录: docs/{REQ_NAME}/
```

### 5. 监控团队进度

等待团队成员消息:
- Frontend + Backend 并行开发，互不阻塞
- 开发者遇到疑问 → Tech Lead 响应指导
- 两者都完成 → Tech Lead 开始代码审查
- 代码审查不通过 → 创建修复任务 → 开发者修复 → 重新审查（最多 3 轮）
- 代码审查通过 → Tech Lead 输出汇总报告

### 6. 汇总开发报告

所有任务完成后，输出报告:

```
## 开发报告: {REQ_NAME}

**状态**: [SUCCESS/PARTIAL/BLOCKED]

### 1. 前端开发
- [完成任务数/总任务数]
- [关键实现摘要]

### 2. 后端开发
- [完成任务数/总任务数]
- [关键实现摘要]

### 3. 代码审查
- [审查轮次: 第 N 轮通过]
- [审查意见摘要]
- [修复项（如有）]

### 后续建议
- [技术债务或优化建议]
- [建议运行 `/review-qa {REQ_NAME}` 进行验收测试]
```

### 7. Git 提交

1. 运行 `git status` + `git diff --stat` 展示变更概要
2. 使用 AskUserQuestion 询问用户是否提交 git:
   - 选项: 提交 / 不提交 / 修改后再提交
3. 用户批准后提交:
   - commit message: `feat({REQ_NAME}): dev-tech 完成前后端开发`
4. **绝不自动提交**，必须等待用户明确批准

### 8. 清理团队

发送 shutdown_request 给所有成员 → 等待确认 → TeamDelete

## Important Notes

- **文档检查是硬门槛** — design.md 和 tasks.md 缺失直接停止，不创建团队
- **AutoCode 预生成在创建团队前完成** — Tech Lead 独立执行，生成 CRUD 基础代码（model/api/router/service/前端页面），Backend 开发者在此基础上补充自定义逻辑，**不得重复创建已生成的文件**
- **代码审查是质量关卡** — 不通过必须修复后重新审查，最多 3 轮
- **Frontend 和 Backend 并行开发**，互不阻塞
- **Tech Lead 全程在线** — 开发阶段响应指导，完成后做代码审查
- **DO NOT** 跳过文档检查直接开发
- **DO NOT** 跳过代码审查直接结束
- **DO NOT** 在没有 design.md 的情况下开始编码
- 每个 agent 使用 docs.py CLI 更新自己角色的 tasks.md 状态
- 所有变更记录到 docs/{REQ_NAME}/log.md

## Error Handling

If 文档检查不通过:
- 输出具体缺失/问题列表
- 提示: `建议先运行 /review-tech {REQ_NAME} 完善技术文档`
- **停止执行**

If 代码审查连续 3 轮不通过:
- Tech Lead 汇总累积问题
- 上报给用户决策：继续修复 / 重新设计 / 接受当前状态

If 开发者遇到阻塞:
- 通知 Tech Lead
- Tech Lead 评估后决定：调整方案 / 使用 brainstorming 与用户探讨 / 记录到 log.md
