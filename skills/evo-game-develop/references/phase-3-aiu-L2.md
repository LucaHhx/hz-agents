# Layer 2 AIU — 依赖 L1（5 并行）

> 进入 L2 前确保 L1 全部完成 + 层间审查通过。
> L2 提供 struct / 限额规则 / 处理器骨架 / Redis 窗口，是业务实现的脚手架。
> **与 PP L2 的结构差异**：EVO **无 per-machine `instance.go`**（实例由 `factory.buildXxxInstance` + `runtime.NewEvoInstance` 装配，L5 做）；PP 的 INSTANCE AIU 在 EVO 拆成 BET_REDIS + BET_WINDOW 两个 evocore 文件 AIU。PP 的 BETPROTO 分析在 EVO 折进 MODELS。

## L2.1 — MODELS（含下注协议分析）

**产物**：`games/<gametype>/<gametype>core/models.go` + `tmp-evo/<dir>/bet_protocol.md`（分析备忘）

**分析输入**（**`client_frame_effects.md` 必读**）：
- **L1.4 `tmp-evo/<dir>/client_frame_effects.md`** ← **强依赖**，决定字段类型 / omitempty / 嵌套结构
- L1 enum.go（常量参考）
- `tmp-evo/<dir>/message.txt`（下游帧逐字段，**per-user 帧 shape 只在这**）+ `message-nobet.txt`（上游帧）
- `roundDetail/<rid>.json`（结算体 struct）
- bundle 补罕见帧

**写 struct 前必须理解每字段客户端表现**（EVO 特有）：
- **个人注态帧是嵌套**（per_user_betstate 按此 shape 剥离/回填，**不可扁平化**）：roulette `tableState.betState{bets:map[betCode]amount, lastGameChips, history}`；game show `<gt>.bets.state{status, chips:map[段名]amount, repeat:map[...](rebet 快照), acceptedBets:map[code]{amount,payout}, rejectedBets, invalidBets, history}`（`chips`≈bets、`repeat`≈lastGameChips、Settled 时 acceptedBets 带 payout）
- **金额是 currencyMult 进制整数**：IDR `10000`=显示 0.5（÷20000）。struct 用数值类型，进制换算在显示/结算层
- **`tableId` 字段语义**：下发帧（派彩/balanceUpdated/subscribe）填**裸 EVO tableId**（PPTableID）。`balanceUpdated` **无 playerId**
- omitempty 决策：客户端 reducer 必读字段（balance/state/gameId）不能 omitempty；可选 UI 字段才 omitempty

**实现内容**：
- 强类型 `Envelope{ID,Type,Args json.RawMessage,Time}` + 各 `ArgsXxx` struct（**按 DICT 实测帧名建，禁照搬 roulette 帧名**；**禁 `map[string]interface{}` 跨边界**）：
  - roulette: `ArgsTableState(.BetState)`/`ArgsWinSpots`/`ArgsBetsAccepted`/`ArgsBetActionResponse`/`ArgsBetAction`/`ArgsWinnersList`/`ArgsRecentResults`/`ArgsBalanceUpdated`/`ArgsAppInfo`
  - game show(IceFishing): `ArgsBets(.State)`/`ArgsGameResolved(.Result,.<seg>Multipliers,.TotalMultiplier)`/`ArgsWheelResult`/`ArgsBonus`/`ArgsBetsOpen(.TimeRemaining)`/`ArgsBetsClosed`/`ArgsBettingStats(.Bettors,.Watchers)`/`ArgsSpinHistory`/`ArgsPlaceChips(.Chips,.BetAction,.BetTags)`/`ArgsRestore(.Version)`/`ArgsBalanceUpdated(无 PlayerId)`——**无 ArgsWinSpots/ArgsBetsAccepted/ArgsBetActionResponse**
- 下发合成帧 struct（subscribe / 个人派彩 / betValidationError）
- 字段 tag 严格（json）；不预设 capture 没出现的字段

