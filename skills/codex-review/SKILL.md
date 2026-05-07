---
name: codex-review
description: 用 codex CLI 做并行代码审查（只审不改）。触发场景：(1) 审查当前未提交代码 / 暂存改动；(2) 分支对比审查（branch A vs branch B、PR diff）；(3) 文件夹/路径下所有内容审查。关键词：codex 审查、codex review、并行审查、未提交审查、分支对比审查、目录审查、code review、PR 审查（除非明确要求 GitHub PR review）。本 skill 只用 codex 做审查，不允许 codex 编码或修改文件。
---

# Codex Review

## 核心约束（严格遵守）

1. **只审不改**：codex 必须用 `--sandbox read-only`。任何让 codex 写文件、改代码、跑构建的请求一律拒绝；那是 `dev-*` / `unify-fix` 等 skill 的职责。
2. **必须过滤输出**：`codex exec --json` 会吐出大量事件流，不过滤会爆上下文。**必须**走 `scripts/codex_review.sh`（已内置 `jq` 过滤），或在裸命令时手动加：
   ```
   | jq -r 'select(.item.type == "agent_message") | .item.text'
   ```
3. **默认并行 3 个**：相同审查指令并行启动 3 个 codex agent，再去重汇总。除非用户明确说"跑一次就行"或"跑 N 次"。
4. **必须设置 `--cd`**：codex 工作目录要明确指向被审查的仓库根，避免 codex 跑到错误目录。

## 工作流

### Step 1 — 确认审查范围

把用户请求映射到三种场景之一：

| 场景 | 触发关键词 | 必要参数 |
|---|---|---|
| 未提交审查 | "审一下当前改动 / 未提交 / staged / WIP / 这次的修改" | 仓库根目录 |
| 分支对比 | "审 PR / 对比 dev / `xxx` 分支相对 `yyy`" | `BASE`、`HEAD` 分支名，仓库根 |
| 路径审查 | "审 `server/service/foo/` / 这个目录 / 这个模块" | 目标路径，仓库根 |

如果用户没说清楚，**先问清楚**再启动 codex（codex 启动有成本，不要瞎跑）。

### Step 2 — 组装 prompt

打开 `references/prompts.md` 取对应模板，把占位符替换好。模板已经包含：

- 通用注入头（强调"只审不改"、按 🔴/🟡/🟢 分类输出）
- 场景专用上下文要求（git diff / 路径范围 / 关注点）
- 可选的"视角差异化"段，用来让 N 个 agent 互补

### Step 3 — 并行启动 codex

**默认开 3 个 Agent (subagent_type=general-purpose) 并行**，每个 agent 调用一次 `bash scripts/codex_review.sh`。在**同一条消息**里发出 3 个 Agent tool call 才能真正并行（不是顺序）。

每个 sub-agent 的 prompt 里要明确告诉它：

- 调用脚本的完整命令（`bash <skill-dir>/scripts/codex_review.sh -d <repo> -l agent-N -- '<prompt>'`）
- 把 codex 的整段输出原样返回，不要二次总结、不要省略
- 不需要它做任何代码修改

脚本路径取决于安装位置，常见为：
```
/Users/luca/.claude/skills/codex-review/scripts/codex_review.sh
```
（也可能解析成 `/Users/luca/github/LucaHhx/hz-agents/skills/codex-review/scripts/codex_review.sh`，两条路径等价。）

### Step 4 — 汇总

3 个 agent 全部返回后，按 `references/aggregation.md` 规则合并：

- 解析每条结论为 `(severity, file, line, desc, fix)`
- 按 `(file, line, desc 前缀)` 近似去重，多 agent 共同提到的标 `_(N agents)_`
- 严重度冲突取更高
- 按 🔴 / 🟡 / 🟢 分桶，文件名+行号排序
- 输出到用户

如果用户明确说"原样并列展示"，跳过去重，直接 `## Agent 1` / `## Agent 2` / `## Agent 3` 三段贴出来。

## 直接调用脚本（不通过 sub-agent 时）

少数情况下不需要并行（如用户说"审一下就行，不用并行"），可在主 agent 里直接 Bash 一次：

```
bash /Users/luca/.claude/skills/codex-review/scripts/codex_review.sh \
  -d /Users/luca/work/pp-game \
  -- '审查当前未提交代码，只审不改，按 🔴/🟡/🟢 分类'
```

脚本特性：

- `-d DIR` 透传给 codex `--cd`，**必填且为绝对路径**
- `-m MODEL` 选模型（默认 codex 自己挑）
- `-l LABEL` 给输出加前缀，并行时区分用
- 自动加 `--sandbox read-only`、`--json`、`jq` 过滤
- `prompt` 通过 `--` 之后的位置参数传，或 stdin 管道传

## 常见误用 / 坑

- ❌ 不加 jq 过滤直接 `codex exec --json`：事件流刷屏，会瞬间吃掉几千行上下文。
- ❌ 让 codex "顺便修一下"：本 skill 不允许，要修改请退出 skill 用 `dev-backend` / `unify-fix`。
- ❌ 并行 3 个 agent 但没在同一条消息里发出 3 个 tool call：会变成串行，慢 3 倍。
- ❌ `--cd` 用相对路径 / 省略：codex 可能跑在意外目录上，审错文件。
- ❌ 直接把 codex 输出贴给用户：必须先按 `references/aggregation.md` 去重分类，否则同一处问题会被列 3 次。

## 文件索引

- `scripts/codex_review.sh` — 封装 codex exec + jq 过滤的 bash 脚本
- `references/prompts.md` — 三种场景的 prompt 模板 + 通用注入头
- `references/aggregation.md` — 多 agent 结果去重和分类规则
