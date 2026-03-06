---
description: "[统一调度] 启动 PM + Tech Lead + UI 团队进行文档整体评审，三端对齐"
argument-hint: [需求名称或ID]
---

# 文档整体评审（三端对齐）

在所有角色文档完整的前提下，启动 PM、Tech Lead、UI 设计师团队，进行文档整体评审与三端对齐。评审中发现分歧或问题时，使用 brainstorming skill 与用户沟通，以用户决策为准修改文档。

## 流程概览

```
1. 参数解析 → 确定需求
2. 文档完整性硬门槛检查（PM + Tech + UI 文档必须齐全）
   ↓ 通过
3. 创建团队，PM / Tech Lead / UI 并行评审
   ↓
4. 三端交叉对齐 → 发现分歧 → brainstorming 与用户决策
   ↓
5. 按用户决策修改文档
6. 汇总报告 + 清理团队
```

## Implementation Steps

### 1. 参数解析 → 确定 REQ_NAME

读取 `$ARGUMENTS`：

- **参数为空** → 扫描 `docs/` 下所有需求目录（排除 project.md, tasks.md, CHANGELOG.md, fixes/），使用 AskUserQuestion 列出需求列表让用户选择
- **参数非空** → 按顺序尝试:
  1. 精确匹配: `docs/{参数}/` 存在？
  2. ID 匹配: `docs/{参数}-*/` 存在？
  3. 短名匹配: `docs/*-{参数}/` 存在？
  4. 全部失败 → 报错，列出可用需求目录，**停止执行**
- **匹配到多个** → 使用 AskUserQuestion 列出候选让用户选择

将确定的需求名称记为 `REQ_NAME`。

### 2. 文档完整性硬门槛检查

逐项检查以下文件是否存在且非空，**任一不满足 → 严格拒绝执行**:

| 层级 | 检查项 | 条件 | 不满足时提示 |
|------|--------|------|-------------|
| L2 业务 | plan.md | `docs/{REQ_NAME}/plan.md` 存在且非空 | "请先运行 `/review-pm {REQ_NAME}` 完善业务文档" |
| L2 业务 | tasks.md | `docs/{REQ_NAME}/tasks.md` 存在且非空 | "请先运行 `/review-pm {REQ_NAME}` 创建功能任务" |
| L3 技术 | backend/design.md | `docs/{REQ_NAME}/backend/design.md` 存在且非空 | "请先运行 `/review-tech {REQ_NAME}` 完善技术方案" |
| L3 技术 | frontend/design.md | `docs/{REQ_NAME}/frontend/design.md` 存在且非空 | "请先运行 `/review-tech {REQ_NAME}` 完善技术方案" |
| L3 技术 | backend/tasks.md | `docs/{REQ_NAME}/backend/tasks.md` 存在且非空 | "请先运行 `/review-tech {REQ_NAME}` 拆解技术任务" |
| L3 技术 | frontend/tasks.md | `docs/{REQ_NAME}/frontend/tasks.md` 存在且非空 | "请先运行 `/review-tech {REQ_NAME}` 拆解技术任务" |
| L3 UI | ui/merge.html | `docs/{REQ_NAME}/ui/merge.html` 存在且非空 | "请先运行 `/review-ui {REQ_NAME}` 产出 UI 设计稿" |
| L3 UI | ui/design.md | `docs/{REQ_NAME}/ui/design.md` 存在且非空 | "请先运行 `/review-ui {REQ_NAME}` 产出设计系统文档" |

如有不满足项 → 列出所有缺失项 + 对应前置命令，**停止执行，不创建团队**。

### 3. 创建团队与任务

```
TeamCreate: team_name: "review-all-{REQ_NAME}"
```

创建 4 个任务:

**任务 1 — PM 业务文档评审** (owner: pm):
- 评审 plan.md、tasks.md 业务完整性和质量
- 重点检查：验收标准是否可量化、用户场景是否覆盖完整、功能任务与验收标准是否一一对应
- 记录发现的业务侧问题，发送给 tech-lead 和 ui-designer

