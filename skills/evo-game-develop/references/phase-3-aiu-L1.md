# Layer 1 AIU — 无依赖（4 并行）

> 进入 L1 前确保 Phase 0 / 1 / 2 已 done。
> L1 是整个对接的协议事实基础，下游全部依赖；ENUM / ODDS_BETCODE 失败 = block 整层（前者协议常量、后者资金赔率）。
> 新族 = `games/<gametype>/<gametype>core/`；模板逐文件见 `evo-platform-primer.md §4`。

## L1.1 — ENUM

**产物**：`server/game/evo/internal/games/<gametype>/<gametype>core/enum.go`

**分析输入**（按需读，不读全部；**payload 是 JSON 字符串，统计用 `.payload|fromjson`**）：
- `tmp-evo/<dir>/message-nobet.txt` recv 帧抽 type 全集（上游事件名 + 状态机帧；**先判状态机 kind**：有 `tableState.state` 枚举即 state_enum，否则离散事件型）
- `tmp-evo/<dir>/message.txt` send 帧抽下游帧全集（看下注帧真名：roulette `betAction{action.type}`；game show `<gt>.placeChips{betAction:"Place"/"Repeat"}`，撤注独立 `<gt>.undo/undoAll`）
- `tmp-evo/<dir>/config.txt` 限红字段名 / currencyMult / game_type
- `clientResources/frontend/evo/mini/js/` grep errorCode 字面量 / 事件名常量

**实现内容**：
- `Variant` 字段约定：`TableID`(=table.Code 带 evo 前缀，我方索引) / `PPTableID`(=table.OriginalId 裸 EVO tableId，协议帧用) / `GameType` / `TableLabel`（**ID 双字段是 EVO 铁律，搞混运行时全挂**）
- 上游事件 type 常量（按 DICT 全集，新族换前缀）
- 🔴 **状态机常量两形，从 capture 判 kind**：(a) **state 枚举型**（roulette）：`State*` 常量 `StateBetsOpen/.../StateGameResolved`，单 `tableState.state` 字段切态；(b) **离散事件型**（game show，IceFishing）：每生命周期是独立 type 帧 → 定义 `Evt*` 事件常量 `EvtBetsOpen="<gt>.betsOpen"`/`EvtBetsClosed`/`EvtWheelResult`/`EvtGameResolved`/`EvtGameCleared` 等，**无 state 枚举**。判据：抽 recv type，出现成对 `*.betsOpen`/`*.gameResolved` 事件帧即离散型。留 `EvtGameCancelled`(取消/退款锚)。
- 下游 action 常量（按 send 帧实测）：roulette `ActionPlace/Remove/Move/Undo`(betAction.action.type)；game show 下注模式 `BetActionPlace="Place"`/`BetActionRepeat="Repeat"` + 撤注事件 `EvtUndo="<gt>.undo"`/`EvtUndoAll="<gt>.undoAll"`
- errorCode 全集常量（betValidationError 用；不 import 其他族 — known-pitfalls I2）
- Redis key 前缀（**统一走 `server/enum/cache_key.go`，不在 evocore 硬编码**；bet key 含 `TableID`(code)+gameId）
- 默认值常量（限红/封顶兜底，与客户端 fallback 一致 — G2）

**B5 验收**：
- `go build ./game/evo/internal/games/<gametype>/<gametype>core/...` PASS
- `go vet` 无新增 warning；单测可后置

**下游消费**：所有后续 AIU

---

## L1.2 — DICT

**产物**：`tmp-evo/<dir>/dict.json`（**非代码，分析备忘**）

**分析输入**：
- 全 capture（事件名 / 字段类型全集）
- **`message-nobet.txt`（上游广播完整协议）+ `message.txt`（下游完整协议）对照 diff** → `message_classification` 直接产出（phase-0 §2A）
- `clientResources/frontend/evo/mini/js/` 业务 chunk 补 capture 没出现的偶发帧（canceled / session / betValidationError / 特殊货币）

