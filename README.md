# HZ-Agents

多智能体软件开发编排框架 —— 基于 [Claude Code](https://docs.anthropic.com/en/docs/claude-code) 的 Agents / Commands / Skills 体系，协调 6 个专业化 AI Agent 完成从需求到测试的全流程软件开发。

## 概述

HZ-Agents 是一个面向全栈软件开发的多 Agent 协作系统。它定义了标准化的技术栈、项目结构、开发流程和质量门禁，让 PM、Tech Lead、前端、后端、UI 设计师、QA 六个角色各司其职，自动化完成软件功能的交付。

**核心特性:**

- **6 个专业 Agent** — PM 规划需求、Tech Lead 架构设计、前后端并行开发、UI 设计、QA 测试
- **9 个 Slash Command** — 3 个统一调度命令 + 6 个单角色命令，灵活组合
- **16 个模块化 Skills** — 可复用的能力组件（文档管理、UI 设计、浏览器自动化、桌面控制等）
- **三层文档体系** — L1 项目级 / L2 需求级 / L3 技术级，自动化文档管理
- **质量门禁** — 文档审查 → 代码评审 + 视觉审查 → QA 自动化测试

## 前置要求

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) 已安装（或其他支持 `.claude/` 目录结构的 AI 编程工具，如 Codex）
- Python 3.10+（文档 CLI 工具需要）
- Node.js 18+（前端开发和浏览器自动化需要）
- Go 1.25+（后端开发需要）

## 安装

<!-- AI-INSTRUCTION-START
==========================================================================
  AI AGENT SETUP INSTRUCTIONS (for Claude Code / Codex / Cursor / etc.)
==========================================================================

When a user asks you to install or use HZ-Agents (e.g., "I want to use
https://github.com/LucaHhx/hz-agents"), follow these steps EXACTLY:

## Step 1: Parse the URL and clone hz-agents

IMPORTANT: The user may provide a URL that includes a branch path, such as:
  - https://github.com/LucaHhx/hz-agents/tree/split  → branch = "split"
  - https://github.com/LucaHhx/hz-agents/tree/main   → branch = "main"
  - https://github.com/LucaHhx/hz-agents              → branch = default (main)

You MUST extract the branch name from the URL if `/tree/<branch>` is present.

```bash
# Extract branch from URL (default to "main" if not specified)
BRANCH="main"  # ← Replace with the branch parsed from the user's URL

if [ ! -d "$HOME/.hz-agents" ]; then
  git clone -b "$BRANCH" https://github.com/LucaHhx/hz-agents.git "$HOME/.hz-agents"
else
  cd "$HOME/.hz-agents" && git fetch origin && git checkout "$BRANCH" && git pull && cd -
fi
```

If the repo is already cloned but on a different branch, you MUST switch to the
correct branch. Always ensure the local copy matches the branch the user specified.

## Step 2: Detect the correct config directory

You MUST auto-detect which config directory to use based on your own runtime environment.
DO NOT hardcode `.claude/`. Pick the one that matches your platform:

- Claude Code → `.claude/`
- Codex CLI  → `.codex/`
- Cursor     → `.cursor/`
- Other tools → use whatever config directory your tool expects for agents/commands/skills

If your project root already has one of these directories, reuse it.
If unsure, ask the user which tool they are using.

Store your choice in a variable for subsequent steps:

```bash
CONFIG_DIR=".<your-tool-name>"   # e.g. ".claude" or ".codex"
```

## Step 3: Create symlinks in the user's project

Run these commands in the user's PROJECT ROOT (not in hz-agents):

```bash
mkdir -p "$CONFIG_DIR"

# Remove existing dirs/links if present (to avoid conflicts)
rm -rf "$CONFIG_DIR/agents" "$CONFIG_DIR/commands" "$CONFIG_DIR/skills"

# Create symbolic links
ln -s "$HOME/.hz-agents/agents"   "$CONFIG_DIR/agents"
ln -s "$HOME/.hz-agents/commands" "$CONFIG_DIR/commands"
ln -s "$HOME/.hz-agents/skills"   "$CONFIG_DIR/skills"
```

## Step 4: Verify installation

```bash
ls -la "$CONFIG_DIR/agents" "$CONFIG_DIR/commands" "$CONFIG_DIR/skills"
```

Expected: 3 symlinks pointing to `~/.hz-agents/...`

## Step 5: Configure tool-specific settings

### If Claude Code (.claude/)

HZ-Agents uses multi-agent team features that require experimental flags and specific
settings. Create or merge into `.claude/settings.local.json`:

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "permissions": {
    "allow": []
  },
  "defaultMode": "bypassPermissions",
  "teammateMode": "tmux"
}
```

Explanation of each field:
- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`: "1" — Enables the experimental agent teams
  feature. REQUIRED for `/unify-dev`, `/unify-doc-review`, `/unify-fix` commands that
  orchestrate multiple agents in parallel.
