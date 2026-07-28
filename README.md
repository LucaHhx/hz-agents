# HZ-Agents

多智能体软件开发编排框架 —— 基于 [Claude Code](https://docs.anthropic.com/en/docs/claude-code) 的 Agents / Commands / Skills 体系，协调 6 个专业化 AI Agent 完成从需求到测试的全流程软件开发。

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
  - https://github.com/LucaHhx/hz-agents/tree/main

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
  - https://github.com/LucaHhx/hz-agents/tree/main            → branch = "main"
  - https://github.com/LucaHhx/hz-agents/tree/main            → branch = "main"
  - https://github.com/LucaHhx/hz-agents/blob/main/README.md       → branch = "main"
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
  feature. REQUIRED for `/team-dev`, `/team-docs`, `/unify-fix` commands that
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
  /team-docs                 # 初始化文档 + 团队评审
  /team-dev <需求名>                # 全团队协作开发
```

Show the full command reference:

```
统一调度（多 Agent 协作）:
  /team-docs [需求名]         # PM + Tech Lead + UI 文档协作评审
  /review-all [需求名]               # PM + Tech Lead + UI 三端对齐
  /team-dev [需求名]                # 全团队开发（开发 + 视觉审查 + QA）
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

## 两种使用模式

HZ-Agents 提供两种使用方式，覆盖不同的开发场景：

- **团队模式** — 一条命令启动多 Agent 自动协作，适合完整需求交付
- **命令拆分模式** — 逐个调用单角色命令，精确控制每一步，适合调试、补充或局部工作

### 选择指南

| 维度 | 团队模式 | 命令拆分模式 |
|------|---------|------------|
| 起点 | `/hz-init` → `/team-docs` | `/hz-init` → `/review-pm` |
| 典型场景 | 新功能端到端交付 | 修一个组件、补一份文档 |
| 控制粒度 | 自动编排 | 手动逐步 |
| 参与 Agent | 2–5 个自动协调 | 每次 1 个 |
| 示例 | `/team-dev 1-login` | `/dev-backend 1-login` |
| 适合 | 首次使用、完整交付 | 熟练用户、调试定位 |

---

## 团队模式

多 Agent 自动协作，按阶段分组：

### 初始化

| 命令 | 说明 | 参与角色 |
|------|------|---------|
| `/hz-init [项目名]` | 交互式创建项目（模板拉取、环境检查、数据库初始化） | — |

### 文档阶段

| 命令 | 说明 | 参与角色 |
|------|------|---------|
| `/team-docs [需求名]` | PM + Tech Lead + UI 协作完善文档和设计 | PM、TL、UI |
| `/review-all [需求名]` | 三端文档对齐评审（需已有文档） | PM、TL、UI |

### 开发阶段

| 命令 | 说明 | 参与角色 |
|------|------|---------|
| `/team-dev [需求名]` | 全团队开发：编码 + 视觉审查 + QA | TL、FE、BE、UI、QA |
| `/dev-tech [需求名] [指令]` | 轻量团队开发：编码 + 代码审查 | TL、FE、BE |

**`/team-dev` vs `/dev-tech` 对比：**

| | `/team-dev`（完整） | `/dev-tech`（轻量） |
|---|---|---|
| 参与角色 | TL + FE + BE + UI + QA | TL + FE + BE |
| UI 视觉审查 | 有 | 无 |
| QA 测试 | 自动执行 | 需手动 `/review-qa` |
| 适用场景 | 完整需求交付 | 快速迭代 |

### 修复阶段

| 命令 | 说明 | 参与角色 |
|------|------|---------|
| `/unify-fix <问题描述>` | 自动诊断问题，动态组建修复团队 | 按需分配 |

---

## 命令拆分模式

逐个调用单角色命令，可按任意顺序组合：

### 初始化

```
/hz-init [项目名]       # 交互式创建项目（模板拉取、环境检查、数据库初始化）
```

### 文档评审

```
/review-pm [需求名]     # PM 评审/完善需求业务文档
/review-tech [需求名]   # Tech Lead 创建/更新技术方案
/review-ui [需求名]     # UI 设计师产出/更新设计稿
```

推荐顺序：`/hz-init` → `/review-pm` → `/review-tech` → `/review-ui`

### 开发

```
/dev-frontend [需求名]  # 前端开发实现代码
/dev-backend [需求名]   # 后端开发实现代码
```

前后端可并行执行，互不依赖。

### 测试

```
/review-qa [需求名]     # QA 执行 API + E2E 验收测试
```

### 自定义工作流示例

```bash
# 从零开始的完整拆分流程
/hz-init my-project
/review-pm 1-payment → /review-tech 1-payment → /review-ui 1-payment
  → /dev-frontend 1-payment + /dev-backend 1-payment
  → /review-qa 1-payment

# 只补后端 + 跑测试
/dev-backend 1-user-system
/review-qa 1-user-system

# 只更新设计稿 + 重新做前端
/review-ui 2-order-module
/dev-frontend 2-order-module
```

---

## 工作流程图

```
/hz-init（项目初始化）
  │
  ├─ 团队模式 ─────────────────────────────────────────────
  │  /team-docs → /review-all（可选）→ /team-dev 或 /dev-tech
  │                                              ↓
  │                                         /unify-fix（按需）
  │
  └─ 拆分模式 ─────────────────────────────────────────────
     /review-pm → /review-tech → /review-ui
       → /dev-frontend + /dev-backend（可并行）
       → /review-qa
```

---

## 安装

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code)（或其他支持 `.claude/` 目录结构的 AI 编程工具）
- Python 3.10+、Node.js 18+、Go 1.25+（按项目需要）