**实现内容**（JSON 结构）：
```jsonc
{
  "gametype": "<gt>",                     // roulette / icefishing / ...
  "upstream_events": { "<gt>.gameResolved": {"_capture_evidence":"...","args_keys":[...]}, ... },
  "downstream_actions": [...],            // roulette: ["betAction(PLACE/REMOVE/MOVE/UNDO)",...]; game show: ["placeChips(Place/Repeat){chips}","undo","undoAll","fetchBalance","metrics.ping","settings.update"]
  "state_machine_kind": "state_enum | discrete_events",
  "state_machine": [...],                 // state_enum: ["BETS_OPEN",...,"GAME_RESOLVED"]; discrete_events: ["<gt>.betsOpen","<gt>.betsClosed","<gt>.wheelSpinning",...,"<gt>.gameResolved","<gt>.gameCleared"]
  "bet_model": "increment_undo_stack | full_chips_snapshot",
  "payout_model": "number_odds | segment_multiplier | card_table",
  "betcodes": [...],                      // 下注帧 betCode 全集（数字 or 字符串段名；记 roundDetail 前缀映射如 IF_）
  "error_codes": [...],                   // betValidationError 码 + 客户端 switch 分支（含 ERRCODE 分析）
  "frame_envelope": {"type":"...","args":"...","id":"...","time":"..."},
  "init_frame_sequence": [...],           // 客户端反向分析得出的 init 必发帧序列（见下）
  "message_classification": { ... },      // 每事件分类 A/B/handle/C（Phase 4 数据源）
  "_sources": ["..."],
  "_conflicts": [...]                     // capture 与 bundle 冲突时列（capture 为准）
}
```

**关键步骤 1 — init 帧序列（最少 + 最必要 + 尽量自合成）**：

`init_frame_sequence` **不是**把 capture init burst 全列，**是按客户端状态机反向推导的"启动必须最小集"**。三原则同 PP，但 **EVO init 锚点不同**——客户端连我方 game ws 后等待这些帧才解锁：

```jsonc
"init_frame_sequence": [
  {
    "event": "subscribe",
    "class": "C 自合成",
    "client_role": "新连接 server-side 发；channel=table-<裸 EVO tableId>，客户端按此路由后续帧。channel 不匹配 → 全部桌态帧被客户端丢弃。",
    "fields": ["channel(=table-<PPTableID>)","table","status"]
  },
  {
    "event": "balanceUpdated",
    "class": "C 自合成（商户余额）",
    "client_role": "🔴 init 必发；余额=商户钱包（非上游渠道 USD）。客户端 ~6s 收不到 → 超时重连 / LOW BALANCE 遮罩。tableId 用裸 EVO tableId。",
    "fields": ["balance","balances[]","currencyCode","tableId(=PPTableID)"]   // 🔴 无 playerId，按连接寻址
  },
  {
    "event": "<个人注态帧>",  // roulette: tableState(B per-user 回填 betState{bets,lastGameChips}); game show: <gt>.bets(state.{status,chips,repeat,acceptedBets,history}) + <gt>.restore.begin/end{version} 重连恢复包
    "class": "B per-user 回填",
    "client_role": "本人当前注 + Rebet 注（personalize 注入）；驱动桌面渲染 + Rebet 按钮。game show 走 <gt>.bets，roulette 走 tableState.betState。"
  },
  { "event": "dealer", "class": "A 直转/缓存回放", "client_role": "荷官名/头像；缺 → 无荷官。" },
  { "event": "appInfo / <gt>.table", "class": "A 直转/缓存回放", "client_role": "版本/桌配置校验。" }
]
```
> 离散事件型（game show）init burst 实测：`subscribe→appInfo→dealer→<gt>.table→tableState(仅 balanceId 绑定)→balanceUpdated→<gt>.restore.begin/<gt>.bets(status:Open)/restore.end`。**`restore.begin/end` 是 game show 重连状态恢复信封（roulette 无），必发**；个人注态回填走 `<gt>.bets` 非 `tableState.betState`。