- `defaultMode`: "bypassPermissions" — Allows agents to execute tools without manual
  approval on every action. Needed because agents run autonomously and cannot wait for
  user confirmation at each step.
- `teammateMode`: "tmux" — Runs each team member agent in a separate tmux pane so you
  can monitor all agents working in parallel in real-time.
- `permissions.allow`: [] — You can add specific tool patterns here to pre-approve
  (e.g. "Bash(npm run *)", "Read(**)"). Leave empty to use defaultMode as fallback.

IMPORTANT: If `.claude/settings.local.json` already exists, MERGE these keys into the
existing file. Do NOT overwrite the user's existing settings.

### If Codex (.codex/) or other tools

No additional settings file is needed. The symlinked agents/commands/skills directories
are sufficient. If the tool has its own team/agent configuration, follow that tool's
documentation.

## Step 6: Add to .gitignore (recommended)

Append to the project's .gitignore if not already present.
Use the actual CONFIG_DIR value you determined in Step 2:

```bash
grep -qxF "$CONFIG_DIR/agents" .gitignore 2>/dev/null || \
  echo -e "\n# HZ-Agents (symlinked)\n$CONFIG_DIR/agents\n$CONFIG_DIR/commands\n$CONFIG_DIR/skills" >> .gitignore
```

## Step 7: Check and install dependencies

HZ-Agents skills rely on external CLI tools. You MUST check which ones are missing and
ASK the user before installing anything. Do NOT silently install tools.

### Dependency table

| Dependency | Required by | What it does | Install command (macOS) |
|------------|-------------|--------------|------------------------|
| `python3` (3.10+) | create-docs (docs.py CLI) | Document management CLI | `brew install python` |
| `node` (18+) + `npm` | create-web, agent-browser | Frontend dev, browser automation | `brew install node` |
| `go` (1.25+) | Backend development | Go backend compilation | `brew install go` |
| `tmux` | Claude Code teammateMode | Multi-agent parallel panes | `brew install tmux` |
| `agent-browser` | agent-browser skill | Browser automation CLI | `npm install -g @anthropic/agent-browser` |
| `uvx` | desktop-control skill | Python tool runner (uv) | `brew install uv` |

### Detection and installation flow

1. **Detect OS**: Check if macOS (`uname -s` == "Darwin") or Linux.

2. **On macOS, check Homebrew first**:
```bash
if ! command -v brew &>/dev/null; then
  # Ask user: "Homebrew is not installed. It's needed to install dependencies.
  #            Install Homebrew? (https://brew.sh)"
  # If user agrees:
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
```

3. **Check each dependency and collect missing ones**:
```bash
MISSING=()
command -v python3 &>/dev/null || MISSING+=("python3")
command -v node &>/dev/null    || MISSING+=("node")
command -v go &>/dev/null      || MISSING+=("go")
command -v tmux &>/dev/null    || MISSING+=("tmux")
command -v agent-browser &>/dev/null || MISSING+=("agent-browser")
command -v uvx &>/dev/null     || MISSING+=("uvx")
```

4. **Present findings to user**:
   - List which dependencies are already installed (with versions)
   - List which are missing
   - Explain what each missing one is used for (reference the table above)
   - ASK: "Would you like me to install the missing dependencies?"
   - Let user choose which ones to install (they may not need all of them)

5. **Install only what the user approves** using the install commands from the table.

