---
name: pp-game-integration
description: PP（Pragmatic Play）机台对接专用工作流。**仅在用户明确表达对接意图时触发**：(1) 给出 PP tableId（小写字母+数字，通常 8-32 字符）并要求对接；(2) 明说"PP 机台对接" / "走 PP 对接流程"；(3) 查询/复用本仓库 PP 机台对接经验。覆盖 baccarat / roulette / sweetbonanza / megaroulette / oneblackjack / poweruproulette / dragontiger 等 PP 全协议族。**不在范围**：单纯讨论 PP 协议字段、其他供应商（PG/JILI/CQ9）、纯代码 review。触发后自主 9 phase 推进；详细停下问用户的边界 / 决策原则 / 工作流见 body 与 references/。
---

# PP 机台对接 Skill

为 pp-game 仓库的 PP 机台对接提供**端到端自主工作流**：从拿到 tableId 到代码上线一条龙。

## ⚠️ 触发后**第一步**（必做）

```bash
# 1. 定位 pp-game 仓库根 + cd 过去
cd "$(git rev-parse --show-toplevel 2>/dev/null)" || cd /Users/luca/work/pp-game
[[ -d server && -f scripts/pp_tables.py ]] || { echo "❌ 不在 pp-game 仓库"; exit 1; }

# 2. 设 SKILL_DIR（所有脚本与 reference 引用都要它）
export SKILL_DIR=$(dirname "$(realpath "$(find ~/.claude/skills ~/github -path '*pp-game-integration/SKILL.md' 2>/dev/null | head -1)")")
[[ -d "$SKILL_DIR/scripts" ]] || { echo "❌ 找不到 SKILL_DIR"; exit 1; }

# 3. 环境前置检查
command -v jq node python3 go >/dev/null || { echo "❌ 缺 jq/node/python3/go"; exit 1; }
node -e "import('playwright')" 2>/dev/null || { echo "⚠️  Playwright 未装：npm install -g playwright && npx playwright install chromium"; }
command -v codex >/dev/null || echo "⚠️  codex CLI 未装，Phase 6 将卡住"
[[ -f scripts/luca.sh ]] || { echo "❌ 缺 scripts/luca.sh（bc.game 认证）"; exit 1; }

# 4. 检查恢复点（基于实际 tableId，已 cd 到仓库根）
cat tmp/<tableId>/state.json 2>/dev/null
```

- state.json **不存在** → fresh start，进 Phase 0
- state.json **存在** → 跳到 `phase + 1` 继续；`status == "failed"` 则从该 phase 重试

## 核心约束（铁律 — 不可违反）

1. **自主执行** — 触发后只在 4 处停下问用户：① Phase 0 询问主分支 ② Phase 1 检测到 factory 已注册 ③ Phase 6 codex 同问题第 3 次 ④ Phase 6 codex 卡死第 3 次。其他全部按 [references/known-pitfalls.md](references/known-pitfalls.md) + `<repo>/docs/integration-experience/` 自主决策
2. **范围限定** — 协议事实**只**信 main.js 字面量 + capture 实际样本。**禁止**参考 `/Users/luca/work/ppgame` 老项目；**禁止**把 `<gametype>.json` 当单机台事实；**禁止**把 chip_amounts/ws_address 等运行时配置当开发资料
3. **事实驱动** — **禁止**预列任何"机台可能用 X 接口/Y 字段"假设；HTTP endpoint / betCode 表 / 错误码表等**只**从当次 main.js / capture / server 现有代码实际发现
4. **余额硬卡** — `lobby_launch.sh` 报告 `minBalanceToPlay > 6000` 时直接退出
5. **fail-closed 资金路径** — Redis 故障 / context 超时 / 解析失败 → 拒绝；详见 [references/known-pitfalls.md](references/known-pitfalls.md) C 节
6. **反复 codex 直到无问题** — 每次重大改动跑一轮，发现 → 修 → 再跑
7. **每次对接结束**写经验文档到 `<repo>/docs/integration-experience/<gametype>/<tableId>.md`
8. **不主动 PR** — worktree 内不 PR，PR 时机由用户决定

## 工作流（9 phase 自主推进）

```
Phase 0 ── 询问主分支（AskUserQuestion；唯一主动交互） ── Phase 1
Phase 1 ── lobby + 6000 卡门槛 + factory 已注册检测 ── Phase 2
Phase 2 ── fetch_client.mjs 录 capture（仅 5min；项目脚本写死 const）── Phase 3
Phase 3 ── 5 个 general-purpose subagent 并行 ── Phase 4
   ├ agent-1 协议字典 → dict.json
   ├ agent-2 HTTP 接口（纯静态分析）→ http_endpoints.json + http_diff.md
   ├ agent-3 UI/投注规则 → ui_rules.md
   ├ agent-4 决策/状态机 → state_machines.md
   └ agent-5 上游消息生命周期 → lifecycle.md
Phase 4 ── 协议设计（design.md，不审，自动进 Phase 5）── Phase 5
Phase 5 ── 复用 worktree-task-flow 的 init-worktree.sh + 自启动 worker（不进它的 brainstorming）
   ├ worker-1 骨架   ├ worker-2 业务   ├ worker-3 HTTP（仅 http_diff 有缺口）   └ worker-4 注册
Phase 6 ── 反复 codex review（实时记录决策；卡死/同问题 ≤ 3 次）
Phase 7 ── verify.sh 全量验收
Phase 8 ── 经验文档归档 + commit
```