分析步骤：
```bash
JS=tmp-evo/<dir>/clientResources/frontend/evo/mini/js
# a. 找客户端启动状态字段（订阅成功 / 余额就绪 / 桌态就绪）
grep -roE 'isSubscribed|onSubscribe|balanceReady|tableReady|onConnect|lowBalance' $JS | sort -u
# b. 找各事件 reducer case → state 字段切换
grep -rB1 -A4 '"(subscribe|balanceUpdated|tableState|dealer|appInfo)"' $JS | head -60
# c. 找下注解锁条件（通常 subscribe success + tableState BETS_OPEN）
grep -rB2 -A3 'BETS_OPEN' $JS | head -30
```
把结果**最小化**记入 `init_frame_sequence`：仅"客户端**等待**才解锁后续动作的帧"。

**关键步骤 2 — 消息分类（Phase 4 输入，§2A）**：四类（按本族帧名，roulette 范例）：
- **A 直转**（broadcast）：`recentResults`(roulette)·`spinHistory`(gs)/`appInfo`/`dealer`。🔴 `winnersList`/`bettingStats`(gs) 非纯直转——须合并我方（中奖者 / 聚合计数）后广播，见 B8·B11
- **A2 communal 演出帧**（game show）：`<gt>.wheelSpinning/wheelStopping/wheelResult/bonus` 全桌开奖动画 → 直转、不缓存
- **B per-user 改写**：个人注态帧剥离+回填（roulette `tableState.betState` / game show `<gt>.bets.state`）+ `balanceUpdated` drop+商户余额重发 — **EVO 大头**
- **handle 业务**：开窗/关窗/结算锚（roulette `tableState{state}`/`winSpots`；game show `<gt>.betsOpen/betsClosed/gameResolved`）
- **C 自合成**：下注回执（roulette `betAction` echo/`betsAccepted`；game show `<gt>.placeChips` echo/`<gt>.bets`）/个人派彩/`betValidationError`/`fetchBalance` 应答
- 🔴 **找 per-user/C 类帧不能只靠 type 集合差**：`comm -23` 只对「per-user 帧从不广播」的 roulette 类成立；**game show 所有 type 两份都有，集合差为空** → 改用**计数悬殊（`<gt>.bets` 146 vs 50、`balanceUpdated` 98 vs 1）+ per-session 字段（影子会话该帧 chips/acceptedBets/balance 恒空）**（见 phase-0 §2A 方法②）。
- ⚠️ **init 回放序列独立于此分类**：仍取「最少+最必要」子集；message-nobet 是 init + 每局广播全流，**勿整段当 init**。

**B5 验收**：JSON 合法 + jq parse 过 + 关键字段非空 + `init_frame_sequence` ≥ 4 项（含 subscribe/balanceUpdated/个人注态帧）+ `state_machine`+`state_machine_kind`+`bet_model`+`payout_model` 实证 + `message_classification` 含全部 P0 事件（A/A2/B/handle/C）

**下游消费**：codex review prompt 数据源 + 经验文档协议节

---

## L1.3 — PAYOUT_MODEL（EVO 资金核心，赔付参数从 capture 反推，**不假设号码赔率**）

**产物**：`games/<gametype>/odds.go`（父目录，**不在 core 内**）+ `tmp-evo/<dir>/betcode.md`（分析）

> EVO 为什么单列：betCode + 赔付参数错一位 = 资金漏洞。**赔付模型因族而异**，必须 **bundle 逆向 + capture 抽样 + roundDetail json 三方交叉**确认全表。🔴 **betCode 双命名空间**：协议帧裸名（`Leaf1`/`"43"`）vs roundDetail/history 可能带前缀（`IF_Leaf1`），须建双向映射。

**分析输入**：
- `message.txt` send 帧的 betCode 全集（roulette `betAction.value` 数字键；game show `placeChips.args.chips` 字符串段名）
- `roundDetail/<rid>.json` 的 `.data.data.participants[].bets[]{code,stake,payout}`（**最可靠**，直接反推 payout 公式）
- `clientResources/frontend/evo/mini/js/<gt>.*.js`（号码集/倍率/特殊码逆向）
- roulette 复用：`server/game/pp/internal/games/roulette/odds.go`

