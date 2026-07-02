# Layer 3 AIU — 依赖 L2（5 并行）

> 进入 L3 前确保 L2 全部完成 + 层间审查通过。
> L3 是业务核心：上游 5 态状态机 / 下游 action 下注 / **per-user 数据构造（EVO 独有）** / 结算 / 投注校验。
> **与 PP L3 的差异**：① EVO 信封一帧一 type，`DecodeUpstream` 直接 switch，**无 orderKeysByPriority、无 B1 字节替换**（下发帧合成时直接填正确 tableId）；② **多一个 PER_USER AIU**（PP 无）；③ HISTORY 移到 L4（EVO history 是通用 JSON 接口，依赖 SETTLE 落盘）。

## L3.1 — UPSTREAM

**产物**：`upstream_dispatch.go` + `upstream_handlers.go`

**分析输入**：
- L2 MODELS / PROCESSOR
- L1 ENUM 事件名 / DICT 全集 + message_classification
- **`tmp-evo/<dir>/message-nobet.txt` recv 帧时序**（mirror-feed：我方生产真正收到的上游广播契约，`DecodeUpstream` 解析/处置以它为准）；`message.txt` 仅作下游完整协议对照
- 模板：`roulettecore/upstream_dispatch.go` + `upstream_handlers.go`

**实现内容**：
- **`DecodeUpstream(raw) → DispatchResult{Type, Disposition, Args, Err}`**：解强类型 `Envelope` 拿 Type → switch → 反序列化对应 `ArgsXxx` + 标 `DispBroadcast`/`DispHandle`/`DispDrop`/`DispUnknown`。**业务关键帧（tableState/winSpots）解析失败必报错，不静默吞。**
  - **无 type 的 root-key 帧**（EVO init 期 `subscribe`/`dealer`/`time`）：按顶层 key 识别（`dealer`→缓存+广播、`subscribe`→drop、`time`→drop）。⚠️ **旧实现一律 Err 丢弃 → dealer 永不缓存 → 客户端无荷官名**（roulettecore 已修，新族照抄）。
- **处置分流（按 §2A 四类 + message_classification，**帧名按本族 DICT**）**：
  - **DispBroadcast（A）**：`recentResults`(roulette)·`spinHistory`(gs)/`appInfo`/`dealer` 直转广播。🔴 `winnersList`/`bettingStats`(gs) **不归 DispBroadcast 裸直转**——拦截后合并我方数据（winnersList 注本局中奖者 / bettingStats 叠聚合计数）再广播（见 §3.3 / L4 WINNERS / B8·B11）
  - **DispBroadcast（A2 communal 演出，game show）**：`<gt>.wheelSpinning/wheelStopping/wheelResult/bonus` 全桌开奖动画**直转、不缓存**（迟到帧客户端自丢；只驱动动画不碰资金，与结算锚 `gameResolved` 区分）
  - **DispHandle**：开窗/关窗/结算锚（roulette `tableState`(5 态)/`winSpots`；game show `<gt>.betsOpen/betsClosed/gameResolved`）
  - **DispDrop**：`balanceUpdated`（drop→商户余额重发，🔴 **无 playerId 按连接寻址**）/ roulette `betsAccepted`/`betActionResponse` + `metrics.pong`/`settings.data`（心跳/杂项）
- **状态机 handler（锚点从 capture 定，roulette 范例）**（`upstream_handlers.go`）。先从 nobet 跑出一局完整 type 时序确定开窗/关窗/结算/清局锚：
  - **开窗锚**（roulette `tableState{BETS_OPEN}`；game show `<gt>.betsOpen` 带 timeRemaining）→ `MarkBetsOpen(gameID)` + `UpsertRoundStartedAt`（H5）+ 兜底 timer
  - **关窗锚**（roulette `BETS_CLOSED`；game show `<gt>.betsClosed`）→ `MarkBetsClosed` + 异步 `go handlers.SubmitBets(ctx.TableID, gameID, p.OnMerchantBetResult)`（**第 3 参必须是 OnMerchantBetResult**，否则 settle 阻断；J11 资金铁律）
  - **演出锚**（game show `wheelSpinning/wheelResult` 等）→ 直转广播（A2），不碰资金
  - **结算锚**（roulette `tableState{GAME_RESOLVED}`+`winSpots`；game show `<gt>.gameResolved` 带 result+倍率盘）→ 🔴 **先 `userBetsSnapshot` 抓本局全用户注（清 Redis 之前！）** → 调 SETTLE `OnGameResult` → per-user 回填下发
  - **取消锚**（`<gt>.gameCancelled` 如有）→ 关窗 + 退款
  - **禁止假设 `tableState.state` 5 态枚举存在**——game show 是离散事件帧。
