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

# 2. 设 SKILL_DIR（本 skill 自有脚本）
export SKILL_DIR=$(dirname "$(realpath "$(find ~/.claude/skills ~/github -path '*pp-game-integration/SKILL.md' 2>/dev/null | head -1)")")
[[ -d "$SKILL_DIR/scripts" ]] || { echo "❌ 找不到 SKILL_DIR"; exit 1; }

# 3. 设 CODEX_COLLAB（codex-collab skill 路径，本 skill 调用其 codex_review.sh / codex_decide.sh / codex_discuss.sh）
export CODEX_COLLAB=$(dirname "$(realpath "$(find ~/.claude/skills ~/github -path '*codex-collab/SKILL.md' 2>/dev/null | head -1)")")
[[ -x "$CODEX_COLLAB/scripts/codex_decide.sh" && -x "$CODEX_COLLAB/scripts/codex_discuss.sh" ]] || { echo "❌ 找不到 codex-collab skill"; exit 1; }

# 4. 环境前置检查
command -v jq node python3 go >/dev/null || { echo "❌ 缺 jq/node/python3/go"; exit 1; }
node -e "import('playwright')" 2>/dev/null || { echo "⚠️  Playwright 未装：npm install -g playwright && npx playwright install chromium"; }
command -v codex >/dev/null || echo "⚠️  codex CLI 未装，Phase 6 将卡住"
[[ -f scripts/luca.sh ]] || { echo "❌ 缺 scripts/luca.sh（bc.game 认证）"; exit 1; }

# 5. 检查恢复点（基于实际 tableId，已 cd 到仓库根）
cat tmp/<tableId>/state.json 2>/dev/null
```

- state.json **不存在** → fresh start，进 Phase 0
- state.json **存在** → 跳到 `phase + 1` 继续；`status == "failed"` 则从该 phase 重试

## 核心约束（铁律 — 不可违反）

1. **完全无人值守** — 触发后 100% 自主推进，**任何阶段都不允许停下问用户**。原 Phase 0 主分支选择、Phase 1 factory 已注册、codex 同问题重复、codex 卡死、项目级修复、follow-up 缺口、scope 取舍、经验文档结构等全部按本 skill 的确定性规则、`state.json`、`known-pitfalls.md` 和经验文档自主决策；无法安全决策时 fail-closed，写入 `state.unresolved[]` 后继续可继续的阶段或结束为 skipped/failed。**与 codex 协作走 codex-collab 三种模式**（审查 / 决策 / 沟通），见 §"codex 协作分工"。
2. **范围限定** — 协议事实**只**信 main.js 字面量 + capture 实际样本。**禁止**参考 `/Users/luca/work/ppgame` 老项目；**禁止**把 `<gametype>.json` 当单机台事实；**禁止**把 chip_amounts/ws_address 等运行时配置当开发资料
3. **事实驱动** — **禁止**预列任何"机台可能用 X 接口/Y 字段"假设；HTTP endpoint / betCode 表 / 错误码表等**只**从当次 main.js / capture / server 现有代码实际发现
4. **余额硬卡** — `lobby_launch.sh` 报告 `minBalanceToPlay > 6000` 时直接退出
5. **fail-closed 资金路径** — Redis 故障 / context 超时 / 解析失败 → 拒绝；详见 [references/known-pitfalls.md](references/known-pitfalls.md) C 节
6. **codex review 硬上限 10 轮** — 不再"反复跑直到无问题"。10 轮跑完后剩余 finding **写入 `state.unresolved[]`**，不无限循环。每轮按 §"自主决策矩阵" 选择性修，不修等于"全 PASS"
7. **每次对接结束**写经验文档到 `<repo>/docs/integration-experience/<gametype>/<tableId>.md`
8. **worktree 边界 + 禁 PR** — 所有代码、测试、文档、commit、push 只允许发生在本 skill 创建或恢复的 worktree 及其子分支内。允许 push 自己创建的 worktree 子分支；禁止 checkout / merge / rebase / reset / push 到非本流程创建的分支，禁止修改主工作区或其他 worktree，禁止操作其他分支。**禁止任何 PR 操作**，包括 `gh pr create`、`gh pr merge`、`gh pr checkout`、`gh pr edit`、`gh pr review` 以及等价命令；PR / 合并 / 部署时机完全由用户在流程外决定。
9. **禁止 issue 操作 + 用 state.unresolved[] 取代**：本 skill 不调用 `gh issue create`（issue 也是仓库协作面动作，与铁律 8 worktree 边界一致）。原"建 issue"的所有触发条件改为追加到 `tmp/<tableId>/state.json` 的 `unresolved[]` 字段后继续推进：
   - codex 同问题 hash ≥ 3 次出现
   - codex 卡死累计 ≥ 3 次
   - finding 命中"large 影响范围"（见 §"自主决策矩阵"）
   - Phase 6 跑满 10 轮仍有未修 finding
   - codex_decide.sh / codex_discuss.sh 超时或不可解析（fallback 到 known-pitfalls 默认 + 写 unresolved[]）

## 工作流（9 phase 自主推进）

```
Phase 0 ── 自动选 base 分支（override 位置参数 > state.base_branch > $PP_BASE_BRANCH > 当前分支[白名单] > live > live-dev > dev > pre > fail-closed）── Phase 1
Phase 1 ── lobby + 6000 卡门槛 + factory 已注册检测（已注册自动 skip-this-table，**只写 state.json**，不动经验文档/不创 worktree，结束）── Phase 2
Phase 2 ── fetch_client.mjs 录 capture（仅 5min；项目脚本写死 const）── Phase 3
Phase 3 ── 5 个 general-purpose subagent 并行 ── Phase 4
   ├ agent-1 协议字典 → dict.json
   ├ agent-2 HTTP 接口（纯静态分析）→ http_endpoints.json + http_diff.md
   ├ agent-3 UI/投注规则 → ui_rules.md
   ├ agent-4 决策/状态机 → state_machines.md
   └ agent-5 上游消息生命周期 → lifecycle.md
   ⚙ 冲突时调 codex_discuss.sh 多轮讨论（≤3 轮 / 15min）
