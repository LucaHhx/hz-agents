---
name: evo-game-develop
description: EVO (Evolution Gaming) 真人桌游戏族对接工作流。用户提供 capture 数据（6 文件包），AI 完成全自主对接，主攻「从零建一个新 EVO 游戏族 core」（baccarat / blackjack / sicbo / dragontiger / game show 等，EVO 现仅有 roulette 一族）。触发：(1) 用户给出 EVO tableId（如 "vctlz20yfnmp1ylr"）并提供 tmp-evo 下对应目录数据包；(2) 明说"用 evo 流程对接" / "对接 EVO 机台" / "新增 EVO 游戏族"。与 pp-game-develop 同构：8 phase 全自主 + AIU DAG 分层 + 三层审查防线（层间 codex / 自问审查 / 整体循环）+ codex-collab 三模式调度 + worktree 隔离 + state.json 断点。与 PP 的本质区别：PP 多数帧直转，EVO 大量帧是 per-session 会话私有（具体帧随游戏族而异：roulette 是 tableState.betState/win，game show 是 bets/balanceUpdated），必须按每个下游用户改写/补结构后定向下发——per-user 数据构造是 EVO 对接的工作量大头。roulette 是现仅有的已建 core，其协议形态是范例非通用，新游戏族必须从 capture 自行推导协议 shape。不在范围：纯协议讨论 / PP 机台（走 pp-game-develop）/ 大厅·会话·视频·容灾基础设施（已建好，本流程复用不重写）。
---

# evo-game-develop

EVO 真人桌对接流程。8 phase；Phase 0/1 可问用户，Phase 2+ 完全无人值守由主 Claude + codex-collab 协作。**主攻新游戏族**：runtime/gateway/video/lobby/failover 基础设施已建好且与机台无关，新游戏族 = 新建一个 `evocore` 包 + 工厂注册 + DB 行 + 报表页，**不碰基础设施**。

## 触发后第一步

```bash
cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "❌ 不在 git 仓库"; exit 1; }
[[ -d server/game/evo && -f scripts/game_dev/evo_fetch.mjs ]] || { echo "❌ 不在 pp-game 仓库（无 evo vendor）"; exit 1; }

export SKILL_DIR="$(dirname "$(realpath "$(find ~/.claude/skills ~/github -path '*evo-game-develop/SKILL.md' 2>/dev/null | head -1)")")"
export CODEX_COLLAB="$(dirname "$(realpath "$(find ~/.claude/skills ~/github -path '*codex-collab/SKILL.md' 2>/dev/null | head -1)")")"

[[ -x "$CODEX_COLLAB/scripts/codex_review.sh" \
   && -x "$CODEX_COLLAB/scripts/codex_decide.sh" \
   && -x "$CODEX_COLLAB/scripts/codex_discuss.sh" ]] || { echo "❌ codex-collab 不完整"; exit 1; }

# capture 目录定位（EVO 比 PP 简单：目录名 = 真实 EVO tableId，不是 hall external_code）。
# 用户输入可能是 EVO tableId（"vctlz20yfnmp1ylr"）或 b_tables.code（"evovctlz20yfnmp1ylr"，带 evo 前缀）。
INPUT_ID="<用户给的 ID>"
CAPTURE_DIR=""
if [[ -d "tmp-evo/$INPUT_ID" && -s "tmp-evo/$INPUT_ID/config.txt" ]]; then
    CAPTURE_DIR="$INPUT_ID"
elif [[ -d "tmp-evo/${INPUT_ID#evo}" && -s "tmp-evo/${INPUT_ID#evo}/config.txt" ]]; then
    CAPTURE_DIR="${INPUT_ID#evo}"     # 剥 evo 前缀（用户给了 b_tables.code）
else
    for d in tmp-evo/*/; do
        TID=$(grep -oE '"table_id"[: ]*"[^"]+"' "$d/config.txt" 2>/dev/null | head -1 | sed -E 's/.*"([^"]+)"$/\1/')
        [[ "$TID" == "$INPUT_ID" || "$TID" == "${INPUT_ID#evo}" ]] && { CAPTURE_DIR=$(basename "$d"); break; }
    done
fi
[[ -z "$CAPTURE_DIR" ]] && { echo "❌ 找不到 capture 目录（应在 tmp-evo/<EVO tableId>/）"; exit 1; }
EVO_TABLE_ID="$CAPTURE_DIR"               # EVO 原始 tableId，用于协议帧（subscribe channel / win.tableId / game ws path）
TABLE_CODE="evo${EVO_TABLE_ID}"           # b_tables.code，用于 instance_factory 索引 / 准入 / Variant.TableID

cat "tmp-evo/$CAPTURE_DIR/state.json" 2>/dev/null  # 检查恢复点
```