### 自动安装（推荐）

直接告诉你的 AI 助手：

> 我要使用 https://github.com/LucaHhx/hz-agents

AI 会自动完成克隆、符号链接、配置和依赖检测。更新只需 `/hz-agents-update`。

### 手动安装

```bash
git clone https://github.com/LucaHhx/hz-agents.git ~/.hz-agents
cd your-project && mkdir -p .claude
ln -s ~/.hz-agents/agents .claude/agents && ln -s ~/.hz-agents/commands .claude/commands && ln -s ~/.hz-agents/skills .claude/skills
```

---

## 工具命令

| 命令 | 说明 | 用法 |
|------|------|------|
| `/hz-init` | 从 hz-admin-base 模板交互式创建项目 | `/hz-init [项目名]` |
| `/cmd-autocode` | AutoCode CRUD 代码生成向导 | `/cmd-autocode` |
| `/hz-agents-update` | 更新 hz-agents 并修复符号链接 | `/hz-agents-update` |

---

## 6 个专业 Agent

| Agent | 角色 | 职责 |
|-------|------|------|
| `hz-pm` | 产品经理 | 需求规划、业务文档、任务拆分、验收标准 |
| `hz-tech-lead` | 技术负责人 | 架构设计、技术方案、代码审查、团队协调 |
| `hz-frontend` | 前端开发 | 页面实现、组件开发、UI 还原、多端任务路由 |
| `hz-backend` | 后端开发 | API 实现、数据库设计、业务逻辑 |
| `hz-ui` | UI 设计师 | 设计稿产出（merge.html）、设计系统、视觉审查 |
| `hz-qa` | QA 测试 | API 测试、浏览器 E2E 测试、验收报告 |

---

<details>
<summary>项目结构 & 技术栈</summary>

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

### 默认技术栈

| 层级 | 技术 |
|------|------|
| 后端 | Go 1.25+, Gin, GORM, SQLite/MySQL/PostgreSQL, JWT, Viper, Zap |
| 管理后台（web/） | Vue 3, Element Plus, Pinia, Vue Router, Vite |
| 客户端前端（client/） | React 19, TypeScript 5.9+, Vite 7+, Tailwind CSS 4+, Zustand |
| 桌面端 | Tauri 2.x (Rust) |
| 移动端 | Capacitor 8+ (iOS/Android) |

> 项目模板基于 [hz-admin-base](https://github.com/LucaHhx/hz-admin-base.git)（GVA 框架定制版），后端统一使用 `hab` module 和 `HAB_` 变量前缀。

</details>

<details>
<summary>Skills 能力模块（19 个）</summary>

| 分类 | Skill | 说明 |
|------|-------|------|
| **项目管理** | `create-docs` | 三层文档管理系统，含 `docs.py` CLI |
| | `brainstorming` | 真实需求理解与方案推荐 |
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

</details>

---

## 实际案例

### [GO PLUS（在线娱乐平台）](https://github.com/LucaHhx/go-plus)

> 声明：本项目仅用于测试 HZ-Agents 多智能体开发框架的能力，不用于任何商业运营或实际部署。

验证框架在中大型复杂项目中的编排能力。多端架构：Go 后端 + React 客户端 + Vue 3 管理后台。

### [Keep Account（记账本）](https://github.com/LucaHhx/keep-account)

由 HZ-Agents 全流程驱动开发的多端云同步记账应用。8 个需求迭代，完整三层文档 + 代码评审 + QA 验证。

## 许可证

Private