- **per-user 改写调用点**：个人注态帧广播前剥会话私有（roulette `stripTableStateBetState` / game show 剥 `<gt>.bets.state`）→ 按连接 userId 回填。**实现在 L3.3 PER_USER，本 AIU 只接入调用。**
- **init 帧缓存**：`dealer`/`appInfo`/裸 `tableState`(binding) 缓存到 `Processor.initFrames`，供新连接 `downstream_init` 回放。按帧时效语义二分（J2 同理）：每局重发的全量桌态缓存最新一帧；纯心跳/时效帧不缓存。
- **报表 messages 录制**（L4 REPORT 前置）：`HandleUpstream` dispatch 之后调归档把整局上游帧落 `b_game_rounds.messages`（漏调 = 报表 messages 永远空）。
- **容灾/重连**：EVO **无 PP 的 `switch`/`seat` 帧**——上游断线/会话失效由 `runtime/runner.go` + `lobby_failover` 自动重连重选会话（基础设施层，evocore 不处理）。Inactivity 由网关 per-user 管。**新族 upstream 不需实现 onSwitch/onSeat**。

**B5 验收**：build/vet/test 过 + `upstream_dispatch_test` 覆盖每 type 的 Disposition + root-key 帧 + 解析失败报错 + 5 态 handler 时序（snapshot-before-settle）

**下游**：PER_USER / SETTLE

---

## L3.2 — DOWNSTREAM

**产物**：`downstream_dispatch.go` + `downstream_bet.go` + `downstream_init.go` + `downstream_settle.go` + `bet_actions.go`

**分析输入**：
- L2 MODELS（ArgsBetAction）/ bet_protocol.md（action 增量 + UNDO 栈）/ RULES
- `tmp-evo/<dir>/message.txt` send 帧（betAction 实例）+ per-user 帧 shape
- L1 DICT `init_frame_sequence`
- 模板：`roulettecore/downstream_*.go` + `bet_actions.go`

**实现内容**：
- **`downstream_dispatch`**：`raw==nil` 新连接 → 发 init 序列（`downstream_init`）；`raw!=nil` → 按 type 分发（下注帧 / fetchBalance / metrics.ping / settings.read/update / `<gt>.undo/undoAll` 如有）
- **`downstream_init`（init 序列，严格按 L1 DICT，C 自合成优先）**：
  1. `subscribe`（channel=`table-<裸 EVO tableId>`，**channel 不匹配 → 客户端丢全部桌态帧**）
  2. `balanceUpdated`（**商户余额**，`p.merchantBalance(ctx)`；客户端 ~6s 收不到 → 超时重连；**无 playerId**）
  3. 个人注态回填（roulette `tableState`+`personalizeTableState`；game show `<gt>.bets`+`<gt>.restore.begin/end` 重连恢复包）
  4. 缓存帧回放（dealer / appInfo / `<gt>.table`）
  - 实现位置 `handleConnect`：JoinRoom → 按序逐帧 send → RegisterConn