- state.json **不存在** → fresh start，进 Phase 0
- state.json **存在** → 按 `state.phase + 1` 继续

## EVO ID 体系（核心铁律，搞错运行时全挂）

| 概念 | 值 | 用途 |
|---|---|---|
| `EVO_TABLE_ID`（= capture 目录名） | `vctlz20yfnmp1ylr` | EVO 原始 tableId。**协议帧**里用：上游 game ws path `/public/<gt>/player/game/<EVO_TABLE_ID>/socket`、subscribe channel `table-<EVO_TABLE_ID>`、下发 `win.tableId` / `balanceUpdated.tableId`（客户端按 URL 匹配，填错判「余额未收到」→ 重连）。`enum`/`Variant.PPTableID` 存它。 |
| `TABLE_CODE`（= `evo`+tableId） | `evovctlz20yfnmp1ylr` | `b_tables.code`，我方机台编号。**索引/路由**用：`instance_factory.implementedTables` 键、`FindByTableCode`、下游 game ws path `:tableId`、`Variant.TableID`、Redis bet key。 |
| `gameType` | `roulette` | 游戏族目录 `games/<gameType>/<gameType>core/`、game ws path `<gt>` 段。 |

> 🔴 **两者绝不混用**：`Variant.TableID = table.Code`（带 evo 前缀，我方索引）；`Variant.PPTableID = table.OriginalId`（裸 EVO tableId，协议帧用）。下发给客户端的 `tableId` 字段一律用 **PPTableID（裸 EVO tableId）**——填 code 客户端 URL 不匹配，判余额/桌态不属本桌。

## 用户交互边界（核心铁律）

| 阶段 | 与用户交互 |
|---|---|
| Phase 0 | ✅ 可汇报失败 + 列补救 |
| Phase 1 | ✅ 可确认 base / 新族命名（如歧义） |
| **Phase 2+** | **❌ 禁止提问，所有不确定走 codex-collab，失败 fallback 写 `state.unresolved[]`** |

## 用户提供的数据契约（必备）

`tmp-evo/<EVO_TABLE_ID>/`（目录名 = 真实 EVO tableId）：