**下注协议分析（bet_protocol.md，两形从 capture 判，禁假设 roulette 增量）**：
- **判据**：抽一个连续下注样本，看下注帧的 betCode map 是 delta（只含新增）还是全量（含本局全部当前注）。
- **(a) 增量型**（roulette）：`betAction.action{type:PLACE/REMOVE/MOVE/UNDO, value:{betCode:amt}}`，Redis canonical=应用 action 累计，**需 per-user UNDO 栈**（processor `betStacks`）。
- **(b) 全量快照型**（game show，IceFishing 实证）：`placeChips{chips:map[段名]amt 全量, betAction:"Place"|"Repeat", betTags}`，每帧带全部当前注，Redis canonical=**直接取 chips 全量覆盖、不维护 UNDO 栈**；撤注是独立事件 `<gt>.undo/undoAll`（如需 handle）；`betAction:"Repeat"` 是 rebet（chips 来自上局 repeat 快照）。
- 🔴 **与 PP I6/J1 对偶**：PP/roulette 怕"快照误判增量"；判清两形，增量必维护 UNDO 栈、快照直接覆盖，**不可混**。

**B5 验收**：build PASS + vet 干净 + struct 字段与真帧一一对照（按本族实测帧名）+ 每 Envelope 在 client_frame_effects.md 有对应章节 + bet_protocol.md 增量/快照结论明确

**下游**：UPSTREAM / DOWNSTREAM / PER_USER / SETTLE

---

## L2.2 — RULES（bet_limits）

**产物**：`games/<gametype>/bet_limits.go`（父目录）+ `tmp-evo/<dir>/rules_matrix.md`

**分析输入**：
- L1 PAYOUT_MODEL（betType/段分类）
- `tmp-evo/<dir>/config.txt` 限红字段（**字段名因族而异，先 grep 全集**：roulette `table_bet_min/max_limit`+`even_bet_max`/`split_bet_min`；game show per-betcode `<segment>_bet_min/max_limit`(如 `leaf_bet_min_limit`)+`payout_limit`；config 可能 `{_source,_endpoint,data}` 包裹，限红在 `.data`）+ `currencyMult`
- bundle fallback 默认值

**实现内容**：
- `bet_limits.go`：`<GameType>Limits`（按 betType/段 min/max + TableBetMax + SafeBetPct[roulette 覆盖率玩法专属]）+ 默认值常量（与客户端 fallback 一致 — G2）；**runtime 注入支持 per-currency override**（`runtime.Load<GameType>Limits(db, tableDBID, currency)`）
- `rules_matrix.md`：客户端展示项 / config 字段名 / 客户端 fallback / 后端 enforce（暂留 `?` 由 L3 CHECK_BET 填）
- ⚠️ **currencyMult 进制**：限额值是进制整数，校验时与下注金额同进制比较

**B5 验收**：bet_limits.go 单测覆盖默认值 + matrix 行数 ≥ betType 数

**下游**：CHECK_BET 填实矩阵 / PAYOUT cap 默认 / CURRENCY_CONFIG

---

## L2.3 — PROCESSOR

**产物**：`games/<gametype>/<gametype>core/processor.go`

**分析输入**：L1 ENUM + L2 MODELS（forward ref）+ 模板 `roulettecore/processor.go`

**实现内容**：
- `Processor struct`（**一桌一单例**）：嵌 `handlers.EventHandler` / `Variant`（TableID+PPTableID+GameType+TableLabel）
- 锁字段：`mu`（桌态/窗口）/ `betsMu` / `cacheMu`（initFrames）/ `stacksMu`（仅增量协议）
- **`betStacks map[userID][]action`**（per-user UNDO 栈）—— **仅增量下注协议（roulette）需要**；全量快照协议（game show placeChips）不建此字段/不建 stacksMu，per-user 注态直接取最新 chips 全量
- **`initFrames` 缓存**（dealer/appInfo/桌配置帧等 init 类帧，供新连接回放；game show 含 `<gt>.table`/`restore.begin/end`/首个 `<gt>.bets`）
- `SetBalanceSource(fn)` 字段（工厂注入 `runtime.PlayerBalance`，缺 → 余额恒 0 → LOW BALANCE）
- `iface.TableProcessor` 接口骨架（HandleUpstream / HandleDownstream / Disconnect / KickUser，先 stub）