**任务 2 — Tech Lead 技术文档评审** (owner: tech-lead):
- 评审 backend/design.md、frontend/design.md 技术方案完整性
- 重点检查：前后端 API 接口契约是否对齐、技术任务是否可执行、架构设计是否合理
- 检查技术方案与 plan.md 业务需求的对应关系
- 记录发现的技术侧问题，发送给 pm 和 ui-designer

**任务 3 — UI 设计评审** (owner: ui-designer):
- 评审 merge.html 设计稿与 plan.md 用户场景的覆盖度
- 重点检查：设计稿是否覆盖所有用户场景、Resources/ 资源完整性、设计系统与前端 design.md 的一致性
- 记录发现的设计侧问题，发送给 tech-lead 和 pm

**任务 4 — 三端交叉对齐** (pm + tech-lead + ui-designer 协作):
- 汇总三端评审发现的问题
- 检查三端一致性：
  - 业务需求 ↔ 技术方案：每个业务场景是否有对应技术实现路径
  - 业务需求 ↔ UI 设计：每个用户场景是否有对应设计页面
  - 技术方案 ↔ UI 设计：前端技术方案是否与 UI 设计系统对齐（组件、样式、资源）
- **发现分歧或不一致 → 使用 brainstorming skill 与用户讨论，以用户决策为准**
- 按决策结果修改对应文档

### 4. 启动团队成员

并行启动三个 agent，使用 Task 工具:

**PM agent:**
```
Task tool:
  subagent_type: "hz-pm"
  team_name: "review-all-{REQ_NAME}"
  name: "pm"
  prompt: |
    你是文档整体评审团队的 PM，负责业务文档评审和三端对齐。

    先读取 create-docs skill 的 SKILL.md (.claude/skills/create-docs/SKILL.md) 了解文档规范。
    再读取 references/update-guide.md (.claude/skills/create-docs/references/update-guide.md) 了解更新规则。

    ## 阶段一：业务文档评审
    评审需求 {REQ_NAME} 的 L1 + L2 业务文档:
    - docs/project.md — 项目概览业务信息完整性
    - docs/{REQ_NAME}/plan.md — 目标、用户场景、验收标准是否可量化
    - docs/{REQ_NAME}/tasks.md — 功能任务是否与验收标准一一对应
    - docs/{REQ_NAME}/log.md — 变更记录

    输出评审报告（问题清单 + 改进建议），发送给 tech-lead 和 ui-designer。

    ## 阶段二：三端对齐
    等待收到 tech-lead 和 ui-designer 的评审报告后：
    1. 汇总三端问题，识别不一致之处
    2. 重点关注：
       - 业务场景是否每个都有技术实现路径和 UI 设计覆盖
       - 验收标准是否与技术任务和设计页面匹配
    3. 发现分歧时：使用 brainstorming skill 与用户讨论，清晰呈现各端差异，请用户决策
    4. 按用户决策修改 plan.md 和 tasks.md
    5. 完成后将最终对齐结果发送给 tech-lead 和 ui-designer
```

**Tech Lead agent:**
```
Task tool:
  subagent_type: "hz-tech-lead"
  team_name: "review-all-{REQ_NAME}"
  name: "tech-lead"
  prompt: |
    你是文档整体评审团队的 Tech Lead，负责技术文档评审和三端对齐。

    先读取 create-docs skill 的 SKILL.md (.claude/skills/create-docs/SKILL.md) 了解文档规范。
    再读取 references/update-guide.md (.claude/skills/create-docs/references/update-guide.md) 了解更新规则。
    再读取 references/tech-stack.md (.claude/skills/create-docs/references/tech-stack.md) 了解项目技术栈。

    ## 阶段一：技术文档评审
    评审需求 {REQ_NAME} 的 L3 技术文档:
    - docs/{REQ_NAME}/backend/design.md — 后端技术方案、架构、接口定义
    - docs/{REQ_NAME}/frontend/design.md — 前端技术方案、组件设计
    - docs/{REQ_NAME}/backend/tasks.md — 后端任务具体可执行性
    - docs/{REQ_NAME}/frontend/tasks.md — 前端任务具体可执行性
    - 前后端 API 接口契约是否对齐（请求/响应格式一致）
    - 技术方案与 plan.md 业务需求的对应关系

    输出评审报告（问题清单 + 改进建议），发送给 pm 和 ui-designer。

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
```