**实现内容（赔付模型三选一，从 capture 定）**：
- **roulette 号码赔率制**：`BetCodeNumbers(bc)→(号码集, 净赔 N:1)`，总返还 `amount×(odds+1)`；`WinningCodes(winNumber)`/`NumberColor`/`redNumbers`。直接复用 `roulettecore/odds.go`（157 码含 0 周边特殊注 154-159，已单测过）；变体（Lightning/Double Ball）赔率不同单独实现。
- **game show 倍率制**（IceFishing）：押中 segment × 该局倍率。**无固定赔率表**——倍率每局上游 `gameResolved.{<seg>Multipliers, totalMultiplier}` 下发。odds.go 退化为 `betCode 全集 + segment→<seg>Multipliers 映射`，payout 由 L4 用结算帧倍率算（押中 result 段 `stake×segmentMul`，未中=0）。roundDetail 实证：`IF_Leaf1 stake2000→payout4000`。
- **牌型制**（baccarat/blackjack 等）：牌型→赔率表，从 roundDetail outcomes 反推。

**B5 验收**：`go build` PASS + `odds_test.go`/`payout_test.go` ≥ 4 个 roundDetail 真样本断言 payout（含中/未中 + 倍率≠1 样本；roulette 含 0/00 特殊码）+ betCode 前缀映射断言

**下游消费**：L3 SETTLE / CHECK_BET / L4 PAYOUT

---

## L1.4 — CLIENT_FRAME_EFFECTS（**L2 MODELS 强依赖**）

> **设计动机**：L2 MODELS 写 struct 字段类型 / omitempty / 嵌套对象时，**必须理解每字段在客户端的作用**才能正确决策。EVO 尤其要懂 per-user 帧（`tableState.betState.{bets,lastGameChips,history}` 的 shape、`balanceUpdated` 的 playerId/tableId 来源）。
> L1.4 把"每帧客户端表现 + 每字段如何用"沉淀成手册，L2/L3/L4 全程引用，Phase 7 归档进经验文档（后续同 gameType 复用）。

**产物**：`tmp-evo/<dir>/client_frame_effects.md`（**非代码，下游共用数据源**）

**分析输入**：L1 DICT 输出（事件全集）+ `clientResources/frontend/evo/mini/js/`（reducer/state 字段）+ L1 ENUM（常量名）+ capture 真帧（字段实际类型/值范围）

**实现内容**（markdown，按 server→client 帧分类，每帧 6 字段）：

```markdown
## §1 init 帧（handleConnect 必发，最少+最必要）
### 1.1 subscribe — C 自合成
- 客户端 reducer: <onSubscribe @offset> · state: isSubscribed false→true
- UI: 解锁桌态路由 + 下注 area · 缺失影响: channel 不匹配 → 全部桌态帧被丢
- 字段表: channel(=table-<裸 tableId>) / table / status(="success")
### 1.2 balanceUpdated — C 自合成（商户余额）
- 缺失影响: 🔴 ~6s 收不到 → 超时重连 / LOW BALANCE
- 字段表: balance(商户) / balances[] / currencyCode / tableId(=裸 tableId) / 金额按 currencyMult 进制 · 🔴 **无 playerId，按连接寻址**
### 1.3 个人注态帧 — B per-user（roulette tableState.betState / game show <gt>.bets.state）
- 会话私有字段广播剥离、init 按用户回填；game show 还有 <gt>.restore.begin/end 重连恢复包

## §2 运行时帧（状态机推进，kind 从 capture 定）
### 2.x 状态机帧 — roulette: tableState BETS_OPEN/CLOSING_SOON/CLOSED/ANNOUNCED/GAME_RESOLVED（5 态枚举）；game show: 离散事件帧 <gt>.betsOpen/betsClosed/gameResolved/gameCleared
- 每态/每帧客户端 UI 切换 + 我方动作（开窗/关窗→/bet/结算）
### 2.y A2 communal 演出帧（game show）— <gt>.wheelSpinning/wheelStopping/wheelResult/bonus 全桌开奖动画，直转不缓存
### 2.z 下注受理回执 — roulette betsAccepted/betActionResponse（独立帧）；game show 合并在 <gt>.bets.state.{acceptedBets,rejectedBets}（无独立受理帧）

## §3 结算帧
### 3.1 结算锚 — roulette winSpots+GAME_RESOLVED（号码）；game show <gt>.gameResolved（result+倍率盘，公共）
### 3.2 个人派彩 — roulette win 帧（私聊，tableId=裸 id）；game show <gt>.bets status→Settled + acceptedBets[code].payout
### 3.3 winnersList（全场赢家，🔴 须合并我方本局中奖者后广播——非纯直转，见 L4 WINNERS 处理 / known-pitfalls B8）

## §4 错误帧
### 4.1 betValidationError（字段全填；extendedErrorCode 仅会话失效场景填）

## §5 心跳: metrics.ping/pong

## §6 状态机映射总览（kind 列）
| 客户端 state 字段 | 触发帧 | kind | 必发? |
|---|---|---|---|
| isSubscribed | subscribe.status=success | 通用 | ✅ |
| balance | balanceUpdated(无 playerId，按连接) | 通用 | ✅ |
| 个人注 | roulette tableState.betState / game show <gt>.bets | per-user 回填 | ✅ |
| windowState | roulette tableState.state / game show betsOpen/betsClosed 事件帧 | 状态机 | 运行时 |
```