6. **After installation, verify**:
```bash
python3 --version
node --version
go version
tmux -V
agent-browser --version
uvx --version
```

IMPORTANT:
- NEVER install anything without asking first
- If on Linux, adapt install commands (apt, dnf, pacman, etc.)
- `agent-browser` and `desktop-control` are OPTIONAL — only needed if the user plans
  to use browser automation or desktop automation skills
- `go` is only needed if the project has a Go backend
- At minimum, `python3`, `node`, and `tmux` are recommended for core functionality

## Step 8: Confirm to user and explain how to use

After installation, you MUST:
1. Briefly explain what HZ-Agents is
2. ASK the user their role in the team
3. Based on their role, show the relevant commands and workflow

Use the user's language (Chinese if they spoke Chinese, English if English, etc.).

### 8.1 — Explain what HZ-Agents is

Tell the user:

> HZ-Agents is a multi-agent software development framework. 6 specialized AI agents
> (PM, Tech Lead, Frontend, Backend, UI Designer, QA) collaborate to build full-stack
> applications — from requirements planning to QA testing.

### 8.2 — Ask the user's role

Ask the user (use AskUserQuestion or equivalent):

> What is your role in the team?

Options:
- PM (Product Manager)
- Tech Lead
- UI Designer
- Frontend Developer
- Backend Developer
- QA Tester

### 8.3 — Show role-specific command guide

Based on the user's answer, show the corresponding section below:

#### If PM:

Your core command is `/review-pm` — create and review requirement documents.

```
/review-pm 新建需求：用户积分系统     # Create a new requirement
/review-pm 7                         # Review requirement #7
/review-pm 7 补充验收标准             # Add acceptance criteria to #7
/review-pm                           # Auto-scan, pick a requirement
```

After finishing, notify Tech Lead to run `/review-tech` and UI Designer to run `/review-ui`.

#### If Tech Lead:

Your core command is `/review-tech` — create technical designs and task breakdowns.

```
/review-tech 7                       # Create technical design for requirement #7
/review-tech 7 追加OAuth登录支持      # Update design: add OAuth support
/review-tech 7 缓存策略改用Redis      # Update design: switch to Redis cache
```

After finishing, notify Frontend to run `/dev-frontend` and Backend to run `/dev-backend`.

#### If UI Designer:

Your core command is `/review-ui` — produce design mockups and design systems.

```
/review-ui 7                         # Create UI design for requirement #7
/review-ui 7 按钮改成圆角风格         # Iterate: rounded button style
/review-ui 7 增加空状态和加载骨架屏    # Add empty state and skeleton screens
```

Deliverables: `ui/merge.html` (mockup), `ui/design.md` (design system), `ui/Resources/` (icons).

#### If Frontend Developer:

Your core command is `/dev-frontend` — implement frontend pages and interactions.

```
/dev-frontend 7                      # Implement all frontend tasks for #7
/dev-frontend 7 先实现登录页          # Start with the login page
/dev-frontend 7 只做表单验证部分      # Only do form validation
```

Note: Always use local resources from `ui/Resources/`, never external URLs.

#### If Backend Developer:

Your core command is `/dev-backend` — implement APIs and business logic.

```
/dev-backend 7                       # Implement all backend tasks for #7
/dev-backend 7 只做用户CRUD接口       # Only do user CRUD APIs
/dev-backend 7 先做数据库迁移         # Start with database migration
```

#### If QA Tester:

Your core command is `/review-qa` — run API + E2E acceptance tests.

```
/review-qa 7                         # Full test for requirement #7
/review-qa 7 重点测试并发和边界场景    # Focus on concurrency and edge cases
/review-qa 7 回归测试用户列表功能      # Regression test user list feature
```

### 8.4 — Show the unified orchestration commands and dependency chain

After the role-specific guide, ALWAYS also show:

**Unified orchestration commands** (coordinate multiple roles at once):

```
/unify-doc-review [req]    # PM + Tech Lead + UI collaborate on docs and design
/unify-dev [req]           # Full team: design → dev → code review → QA test
/unify-fix <description>   # Smart bug fix: auto-assemble repair team
```