- **下注 action 应用（模型从 L2 bet_protocol 定）**：roulette `bet_actions.go` 把 `betAction.action.type` PLACE/REMOVE/MOVE/UNDO 应用到 per-user UNDO 栈算累计注；**game show `placeChips.chips` 全量快照覆盖 Redis canonical**，`betAction:"Repeat"` 取上局 repeat 快照。🔴 **撤注仍须建服务端快照栈**（`bet_undo.go`，镜像 icefishing/funkytime/crazytime）：客户端 `<gt>.undo/undoAll`（独立帧或 `<gt>.bet` 的 Undo action）**只发撤注信号、不重发 placeChips**，服务端须弹快照栈恢复上一态覆盖 Redis 回缩减态——**勿因「全量快照」误判无需 UNDO 栈**（漏处理=撤注无效+残留注超扣，known-pitfalls K6）。CrazyTime 另有 Chip/BulkBet 增量模式，Chip action 须增量加单子（known-pitfalls A4）。
- **`downstream_bet`**：解下注帧 → CheckBet（窗口）→ applyBet 落 Redis canonical（**不扣款**）→ 合成回执
  - 🔴 **bet 确认时序 + 资金（EVO 同 PP J10/J11）**：
    - `betActionResponse` 即时 ack（客户端知"收到、可继续放筹码"）；**`betsAccepted` 最终受理集在 BETS_CLOSED 之后下发**，绝不在下注期逐帧定格
    - `MarkBetAccepted` **只在 `OnMerchantBetResult` accepted 分支标**（商户 /bet 落账后），**绝不在 betAction/applyBet 标**
    - `onBetsClosed` **必须 `go handlers.SubmitBets`** 向下游商户 /bet 扣本金——漏调 = 无扣款派彩 = 资金漏洞
  - **betValidationError** 字段全填；error code 必须命中客户端真识别的 toast 分支（不要用客户端 default 的通用错误码）；普通拒单 `extendedErrorCode` 留空（仅会话失效场景填）
  - **空/撤单防御**：撤单（REMOVE/UNDO 清注）必须先 CheckBet 校验窗口才改 Redis（关窗后撤单 = 资金风险，C3）
- **`downstream_settle`**：结算 per-user 帧合成辅助（roulette `win` 帧；game show 复用 `<gt>.bets` status→Settled）
- **balanceUpdated 重发**：上游 drop 后，**按下游连接**（per-connection，非帧内 playerId）用商户余额重发（B per-user，余额源 `runtime.PlayerBalance`）

**B5 验收**：build/vet/test 过 + `downstream_bet_test` 覆盖下注模型应用（roulette PLACE/REMOVE/UNDO 累计 / game show placeChips 全量覆盖）+ 撤单窗口校验 + 受理回执时序（关窗后）+ betValidationError 字段

**下游**：CHECK_BET 协作 / PER_USER（init 回填）

---

## L3.3 — PER_USER（⭐ EVO 独有，PP 无对应，最易错）

**产物**：`per_user_betstate.go` + `per_user_wire_test.go` + `tmp-evo/<dir>/frame_contract.md`

> **为什么单列**：真 EVO per-player 连接、只推该玩家自己的注/余额；我方一上游广播多下游。整帧广播 → 全桌收代理账号的注（别人的注上自己板面、Rebet 错乱、余额串账）。这是 EVO 对接最大、最易错的工作量，单列一个 AIU 重点保障。**模板照抄 `roulettecore/per_user_betstate.go`，换字段名。**

> 🔴🔴 **写合成代码前先跑 `references/per-user-frame-fidelity.md` 的步骤 A/B/C（强制）**：从 `message.txt`（=客户端期待的 target）建逐相位×逐 status 字段契约 + 广播频率契约 + 渲染源判定，写进 `frame_contract.md`。**漏字段 = 客户端崩 `undefined.map`/卡死/不渲染；广播频率不足 = 卡面/计时器/红点停滞。这类 bug 编译+单测+codex 全查不出，只能靠契约提前发现。** Monopoly Big Baller 因跳过此步被用户连续指证 5 轮（luckySymbols/threeRollsBalls/timeRemaining 缺字段崩、卡格红点不更新、广播频率不足）——见 fidelity.md §6。完成后 `per_user_wire_test.go` 逐 (相位,status) 断言字段集 ⊇ 契约 + 所有数组字段非 null。

**分析输入**：
- L1.4 client_frame_effects.md（个人注态帧字段）
- L2 MODELS（个人注态帧 shape：roulette `ArgsTableState.BetState` / game show `ArgsBets.State`）
- L2 BET_REDIS（GetRedisUserBets）
- 模板 `roulettecore/per_user_betstate.go`（逐函数照抄机制）

