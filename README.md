# HZ-Agents

多智能体软件开发编排框架 —— 协调 6 个专业化 Claude AI Agent 完成从需求到测试的全流程软件开发。

## 概述

HZ-Agents 是一个面向全栈软件开发的多 Agent 协作系统。它定义了标准化的技术栈、项目结构、开发流程和质量门禁，让 PM、Tech Lead、前端、后端、UI 设计师、QA 六个角色各司其职，自动化完成软件功能的交付。

## 核心特性

- **6 个专业 Agent** — PM 规划需求、Tech Lead 架构设计、前后端并行开发、UI 设计、QA 测试
- **固定技术栈** — 消除技术选型分歧，确保一致性
- **三层文档体系** — L1 项目级 / L2 需求级 / L3 技术级，自动化文档管理
- **质量门禁** — 文档审查 → 两阶段代码评审 → QA 自动化测试
- **18 个模块化 Skills** — 可复用的能力组件（UI 设计、浏览器自动化、桌面控制等）

## 技术栈约束

| 层级 | 技术 |
|------|------|
| 后端 | Go 1.25+, Gin, GORM, SQLite, JWT, Viper, Zap |
| 前端 | React 19, TypeScript 5.9+, Vite 7+, Tailwind CSS 4+, Zustand, Axios |
| 桌面端 | Tauri 2.x (Rust) |
| 移动端 | Capacitor 8+ (iOS/Android) |

## 目录结构

```
hz-agents/
├── agents/                    # Agent 定义
│   ├── hz-pm.md              # 产品经理
│   ├── hz-tech-lead.md       # 技术负责人
│   ├── hz-frontend.md        # 前端开发
│   ├── hz-backend.md         # 后端开发
│   ├── hz-ui.md              # UI 设计师
│   └── hz-qa.md              # QA 测试
├── commands/                  # Slash 命令
│   ├── dev-team.md           # 完整团队编排
│   ├── doc-review.md         # 文档审查
│   ├── fix.md                # Bug 修复流程
│   └── qa-test.md            # QA 测试执行
└── skills/                    # 模块化能力
    ├── create-docs/          # 三层文档管理 (含 CLI)
    ├── create-web/           # React 项目脚手架
    ├── tauri-v2/             # Tauri 桌面应用开发
    ├── ui-ux-pro-max/        # UI/UX 设计系统
    ├── agent-browser/        # 无头浏览器自动化
    ├── desktop-control/      # 桌面自动化 (PyAutoGUI)
    ├── subagent-driven-development/  # 子 Agent 驱动开发
    ├── brainstorming/        # 需求头脑风暴
    ├── create-agent/         # Agent 创建框架
    ├── create-command/       # 命令创建框架
    ├── create-skill/         # Skill 创建框架
    ├── find-skills/          # Skill 发现
    ├── pm-mcp-guide/         # 进程管理
    ├── wda/                  # iOS WebDriver 自动化
    ├── ios-glass-ui-designer/  # iOS 原生设计
    └── tailwindcss-advanced-components/  # Tailwind 组件库
```

## 开发流程

```
用户需求
  ↓
PM 需求规划 (头脑风暴 + 任务拆分)
  ↓
Tech Lead 架构设计 (创建 L3 目录 + 设计文档)
  ↓
前端 + 后端 并行开发
  ↓
Tech Lead 代码评审 (规格合规 → 代码质量)
  ↓
QA 测试 (API 测试 → 浏览器 E2E 测试)
  ↓
验收交付
```

## 项目结构约定

使用本框架开发的项目遵循统一结构:

```
project/
├── server/    # Go 后端
├── web/       # React 前端
└── docs/      # 三层文档
    ├── project.md
    ├── tasks.md
    ├── CHANGELOG.md
    └── <N>-<需求名>/
        ├── plan.md
        ├── tasks.md
        ├── log.md
        ├── backend/
        ├── frontend/
        ├── ui/
        └── qa/
```

## 命令使用指南

将 `commands/` 目录下的 `.md` 文件复制到目标项目的 `.claude/commands/` 目录即可注册为 Slash Command。

### `/dev-team` — 完整团队开发

启动 Tech Lead 协调的 5 人开发团队，按设计文档实现需求并验收。

```bash
# 开发指定需求
/dev-team 1-account-system

# 自动扫描待开发需求
/dev-team
```

**完整流程:**

```
1. Tech Lead 文档检查 ── 不通过 → 暂停，提示先完善文档
                          ↓ 通过
2. Frontend + Backend 并行开发
                          ↓
3. Tech Lead 代码审查 + UI 视觉审查 ── 不通过 → 回到步骤 2 修复
                          ↓ 通过
4. QA 测试（API 测试 + 浏览器有头模拟测试）
                          ↓
5. 汇总开发报告
```