**Command dependency chain** (the order commands should be run):

```
/review-pm ──┬── /review-tech ──┬── /dev-backend ──┐
             │                  │                  │
             └── /review-ui ────┼── /dev-frontend ─┤
                                │                  │
                                └──────────────────┴── /review-qa
```

**Recommended first step:**
If the project has no `docs/` directory yet, run `/unify-doc-review` to initialize.
The PM will discuss requirements with you, and the Tech Lead will plan the architecture.

**Updating HZ-Agents:**
```
cd ~/.hz-agents && git pull
```
All linked projects update automatically.

---

## Updating

To update HZ-Agents to the latest version, simply:

```bash
cd ~/.hz-agents && git pull
```

Because we use symlinks, all projects using HZ-Agents will automatically get the update.

AI-INSTRUCTION-END -->

### 自动安装（推荐）

直接告诉你的 AI 助手：

> 我要使用 https://github.com/LucaHhx/hz-agents

AI 会自动完成以下操作：
1. 将 hz-agents 克隆到 `~/.hz-agents/`
2. 自动识别你使用的工具（Claude Code / Codex / Cursor 等），创建对应的配置目录
3. 通过符号链接将 agents / commands / skills 链接到项目中
4. 配置工具所需的设置（如 Claude Code 的团队模式、权限等）
5. 添加 `.gitignore` 规则
6. 检测缺失的依赖工具（python3 / node / go / tmux / agent-browser 等），询问你是否安装

更新只需 `cd ~/.hz-agents && git pull`，所有项目自动生效。

### 手动安装

```bash
# 1. 克隆到 home 目录
git clone https://github.com/LucaHhx/hz-agents.git ~/.hz-agents

# 2. 在项目根目录创建符号链接
#    将 .claude 替换为你使用的工具对应的目录（.codex / .cursor 等）
cd your-project
mkdir -p .claude
ln -s ~/.hz-agents/agents   .claude/agents
ln -s ~/.hz-agents/commands .claude/commands
ln -s ~/.hz-agents/skills   .claude/skills
```

## 快速开始

安装完成后，在项目目录中启动 Claude Code 即可使用。

### 从零开始一个新项目

```bash
# 第一步：初始化文档
# PM 和 Tech Lead 会与你交互确认需求和技术方案
/unify-doc-review

# 第二步：启动团队开发第一个需求
/unify-dev 1-account-system

# 第三步：修复 Bug（可选）
/unify-fix 登录页在 iOS 上有额外滚动条
```

### 日常开发

```bash
# 统一调度 —— 多角色协作
/unify-doc-review 2-quick-bookkeeping   # 文档评审
/unify-dev 2-quick-bookkeeping          # 团队开发
/unify-fix 记账接口返回 500 错误        # Bug 修复

# 单角色 —— 精准控制单个 Agent
/review-pm 3-transaction-list           # PM 评审需求文档
/review-tech 3-transaction-list         # Tech Lead 制定技术方案
/review-ui 3-transaction-list           # UI 设计师产出设计稿
/dev-frontend 3-transaction-list        # 前端独立开发
/dev-backend 3-transaction-list         # 后端独立开发
/review-qa 3-transaction-list           # QA 执行测试
```

## 架构

### 6 个专业 Agent

| Agent | 角色 | 职责 |
|-------|------|------|
| `hz-pm` | 产品经理 | 需求规划、业务文档、任务拆分、验收标准 |
| `hz-tech-lead` | 技术负责人 | 架构设计、技术方案、代码审查、团队协调 |
| `hz-frontend` | 前端开发 | 页面实现、组件开发、UI 还原、状态管理 |
| `hz-backend` | 后端开发 | API 实现、数据库设计、业务逻辑、数据同步 |
| `hz-ui` | UI 设计师 | 设计稿产出（merge.html）、设计系统、视觉审查 |
| `hz-qa` | QA 测试 | API 测试、浏览器 E2E 测试、验收报告 |

### 9 个 Slash Command

命令分为两类：**统一调度**（多 Agent 协作）和**单角色**（独立执行）。

#### 统一调度命令

