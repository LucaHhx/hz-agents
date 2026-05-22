# Phase 3 — 层间 codex 审查

> 触发：每层（L1-L5）全部 AIU commit 完成后立即跑。
> 软上限：每层 ≤ 2 轮。
> 模式：codex-collab review 模式（`$CODEX_COLLAB/scripts/codex_review.sh`）。

## 调用模板

```bash
LAYER=L1  # 或 L2/L3/L4/L5
ROUND=1
WT=$(jq -r .worktree_path tmp/<tid>/state.json)
HEAD_N=$(jq ".aiu_progress.$LAYER.commits | length" tmp/<tid>/state.json)

bash $CODEX_COLLAB/scripts/codex_review.sh \
    -d "$WT" \
    -l "layer-${LAYER}-round-${ROUND}" \
    -- "$(render_layer_review_prompt $LAYER $HEAD_N)"
```

## 每层审查重点（注入 prompt）

### L1 — ENUM / DICT / ERRCODE（协议事实正确性）

**审查重点**：
- 事件名是否含 capture 实证 + main.js 补全（罕见 canceled/session 等）
- bc 全集是否完整（capture 触发的 + main.js Qp 枚举全集）
- face↔bc 双向映射对称（FaceValueToBC[v]==k iff BCToFaceValue[k]==v）
- errorCode 全集 ≥ 30 项，每码客户端展示分支标注
- **extendedErrorCode** 仅 9018 InvalidToken 触发 SESSION_TIMEOUT（I3）
- Redis key 前缀走 enum.go 常量

**主信息源**：
- capture: `tmp/<tid>/{message.txt, tableConfig.txt}`
- main.js: `tmp/<tid>/clientResources/apps/<key>/<ver>/main.js`
- 上游：无

### L2 — MODELS / BETPROTO / RULES / PROCESSOR / INSTANCE（struct 与真帧匹配）

**审查重点**：
- models.go 各 struct 字段 vs `tmp/<tid>/message.txt` recv 帧逐字段对照
- 字段类型严格（string/number/嵌套对象 — 如 jackpotwheel_rng.slot 是嵌套不是平铺）
- omitempty 标签是否合理（可选字段才标）
- bet_limits.go 含 G2 默认值常量（DefaultMaxMultiplier=20000 / DefaultEuroTablePayoutMax=500000）
- tableConfig 字段名沿用 PP 原始 typo（如 fourty）
- PROCESSOR 锁字段齐全（mu/betsMu/cacheMu/pendingMu）
- INSTANCE bet_window fail-closed (C1) + bet_redis context.WithTimeout 5s (C9)

**主信息源**：
- 全 capture 5 文件
- main.js
- 上游：L1 enum.go / dict.json / error_codes.md

### L3 — UPSTREAM / DOWNSTREAM_BET / SETTLE / HISTORY_PARSER / CHECK_BET（业务符合 lifecycle）

**审查重点**：
- upstream tableId 字节替换 (B1) + orderKeysByPriority (B3)
- downstream_bet **incremental** loadExistingBets + mergeBets (I6)
- downstream_bet partial-accept (I7) + bet echo (B5) + betValidationError 7 字段 (B9)
- settle face_value→bc 映射 + b_game_rounds.Extra 字段齐全（capture 真帧每字段都落盘）
- history_<gametype>.go XML 字段名 vs gameDetail.txt 真 XML 逐字段对照
- history parser multiplier/payout 缺数据填 "0" 不空串 (I8)
- CheckBet 双重 fail-closed（内存 + Redis C1）
- CheckBet 9 段位单注 + 台限累加 + bonus 联动 (B8)

**主信息源**：
- capture message.txt 双向帧（lifecycle 时序）
- **gameDetail.txt 真 XML**（HISTORY_PARSER 唯一权威）
- tableConfig.txt（CHECK_BET 限额）
- main.js（rejectBet 分支）
- 上游：L1 + L2 全部产物

### L4 — PAYOUT / BETSTATS / WINNERS / 3 个 API（派生产物字段一致性）

