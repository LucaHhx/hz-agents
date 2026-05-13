---
name: pp-game-develop
description: PP (Pragmatic Play) 机台对接 v2 工作流。用户提供 capture 数据（5 文件包），AI 完成全自主对接。触发：(1) 用户给出 PP tableId 并提供 tmp/tableId/ 数据包；(2) 明说"用 v2 流程对接 PP 机台" / "AIU 流程对接"。覆盖 baccarat / roulette / sweetbonanza / dragontiger / jackpotwheel 等 PP 全协议族。与老 skill 区别：本 skill 不录 capture（用户录），不依赖 PP/bc.game 网络；走 AIU DAG 实现 + 三层审查防线（层间 codex / 自问审查 / 整体循环）+ codex-collab 三模式调度。Phase 2 起完全无人值守，所有不确定走 codex-collab。不在范围：纯协议讨论 / 其他供应商 / 单纯代码 review。
---

# pp-game-develop

PP 机台对接 v2 流程。8 phase；Phase 0/1 可问用户，Phase 2+ 完全无人值守由主 Claude + codex-collab 协作。

## 触发后第一步

```bash
cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "❌ 不在 git 仓库"; exit 1; }
[[ -d server && -f scripts/pp_tables.py ]] || { echo "❌ 不在 pp-game 仓库"; exit 1; }

export SKILL_DIR="$(dirname "$(realpath "$(find ~/.claude/skills ~/github -path '*pp-game-develop/SKILL.md' 2>/dev/null | head -1)")")"
export CODEX_COLLAB="$(dirname "$(realpath "$(find ~/.claude/skills ~/github -path '*codex-collab/SKILL.md' 2>/dev/null | head -1)")")"

[[ -x "$CODEX_COLLAB/scripts/codex_review.sh" \
   && -x "$CODEX_COLLAB/scripts/codex_decide.sh" \
   && -x "$CODEX_COLLAB/scripts/codex_discuss.sh" ]] || { echo "❌ codex-collab 不完整"; exit 1; }

cat tmp/<tableId>/state.json 2>/dev/null  # 检查恢复点
```

- state.json **不存在** → fresh start，进 Phase 0
- state.json **存在** → 按 `state.phase + 1` 继续

## 用户交互边界（核心铁律）

| 阶段 | 与用户交互 |
|---|---|
| Phase 0 | ✅ 可汇报失败 + 列补救 |
| Phase 1 | ✅ 可确认 base（如歧义） |
| **Phase 2+** | **❌ 禁止提问，所有不确定走 codex-collab，失败 fallback 写 `state.unresolved[]`** |

## 用户提供的数据契约（必备）

`tmp/<tableId>/`：

- `message.jsonl` — game WS 双向帧（每行 JSON）
- `tableConfig.jsonl` — tableConfig 响应
- `statisticHistory.jsonl` — 历史响应
- `gameDetail.txt` — game.jsp XML（每行一条，推荐 ≥ 1）
- `clientResources/apps/<gameLoaderKey>/<ver>/main.js`

录制工具：pp-game 仓库 `scripts/game_dev/fetch_client.mjs`（headed 模式 + 实时 JSONL）。**本 skill 不主动录**。

## 8 Phase 概览 + 读取计划（progressive disclosure）

**重要**：每 phase 执行**前**才读对应 reference，不要预先读全部。每 phase 完成更新 state.json 才进下一 phase。

| Phase | 工作 | 执行前读 |
|---|---|---|
| **0** | 输入验收 + 元信息抽取 | `references/phase-0-acceptance.md` |
| **1** | 选 base + factory 注册检测（AI 直接 bash） | 本 SKILL.md「Phase 1」节即可 |
| **2** | 创建 worktree（调 worktree-task-flow init-worktree.sh）— 自此无人值守 | 本 SKILL.md「Phase 2」节即可 |
| **3** | AIU DAG 实现（5 层 17 单元，每层完成立即层间 codex 审查） | `references/phase-3-aiu-overview.md`，进入某 L 时再读对应 `phase-3-aiu-LN.md` + `phase-3-layer-review.md` |
| **4** | 自问审查 4 题 + codex_decide 每题决策 | `references/phase-4-self-review.md` |
| **5** | 整体循环 codex review（≤5 轮） | `references/phase-5-overall-review.md` |
| **6** | verify 7 项（含 I9 + I10） | `references/phase-6-verify.md` |
| **7** | 经验文档归档（13 节） | `references/phase-7-experience-doc.md` |

