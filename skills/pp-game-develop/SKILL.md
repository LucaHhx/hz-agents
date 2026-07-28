---
name: pp-game-develop
description: PP (Pragmatic Play) 机台对接 v2 工作流。用户提供 capture 数据（5 文件包），AI 完成全自主对接。触发：(1) 用户给出 PP tableId 并提供 tmp/tableId/ 数据包；(2) 明说"用 v2 流程对接 PP 机台" / "AIU 流程对接"。覆盖 baccarat / roulette / sweetbonanza / dragontiger / jackpotwheel 等 PP 全协议族。与老 skill 区别：本 skill 不录 capture（用户录），不依赖 PP/bc.game 网络；走 AIU DAG 实现 + 三层审查防线（层间 codex / 铁律核对 / 整体循环 codex）+ codex-collab 三模式调度。Phase 2 起完全无人值守，所有不确定走 codex-collab。不在范围：纯协议讨论 / 其他供应商 / 单纯代码 review。
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

# capture 目录定位（关键：目录名 = hall external_code，不等于 PP tableId）
# hall-for-live 上游不支持长 gameId 取链接，capture 工具用 hall external_code（数字）命名
# 目录，AI 必须从 tableConfig.txt 第一条记录的 tableId 字段反查真实 PP tableId。
# 用户输入可能是 PP tableId（如 "gatesofolympus01"）或 capture 目录名（如 "2244"）。
INPUT_ID="<用户给的 ID>"
CAPTURE_DIR=""
# 路径 A：用户直接给 capture 目录名
if [[ -d "tmp/$INPUT_ID" && -s "tmp/$INPUT_ID/tableConfig.txt" ]]; then
    CAPTURE_DIR="$INPUT_ID"
