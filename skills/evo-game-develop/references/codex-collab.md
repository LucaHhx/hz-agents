# codex-collab 三模式调度（跨 Phase 共用）

> 汇总 codex-collab 三模式（review / decide / discuss）的全部触发点 + prompt 模板。
> 各 phase 遇到 codex 调用时引用此文件。方法论与 PP 同；EVO 特化在触发点 + 示例（per-user / currencyMult / tmp-evo 路径 / roulettecore 模板）。

## 三模式速览

| 模式 | 脚本 | 用途 | 适合 | 不适合 |
|---|---|---|---|---|
| **review** | `$CODEX_COLLAB/scripts/codex_review.sh` | 只读代码审查，🔴/🟡/🟢 findings | 实现完成后审查 | 方案选择 / 卡死诊断 |
| **decide** | `$CODEX_COLLAB/scripts/codex_decide.sh` | 一次性方案决策，结构化输出（含 INSUFFICIENT_CONTEXT 自检） | A vs B 二选一 / 字段命名 / 架构评估 | 开放探索 / 反复迭代 |
| **discuss** | `$CODEX_COLLAB/scripts/codex_discuss.sh` | 多轮对话（thread_id resume）+ 每轮自检 | 卡死根因诊断 / 冲突收敛 | 简单选型 |

## 全流程触发点矩阵

| Phase | review | decide | discuss |
|---|---|---|---|
| 0 输入验收 | — | — | — |
| 1 选 base/复用边界 | — | — | — |
| 2 建 worktree | — | — | — |
| 3 AIU 实现 | **每层 ≤ 2 轮层间审查**（L1-L5） | D1 AIU 路径不确定 / D2 MODELS 字段歧义 / **D2' per-user 改写时序/字段不确定** | S1 AIU 卡 ≥10min / 失败 ≥2 次 |
| 4 自问审查 | — | **D3 每个自问问题一次** | S4 决策不收敛（可选） |
| 5 整体循环 | **≤ 5 轮跨层审查** | D4 finding fix 分流争议 | S2 同 finding hash ≥ 3 次 |
| 6 verify | — | D5 verify 失败 ≥ 2 次根因 | S3 决策不收敛 / 失败跨边界 |
| 7 归档 | — | — | — |

调用频次预估（单族）：review 6-12 次 / decide 4-10 次 / discuss 0-3 次。

---

## 模式 1: review（代码审查）

详见 `phase-3-layer-review.md`（层间）+ `phase-5-overall-review.md`（整体）。通用 prompt 结构：

```
你是 EVO <gametype> 桌 <evo_table_id> Phase N <scope> 代码审查者。
只审查、不修改任何文件。按 🔴/🟡/🟢 分类输出。
【审查范围】<具体 git diff>
【审查重点】<按 phase/layer 注入清单>
【主信息源】
- capture: tmp-evo/<dir>/{message.txt, message-nobet.txt, config.txt, gameDetail.txt, roundDetail/, clientResources/frontend/}
  （⚠️ message.txt 每行 payload 是 JSON 字符串，解析须 `.payload|fromjson|.type`，直接 `.payload.type` 抛 `Cannot index string`；roundDetail 结算体在 `.data.data`）
- 模板: server/game/evo/internal/games/roulette/roulettecore/
- 上游 AIU 产物: <list>
- known-pitfalls: $SKILL_DIR/references/{known-pitfalls,evo-platform-primer}.md
【输出格式】🔴/🟡/🟢 + file:line + 描述 + 修复建议 + 引用 known-pitfalls 条目
【硬规则】
- capture 真帧与 bundle 字面量冲突 → capture 为准
- struct 字段名/下发帧 tableId 与 capture 不一致 → 🔴 must-fix
- per-user 改写缺失/快照时序错/余额来源错 → 🔴 must-fix（资金/UX 安全）
- "功能对了但 capture 没验证过" → 🟡 should-fix
- 与 roulettecore 模板不一致但符合本族 capture → ✅ OK 不报
```

### review fix 决策矩阵（自主分流）

| finding 类型 | 处理 |
|---|---|
| 🔴 must-fix small（≤50 行/单文件） | 立即修 + commit |
| 🔴 must-fix medium 资金/per-user 安全必要 | 立即修 |
| 🟡 medium 非必要 | 写 `state.unresolved[]` |
| 🟡 large（跨 AIU/新表/新 API） | 写 `state.unresolved[]` |
| 🟢 nice-to-have | 跳过 |
| 同 hash ≥ 3 次重提 | 写 unresolved + 后续跳过 |

---

## 模式 2: decide（结构化决策）

### decide 触发点

| # | Phase | 触发条件 | 典型候选 |
|---|---|---|---|
| **D1** | 3 AIU 启动前 | 实现路径不确定 | A 照搬 roulettecore 机制 / B 抽 common helper / C 本族独立实现 |
| **D2** | 3 L2 MODELS | 字段类型歧义（capture vs bundle 不一致） | A 按 capture 真帧类型 / B 按 bundle 字面量 / C json.RawMessage 容错 |
| **D2'** | 3 L3 PER_USER | per-user 改写时序/字段不确定（EVO 特有） | A 照 roulettecore strip/snapshot 时序（注意载体 roulette=`tableState.betState`，game show=`<gt>.bets`，帧名/字段可能不同）/ B 新族字段差异调整 / C 待 capture 实证 |
| **D3** | 4 自问审查 | 每个自问发现问题 | A 修 / B 不修-本族特殊 / C 不修-可接受 / D 待人工 |
| **D4** | 5 整体循环 | finding fix 分流争议 | A small 立即修 / B medium 必要修 / C unresolved / D large unresolved |
| **D5** | 6 verify | verify 失败 ≥2 次根因分类 | A 实现 bug 回 Phase 3 / B 测试断言错 / C policy-pr 拆 / D 设计遗漏 回 Phase 4 |