| 命令 | 说明 | 用法 |
|------|------|------|
| `/unify-doc-review` | 启动 PM + Tech Lead + UI 设计师协作完善文档和设计稿 | `/unify-doc-review [需求名称]` |
| `/unify-dev` | 启动 Tech Lead + UI + Frontend + Backend + QA 团队开发 | `/unify-dev [需求名称]` |
| `/unify-fix` | 诊断并修复 Bug，自动组建修复团队 | `/unify-fix <问题描述>` |

#### 单角色命令

| 命令 | 说明 | 用法 |
|------|------|------|
| `/review-pm` | PM 评审/完善需求业务文档，或新建需求 | `/review-pm [需求名称] [指令]` |
| `/review-tech` | Tech Lead 创建/更新技术方案和任务 | `/review-tech [需求名称] [指令]` |
| `/review-ui` | UI 设计师产出/更新设计稿和设计系统 | `/review-ui [需求名称] [指令]` |
| `/dev-frontend` | 前端开发实现前端代码 | `/dev-frontend [需求名称] [指令]` |
| `/dev-backend` | 后端开发实现后端代码 | `/dev-backend [需求名称] [指令]` |
| `/review-qa` | QA 执行 API + E2E 验收测试 | `/review-qa [需求名称] [指令]` |

### 开发流程

```
用户需求
  ↓
/unify-doc-review ─── PM 需求规划 + Tech Lead 架构设计 + UI 设计稿产出
  ↓
/unify-dev ────────── Frontend + Backend 并行开发
                        ↓
                      Tech Lead 代码审查 + UI 视觉审查
                        ↓
                      QA 测试（API + 浏览器 E2E）
  ↓
验收交付
```

**关键机制:**

- **文档检查是硬门槛** — `/unify-dev` 会先检查文档完整性，不通过则停止
- **代码审查 + UI 视觉审查并行** — Tech Lead 审代码质量，UI 设计师审视觉还原
- **审查不通过自动循环修复** — 创建修复任务 → 开发者修复 → 重新审查（上限 3 轮）
- **QA 测试两阶段** — 先 API 接口测试，再浏览器有头模式 E2E 测试

## 项目结构约定

使用本框架开发的项目遵循统一结构：

```
project/
├── .claude/
│   ├── agents/       # Agent 定义（从 hz-agents 复制）
│   ├── commands/     # Slash 命令（从 hz-agents 复制）
│   └── skills/       # 模块化能力（从 hz-agents 复制）
├── server/           # Go 后端
├── web/              # React 前端
└── docs/             # 三层文档
    ├── project.md         # L1 项目概述
    ├── tasks.md           # L1 需求列表
    ├── CHANGELOG.md       # 变更日志
    └── <N>-<需求名>/      # L2 需求目录
        ├── plan.md        # 需求计划 + 验收标准
        ├── tasks.md       # 功能任务列表
        ├── log.md         # 变更记录
        ├── backend/       # L3 后端技术文档 + 任务
        ├── frontend/      # L3 前端技术文档 + 任务
        ├── ui/            # L3 UI 设计稿 + 资源
        └── qa/            # L3 测试方案 + 任务
```

## 默认技术栈

| 层级 | 技术 |
|------|------|
| 后端 | Go 1.25+, Gin, GORM, SQLite, JWT, Viper, Zap |
| 前端 | React 19, TypeScript 5.9+, Vite 7+, Tailwind CSS 4+, Zustand, Axios |
| 桌面端 | Tauri 2.x (Rust) |
| 移动端 | Capacitor 8+ (iOS/Android) |

> 技术栈可在 `/unify-doc-review` 初始化阶段与 Tech Lead 讨论调整。

## Skills 能力模块

Skills 是可复用的能力组件，供各 Agent 按需调用。