**跨 phase 共用 references**（按需 grep，不必预读）：
- `references/codex-collab.md` — 三模式调用 + 全 prompt 模板 + state 跟踪
- `references/known-pitfalls.md` — 协议铁律 A-I 精华版

## Phase 1 — 选 base + factory 检测（AI 直接执行）

```bash
TABLE_ID=<tableId>; REPO_ROOT=$(git rev-parse --show-toplevel); STATE="$REPO_ROOT/tmp/$TABLE_ID/state.json"
BASE_BRANCH=""; WHITELIST=(live live-dev dev pre)
[[ -n "${PP_BASE_BRANCH:-}" ]] && BASE_BRANCH="$PP_BASE_BRANCH"
if [[ -z "$BASE_BRANCH" ]]; then
    CURRENT=$(git rev-parse --abbrev-ref HEAD)
    for b in "${WHITELIST[@]}"; do [[ "$CURRENT" == "$b" ]] && { BASE_BRANCH="$CURRENT"; break; }; done
fi
if [[ -z "$BASE_BRANCH" ]]; then
    for b in "${WHITELIST[@]}"; do
        git show-ref --verify --quiet "refs/heads/$b" && { BASE_BRANCH="$b"; break; }
        git show-ref --verify --quiet "refs/remotes/origin/$b" && { BASE_BRANCH="$b"; break; }
    done
fi
[[ -z "$BASE_BRANCH" ]] && { echo "❌ 找不到 base"; exit 2; }

# factory 已注册检测
if grep -q "\"$TABLE_ID\":" "$REPO_ROOT/server/game/pp/internal/factory/instance_factory.go" 2>/dev/null; then
    jq --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '. + {phase:1,status:"skipped",already_registered:true,last_updated:$ts}' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
    exit 0  # 流程结束
fi

jq --arg b "$BASE_BRANCH" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '. + {phase:1,status:"done",base_branch:$b,last_updated:$ts}' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
```

## Phase 2 — 创建 worktree

```bash
GAMETYPE=$(jq -r .lobby.gameType "$STATE"); TAIL=$(echo "$TABLE_ID" | tail -c 9)
WT_SKILL=$(dirname "$(realpath "$(find ~/.claude/skills ~/github -path '*worktree-task-flow/SKILL.md' 2>/dev/null | head -1)")")
bash "$WT_SKILL/scripts/init-worktree.sh" "$BASE_BRANCH" "${GAMETYPE}-${TAIL}"
# 抓输出的 worktree_path + branch，写入 state
```

🔒 **本步完成即进入完全无人值守**。Phase 3-7 禁止向用户提问。

## state.json 字段

```jsonc
{
  "tableId": "...", "phase": 3, "status": "done|failed|skipped|degraded",
  "base_branch": "live", "worktree_path": "...", "worktree_branch": "...",
  "lobby": { "gameType": "...", "gameLoaderKey": "...", "limits": {...} },
  "capture_audit": { "p0_passed": true, "p1_warnings": [...] },
  "aiu_progress": { "L1": {"done": [...], "commits": [...]}, ... },
  "codex_reviews": [], "codex_decisions": [], "codex_discussions": [],
  "self_review_path": "tmp/<tableId>/self-review.md",
  "unresolved": [],
  "last_updated": "ISO-8601"
}
```

## 完成判定

8 phase 全 done / Phase 0 拒收 / Phase 1 skip。最终输出：

1. worktree 子分支（commits + 文档归档）— 不 PR
2. `docs/integration-experience/<gametype>/<tableId>.md`
3. `tmp/<tableId>/self-review.md`
4. 完成摘要（commits / coverage / codex 调用次数 / unresolved 数）

## 关联

- 共享方法论（pp-game 仓库）：`docs/integration-experience/common/{capture-acceptance,self-review-checklist,protocol-fidelity-checklist,client-rules-analysis,history-display-analysis}.md`
- 老 skill（仅历史参考）：`pp-game-integration`（AI 录 capture，已被本 skill 取代）
- 必需协作 skill：`codex-collab`（Phase 2+ 唯一决策途径）
- 工具 skill：`worktree-task-flow`（仅复用 `scripts/init-worktree.sh`）