> 🔴 **锚帧名随族而异**（机制照抄、帧名/字段从 capture 取）：roulette 改写 `tableState.betState.{bets,lastGameChips,history}`；game show 改写 **`<gt>.bets.state.{chips,repeat,acceptedBets,history}`**（一帧合并了 roulette 的 betState+受理+派彩职能）。下面函数名是 roulette 模板，新族换帧名（如 `stripBetsState`/`personalizeBets`），mechanism 不变。

**实现内容（4 个函数 + 时序铁律，函数名 roulette 范例）**：
1. **`stripTableStateBetState(raw)`**：广播前剥 `betState.{bets,lastGameChips,history}`，只留公共桌态。解析失败回退原帧（不破坏转发）。
2. **`personalizeTableState(raw, currentBets, lastGameChips)`**：把某用户当前注 + 上局 Rebet 注注入一帧公共 tableState，供 init 回放定向发该连接。两者皆空原样返回。
3. **`broadcastTableStatePerUser(state, stripped, betsByUser)`**：走 `events.BroadcastToTablePerUser(tableID, fn(userID))` 按连接改写——
   - 有注用户：注入本局 `betState.bets`（修 **1007 LateBet**：客户端 BETS_CLOSED 读本帧 bets 与本地注对账；封盘前后逐帧含本人注，**含 GAME_RESOLVED**）
   - `BETS_OPEN` 帧：额外注入上局 `lastGameChips`（rebet「重复上局」）
   - 无注/匿名连接：收公共剥离版
4. **`userBetsSnapshot(tableID, gameID)`** + **`userLastGameChips(tableCode, uuid)`**：前者读本局全用户累计注（Redis），后者读 DB 最近一局注（rebet）。best-effort 失败返 nil 不阻断。

🔴 **快照时序铁律（最易错，必守）**：`broadcastTableStatePerUser` 的 `betsByUser` 必须在**「GAME_RESOLVED 触发结算清 Redis 之前」**用 `userBetsSnapshot` 抓。否则下发时现查 Redis 读空、丢本局注（真 EVO 的 GAME_RESOLVED 是带注的）。**L3.1 UPSTREAM 的 handleTableState 在清注前 snapshot 传入。**

🔴 **裸 tableId 铁律**：per-user 改写/下发帧的 `tableId` 字段填 **PPTableID（裸 EVO tableId）**，不是 b_tables.code。

**B5 验收**：build/vet/test 过 + `per_user_betstate_test` 覆盖 strip 后无 betState 私有字段 + personalize 回填 + snapshot-before-clear 时序（构造 GAME_RESOLVED 验证下发帧仍带注）

**下游**：UPSTREAM 接入广播 / DOWNSTREAM init 回填 / SETTLE per-user win

---

## L3.4 — SETTLE

**产物**：`settle.go`（+ 可选 `downstream_settle` 协作）

**分析输入**：
- L2 MODELS（结算锚 struct：roulette `tableState{GAME_RESOLVED}`+`winSpots` / game show `<gt>.gameResolved`）
- L1 PAYOUT_MODEL（赔付模型：号码 odds / segment 倍率 / 牌型）
- `tmp-evo/<dir>/message.txt` 结算锚真帧 + `roundDetail/<rid>.json`（`.data.data.participants[].bets[]{code,stake,payout}` 结算体对照）
- 模板 `roulettecore/settle.go`

