# HZ-Agents

多智能体软件开发编排框架 —— 基于 [Claude Code](https://docs.anthropic.com/en/docs/claude-code) 的 Agents / Commands / Skills 体系，协调 6 个专业化 AI Agent 完成从需求到测试的全流程软件开发。

## 概述

HZ-Agents 是一个面向全栈软件开发的多 Agent 协作系统。它定义了标准化的技术栈、项目结构、开发流程和质量门禁，让 PM、Tech Lead、前端、后端、UI 设计师、QA 六个角色各司其职，自动化完成软件功能的交付。

**核心特性:**

- **6 个专业 Agent** — PM 规划需求、Tech Lead 架构设计、前后端并行开发、UI 设计、QA 测试
- **14 个 Slash Command** — 4 个统一调度 + 1 个团队调度 + 6 个单角色 + 3 个工具命令
- **19 个模块化 Skills** — 可复用的能力组件（项目管理、文档管理、代码生成、UI 设计、数据库操作等）
- **三层文档体系** — L1 项目级 / L2 需求级 / L3 技术级，自动化文档管理
- **项目模板** — 基于 [hz-admin-base](https://github.com/LucaHhx/hz-admin-base.git)（GVA 框架），一键初始化后台管理项目
- **多端项目支持** — server + web（Vue 3 管理后台）+ client（React 客户端），按需组合
- **质量门禁** — 文档审查 → 代码评审 + 视觉审查 → QA 自动化测试

## 前置要求

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) 已安装（或其他支持 `.claude/` 目录结构的 AI 编程工具）
- Python 3.10+（文档 CLI 工具需要）
- Node.js 18+（前端开发和浏览器自动化需要）
- Go 1.25+（后端开发需要）

## 安装

<!-- AI-INSTRUCTION-START
==========================================================================
  AI AGENT SETUP INSTRUCTIONS (for Claude Code / Codex / Cursor / etc.)
==========================================================================

When a user asks you to install, use, or UPDATE HZ-Agents, follow the
instructions below. First determine which scenario applies:

## Scenario A: UPDATE (user wants to update an existing installation)

Trigger keywords: "更新", "update", "upgrade", "pull latest", "同步最新",
or user provides a URL like:
  - https://github.com/LucaHhx/hz-agents
  - https://github.com/LucaHhx/hz-agents/tree/hz-project
  - https://github.com/LucaHhx/hz-agents/blob/hz-project/README.md

### How to update:

1. **Parse branch from URL** (same rules as install):
   - `/tree/<branch>` or `/blob/<branch>/...` → extract that branch
   - No branch in URL → default to "main"

2. **Pull latest code**:
```bash
cd "$HOME/.hz-agents" && git fetch origin && git checkout "$BRANCH" && git pull
```

3. **Verify symlinks still work**:
```bash
# Auto-detect config dir
CONFIG_DIR=""
for dir in .claude .codex .cursor; do
  if [ -d "$dir" ]; then CONFIG_DIR="$dir"; break; fi
done

if [ -n "$CONFIG_DIR" ]; then
  ls -la "$CONFIG_DIR/agents" "$CONFIG_DIR/commands" "$CONFIG_DIR/skills"
fi
```

4. **If symlinks are broken or missing**, re-create them:
```bash
rm -rf "$CONFIG_DIR/agents" "$CONFIG_DIR/commands" "$CONFIG_DIR/skills"
ln -s "$HOME/.hz-agents/agents"   "$CONFIG_DIR/agents"
ln -s "$HOME/.hz-agents/commands" "$CONFIG_DIR/commands"
ln -s "$HOME/.hz-agents/skills"   "$CONFIG_DIR/skills"
```

5. **Report to user**: Tell them what changed (new commands, updated agents, etc.)
   and remind them the update is effective immediately for all linked projects.

That's it for updates. No need to re-run the full install flow.

---

## Scenario B: FRESH INSTALL (user wants to install for the first time)

Trigger: user says "I want to use hz-agents", "安装 hz-agents", etc.
Follow these steps EXACTLY:

## Step 1: Parse the URL and clone hz-agents

IMPORTANT: The user may provide a URL that includes a branch path, such as:
  - https://github.com/LucaHhx/hz-agents/tree/hz-project     → branch = "hz-project"
  - https://github.com/LucaHhx/hz-agents/tree/main            → branch = "main"
  - https://github.com/LucaHhx/hz-agents/blob/hz-project/README.md → branch = "hz-project"
  - https://github.com/LucaHhx/hz-agents                      → branch = default (main)

You MUST extract the branch name from the URL if `/tree/<branch>` or `/blob/<branch>/` is present.

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
| `node` (18+) + `npm` | Frontend dev, browser automation | Frontend and tooling | `brew install node` |
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

## Step 8: Confirm to user and show quick start

After installation, you MUST:
1. Briefly explain what HZ-Agents is
2. Show the quick start workflow below

Tell the user:

> HZ-Agents 已安装完成！这是一个多智能体软件开发框架，6 个专业 AI Agent（PM、Tech Lead、前端、后端、UI 设计师、QA）协作完成全栈应用开发。

Show the quick start:

```
新项目？从这里开始：
  /hz-init                          # 从 hz-admin-base 模板创建项目

已有项目？从这里开始：
  /unify-doc-review                 # 初始化文档 + 团队评审
  /unify-dev <需求名>                # 全团队协作开发
```

Show the full command reference:

```
统一调度（多 Agent 协作）:
  /unify-doc-review [需求名]         # PM + Tech Lead + UI 文档协作评审
  /review-all [需求名]               # PM + Tech Lead + UI 三端对齐
  /unify-dev [需求名]                # 全团队开发（开发 + 视觉审查 + QA）
  /unify-fix <问题描述>              # 自动诊断修复 Bug

团队调度:
  /dev-tech [需求名]                 # Tech Lead 带队开发 + 代码审查

单角色:
  /review-pm [需求名]                # PM 评审需求文档
  /review-tech [需求名]              # Tech Lead 技术方案
  /review-ui [需求名]                # UI 设计师设计稿
  /dev-frontend [需求名]             # 前端开发
  /dev-backend [需求名]              # 后端开发
  /review-qa [需求名]                # QA 验收测试

工具:
  /hz-init [项目名]                  # 交互式项目初始化
  /cmd-autocode                     # AutoCode 代码生成向导
  /hz-agents-update                 # 更新 hz-agents 并修复链接
```

更新只需：`/hz-agents-update`，自动拉取最新代码并修复符号链接，所有项目自动生效。

---

## Updating

To update HZ-Agents to the latest version:

```
/hz-agents-update
```

Or manually: `cd ~/.hz-agents && git pull`

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
6. 检测缺失的依赖工具，询问是否安装

更新只需 `cd ~/.hz-agents && git pull`，所有项目自动生效。

### 手动安装

```bash
# 1. 克隆到 home 目录
git clone https://github.com/LucaHhx/hz-agents.git ~/.hz-agents

# 2. 在项目根目录创建符号链接
cd your-project
mkdir -p .claude
ln -s ~/.hz-agents/agents   .claude/agents
ln -s ~/.hz-agents/commands .claude/commands
ln -s ~/.hz-agents/skills   .claude/skills
```

## 快速开始

### 创建新项目（推荐）

```bash
# 使用 /hz-init 从 hz-admin-base 模板创建项目
# 交互式选择项目形态、数据库、技术栈
/hz-init my-project
```

`/hz-init` 会引导你完成：
1. 选择项目形态（纯后台 / 后台+客户端 / 纯API）
2. 从 hz-admin-base 模板拉取代码
3. 定制化配置（数据库、JWT、日志前缀等）
4. 链接 hz-agents
5. 与 PM 协作定义业务需求

### 已有项目接入

```bash
# 第一步：初始化文档（PM 和 Tech Lead 会与你交互确认需求和技术方案）
/unify-doc-review

# 第二步：启动团队开发（两种方式任选）
/unify-dev 1-user-system              # 完整流程：开发 + 视觉审查 + QA
/dev-tech 1-user-system               # 轻量开发：Tech Lead 带队 + 代码审查

# 第三步：修复 Bug（可选）
/unify-fix 登录页在 iOS 上有额外滚动条
```

### 日常开发

```bash
# 统一调度 —— 多角色协作
/unify-doc-review 2-order-module      # 文档评审
/review-all 2-order-module            # 三端对齐
/unify-dev 2-order-module             # 团队开发
/unify-fix 订单接口返回 500           # Bug 修复

# 团队开发 —— Tech Lead 带队
/dev-tech 3-payment 先实现支付接口     # 带指令

# 单角色 —— 精准控制
/review-pm 新建需求：积分系统          # PM 新建需求
/review-tech 3-payment                # Tech Lead 技术方案
/review-ui 3-payment                  # UI 设计师设计稿
/dev-frontend 3-payment               # 前端独立开发
/dev-backend 3-payment                # 后端独立开发
/review-qa 3-payment                  # QA 测试

# 代码生成 —— AutoCode
/cmd-autocode                         # 交互式 CRUD 代码生成
```

## 架构

### 6 个专业 Agent

| Agent | 角色 | 职责 |
|-------|------|------|
| `hz-pm` | 产品经理 | 需求规划、业务文档、任务拆分、验收标准 |
| `hz-tech-lead` | 技术负责人 | 架构设计、技术方案、代码审查、团队协调 |
| `hz-frontend` | 前端开发 | 页面实现、组件开发、UI 还原、多端任务路由 |
| `hz-backend` | 后端开发 | API 实现、数据库设计、业务逻辑 |
| `hz-ui` | UI 设计师 | 设计稿产出（merge.html）、设计系统、视觉审查 |
| `hz-qa` | QA 测试 | API 测试、浏览器 E2E 测试、验收报告 |

### 14 个 Slash Command

#### 统一调度命令

| 命令 | 说明 | 用法 |
|------|------|------|
| `/unify-doc-review` | PM + Tech Lead + UI 协作完善文档和设计 | `/unify-doc-review [需求名]` |
| `/unify-dev` | Tech Lead + UI + Frontend + Backend + QA 团队开发 | `/unify-dev [需求名]` |
| `/unify-fix` | 诊断并修复 Bug，自动组建修复团队 | `/unify-fix <问题描述>` |
| `/review-all` | PM + Tech Lead + UI 三端文档对齐评审 | `/review-all [需求名]` |

#### 团队调度命令

| 命令 | 说明 | 用法 |
|------|------|------|
| `/dev-tech` | Tech Lead 带队前后端开发 + 代码审查 | `/dev-tech [需求名] [指令]` |

#### 单角色命令

| 命令 | 说明 | 用法 |
|------|------|------|
| `/review-pm` | PM 评审/完善需求业务文档 | `/review-pm [需求名] [指令]` |
| `/review-tech` | Tech Lead 创建/更新技术方案 | `/review-tech [需求名] [指令]` |
| `/review-ui` | UI 设计师产出/更新设计稿 | `/review-ui [需求名] [指令]` |
| `/dev-frontend` | 前端开发实现代码 | `/dev-frontend [需求名] [指令]` |
| `/dev-backend` | 后端开发实现代码 | `/dev-backend [需求名] [指令]` |
| `/review-qa` | QA 执行验收测试 | `/review-qa [需求名] [指令]` |

#### 工具命令

| 命令 | 说明 | 用法 |
|------|------|------|
| `/hz-init` | 交互式项目初始化（从模板创建） | `/hz-init [项目名]` |
| `/cmd-autocode` | AutoCode CRUD 代码生成向导 | `/cmd-autocode` |
| `/hz-agents-update` | 更新 hz-agents 并修复符号链接 | `/hz-agents-update` |

### 开发流程

```
需求输入
  ↓
/hz-init ──────────── 新项目初始化（可选，仅首次）
  ↓
/unify-doc-review ─── PM 需求规划 + Tech Lead 架构 + UI 设计稿
  ↓
/review-all ────────── PM + Tech Lead + UI 三端对齐（可选）
  ↓
  ├─ 路径 A（完整流程）:
  │  /unify-dev ────── Frontend + Backend 并行开发
  │                      ↓
  │                    Tech Lead 代码审查 + UI 视觉审查（并行）
  │                      ↓
  │                    QA 测试（API + 浏览器 E2E）
  │
  └─ 路径 B（轻量开发）:
     /dev-tech ──────── Frontend + Backend 并行开发
                          ↓
                        Tech Lead 代码审查（最多 3 轮）
                          ↓
                        可选: /review-qa 单独跑测试
  ↓
验收交付
```

**两条开发路径对比:**

| | `/unify-dev`（完整） | `/dev-tech`（轻量） |
|---|---|---|
| 参与角色 | TL + FE + BE + UI + QA | TL + FE + BE |
| UI 视觉审查 | 有 | 无 |
| QA 测试 | 自动执行 | 需手动 `/review-qa` |
| 适用场景 | 完整需求交付 | 快速迭代 |

## 项目结构

### 三种项目形态

```bash
# A: 纯后台管理系统（默认）
project/
├── server/        # Go 后端（hab 框架）
├── web/           # Vue 3 + Element Plus 管理后台
├── docs/          # 三层文档
└── .claude/       # hz-agents 链接

# B: 后台 + 客户端
project/
├── server/        # Go 后端
├── web/           # Vue 3 管理后台
├── client/        # React 19 客户端前端
├── docs/          # 三层文档
└── .claude/

# C: 纯 API 服务
project/
├── server/        # Go 后端
├── docs/          # 三层文档
└── .claude/
```

### 三层文档体系

```
docs/
├── project.md              # L1 项目概述
├── tasks.md                # L1 需求列表
├── CHANGELOG.md            # 变更日志
└── <N>-<需求名>/            # L2 需求目录
    ├── plan.md             # 需求计划 + 验收标准
    ├── tasks.md            # 功能任务列表
    ├── log.md              # 变更记录
    ├── backend/            # L3 后端技术文档 + 任务
    ├── frontend/           # L3 前端技术文档 + 任务
    ├── ui/                 # L3 UI 设计稿 + 资源
    └── qa/                 # L3 测试方案 + 任务
```

### 多端项目任务路由

当项目同时包含 `web/` 和 `client/` 时，前端任务通过标签路由：

| 标签 | 代码目录 | 技术栈 |
|------|---------|--------|
| `[web]` | `web/` | Vue 3 + Element Plus |
| `[client]` | `client/` | React 19 + Tailwind CSS |
| 无标签 | 根据项目结构自动判断 | — |

## 默认技术栈

| 层级 | 技术 |
|------|------|
| 后端 | Go 1.25+, Gin, GORM, SQLite/MySQL/PostgreSQL, JWT, Viper, Zap |
| 管理后台（web/） | Vue 3, Element Plus, Pinia, Vue Router, Vite |
| 客户端前端（client/） | React 19, TypeScript 5.9+, Vite 7+, Tailwind CSS 4+, Zustand |
| 桌面端 | Tauri 2.x (Rust) |
| 移动端 | Capacitor 8+ (iOS/Android) |

> 项目模板基于 [hz-admin-base](https://github.com/LucaHhx/hz-admin-base.git)（GVA 框架定制版），后端统一使用 `hab` module 和 `HAB_` 变量前缀。

## Skills 能力模块

| 分类 | Skill | 说明 |
|------|-------|------|
| **项目管理** | `hz-project` | 项目全生命周期管理知识库（10 个模块） |
| | `create-docs` | 三层文档管理系统，含 `docs.py` CLI |
| | `brainstorming` | 需求探索与设计验证 |
| **代码生成** | `hab-autocode` | AutoCode API 操作指南（CRUD 模块生成） |
| | `subagent-driven-development` | 子 Agent 驱动开发 + 代码审查 |
| **UI/设计** | `ui-ux-pro-max` | 综合 UI/UX 设计系统（50+ 风格） |
| | `ios-glass-ui-designer` | iOS 玻璃材质设计规范 |
| | `tailwindcss-advanced-components` | Tailwind CSS 高级组件模式 |
| **数据库** | `mysql-operator` | MySQL 数据库操作 |
| | `redis-operator` | Redis 缓存操作 |
| **自动化** | `agent-browser` | 无头/有头浏览器自动化 |
| | `desktop-control` | 桌面自动化控制 |
| | `wda` | iOS WebDriverAgent 自动化 |
| | `ios-device-automation` | iOS 设备视觉自动化 |
| | `pm-mcp-guide` | 后端服务进程管理 |
| **跨平台** | `tauri-v2` | Tauri 2 桌面应用开发 |
| **框架扩展** | `create-agent` | Agent 创建指南 |
| | `create-command` | Command 创建指南 |
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
├── commands/                            # 14 个 Slash 命令
│   ├── unify-dev.md                     # [统一调度] 团队开发
│   ├── unify-doc-review.md              # [统一调度] 文档评审
│   ├── unify-fix.md                     # [统一调度] Bug 修复
│   ├── review-all.md                    # [统一调度] 三端对齐
│   ├── dev-tech.md                      # [团队调度] Tech Lead 带队
│   ├── dev-frontend.md                  # [单角色] 前端开发
│   ├── dev-backend.md                   # [单角色] 后端开发
│   ├── review-pm.md                     # [单角色] PM 评审
│   ├── review-tech.md                   # [单角色] Tech Lead 评审
│   ├── review-ui.md                     # [单角色] UI 设计
│   ├── review-qa.md                     # [单角色] QA 测试
│   ├── hz-init.md                       # [工具] 项目初始化
│   ├── cmd-autocode.md                  # [工具] 代码生成向导
│   └── hz-agents-update.md             # [工具] 框架更新
└── skills/                              # 19 个模块化能力
    ├── hz-project/                      # 项目全生命周期管理
    │   ├── SKILL.md                     # 索引入口
    │   ├── modules/                     # 10 个知识模块
    │   └── references/                  # 参考文件
    ├── create-docs/                     # 三层文档管理（含 CLI）
    ├── brainstorming/                   # 需求头脑风暴
    ├── hab-autocode/                    # AutoCode 代码生成
    ├── subagent-driven-development/     # 子 Agent 驱动开发
    ├── ui-ux-pro-max/                   # UI/UX 设计系统
    ├── ios-glass-ui-designer/           # iOS 原生设计
    ├── tailwindcss-advanced-components/ # Tailwind 组件库
    ├── mysql-operator/                  # MySQL 操作
    ├── redis-operator/                  # Redis 操作
    ├── agent-browser/                   # 浏览器自动化
    ├── desktop-control/                 # 桌面自动化
    ├── wda/                             # iOS 自动化
    ├── pm-mcp-guide/                    # 进程管理
    ├── tauri-v2/                        # Tauri 桌面应用
    ├── create-agent/                    # Agent 创建框架
    ├── create-command/                  # 命令创建框架
    ├── create-skill/                    # Skill 创建框架
    └── find-skills/                     # Skill 发现
```

## 实际案例

### [GO PLUS（在线娱乐平台）](https://github.com/LucaHhx/go-plus)

> 声明：本项目仅用于测试 HZ-Agents 多智能体开发框架的能力，不用于任何商业运营或实际部署。

验证框架在中大型复杂项目中的编排能力。多端架构：Go 后端 + React 客户端 + Vue 3 管理后台。

### [Keep Account（记账本）](https://github.com/LucaHhx/keep-account)

由 HZ-Agents 全流程驱动开发的多端云同步记账应用。8 个需求迭代，完整三层文档 + 代码评审 + QA 验证。

## 许可证

Private