**审查重点**：
- payout.Calculate 公式**含本金**
- G3 三路 cap min（maxMultiplier × stake / EUR 等值 / 本币硬封顶；**用户级非单注**）
- CapUserPayout 等比缩放 (C8) + mCap=true 触发
- betstats 9 段位 bucket key 与 main.js 实测 key 一致
- B7 完整 envelope + unwrapEnvelope（双信封陷阱）
- winners **pass 透传** (B2 修正版默认；不是丢弃)
- api_stats betResultStats key 与 main.js `Object.keys(tf)` 实测一致
- api_table_config 含 typo（如 fourty_bet_* 内部 → Forty 外部）
- api_rtp 响应非空 body

**主信息源**：
- 全 capture 5 文件
- main.js（betResultStats 读取 / fallback 默认 / typo 字段）
- 上游：L1 + L2 + L3 全部产物

### L5 — FACTORY（注册完整性）

**审查重点**：
- import 路径正确
- ImplementedTableIDs 含新 TableID
- NewGameInstance switch case 含新分支
- **全 build pass**（含 server + web + tests）
- 无重复 case / 无遗漏分支

**主信息源**：
- 上游：L1 enum.go（TableID 常量）
- 既有 instance_factory.go

## 通用 codex review prompt 结构

```
你是 PP 机台 <tableId> (<gametype>) Phase 3 Layer N 完成后的代码审查者。
只审查、不修改任何文件。按 🔴/🟡/🟢 分类输出，每条 file:line + 描述 + 修复建议。

【本层范围】Layer N 完成的 AIU：<list AIU names>
本层 diff：git diff HEAD~<M>..HEAD（M = 本层 AIU 数 + 本层 fix 数）

【审查重点】<按层注入对应 checklist，见上方各节>

【主信息源（必读，用于验证产物正确性）】
1. capture（事实最高权威）：
   - tmp/<tid>/message.txt
   - tmp/<tid>/tableConfig.txt
   - tmp/<tid>/statisticHistory.txt
   - tmp/<tid>/gameDetail.txt
   - tmp/<tid>/clientResources/apps/<key>/<ver>/main.js
2. 上游 AIU 产物（参考，不审）：
   - L1: enum.go / dict.json / error_codes.md
   - L2: ... (按 N 注入)
3. 既有经验：
   - <repo>/docs/integration-experience/<gametype>/*.md
   - $SKILL_DIR/references/known-pitfalls.md

【输出格式】
🔴/🟡/🟢 + file:line + 一句话描述 + 一句话修复建议 + 引用 known-pitfalls 条目（B1/I3/G3 等）

【硬规则】
- capture 真帧与 main.js 字面量冲突时以 capture 为准
- struct 字段名与 capture 真帧不一致 → 🔴 must-fix
- "代码功能对了但 capture 没验证过" → 🟡 should-fix
- 与既有机台模板不一致但符合本机台 capture → ✅ OK 不报
```

## fix 决策（每个 finding 走自主分流）

| finding 类型 | 处理 |
|---|---|
| 🔴 must-fix small（≤50 行 / 单文件） | 立即修 + commit |
| 🔴 must-fix medium 资金安全必要 | 立即修 |
| 🟡 medium 非必要 | 写 `state.unresolved[]`（category="medium-non-essential"） |
| 🟡 large（跨 AIU / 新表 / 新 API） | 写 `state.unresolved[]`（category="large-impact"） |
| 🟢 nice-to-have | 跳过 |
| 同 hash ≥ 3 次重提 | 写 `state.unresolved[]`（category="repeated-N-times"）+ 后续跳过 |
| 项目级（见 pp-game `docs/integration-experience/common/project-level-skips.md`） | 跳过 + 第 1 次提及记入经验文档第 10 节 |

## 退出条件

- codex 报"无重大问题" → 进下层
- 2 轮跑完仍有 finding → 写 `state.unresolved[]` + 进下层（绝不停问用户）
- codex CLI 卡死 → 写 unresolved（category="codex-script-failed"）+ 进下层

## state.json 写入

```jsonc
{
  "codex_reviews": [
    {
      "layer": "L1", "round": 1, "started_at": "...",
      "findings": 5, "fixed": 4,
      "unresolved_count": 1
    }
  ],
  "aiu_progress": {
    "L1": {
      "done": ["ENUM","DICT","ERRCODE"],
      "commits": [...],
      "review_rounds": 2,
      "review_fixed": 4,
      "review_unresolved": 1
    }
  }
}
```