### decide 通用 prompt 模板

```bash
bash $CODEX_COLLAB/scripts/codex_decide.sh -d "$REPO_ROOT" -l "<phase-stage>-decide-<uuid>" \
  -- "## 背景
gameType: <...> / evo_table_id: <...> / worktree: <...> / 触发场景：<...>
## 关联文件（codex 自己 rg/cat 探索，不喂答案）
- 实现入口: <file:line>  · 模板对照: roulettecore 同名文件
- capture 证据: tmp-evo/<dir>/<file> + grep 命令
- known-pitfalls: <相关条款>
## 决策点：<具体问题>
候选 A: <...> / B: <...> / C: <...> / D: 待人工（信息不足）
判断标准：<资金/per-user 安全 / capture 实证 / 跨族一致性>"
```

### decide 关键设计原则
- **不喂答案让 codex 选**：主 Claude 给"问题 + 入口路径"，codex 自己 rg/cat 探索
- **上下文不足自检**：codex 返回 `INSUFFICIENT_CONTEXT` → Claude 补充后再调一次（≤2 次）
- **候选 D 兜底**：codex 选 D → fallback 写 `state.unresolved[]`（不停问用户）
- **结果写 `state.codex_decisions[]`**

### decide 行动

| codex 输出 | 行动 |
|---|---|
| A 修 | Agent 启动 fix worker 按 codex 路径修 |
| B/C 不修 | 写 `state.unresolved[]` |
| D 待人工 | 写 `state.unresolved[]`（category="self-review-no-evidence"/"verify-decide-deferred"） |
| INSUFFICIENT_CONTEXT | 补充关联文件再调一次（不超 2 次） |
| 超时 / 不可解析 | fallback 写 `state.unresolved[]`（category="codex-script-failed"） |

---

## 模式 3: discuss（多轮对话）

### discuss 触发点

| # | Phase | 触发条件 | 目标 | 轮数上限 |
|---|---|---|---|---|
| **S1** | 3 AIU | worker 卡 ≥10min / 失败 ≥2 次 | 根因诊断 + 修复路径 | ≤3 轮 |
| **S2** | 5 整体 | 同 finding hash ≥3 次反复 | 根本设计原因 | ≤3 轮 |
| **S3** | 6 verify | decide 不收敛 / 失败跨边界 | 系统性根因 | ≤2 轮 |
| **S4** | 4 自问 | decide 选 D 占多数（可选） | "补 capture 重做" vs "接受 unresolved" | ≤2 轮 |

### discuss 通用模板（thread_id resume）

```bash
# 第 1 轮（新会话）
bash $CODEX_COLLAB/scripts/codex_discuss.sh -d "$REPO_ROOT" --round 1 --max-rounds 3 -l "<tag>" \
  -- "<问题描述 + 当前 diff/失败日志/prompt 摘要>"
# 抓 THREAD_ID → 写 state.codex_discussions[id].thread_id
# 第 2/3 轮 resume
bash $CODEX_COLLAB/scripts/codex_discuss.sh -t "<thread_id>" --round 2 --max-rounds 3 -- "<追问>"
```

### discuss 退出条件

| codex 状态 | 行动 |
|---|---|
| `discussion_status: closing` | 写 status="closed" + summary 落 self-review.md 或经验文档 §7 |
| `discussion_status: unresolved` / 达 max-rounds | 写 `state.unresolved[]`（category="codex-discuss-no-converge"）+ Claude 按 fail-closed 最保守路径继续 |
| 卡死 / 不可解析 | fallback 同上 + category="codex-script-failed" |

**绝不停问用户**。

---

## state.json 跟踪 codex 调用

```jsonc
{
  "codex_reviews": [
    {"scope":"L1-layer","round":1,"findings":3,"fixed":3,"verdict":"clean"},
    {"scope":"L3-layer","round":1,"findings":5,"fixed":4,"unresolved_count":1},
    {"scope":"overall","round":1,"findings":2,"fixed":2,"verdict":"clean-after-round-2"}
  ],
  "codex_decisions": [
    {"id":"decision-<uuid>","phase":4,"timing":"self-review-q1","question":"per-user 快照时序是否需调",
     "options":["A 照 roulettecore","B 本族调整","C 待人工"],"selected":"A","rationale":"<codex 理由>",
     "inputs":["<file:line>"],"written_to":"self-review.md §1","created_at":"ISO"}
  ],
  "codex_discussions": [
    {"id":"discuss-<uuid>","phase":3,"label":"L3-PER_USER-stuck","thread_id":"<...>",
     "rounds":[{"round":1,"input":"...","output_summary":"..."}],"final_status":"closed","summary":"<...>","created_at":"ISO"}
  ],
  "codex_budget_guard": {"decision_calls":8,"discussion_rounds":4,"max_discussion_rounds_per_trigger":3}
}
```

## 选型决策树

```
需要 codex 协助？
├─ 有完整代码需审查？ ──► review
├─ 有 2-4 个明确候选要选？ ──► decide
├─ 卡住不知方向？ ──► discuss
└─ 没明确决策点 / 只想要意见？ ──► 不调 codex，按 known-pitfalls + evo-platform-primer 自决
```