**UI Designer agent:**
```
Task tool:
  subagent_type: "hz-ui"
  team_name: "review-all-{REQ_NAME}"
  name: "ui-designer"
  prompt: |
    你是文档整体评审团队的 UI 设计师，负责设计文档评审和三端对齐。

    先读取 create-docs skill 的 SKILL.md (.claude/skills/create-docs/SKILL.md) 了解文档规范和 CLI 用法。

    ## 阶段一：设计文档评审
    评审需求 {REQ_NAME} 的 UI 设计文档:
    - docs/{REQ_NAME}/ui/merge.html — 设计稿是否覆盖 plan.md 中的所有用户场景
    - docs/{REQ_NAME}/ui/design.md — 设计系统完整性（配色、字体、间距、组件）
    - docs/{REQ_NAME}/ui/Introduction.md — 前端设计说明是否清晰
    - docs/{REQ_NAME}/ui/Resources/ — 资源交付完整性:
      - icons/*.svg 是否覆盖设计稿所有图标
      - tokens.css 和 tailwind.config.js 是否与 design.md 一致
      - assets-manifest.md 自检清单是否通过
    - merge.html 中禁止外部 URL 引用本地资源

    输出评审报告（问题清单 + 改进建议），发送给 tech-lead 和 pm。

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
```

### 5. 等待完成并汇总

等待三个 agent 完成两个阶段（独立评审 + 三端对齐）后，汇总整体评审报告:

```
## 文档整体评审报告: {REQ_NAME}

**状态**: [ALIGNED/PARTIAL/BLOCKED]

### 1. 业务文档评审（PM）
- [问题数/已修复数]
- [关键发现摘要]

### 2. 技术文档评审（Tech Lead）
- [问题数/已修复数]
- [关键发现摘要]

### 3. UI 设计评审（UI Designer）
- [问题数/已修复数]
- [关键发现摘要]

### 4. 三端对齐结果
- **业务 ↔ 技术**: [对齐状态，解决的分歧]
- **业务 ↔ UI**: [对齐状态，解决的分歧]
- **技术 ↔ UI**: [对齐状态，解决的分歧]

### 5. 用户决策记录
- [brainstorming 中用户做出的关键决策列表]

### 6. 文档变更汇总
- [本次评审修改的文件列表]

### 后续建议
- [如有遗留问题或建议，列出]
```

### 6. 清理团队

发送 shutdown_request 给所有成员 → 等待确认 → TeamDelete

### 7. Git 提交

1. 运行 `git status` + `git diff --stat` 展示变更概要
2. 使用 AskUserQuestion 询问用户是否提交 git:
   - 选项: 提交 / 不提交 / 修改后再提交
3. 用户批准后提交:
   - commit message: `docs({REQ_NAME}): review-all 三端文档对齐评审`
4. **绝不自动提交**，必须等待用户明确批准

## Important Notes

- **文档完整性是硬门槛** — PM、Tech、UI 三端文档必须齐全才能启动评审，任一缺失直接停止
- **brainstorming 是核心沟通机制** — 发现分歧或不一致时，必须通过 brainstorming skill 与用户讨论，不得自行决策
- **用户决策优先** — 所有分歧的最终裁决权归用户，agent 按用户决策修改文档
- **三端并行评审，对齐阶段协作** — 阶段一独立评审互不阻塞，阶段二基于三端结果交叉对齐
- **鼓励直接修复** — 发现明确的文档质量问题（格式、遗漏、不一致）直接修复，不仅列出
- **DO NOT** 修改代码文件，仅涉及 docs/
- **DO NOT** 创建新需求或新增功能，仅评审和对齐已有文档
- **DO NOT** 在未经用户确认的情况下做出架构或业务范围级别的文档变更
- Agent 自身已有完整的角色职责定义，prompt 只需指明评审任务和 skill 规范位置