- `message.txt` — **有头下注会话**的 game WS 双向帧（每行 JSON：`{ts,dir,payload}`，🔴 **`payload` 是 JSON 编码的字符串、不是对象**——解析一律 `.payload|fromjson|.type`，直接 `.payload.type` 抛 `Cannot index string with string` 终止脚本；`dir` ∈ `recv`/`send`/`ws`，`ws` 是连接 open/close 事件无 payload）= **我方 ↔ 下游用户的完整协议**（下游视角全集：公共桌态广播 + **per-user 帧**，其 type 名/shape **随游戏族而异**：roulette = `betAction` echo/`betsAccepted`/`betActionResponse`/个人 `win`/per-user `tableState.betState`；game show(IceFishing) = `<gt>.placeChips` echo/**`<gt>.bets`**(会话私有 `state.{status,chips,acceptedBets,rejectedBets,repeat,history}`，合并了 roulette 的 betState+受理+派彩四职能)/`balanceUpdated`/`betValidationError`。我方生产**收不到、必须自合成或 per-user 改写**的帧真实 shape 都在这）
- `message-nobet.txt` — **无头 nobet 影子账号（只看不动）**会话的 game WS 帧 = **上游广播给我方的完整协议**（mirror-feed：我方一会话连上游 game ws、不下注，生产真正收到的就是这一份；含 init 握手帧 + 每局全桌广播（**帧名随族而异**：roulette=`tableState`(5 态)/`winSpots`/`winnersList`/`recentResults`；game show=`<gt>.betsOpen/betsClosed/wheelSpinning/wheelStopping/wheelResult/gameResolved/gameCleared`(离散生命周期 7 帧)/`<gt>.winnersList`/`<gt>.spinHistory`/**`<gt>.bettingStats`**(投注热度聚合，最高频)/`<gt>.bonus`(演出)）+ `dealer`/`appInfo` + 渠道 `balanceUpdated`。与 message.txt 同机台、同批局、时间对齐。影子账号严格"只看不动"→ 此份 per-user 帧只剩公共空壳，per-session 私有内容为空，**但同名帧仍会广播**——实锤 mirror-feed，但也意味着「集合差」找不出 game show 的 per-user 帧，见 §2A）
- `config.txt` — `/config?table_id=X` 响应（150+ keys，可能 `{_source,_endpoint,data}` 包裹、限红在 `.data`：`table_id` / `game_type` / `currencyCode` / **`currencyMult`（进制：IDR÷20000、BRL×5、INR×100，所有金额必乘）** / `chipAmounts` / 限红字段（**随族而异**：roulette=`table_bet_min/max_limit`+betType 分注限额；game show=per-betcode `<segment>_bet_min/max_limit`+`payout_limit`）/ 视频 `video.stream.name`·`video.token.issuer`·区域 host / `wsUrl` / `wrapper_token` JWT。**EVO 无 PP 的 tableConfig.txt**，桌运行配置全在这）
- `gameDetail.txt` — `/public/player/history/v{N}/game/{id}` 玩家单局结算记录（`BuildGameDetail` / history API 权威数据源；EVO 多为 JSON，非 PP 的 XML）
- `roundDetail/` — `{rid}.html`（玩家可直开报表页，1:1 还原基线）+ `{rid}.json`（hall B2B `evo/rounds/{rid}/detail` 完整结算体：participants/bets/result.outcomes。**EVO 比 PP 多这份结构化 JSON**，报表前端页可直接对照）
- `clientResources/frontend/` — 前端 bundle（`evo/mini/js/` 业务逻辑·协议常量、`loc/strings/<lang>/` 本地化、`cvi/evo-video-components/` 视频组件含 descrambler；协议字段 / betCode / 视频 token 算法逆向源）

录制工具：pp-game 仓库 `scripts/game_dev/evo_fetch.mjs`（**双会话对比**：有头下注 → message.txt；无头 nobet 影子账号 → message-nobet.txt；浏览器自动开 Details，落 `.json`/`.html`）。**本 skill 不主动录**。

### message.txt vs message-nobet.txt —— 协议分类权威（mirror-feed 核心）

两份同机台、同批局、时间对齐，**对照得分类**。EVO 信封一帧一事件，但 🔴 **`payload` 是 JSON 字符串**——解析一律 `jq '.payload|fromjson|.type'` 且先 `select(.dir=="recv" or .dir=="send")` 排除无 payload 的 `ws` 帧。帧名前缀随族而异（roulette=`roulette.*`，IceFishing=`icefishing.*`）。按 `type` 分**四类处置**：

- **A 直转/广播**：纯公共展示（roulette `recentResults`；game show `<gt>.spinHistory`）+ `appInfo`/`dealer`。🔴 **`winnersList`/`bettingStats` 名为公共帧但不在此列**——必须**先合并我方数据再广播**（winnersList 注入我方本局中奖者按 payout 重排、bettingStats 叠加我方计数），裸直转会漏我方 seamless 玩家上榜/计数（IceFishing000001 实测被用户指证，见 known-pitfalls B8/B11）。
- **A2 communal 演出帧**（game show 常有，roulette 无）：全桌一份开奖动画（`<gt>.wheelSpinning`/`wheelStopping`/`wheelResult`/`bonus`，含 `<segment>Multipliers`/`sector`）→ **直转广播、不剥不改写、不缓存**（迟到的演出帧客户端自丢）。与结算锚帧区分：演出帧只驱动客户端动画、不碰资金。
- **B per-user 改写**：会话私有态剥离后按下游连接回填。判定对象不是固定 type 名，而是**任一同名帧内的个人字段**：下注快照、上局 repeat、受理/拒单、派彩、个人余额等。若一个结果/终局帧在有下注会话出现个人下注/派彩子对象，而 nobet 同名帧没有该子对象，则该帧是 **公共开奖 + per-user 私有字段混合帧**：公共字段可广播，私有字段必须按连接注入；无注连接保持 nobet shape。
- **handle 业务**：驱动状态机/结算（开窗 `betsOpen`、关窗 `betsClosed`、结算锚 roulette `tableState{GAME_RESOLVED}`+`winSpots` / game show `<gt>.gameResolved`）。
- **C 自合成**（message.txt 有 + 上游不主动给）：下注回执（roulette `betAction` echo/`betsAccepted`；game show `<gt>.placeChips` echo/`<gt>.bets`）、个人 `win`、`betValidationError`、`fetchBalance` 应答、`subscribe` ack。**shape 从 message.txt 取**。

🔴 **找 per-user 帧的判据（铁律，最易错）**：**不能只靠 type 集合差（`comm -23`）**——那只对「per-user 帧从不广播」的族成立；同名帧也可能一边是公共空壳、一边夹带个人字段。每个 type 必须做三层 diff：①计数差；②`args` key-set / 嵌套 key-set 差；③字段值域差（影子会话个人字段恒空/默认，有下注会话出现筹码、受理、派彩、余额）。只要同名帧含个人字段，就不能裸广播。

#### 消息分类判定方法（不要写死 type）

对每个 `recv` / `send` type 生成一张 `message_classification` 表，逐项写 capture 证据：

| 判定问题 | 归类 |
|---|---|
| 是否改变下注窗口、当前局号、开奖结果、取消/退款、结算倍率，或后续资金处理依赖它？ | **handle**。处理业务副作用；若同帧还含个人字段，再叠加 B per-user 改写。 |
| 同名帧在 message 有个人字段、message-nobet 无或为空；或计数明显随下注增加；或字段语义是本人注单/余额/派彩/受理/拒单/rebet？ | **B per-user 改写/drop+重发**。不能裸广播；按连接 userId 构造。 |
| 是否只驱动全桌动画、走势、荷官、桌信息、公共倍率展示，且两份 feed shape/值域一致，无个人字段？ | **A/A2 直转**。演出帧通常不缓存；init/走势类按需缓存。 |
| 是否是上游不会给我方、但客户端下注/初始化/设置/余额流程必须收到的回执？ | **C 自合成**。shape 从 message.txt 的 send/recv 样本取。 |
| 是否是上游渠道账号余额、订阅 ack、心跳、影子账号恢复标记、连接踢出等不应给下游的代理会话数据？ | **drop**。需要时由我方按下游连接自合成等价帧。 |

🔴 **per-user 帧时序 + 余额来源（铁律）**：① 余额用**商户钱包**（drop 上游渠道 USD `balanceUpdated`，**按下游连接寻址 per-connection 重发**——`balanceUpdated` 不一定带 playerId，IceFishing 只含 `balance/balances[]/currencyCode/tableId`，靠 ws 连接定向），客户端 ~6s 收不到即重连；② 下发帧 `tableId` 用**裸 EVO tableId**（PPTableID），填 code 客户端判「未收到」；③ 结算 per-user 帧在**结算锚帧触发清 Redis 之前**抓 `userBetsSnapshot`；④ `currencyMult` 进制——所有金额按币种乘系数。

⚠️ **diff 是候选不是真相**：稀有帧（`betValidationError`/`canceled`/`gameCancelled`/`restore`/特殊货币/大奖）可能从不出现。结合 `clientResources/frontend/evo/mini/js/` 反推 + roulette 既有实现沉淀。capture 是事实下限。

### 🔴 新游戏族：协议 shape 必须从 capture 自推导（铁律）

EVO 现仅 roulette 一族；上文及各 reference 的 roulette 帧（5 态 `tableState`、`betAction` PLACE/UNDO、`winSpots`、号码赔率、无 betstats）是 **roulette 特化范例，不是 EVO 通用契约**。新族对接**先抽 recv/send type 全集**（`jq -rs 'select(.dir=="recv")|.payload|fromjson|.type' nobet | sort | uniq -c`），实证下面 6 个变量轴，**禁止照搬 roulette 形态**：

| 变量轴 | roulette | game show（IceFishing 实证） | 推导来源 |
|---|---|---|---|
| 状态机 | `tableState.state` 5 态枚举 | 7 离散事件帧 `betsOpen→betsClosed→wheelSpinning→wheelStopping→wheelResult→gameResolved→gameCleared`（无 state 枚举，`tableState` 仅绑 balanceId） | message-nobet 时序 |
| 下注模型 | `betAction{type:PLACE/REMOVE/MOVE/UNDO,value}` 增量 + UNDO 栈 | `placeChips{chips:map[段名]额, betAction:"Place"\|"Repeat", betTags}` 全量快照、无 UNDO 栈（撤注走独立 `<gt>.undo/undoAll`） | message.txt send 帧 |
| betCode | 数字键（`"43"`） | 字符串段名（`Leaf1`/`LilBlues`）；结算侧带前缀（`IF_Leaf1`），**两套码须双向映射** | 下注帧 + roundDetail json |
| 结算/赔付 | 押中号码集→固定 odds，`amount×(odds+1)` | 押中 segment→该局倍率（`gameResolved.{<seg>Multipliers,totalMultiplier}`），`amount×倍率`（未中=0） | gameResolved + roundDetail json |
| betstats | **无** | **有** `<gt>.bettingStats{bettors,watchers}`（最高频，communal 聚合计数，**非 per-player**——只能加我方聚合计数、不能注单玩家注） | type 统计 |
| A2 演出帧 / restore | 无 | 有（wheel/bonus 全桌动画 + `<gt>.restore.begin/end{version}` 重连恢复包） | type 统计 |

**EVO 通用、与族无关、照抄复用**：per-user 数据构造机制 / 资金流（drop 渠道余额、商户钱包 per-connection 重发、/result 必先 /bet、OnRoundSettled 必调、snapshot-before-settle）/ JSON `{type,args(,id)}` 信封（payload 字符串需 fromjson）/ mirror-feed 双会话 / ID 双字段（PPTableID 裸 id vs TABLE_CODE）/ currencyMult 进制 / lobby·video·failover 基础设施复用。

## 8 Phase 概览 + 读取计划（progressive disclosure）

**重要**：每 phase 执行**前**才读对应 reference，不要预先读全部。每 phase 完成更新 state.json 才进下一 phase。

| Phase | 工作 | 执行前读 |
|---|---|---|
| **0** | 输入验收（capture 6 文件 + 协议分类 diff）+ 元信息抽取 | `references/phase-0-acceptance.md` |
| **1** | 选 base + 复用边界判定（新游戏族 / 复用既有 core）+ factory 注册检测 | 本 SKILL.md「Phase 1」节即可 |
| **2** | 创建 worktree（调 worktree-task-flow init-worktree.sh）— 自此无人值守 | 本 SKILL.md「Phase 2」节即可 |
| **3** | AIU DAG 实现（5 层，建 `evocore` 包 + per-user 构造 + 工厂注册 + 报表页；每层完成立即层间 codex 审查） | `references/phase-3-aiu-overview.md`，进入某 L 时再读 `phase-3-aiu-LN.md` + `phase-3-layer-review.md` |
| **4** | 自问审查 + codex_decide 每题决策 | `references/phase-4-self-review.md` |
| **5** | 整体循环 codex review（≤5 轮） | `references/phase-5-overall-review.md` |
| **6** | verify 全量（per-user 闸门 + 资金 /bet→/result + 货币/视频边界） | `references/phase-6-verify.md` |
| **7** | 经验文档归档 | `references/phase-7-experience-doc.md` |

**跨 phase 共用 references**（按需 grep，不必预读）：
- `references/per-user-frame-fidelity.md` — 🔴 **per-user 合成帧保真度方法论（L3 PER_USER 必读，反复踩坑根因）**：三方对比（nobet 收=原料 / 我方合成 / message.txt=客户端期待 target）+ 逐相位×逐 status 字段契约 + 广播频率契约 + 「客户端渲染源」判定 + wire 单测。漏字段/频率不足 = 客户端崩 `undefined.map`/卡死/不渲染，编译+单测+codex 都查不出，**只能靠这套方法论提前发现**。
- `references/evo-platform-primer.md` — EVO 基础设施复用边界 + **per-user 数据构造全模式** + roulettecore 作为新族模板逐文件映射（Phase 1/3 高频参考，EVO 最关键文档）
- `references/codex-collab.md` — 三模式调用 + 全 prompt 模板 + state 跟踪
- `references/known-pitfalls.md` — EVO 协议铁律 A-J 精华版（per-user / 资金 / 视频 / 货币 / 容灾）
- `references/phase-3-game-record-render.md` — **游戏记录详情 render 1:1 复刻方法**（L4.3 配套）：renders 子包架构 + 四步法（分析 / 验资源 / 抽模板 / 字节对比）+ 逆向硬细节 + bonus 帧落库。让「我的历史→游戏详情」局面区逐字节还原，非纯文字降级。

## Phase 1 — 选 base + 复用边界 + factory 检测（AI 直接执行）

```bash
# CAPTURE_DIR / EVO_TABLE_ID / TABLE_CODE 在「触发后第一步」已确定。
REPO_ROOT=$(git rev-parse --show-toplevel); STATE="$REPO_ROOT/tmp-evo/$CAPTURE_DIR/state.json"
GAMETYPE=$(jq -r .lobby.gameType "$STATE")
BASE_BRANCH=""; WHITELIST=(live live-dev dev pre)
[[ -n "${EVO_BASE_BRANCH:-}" ]] && BASE_BRANCH="$EVO_BASE_BRANCH"
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

# 复用边界：该 gameType 是否已有 evocore 包？
REUSE_CORE="none"
if [[ -d "$REPO_ROOT/server/game/evo/internal/games/$GAMETYPE" ]]; then
    REUSE_CORE="$GAMETYPE"   # 已有同族 core（如又一张 roulette 桌）→ 只加 factory case + DB，几乎零新代码
fi

# factory 已注册检测（键 = b_tables.code 带 evo 前缀）
if grep -q "\"$TABLE_CODE\":" "$REPO_ROOT/server/game/evo/internal/factory/instance_factory.go" 2>/dev/null; then
    jq --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '. + {phase:1,status:"skipped",already_registered:true,last_updated:$ts}' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
    exit 0  # 流程结束
fi

jq --arg b "$BASE_BRANCH" --arg rc "$REUSE_CORE" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   '. + {phase:1,status:"done",base_branch:$b,reuse_core:$rc,last_updated:$ts}' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
```

- `reuse_core != "none"` → **复用既有 core**：Phase 3 退化为「factory case + DB 行 + 报表页 + per-user/限额差异核对」，AIU DAG 大幅收敛（见 `phase-3-aiu-overview.md`「复用分支」）。
- `reuse_core == "none"` → **新游戏族**（本 skill 主攻）：Phase 3 走完整 AIU DAG 建 `games/<gametype>/<gametype>core/` 全套。

## Phase 2 — 创建 worktree

```bash
TAIL=$(echo "$EVO_TABLE_ID" | tail -c 9)
WT_SKILL=$(dirname "$(realpath "$(find ~/.claude/skills ~/github -path '*worktree-task-flow/SKILL.md' 2>/dev/null | head -1)")")
bash "$WT_SKILL/scripts/init-worktree.sh" "$BASE_BRANCH" "evo-${GAMETYPE}-${TAIL}"
# 抓输出的 worktree_path + branch，写入 state
```

🔒 **本步完成即进入完全无人值守**。Phase 3-7 禁止向用户提问。

## state.json 字段

```jsonc
{
  "evo_table_id": "vctlz20yfnmp1ylr",   // 裸 EVO tableId（capture 目录名 / 协议帧 / PPTableID）
  "table_code": "evovctlz20yfnmp1ylr",  // b_tables.code（factory 索引 / Variant.TableID）
  "capture_dir": "vctlz20yfnmp1ylr",    // = evo_table_id，所有 tmp-evo/<dir>/ 路径用
  "phase": 3, "status": "done|failed|skipped|degraded",
  "base_branch": "live", "reuse_core": "none|roulette", "worktree_path": "...", "worktree_branch": "...",
  "lobby": { "gameType": "...", "casinoHost": "...", "currencyMult": 20000, "limits": {...}, "dealer": {...} },
  "capture_audit": { "p0_passed": true, "p1_warnings": [...], "classification": {"broadcast":[...],"per_user":[...]} },
  "aiu_progress": { "L1": {"done": [...], "commits": [...]}, ... },
  "codex_reviews": [], "codex_decisions": [], "codex_discussions": [],
  "self_review_path": "tmp-evo/<capture_dir>/self-review.md",
  "unresolved": [],
  "last_updated": "ISO-8601"
}
```

## 完成判定

8 phase 全 done / Phase 0 拒收 / Phase 1 skip。最终输出：

1. worktree 子分支（commits + 文档归档）— 不 PR
2. `docs/integration-experience/evo/<evo_table_id>.md`
3. `tmp-evo/<evo_table_id>/self-review.md`
4. 完成摘要（commits / coverage / codex 调用次数 / unresolved 数）

## 关联

- **EVO 基础设施全景 + per-user 构造模式**：`references/evo-platform-primer.md`（最重要的 EVO 特异性文档，Phase 1/3 必读）
- EVO 设计文档（仓库内，背景参考，注意是实现前方案，以 as-built 代码为准）：`docs/evo-explore/{EVO-GAME-TABLE-DEV-GUIDE,GAME-TABLE-SELFHOST-DESIGN}.md`
- 新族模板：`server/game/evo/internal/games/roulette/roulettecore/`（17 文件，逐文件映射见 primer）
- 必需协作 skill：`codex-collab`（Phase 2+ 唯一决策途径）
- 工具 skill：`worktree-task-flow`（仅复用 `scripts/init-worktree.sh`）
- 域名占位铁律：对接文档用 `<PROVIDER_HOST>`/`<CLIENT_HOST>` 占位符，真实域名只在会话里给