**B5 验收**：build PASS + Processor 满足 iface + 单例锁字段齐

**下游**：UPSTREAM / DOWNSTREAM / PER_USER / SETTLE 全部嵌入

---

## L2.4 — BET_REDIS

**产物**：`games/<gametype>/<gametype>core/bet_redis.go`

**分析输入**：L1 ENUM Redis key 前缀（走 `server/enum/cache_key.go`）+ 模板 `roulettecore/bet_redis.go`

**实现内容**：
- per-user canonical bets 读写：`GetRedisUserBets(tableID, gameID, requireAccepted) → ([]*UserBets, error)`
- **fail-closed（C7/C9）**：SCAN/HGetAll 失败返 error **不返 nil**（否则被当"无下注" → 不结算/漏退款）；`context.WithTimeout(ctx, 5s)`
- `requireAccepted=true` → 只返已 `betAcceptedAt`(已 /bet) 的注（结算用，资金闸门）
- BC 解析失败显式跳过 + ERROR log（C5），bets JSON 解析失败 continue 跳过用户（C6）

**B5 验收**：build PASS + 单测覆盖 Redis 异常 fail-closed 分支 + requireAccepted 过滤

**下游**：DOWNSTREAM(applyBet 写) / SETTLE(读 requireAccepted) / PER_USER(snapshot 读)

---

## L2.5 — BET_WINDOW

**产物**：`games/<gametype>/<gametype>core/bet_window.go`

**分析输入**：L1 状态机序列 + 模板 `roulettecore/bet_window.go`

**实现内容**：
- 内存窗口状态机：`MarkBetsOpen(gameID)` / `MarkBetsClosed()` + 兜底 timer（上游漏 BETS_CLOSED 时本地超时关窗）
- `IsBetsOpen()` / **`CanBet()` Redis 异常 return false（C1，宁拒不放，防开奖后补投）**
- 窗口锚因状态机 kind 而异：state 枚举型锚 `state==BETS_OPEN`→SET（TTL30s）/`BETS_CLOSED`→DEL；离散事件型锚事件帧 `<gt>.betsOpen`(MarkBetsOpen，可用 args.timeRemaining 设兜底 timer)/`<gt>.betsClosed`(MarkBetsClosed)

**B5 验收**：build PASS + 单测覆盖 Redis 异常分支 return false

**下游**：UPSTREAM(状态机调 Mark) / DOWNSTREAM·CHECK_BET(CanBet 校验)

---

## prompt 模板

参考 `phase-3-aiu-L1.md` 末尾通用模板，注入本 AIU 名称/产物/输入/要点 + L1 已 commit sha。

**集成铁律 reminder（注入每个 L2 AIU prompt）**：
- ID 双字段：协议帧 tableId 用 PPTableID(裸)，索引用 TableID(code)
- per-user：个人注态帧是会话私有（roulette `tableState.betState` / game show `<gt>.bets.state`，L3 PER_USER 处理）；balanceUpdated 上游 drop、本地商户余额重发（**无 playerId，按连接寻址**）
- currencyMult 进制：金额/限额按币种乘系数
- 下注按 L2.1 实测：roulette 增量 + per-user UNDO 栈；game show 全量 chips 快照覆盖、撤注走独立 `<gt>.undo/undoAll`
- C1/C5/C6/C7/C9 Redis fail-closed
- 强类型：禁 map[string]interface{} 跨边界
- I2 错误码独立定义不跨族 import
