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

## 实际案例

### [Keep Account（记账本）](https://github.com/LucaHhx/keep-account)

一款由 HZ-Agents 全流程驱动开发的多端云同步记账应用，从需求规划、UI 设计、前后端开发到 QA 测试均由 6 个 Agent 协作完成。

- **产品定位** — 面向个人的极简记账工具，主打"3 秒记一笔账"
- **技术实现** — Go + Gin + SQLite 后端 / React 19 + Tailwind 前端 / Tauri 2 桌面和移动端
- **功能覆盖** — 快速记账、流水管理、财务报表（月度总览/分类占比/趋势分析）、分类管理、明暗主题
- **开发过程** — 完整经历了 8 个需求迭代（账户系统 → 快速记账 → 流水列表 → 数据报表 → 云同步 → 多端适配 → 部署流程 → 服务信息展示），每个需求都包含三层文档、代码评审和 QA 截图验证

该项目展示了 HZ-Agents 在真实产品开发中的完整能力：需求拆分、架构设计、并行开发、质量门禁和自动化测试。

## 快速开始

1. 将 `agents/` 目录下的 Agent 配置到 Claude Code
2. 将 `commands/` 下的命令注册为 Slash Command
3. 使用 `/dev-team` 命令启动完整开发流程，或单独调用各角色 Agent

## 许可证

Private