**实现内容**：
- **`OnGameResult`** 入口：解结算锚（roulette `winNumber`+号码集；game show `gameResolved.{result, <seg>Multipliers, totalMultiplier}` 倍率）。**禁假设 winNumber/odds 制。**
- 写 `b_game_rounds`（Result/ResultCode/Extra/RawData；**列宽 ≥ 协议族最长显示串**，game show 的段名+倍率序列化串比 roulette winNumber 宽，防超长整局丢库——EVO 同 J12）
- **读 Redis bets `GetRedisUserBets(tableID, gameID, requireAccepted=true)`**（fail-closed C7）。⚠️ **betCode 双命名空间**：Redis 用下注帧裸名、roundDetail 对账用前缀名（`IF_`），先映射
- 全用户结算循环：赔付走 L4 PAYOUT 的**通用模型**（roulette `amount×(odds+1)`；game show 押中 segment `stake×(倍率+1)`、未中=0）
- 🔴 **交互式 bonus 派彩 per-player（玩家选择型，FunkyTime 类）**：Bar/StayinAlive 倍率取决于玩家选杯/选色 → settle 须按 user 记录的选择查倍率盘；**未选玩家 auto 随机选一个（非取最小，匹配 EVO）**、**倍率盘缺失且有人押中该段须 fail-closed（不按 0 把中奖当未中）**（known-pitfalls K3/K5）。Disco 类 communal 单值无选择。纯数字/字母段仍按 base×topSlot。
- **`handlers.SettleUsersSeamless(/result)`** 派彩 → 内置 `hasSuccessfulBetDebit` 闸门（**/result 必先有成功 /bet**，EVO 同 J11）
- **per-user 下发**：`events.SendToUser(tableCode, userID, frame)`（只给本局有注用户；roulette `win` 帧 / game show `<gt>.bets` status→Settled+payout）+ `balanceUpdated`（商户余额，**tableId 用裸 EVO tableId**）
- **取消路径**：`<gt>.gameCancelled`（如有）→ `OnRoundCancelled` 退款
- 🔴 **`OnRoundSettled` 必调**（settle 成功），否则下一局误标 cancelled + 重复退款
- **fail-closed log（D）**：UpsertRound / GetRedisUserBets / SettleUsersSeamless 失败全部 `zap.Error`
- **Extra 前瞻落盘（H2）**：所有族特色字段（winNumber / 倍数 / bonus / 子序列）凡 history/报表可能渲染的都落，**禁止因本局 capture 未触发而省略**

**B5 验收**：build/vet/test 过 + `settle_*_test` ≥ 4 个 roundDetail/capture 真样本断言 payout + requireAccepted fail-closed + OnRoundSettled 调用断言 + cover ≥ 25%

**下游**：PAYOUT（L4）/ HISTORY（L4）数据源

---

## L3.5 — CHECK_BET

**产物**：`check_bet.go`

**分析输入**：L2 RULES bet_limits + rules_matrix.md / L2 BET_WINDOW / L1 ENUM errorCode

**实现内容**：
- `CheckBet` hook
- **双重 fail-closed（C1）**：内存窗口 + Redis 窗口任一异常返错
- 按 betType 单注限额 → `ErrCodeBetTooLow/TooHigh`（**currencyMult 进制比较**）
- 用户当前局总 stake + 新注 > 台限 → `ErrCodeTableLimitExceeded`
- betCode 白名单校验 → `ErrCodeUnknownBetCode`（roulette 数字 / game show 字符串段名）
- 下注规则必须 capture 实证不凭直觉（J3 同理）；`SafeBetPct` 高覆盖率玩法是 **roulette 专属**（game show 固定段+bonus 无覆盖率概念，删此句），派彩失控由 settle 三路 cap 兜底
- **撤单类非窗口拒绝才清注；窗口拒绝不改 Redis**（C4，防"界面已撤实际扣款"；game show 撤单是 placeChips 减额/空 chips 或独立 undo 事件）

**B5 验收**：build/vet/test 过 + `check_bet_test` 覆盖单注/台限/窗口/betCode 4 类 + currencyMult 进制

**下游**：填实 L2 rules_matrix.md enforce 列

---

## prompt 模板

参考 `phase-3-aiu-L1.md` 末尾通用模板。L3 AIU prompt 额外注入：
- **铁律 reminder**：per-user（strip/personalize/snapshot-before-settle/裸 tableId/余额来源）+ C1/C3/C4/C7/C9 + D 全部 zap.Error + H2/H5 + OnRoundSettled 必调 + /result 必先 /bet（SubmitBets + hasSuccessfulBetDebit）+ betsAccepted 时序（关窗后）+ J12 列宽
- 上游 AIU 已 commit sha + 产物路径（state.aiu_progress.L1/L2.commits）