| 分类 | Skill | 说明 |
|------|-------|------|
| **开发流程** | `create-docs` | 三层文档管理系统，含 `docs.py` CLI |
| | `brainstorming` | 需求探索与设计验证 |
| | `subagent-driven-development` | 子 Agent 驱动开发 + 两阶段代码审查 |
| **项目脚手架** | `create-web` | React + TypeScript 脚手架（20+ 组件模板） |
| | `tauri-v2` | Tauri 2 跨平台应用开发 |
| **UI/设计** | `ui-ux-pro-max` | 综合 UI/UX 设计系统（50+ 风格） |
| | `ios-glass-ui-designer` | iOS 玻璃材质设计规范 |
| | `tailwindcss-advanced-components` | Tailwind CSS 高级组件模式 |
| **自动化测试** | `agent-browser` | 无头/有头浏览器自动化 |
| | `desktop-control` | 桌面自动化控制（PyAutoGUI） |
| | `wda` | iOS WebDriverAgent 自动化 |
| | `pm-mcp-guide` | 后端服务进程管理 |
| **框架扩展** | `create-agent` | Agent 创建指南 |
| | `create-command` | Slash Command 创建指南 |
| | `create-skill` | Skill 创建指南 |
| | `find-skills` | Skill 发现与安装 |

## 目录结构

```
hz-agents/
├── agents/                              # 6 个 Agent 定义
│   ├── hz-pm.md                         # 产品经理
│   ├── hz-tech-lead.md                  # 技术负责人
│   ├── hz-frontend.md                   # 前端开发
│   ├── hz-backend.md                    # 后端开发
│   ├── hz-ui.md                         # UI 设计师
│   └── hz-qa.md                         # QA 测试
├── commands/                            # 9 个 Slash 命令
│   ├── unify-dev.md                     # [统一调度] 团队开发
│   ├── unify-doc-review.md              # [统一调度] 文档评审
│   ├── unify-fix.md                     # [统一调度] Bug 修复
│   ├── dev-frontend.md                  # [单角色] 前端开发
│   ├── dev-backend.md                   # [单角色] 后端开发
│   ├── review-pm.md                     # [单角色] PM 评审
│   ├── review-tech.md                   # [单角色] Tech Lead 评审
│   ├── review-ui.md                     # [单角色] UI 设计
│   └── review-qa.md                     # [单角色] QA 测试
└── skills/                              # 16 个模块化能力
    ├── create-docs/                     # 三层文档管理（含 CLI）
    ├── brainstorming/                   # 需求头脑风暴
    ├── subagent-driven-development/     # 子 Agent 驱动开发
    ├── create-web/                      # React 项目脚手架
    ├── tauri-v2/                        # Tauri 桌面应用
    ├── ui-ux-pro-max/                   # UI/UX 设计系统
    ├── ios-glass-ui-designer/           # iOS 原生设计
    ├── tailwindcss-advanced-components/ # Tailwind 组件库
    ├── agent-browser/                   # 浏览器自动化
    ├── desktop-control/                 # 桌面自动化
    ├── wda/                             # iOS 自动化
    ├── pm-mcp-guide/                    # 进程管理
    ├── create-agent/                    # Agent 创建框架
    ├── create-command/                  # 命令创建框架
    ├── create-skill/                    # Skill 创建框架
    └── find-skills/                     # Skill 发现
```

## 实际案例

### [Keep Account（记账本）](https://github.com/LucaHhx/keep-account)

一款由 HZ-Agents 全流程驱动开发的多端云同步记账应用。

- **产品定位** — 面向个人的极简记账工具，主打"3 秒记一笔账"
- **技术实现** — Go + Gin + SQLite / React 19 + Tailwind / Tauri 2
- **开发过程** — 8 个需求迭代，每个需求包含三层文档、代码评审和 QA 验证

### [GO PLUS（在线娱乐平台）](https://github.com/LucaHhx/go-plus)

> 声明：本项目仅用于测试 HZ-Agents 多智能体开发框架的能力，不用于任何商业运营或实际部署。

一款由 HZ-Agents 全流程驱动开发的在线娱乐平台测试项目，验证框架在中大型复杂项目中的编排能力。

- **测试目的** — 复杂 UI 设计稿精确还原、多需求并行推进、三期递进交付
- **技术实现** — Go + Gin + SQLite / React 19 + TypeScript + Tailwind / 管理后台独立部署
- **开发过程** — 第一期 6 个需求迭代，前端 1:1 还原 UI 设计图纸，完整的三层文档和质量门禁

## 许可证

Private