**关键机制:**
- 文档检查是硬门槛 — 不通过直接停止，不创建团队
- 代码审查分两阶段 — 规格合规检查 + 代码质量检查
- Tech Lead 代码审查与 UI 视觉审查并行执行
- 审查不通过会创建修复任务，循环直到通过（上限 3 轮）
- QA 测试两阶段 — 先 API 接口测试，再浏览器 E2E 测试

### `/doc-review` — 文档协作评审

启动 PM + Tech Lead + UI 设计师团队，协作完善项目文档和设计稿。

```bash
# 评审指定需求文档
/doc-review 2-quick-bookkeeping

# 全量文档评审（含初始化）
/doc-review
```

**适用场景:**
- 项目尚未初始化 `docs/` 目录 — 自动进入"用户驱动的文档初始化"，PM 通过头脑风暴和用户确定需求，Tech Lead 和用户讨论技术选型
- 已有文档需要评审 — 三个 Agent 并行评审业务文档、技术文档，UI 设计师产出设计稿（merge.html）
- 评审发现问题会直接修复，而非仅列出问题清单

### `/fix` — 智能 Bug 修复

根据问题复杂度自动选择直接修复或组建团队。

```bash
/fix 登录页在 iOS 上有额外滚动条
/fix 记账接口返回 500 错误
/fix 前端显示金额与后端不一致
```

**自动判断修复路径:**

| 复杂度 | 判断条件 | 修复方式 |
|--------|----------|----------|
| 简单 | 改动 ≤3 文件、单端问题、根因明确 | 主 Agent 直接修复 |
| 复杂 | 改动 >3 文件、需多端协调、涉及架构 | 组建 Tech Lead + 开发者团队 |

**团队组建规则:**
- 前端问题 → tech-lead + frontend
- 后端问题 → tech-lead + backend
- 全栈联调 → tech-lead + frontend + backend
- P0 严重 Bug → 强制加入 QA 验证

所有修复都会自动生成 `docs/fixes/<N>-<slug>.md` 修复记录。

### `/qa-test` — QA 验收测试

以 QA 为主导的测试闭环，发现 Bug 后自动分配修复并回归测试。

```bash
# 测试指定需求
/qa-test 3-transaction-list

# 自动扫描可测试需求
/qa-test
```

**闭环流程:**

```
QA 执行验收测试 (API + 浏览器 E2E)
        ↓
    全部通过? ── YES → 输出验收报告，完成
        ↓ NO
QA 输出 Bug 报告 → PM 审查文档 + Tech Lead 分析根因
        ↓
Tech Lead 创建修复任务 → Frontend / Backend 并行修复
        ↓
QA 回归测试 → 回到 "全部通过?" 判断（上限 3 轮）
```

## Skills 能力模块

Skills 是可复用的能力组件，供各 Agent 按需调用。将 `skills/` 目录复制到目标项目的 `.claude/skills/` 即可使用。

### 开发流程类

| Skill | 说明 |
|-------|------|
| **create-docs** | 三层文档管理系统，含 `docs.py` CLI 工具。支持初始化项目文档 (`docs.py init`)、创建需求目录 (`docs.py req <name>`)、创建角色目录 (`docs.py role <req> <role>`)、更新任务状态 (`docs.py task`)、记录变更日志 (`docs.py log`) |
| **brainstorming** | 需求探索与设计验证。在实现前通过对话深入理解用户意图，细化需求、探索方案，输出完整的设计规格 |
| **subagent-driven-development** | 子 Agent 驱动开发。将实现计划拆分为独立任务，分派子 Agent 执行，包含两阶段代码审查（规格合规 → 代码质量） |

### 项目脚手架类

| Skill | 说明 |
|-------|------|
| **create-web** | React + TypeScript 项目脚手架。内含 20+ 生产级组件模板（图表、表单、布局、导航等），深色/浅色主题，响应式布局系统 |
| **tauri-v2** | Tauri 2 跨平台应用开发指南。涵盖配置管理 (`tauri.conf.json`)、Rust 命令实现、IPC 模式（invoke/emit/channel）、权限与能力管理、桌面和移动端构建部署 |

### UI/设计类

| Skill | 说明 |
|-------|------|
| **ui-ux-pro-max** | 综合 UI/UX 设计系统。50+ 设计风格、21+ 配色方案、50+ 字体搭配、20+ 图表类型，支持 9 种技术栈。涵盖 glassmorphism、minimalism、dark mode 等风格 |
| **ios-glass-ui-designer** | iOS 原生设计规范。基于 Apple 玻璃材质体系（半透明、模糊、景深），SF Pro 字体、安全区适配、系统组件行为，遵循 Apple HIG |
| **tailwindcss-advanced-components** | Tailwind CSS 高级组件模式。使用 CVA (Class Variance Authority) 管理组件变体，生产级的响应式、焦点状态、禁用状态处理 |

### 自动化测试类