Phase 4 ── 协议设计（design.md）+ codex_decide.sh 一次性决策协议处理 / 缺口分流 ── Phase 5
   ⚙ design 草稿空洞调 codex_discuss.sh（≤2 轮）
Phase 5 ── 复用 worktree-task-flow 的 init-worktree.sh + 自启动 worker（不进它的 brainstorming）
   ├ worker-1 骨架   ├ worker-2 业务   ├ worker-3 HTTP（仅 http_diff 有缺口）   └ worker-4 注册
   ⚙ worker 卡 ≥10min 或失败 ≥2 次调 codex_discuss.sh（≤3 轮）；启动前路径不确定调 codex_decide.sh
Phase 6 ── 反复 codex review（codex_review_loop.sh，10 轮硬顶；剩余 finding 入 state.unresolved[]）
Phase 7 ── verify.sh 全量验收（失败首轮自动修；失败 ≥2 次先 codex_decide.sh 分类根因，不收敛再 codex_discuss.sh ≤2 轮）
Phase 8 ── 经验文档归档 + commit（worktree 子分支，可 push；不 PR）
```

详细状态机 + 决策树 + 异常处理 + 各 phase state 更新命令 见 [references/workflow.md](references/workflow.md)。

## codex 协作分工

**Claude 角色**：编码（worker 实现 / 修 finding）、状态机驱动、phase 推进、`state.json` 更新、`unresolved[]` 写入。
**codex 角色**：审查（Phase 6） + 决策（Phase 3→4 / 4 / 5 / 7）+ 沟通（Phase 3 / 4 / 5 / 7）。

| 模式 | 脚本 | 触发场景 | 退出条件 |
|---|---|---|---|
| **审查** | `$SKILL_DIR/scripts/codex_review_loop.sh` → `$CODEX_COLLAB/scripts/codex_review.sh` | Phase 6 — 反复 review worker 实现 | "无重大问题" / 10 轮硬顶 |
| **决策** | `$CODEX_COLLAB/scripts/codex_decide.sh` | Phase 3→4 协议 pass/drop/rewrite；Phase 4 HTTP/history 缺口分流；Phase 5 worker 路径与失败重启；Phase 7 verify 失败根因分类 | 一次性输出结构化 markdown 决策块（codex 自动做"上下文足够性自检"，不足返回 `INSUFFICIENT_CONTEXT`）|
| **沟通** | `$CODEX_COLLAB/scripts/codex_discuss.sh` | Phase 3 capture/main.js 解析冲突（≤3 轮 / 15min）；Phase 4 design 草稿空洞（≤2 轮）；Phase 5 worker 卡 ≥10min 或失败 ≥2 次（≤3 轮）；Phase 7 verify 失败 ≥2 次（≤2 轮） | `discussion_status: closing/unresolved` 或达 max-rounds |

**关键设计原则**（codex-collab 强制实现）：调用 `codex_decide.sh` 时，Claude 提供"问题 + 入口路径"（哪个文件、哪个函数、哪个 state 字段），**不直接喂答案让 codex 选**。codex 自己用 `rg` / `cat` 主动探索代码，给出引用 `file:line` 的有依据决策。上下文不足时 codex 返回 `INSUFFICIENT_CONTEXT` 列出还需哪些路径，由 Claude 补充后再调一次。

**fallback 规则**（铁律 9）：codex_decide.sh / codex_discuss.sh 超时（>10min 无响应）或不可解析时，Claude 回退按 `references/known-pitfalls.md` + design 默认规则决策，**同时写 `state.unresolved[]`** 标 `category: codex-script-failed`，继续推进；不创建 issue / PR。

详细 phase 调用模板和 state 字段见 [references/workflow.md](references/workflow.md) 与 [references/codex-review-loop.md](references/codex-review-loop.md)。

## 决策原则

按下列优先级，**不打断流程问用户**：

1. **`<repo>/docs/integration-experience/common/`** — 项目内方法论（**Phase 3-4 强制读**）：
   - `client-rules-analysis.md` — 4 类客户端规则分析方法论 + §9 矩阵输出模板（agent-3 必读）
   - `history-display-analysis.md` — 5 类历史入口分析方法论 + §10 审查表模板（agent-2 必读）
   - **`protocol-fidelity-checklist.md`** — 协议保真度检查清单（**Phase 3 dict.json 必填字段 + Phase 5 worker 实现自检矩阵 + Phase 7 verify 6 项自动断言**；防"抄既有机台模板"踩坑；来源：drag0ntig3rsta48 Round 11/12 26 个 finding 的教训）
   - **Phase 4 design.md 必须含 §7 矩阵 + §8 历史链路审查**（之前的设计错误：放到 Phase 8 才补 → 缺口到 codex 阶段才暴露）
2. 查 `<repo>/docs/integration-experience/<gametype>/*.md` — 同 gametype 已有先例（精确匹配 tableId 优先；无则回退到大类如 baccarat/ 任一文件 → 再无则回退到相邻 gametype 如 sweetbonanza/）。**首次对接时该目录可能不存在 → 视为合法**
3. 查 [references/known-pitfalls.md](references/known-pitfalls.md) — 共性陷阱
4. 按 skill 设计原则自主决定 — fail-closed / 事实驱动 / struct-only / silent error 写日志 / 注释最少
5. 决策完成后追加到对应经验文档（详见 [references/codex-review-loop.md](references/codex-review-loop.md) 实时记录格式）

## 自主决策矩阵（codex finding / 后续 follow-up gap 分流）

不要"codex 找到的所有问题都修"。每个 finding 按下表分流，**自主决断**：

| 等级 | 判定标准 | 处理 |
|---|---|---|
| **small** | 单文件改动 ≤ 50 行；本机台范围；无新抽象；测试只补 1-3 例；不影响其他机台 | **立即修** + commit + 实时记入经验文档 |
| **medium** | 跨 1-2 文件 / 50-200 行；本机台 + 1 个相关公共 helper；改动模式与既有机台一致；可独立 PR | **看资金安全必要性**：是 → 修；否 → 写 `state.unresolved[]` 留 follow-up |
| **large** | 跨机台联动 / 通用层重构 / 新建 model 表 / 新增 API 接口 / 改动 > 200 行 / 涉及未明确的协议字段语义 | **自动写 `state.unresolved[]`** + 经验文档第 15 节"已建 follow-up"摘要标注，**本 worktree 不修** |

**资金安全必要性判断**（medium 级用）：
- ✅ 必要：扣款/派彩金额错误 / 资金竞态 / fail-closed 缺失 / 玩家可绕过的协议校验缺失
- ❌ 非必要：审计字段缺失（不影响实际资金）/ 历史 XML 节点缺失（不影响结算）/ 重复代码 / 命名不一致 / 测试组织风格

**项目级跳过判断**（命中 [project-level-skips.md](references/project-level-skips.md) 5 项之一）：
- 默认跳过；如**已修复版本存在于本 worktree / 历史经验文档**则不再次提及，直接进下一轮
- codex 重提项目级问题 ≥ 2 次 → 写入 `state.unresolved[]`（不再建 issue，铁律 9）+ 经验文档第 10 节"项目级跳过状态" + 不再回应

**`state.unresolved[]` 模板**（替代原 gh issue create）：

```jsonc
{
  "id": "unresolved-<uuid>",
  "phase": 6,
  "category": "repeated-N-times | stuck-3-times | large-impact | round-cap-leftover | codex-script-failed | project-level-recurring",
  "source": {
    "round": 7,
    "label": "agent-2-traps",
    "finding": {"file": "...", "line": 42, "desc": "..."}
  },
  "verdict": {
    "impact": "small | medium-非必要 | large | project-level",
    "fund_safety": false,
    "repeat_count": 3
  },
  "suggested_action": "跨机台联动需独立设计 / 缺 capture 样本待生产数据 / 与项目级 #N 合并 / scope cap 已达 10 轮硬顶 / 同问题 3 次重提",
  "snapshot": {
    "state_json": "tmp/<tableId>/state.json",
    "worktree": "<worktree_path>"
  },
  "created_at": "ISO-8601"
}
```

每轮迭代结束自动写到 `state.unresolved[]`；Phase 8 经验文档第 15 节列出 `unresolved[]` 摘要供用户后续决策（用户在流程外手动建 issue / 排期 / 忽略）。

**绝不再问用户的场景**（之前犯过的错）：
- ❌ "codex 第 N 次重提 X，怎么推进？" → 写 unresolved[] 跳过
- ❌ "F3+F4+F7 vs all vs none?" → 按矩阵自主分流
- ❌ "项目级修复要不要做？" → small/medium 必要的修；large/重提 ≥2 次 写 unresolved[]
- ❌ "经验文档要不要补 §X 节？" → 必要就补，不必要就不补，自己判断
- ❌ "Phase 0 主分支用哪个？" → 按铁律 1 优先级链自动选
- ❌ "factory 已注册要不要重做？" → 默认 skip-this-table

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
| `scripts/codex_review_loop.sh` | **AI 包装器**（非确定性）| Phase 6 — 审查（薄包装，调 codex-collab/codex_review.sh）| `<worktree_path> <round_label> <base_branch>` |
| `scripts/verify.sh` | 确定性 | Phase 7 | `<worktree_path> <gametype> <tableId> <base_branch>` |
| `scripts/archive_experience.sh` | 确定性 | Phase 8 | `<tableId> [--overwrite|--backup]` |

> 决策 / 沟通脚本（`codex_decide.sh` / `codex_discuss.sh`）住在 `codex-collab` skill，本 skill 直接调用 `$CODEX_COLLAB/scripts/...`（在"触发后第一步"段已 export $CODEX_COLLAB）。

## 与其他 skill 的协作

- **worktree-task-flow** — Phase 5 **只复用其 `scripts/init-worktree.sh`**，不进入它的 brainstorming/串行 worker/squash gate（本 skill 自管 worker 流程）
- **codex-collab**（旧名 codex-review）— 三种模式全用：
  - **审查**：本 skill 的 `scripts/codex_review_loop.sh` → 调 `$CODEX_COLLAB/scripts/codex_review.sh`
  - **决策**：直接调 `$CODEX_COLLAB/scripts/codex_decide.sh`（一次性 + 上下文自检 + INSUFFICIENT_CONTEXT 反馈）
  - **沟通**：直接调 `$CODEX_COLLAB/scripts/codex_discuss.sh`（轮数感知 + 每轮自检）
- **brainstorming** — **完全禁用**（铁律 1：完全无人值守，brainstorming 会问用户）

## 完成判定

9 phase 全 pass，或 Phase 1 已注册自动 skip，或 Phase 0 base-branch fail-closed。最终输出：

1. worktree 子分支（worker commits + codex 修复 commits + 测试 + 文档归档 commit；可 push 该子分支，**不做任何 PR 操作**）
2. `<repo>/docs/integration-experience/<gametype>/<tableId>.md` 经验文档（含第 15 节 unresolved[] 摘要）
3. 一句话总结报告（commits / coverage / codex 审查轮数 / 决策次数 / 沟通次数 / unresolved 数 / HTTP 接口改动数）

完成后**不主动 PR**（铁律 8）。`state.unresolved[]` 中的 follow-up 由用户在流程外决定（建 issue / 排期 / 忽略）。

---

**配套规范**：与 `<repo>/server/game/pp/internal/games/DEVELOPMENT.md`、`<repo>/server/game/common/runtime/ARCHITECTURE.md` 协同。