**实现约束**：
1. 每帧**必含** 6 字段：分类 / 客户端 reducer(evidence) / state 切换 / UI 表现 / 缺失影响 / 字段说明表
2. 字段说明表每字段含：类型 / 客户端用途 / server 填法（**含 per-user 帧的 betState 子字段、tableId 用裸 id、金额 currencyMult 进制**）
3. 严禁泛化（"用于显示"）— 具体到 reducer + state 字段 + UI
4. 字段类型 grep capture 真帧验证

**B5 验收**：≥ 60 行 + 覆盖 init/运行时/结算/错误/心跳 + 每帧 6 字段 + bundle evidence + capture 对照

**下游消费**：L2 MODELS（struct 字段）/ L3 UPSTREAM(init 序列)·DOWNSTREAM(echo 字段时序)·PER_USER(betState 字段)·SETTLE(win 字段) / Phase 7 经验文档

---

## AIU prompt 模板（按 L1 通用，每 AIU 各替换）

```
你是 AIU-<NAME>（Layer 1），做 EVO <gametype> 桌 <evo_table_id> 对接的"分析 + 实现 <产物>"工作单元。

## 工作区
- worktree: <worktree_path>（cd 保持，不切分支）· 分支: <worktree_branch> · HEAD: <head_sha> · 主仓库: <repo_root>

## 分析阶段（in-context）
### 输入（按优先级读，不读全部）
1. capture（事实最高权威）：<本 AIU 需要的具体文件 + 读哪部分>
2. bundle（capture 缺失补）：<clientResources grep 命令>
3. 上游 AIU 产物：L1 无上游
4. 模板参考：roulettecore 对应文件 + evo-platform-primer.md §4
### 分析任务（1-3 个问题）：<本 AIU 特化>

## 实现阶段
### 目标文件：<具体路径>
### 实现要点：<本 AIU 清单>
### 实现约束
1. 单文件 ≤ 500 行（超就拆，仍属本 AIU）
2. 注释最少（默认不写，仅 WHY 一行）
3. 强类型铁律：禁 map[string]interface{} 跨边界
4. ID 双字段：协议帧 tableId 用 PPTableID(裸)，索引用 TableID(code)
5. 协议铁律遵守（known-pitfalls）
### 验收：go build / go vet / 单测(若有) / policy-pr ≤500 行 / git commit

## 完成回报（B5 契约）
1. commit sha  2. git show --stat HEAD  3. build/vet/test 结果  4. 关键决策（与 roulettecore 模板差异 / 与 capture 验证情况）
最后一句："等待主 claude 验收并启动 Layer N+1"
```