else
    # 路径 B：用户给 PP tableId，扫 tmp/*/tableConfig.txt 反查
    for d in tmp/*/; do
        TID=$(jq -s -r '.[0].tableId // empty' "$d/tableConfig.txt" 2>/dev/null)
        [[ "$TID" == "$INPUT_ID" ]] && { CAPTURE_DIR=$(basename "$d"); break; }
    done
fi
[[ -z "$CAPTURE_DIR" ]] && { echo "❌ 找不到 capture 目录"; exit 1; }
PP_TABLE_ID=$(jq -s -r '.[0].tableId' "tmp/$CAPTURE_DIR/tableConfig.txt")

cat "tmp/$CAPTURE_DIR/state.json" 2>/dev/null  # 检查恢复点
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

`tmp/<capture-dir>/`：

> `<capture-dir>` = hall external_code（**数字**，如 `2244`），**不等于 PP tableId**（字符串，如 `gatesofolympus01`）。
> hall-for-live 上游不支持长 gameId 取启动链接，fetch_client.mjs 用 hall external_code 命名 capture 目录。
> AI 永远从 `tableConfig.txt` 第一条记录的 `tableId` 字段反查 **真实 PP tableId**（用于机台目录命名 / enum.TableID / instance_factory 注册），目录名只是 capture 路径。

- `message.txt` — **有头下注会话**的 game WS 双向帧（每行 JSON）= **我方 ↔ 下游用户的完整协议**（下游视角全集：广播帧 + per-user 帧 bet echo / win / 决策回执 tiDecision* / 个人派彩 tiPlayerWin / tiMapReveal 等。我方**需自合成**的帧的真实 shape 都在这；录"下注但不操作"时 per-user 帧还带 auto 建议 + `autoDec:true` → 无操作 auto-decision 默认行为）
- `message-nobet.txt` — **无头 nobet 影子账号（不下注）**会话的 game WS 帧 = **上游广播给我方的完整协议**（mirror-feed 我方不向上游下注，生产真正收到的就是这一份；含 init 握手帧 + **每一局**全桌广播。与 message.txt 同机台、同批局、时间对齐）
- `tableConfig.txt` — tableConfig 响应（**含真实 PP tableId 字段，AI 唯一权威**）
- `statisticHistory.txt` — 历史响应
- `gameDetail.txt` — `cgibin/usermanagement/audit/game.jsp` 玩家历史 XML（**BuildGameDetail 权威数据源**，每行一条，推荐 ≥ 1）
- `roundDetail/` — `gameHistory/game.jsp?token=...` PP 报表页面 HTML 目录（**报表前端页 1:1 还原的权威基线**，每 round 一对 `{rid}.html` + `{rid}-Details-<userId>.html`，含 PP SPA 渲染完成后的 DOM + 内嵌 base64 SVG；report 重构后由 `client/reports/<tableId>/` 前端页复刻它，后端不再 render HTML）
- `clientResources/apps/<gameLoaderKey>/<ver>/main.js`

### message.txt vs message-nobet.txt —— 协议分类权威（mirror-feed 机台核心）

两份同机台、同批局、时间对齐，**对照即得协议分类，零猜测**（取代旧 uId 启发式 / 事后单独补录对照）：

- **`message-nobet` 有的事件** = 上游广播给我方 → 我方 mirror-feed 生产**能收到**。`HandleUpstream` 解析/转发/缓存的契约**以 message-nobet 为准**。分 A 直转 / A2 communal 演出（bonus board / dice / 开球等）/ B rewrite 注入我方（如 winners）。
- **`message.txt` 有、`message-nobet` 没有的事件（按顶层 key diff）** = per-user 会话定向 → 我方生产**收不到、必须自合成（C 类）**：bet echo / win / tiDecision / tiDecisionInc / tiMapReveal / tiPlayerWin / betValidationError 等。**shape 从 message.txt 取**（含 auto-decision 行为）。
  - 🔴 **C 类帧不止验 shape，必须验时序（铁律）**：每个自合成帧相对生命周期帧（betsopen/betsclosed/`<gametype>`gameresult/winners）的**发送时机**要对照 capture（看 message.txt 里该帧的 ts 落在哪些帧之间），与真实 PP 一致。错时序的典型恶果：bet echo 下注期发 → 客户端定格、只能下一个位置（J10）；win 早于 winners → 帧序错乱；tiDecisionInc 漏发/迟发 → 客户端无法进入操作。**只对内容不对时机 = bug**。
- ⚠️ **init 回放序列 ≠ message-nobet 全集**：message-nobet 是 init 握手帧 + 每局广播的**全流**；init 回放仍按客户端状态机反向分析取「最少 + 最必要 + 尽量自合成」子集（见 phase-3-aiu-L1 DICT，逻辑不变）。**不可把 message-nobet 整段塞进 init**。
- ⚠️ **mirror-feed 判定**：message-nobet 只发 `<ping>`、整流无 per-user 帧 → 实锤"我方不向上游下注，下游对我方下注、我方本地结算"（同 jackpotwheel）。若某机台 message-nobet 反而含 per-user（罕见，真上游下注模型），则非 mirror-feed，分类规则不适用。

> **⚠️ diff 是候选不是真相 —— 双判据 + 客户端代码兜底（铁律）**：
> 1. **采样缺口**：某帧不在 message-nobet **≠ 不广播**，可能只是没采到那种 bonus 局 / 边角触发（message-nobet 自愈重连 + `flags:'w'` 截断重录，单份覆盖有限。treasureisland 实例：某份重录后只剩 Bingo+BBM，Marbles/CFT 演出帧误入 C 列，实为广播）。→ **uId 双判据定锤**：无 uId + 桌级字段(tableId)=广播(A/A2/B)；有 uId / 个人会话定向=per-user(C)。**diff 出候选，uId + 跨多份 no-bet feed 交叉才能定**。
> 2. **录制天然不完整，必须结合客户端代码**：capture 只是"录时恰好发生的"，**不是完整协议**。特殊 / 稀有帧（错误 betValidationError、取消 canceled、会话 session、稀有 bonus 如 rc8 CFT 录几小时都不出、桌级自动消息 toasterMessage 整份仅 1 条易漏）可能**从不出现**在任何 capture。**不可"没录到=不存在"** —— 必须结合客户端 JS chunk 协议反推（事件名/字段/渲染组件）+ 同供应商既有机台沉淀。**capture 是事实下限，非协议上限**。

#### token 失效 / 同桌互斥 / 视频连接边界

- **同 token 同桌互斥**：只在 game WS 做桌级 lease；第二个窗口进入同一桌时，新连接抢占成功后继续玩，旧连接收到 `{"duplicated_connection":{}}` 并关闭。不要把该帧发给新连接，否则 `Continue Here` 会无效或出现两个窗口轮流顶号。
- **token/session 失效**：`session.offline` 只用于 token 失效、会话被注销、账号被别处使用等真正失效场景；发送后客户端会按 PP 原生流程关闭 game/video/chat 并提示用户。不要把 Redis 占用失败、内部错误、同桌互斥误包装成 `session.offline`。
- **视频/chat/dga/stub**：这些连接只做 token 失效保险监控，不能做桌级互斥 lease。PP 视频可能重连或存在多路流；给 video 加玩家占用会直接导致游戏内视频 WS 被拒绝。
- **错误处理**：lease/Redis 异常无法判定玩家状态时，宁可记录日志并关闭当前异常连接，不能伪造 duplicate/session 协议给客户端，避免触发错误弹窗和错误流程。
- **验证点**：补 game WS 同桌抢占测试（旧连接收到 duplicate、新连接可继续）、video WS 不因 game lease 被拒测试、token 失效关闭 game/video/chat 的回归测试；不要只验证单浏览器登录。

录制工具：pp-game 仓库 `scripts/game_dev/fetch_client.mjs`（**双路会话**：有头下注 → message.txt；无头 nobet 影子账号 → message-nobet.txt；浏览器自动点 Details，数据落 `.txt` / `.html`）。**本 skill 不主动录**。

## 8 Phase 概览 + 读取计划（progressive disclosure）

**重要**：每 phase 执行**前**才读对应 reference，不要预先读全部。每 phase 完成更新 state.json 才进下一 phase。

| Phase | 工作 | 执行前读 |
|---|---|---|
| **0** | 输入验收（含 capture 目录归属校验）+ 元信息抽取 | `references/phase-0-acceptance.md` |
| **1** | 选 base + factory 注册检测（AI 直接 bash） | 本 SKILL.md「Phase 1」节即可 |
| **2** | 创建 worktree（调 worktree-task-flow init-worktree.sh）— 自此无人值守 | 本 SKILL.md「Phase 2」节即可 |
| **3** | AIU DAG 实现（5 层 18 单元，每层完成立即层间 codex 审查；**L3.4 BuildGameDetail（Go XML）/ L3.5 报表前端页（client/reports/<tableId>/，自包含一机台一份，后端零代码）**） | `references/phase-3-aiu-overview.md`，进入某 L 时再读对应 `phase-3-aiu-LN.md` + `phase-3-layer-review.md` |
| **4** | 对接铁律核对 5 题（历史 P0 沉淀的项目特有陷阱）；有争议的问题才调 codex_decide | `references/phase-4-self-review.md` |
| **5** | 整体循环 codex review（≤5 轮） | `references/phase-5-overall-review.md` |
| **6** | verify 全量（含 I9/I10 + V10-V13 生产 bug 闸门 + V14 赢钱反推 + **V16 资金安全 /bet→/result wiring 闸门**） | `references/phase-6-verify.md` |
| **7** | 经验文档归档（16 节） | `references/phase-7-experience-doc.md` |

**跨 phase 共用 references**（按需 grep，不必预读）：
- `references/codex-collab.md` — 三模式调用 + 全 prompt 模板 + state 跟踪
- `references/known-pitfalls.md` — 协议铁律 A-J 精华版（J = 生产 bug 复盘）

## Phase 1 — 选 base + factory 检测（AI 直接执行）

```bash
# CAPTURE_DIR / PP_TABLE_ID 在「触发后第一步」已经从 tableConfig 校验完成。
# Phase 1 起所有路径用 CAPTURE_DIR，所有 enum.TableID / 注册键用 PP_TABLE_ID。
TABLE_ID="$PP_TABLE_ID"; REPO_ROOT=$(git rev-parse --show-toplevel); STATE="$REPO_ROOT/tmp/$CAPTURE_DIR/state.json"
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
  "tableId": "gatesofolympus01",     // 真实 PP tableId（从 tableConfig 抽，机台目录名 / enum.TableID 用）
  "capture_dir": "2244",             // capture 目录名（hall external_code，所有 tmp/<dir>/ 路径用）
  "phase": 3, "status": "done|failed|skipped|degraded",
  "base_branch": "live", "worktree_path": "...", "worktree_branch": "...",
  "lobby": { "gameType": "...", "gameLoaderKey": "...", "limits": {...} },
  "capture_audit": { "p0_passed": true, "p1_warnings": [...] },
  "aiu_progress": { "L1": {"done": [...], "commits": [...]}, ... },
  "codex_reviews": [], "codex_decisions": [], "codex_discussions": [],
  "self_review_path": "tmp/<capture_dir>/self-review.md",
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