详细状态机 + 决策树 + 异常处理 + 各 phase state 更新命令 见 [references/workflow.md](references/workflow.md)。

## 决策原则

按下列优先级，**不打断流程问用户**：

1. 查 `<repo>/docs/integration-experience/<gametype>/*.md` — 同 gametype 已有先例（精确匹配 tableId 优先；无则回退到大类如 baccarat/ 任一文件）。**首次对接时该目录可能不存在 → 视为合法**
2. 查 [references/known-pitfalls.md](references/known-pitfalls.md) — 共性陷阱
3. 按 skill 设计原则自主决定 — fail-closed / 事实驱动 / struct-only / silent error 写日志 / 注释最少
4. 决策完成后追加到对应经验文档（详见 [references/codex-review-loop.md](references/codex-review-loop.md) 实时记录格式）

## 详细参考（按需读取）

| 文件 | 何时读 |
|---|---|
| [references/workflow.md](references/workflow.md) | 各 phase 入口/产出/失败处理 + state.json 更新命令 |
| [references/parallel-team.md](references/parallel-team.md) | Phase 3 — 5 个并行 agent 启动模板（必看 §占位符替换） |
| [references/worker-prompts.md](references/worker-prompts.md) | Phase 5 — 4 个 worker 完整 prompt 模板 |
| [references/client-analysis.md](references/client-analysis.md) | Phase 3 — main.js / message.json grep 手册 |
| [references/http-analysis.md](references/http-analysis.md) | Phase 3 — agent-2 HTTP 接口分析方法（**禁止预列**）|
| [references/protocol-decision-table.md](references/protocol-decision-table.md) | Phase 4 — verdict 推导规则（**所有铁律详见 known-pitfalls.md**） |
| [references/frame-synthesis.md](references/frame-synthesis.md) | Phase 4 — 帧合成判定（按机台类型；**铁律见 known-pitfalls.md**） |
| [references/known-pitfalls.md](references/known-pitfalls.md) | **铁律单一权威**（A-F 节通用陷阱；具体机台特例放 docs/integration-experience/）|
| [references/project-level-skips.md](references/project-level-skips.md) | Phase 6 — 5 项项目级问题（与各机台一致，单机台不修）|
| [references/codex-review-loop.md](references/codex-review-loop.md) | Phase 6 — codex prompt 模板 + 闭环条件 + state 更新命令 |
| [references/test-design-guide.md](references/test-design-guide.md) | Phase 5 — 测试设计原则（按真实数据写）|
| [references/experience-doc-structure.md](references/experience-doc-structure.md) | Phase 8 — 经验文档 13 节结构 |

## 工具脚本

| 脚本 | 类型 | 何时调 | 参数 |
|---|---|---|---|
| `scripts/lobby_launch.sh` | 确定性 | Phase 1 | `<tableId>` |
| `scripts/fetch_capture.sh` | 确定性 | Phase 2 | `<tableId>` |
| `scripts/grep_client_dict.sh` | 确定性 | Phase 3（agent-1 内部用） | `<capture_dir>` |
| `scripts/codex_review_loop.sh` | **AI 包装器**（非确定性）| Phase 6 | `<worktree_path> <round_label> <base_branch>` |
| `scripts/verify.sh` | 确定性 | Phase 7 | `<worktree_path> <gametype> <tableId> <base_branch>` |
| `scripts/archive_experience.sh` | 确定性 | Phase 8 | `<tableId> [--overwrite|--backup]` |

## 与其他 skill 的协作

- **worktree-task-flow** — Phase 5 **只复用其 `scripts/init-worktree.sh`**，不进入它的 brainstorming/串行 worker/squash gate（本 skill 自管 worker 流程）
- **codex-review** — Phase 6 通过 `scripts/codex_review_loop.sh` 包装调用其 `codex_review.sh`
- **brainstorming** — 仅 4 处停下问用户的场景才进

## 完成判定

9 phase 全 pass。最终输出：

1. worktree 分支（worker commits + codex 修复 commits + 测试 + 文档归档 commit）
2. `<repo>/docs/integration-experience/<gametype>/<tableId>.md` 经验文档
3. 一句话总结报告（commits / coverage / codex 轮数 / HTTP 接口改动数）

完成后**不主动 PR**（铁律 8）。

---

**配套规范**：与 `<repo>/server/game/pp/internal/games/DEVELOPMENT.md`、`<repo>/server/game/common/runtime/ARCHITECTURE.md` 协同。