| Skill | 说明 |
|-------|------|
| **agent-browser** | 无头/有头浏览器自动化。导航网页、点击元素、填写表单、截图、提取数据。QA 测试时使用 `--headed` 有头模式模拟真实用户操作 |
| **desktop-control** | 桌面自动化控制。基于 PyAutoGUI 实现鼠标/键盘控制、截图分析、窗口管理、应用程序操作 |
| **wda** | iOS WebDriverAgent 自动化。通过纯 HTTP API 直接控制 iOS 设备/模拟器，支持元素查找、点击、滑动、输入、截图、应用管理 |
| **pm-mcp-guide** | 进程管理 MCP。管理长期运行的后端服务生命周期，支持启动/停止服务、查看日志、搜索日志、编排服务启动顺序 |

### 框架扩展类

| Skill | 说明 |
|-------|------|
| **create-agent** | Agent 创建指南。定义自主子进程的结构、触发条件、系统提示词设计、模型选择 |
| **create-command** | Slash Command 创建指南。设计可复用的工作流命令，支持代码审查、PR 提交、CI 修复等模式 |
| **create-skill** | Skill 创建指南。设计模块化能力包，集成工具/API、打包领域专业知识和资源 |
| **find-skills** | Skill 发现与安装。搜索和安装开源 Agent 技能生态中的 Skill |

## 实际案例

### [Keep Account（记账本）](https://github.com/LucaHhx/keep-account)

一款由 HZ-Agents 全流程驱动开发的多端云同步记账应用，从需求规划、UI 设计、前后端开发到 QA 测试均由 6 个 Agent 协作完成。

- **产品定位** — 面向个人的极简记账工具，主打"3 秒记一笔账"
- **技术实现** — Go + Gin + SQLite 后端 / React 19 + Tailwind 前端 / Tauri 2 桌面和移动端
- **功能覆盖** — 快速记账、流水管理、财务报表（月度总览/分类占比/趋势分析）、分类管理、明暗主题
- **开发过程** — 完整经历了 8 个需求迭代（账户系统 → 快速记账 → 流水列表 → 数据报表 → 云同步 → 多端适配 → 部署流程 → 服务信息展示），每个需求都包含三层文档、代码评审和 QA 截图验证

该项目展示了 HZ-Agents 在真实产品开发中的完整能力：需求拆分、架构设计、并行开发、质量门禁和自动化测试。

### [GO PLUS（在线娱乐平台）](https://github.com/LucaHhx/go-plus)

> **声明：本项目仅用于测试 HZ-Agents 多智能体开发框架的能力，不用于任何商业运营或实际部署。**

一款由 HZ-Agents 全流程驱动开发的在线娱乐平台测试项目，从需求规划、UI 设计图纸还原、前后端开发到 QA 测试均由 6 个 Agent 协作完成。

- **测试目的** — 验证 HZ-Agents 在中大型复杂项目中的全流程编排能力，包括复杂 UI 设计稿精确还原、多需求并行推进和三期递进交付策略
- **技术实现** — Go + Gin + SQLite 后端 / React 19 + TypeScript + Tailwind 前端 / 管理后台独立部署
- **功能覆盖** — 用户系统（OTP/Google登录）、首页导航（内容流/侧边菜单/底部Tab）、游戏大厅（分类/筛选/搜索/收藏）、钱包支付（充值/提现/交易记录）、客服系统、管理后台
- **开发过程** — 三期递进交付（全部页面+mock → 真实业务接口 → 裂变生态），第一期包含 6 个需求迭代（用户系统 → 首页导航 → 游戏大厅 → 钱包支付 → 客服系统 → 管理后台），前端 1:1 还原 UI 设计图纸（merge.html），每个需求包含三层文档和完整的 L3 角色目录（backend/frontend/ui/qa）
- **项目特色** — 移动优先深色主题设计、多市场架构预留、核心交易链路优先交付、mock 数据渐进替换

该项目展示了 HZ-Agents 在复杂产品场景下的编排能力：大规模 UI 设计稿还原、6 个需求并行管理、三层文档体系和完整的质量门禁流程。

## 快速开始

### 1. 安装到目标项目

将 agents、commands、skills 复制到目标项目的 `.claude/` 目录:

```bash
# 在目标项目根目录下执行
mkdir -p .claude
cp -r /path/to/hz-agents/agents .claude/agents
cp -r /path/to/hz-agents/commands .claude/commands
cp -r /path/to/hz-agents/skills .claude/skills
```

### 2. 从零开始一个新项目

```bash
# 第一步: 初始化文档（PM 和 Tech Lead 会与你交互确认需求和技术方案）
/doc-review

# 第二步: 开发第一个需求
/dev-team 1-account-system

# 第三步: 验收测试
/qa-test 1-account-system
```

### 3. 日常开发流程

```bash
# 完善已有文档和设计稿
/doc-review 2-quick-bookkeeping

# 启动团队开发需求
/dev-team 2-quick-bookkeeping

# 修复 Bug
/fix 登录页在 iOS 上有额外滚动条

# 独立运行 QA 测试
/qa-test 2-quick-bookkeeping
```

## 许可证

Private
