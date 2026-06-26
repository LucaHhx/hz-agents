# EVO 平台基础设施 + per-user 数据构造（最关键的 EVO 特异性文档）

> **本文件无 PP 对应物**——它是 EVO 与 PP 的本质区别所在。Phase 1 判复用边界、Phase 3 建 evocore、Phase 6 verify per-user 闸门都高频引用。
> 一句话：EVO 的 runtime/gateway/video/lobby/failover/资金 全部已建好且与机台无关，新游戏族**只建一个 `evocore` 包 + 工厂注册 + DB 行 + 报表页**；而新族最大的工作量是 **per-user 数据构造**（PP 多数帧直转，EVO 大量帧是会话私有、必须按每个下游用户改写/补结构）。
>
> 目录：[§1 复用 vs 新建总表](#1) · [§2 三层架构](#2) · [§3 per-user 数据构造全模式](#3) · [§4 roulettecore 18 文件逐文件模板](#4) · [§5 资金链路复用](#5) · [§6 注册链路](#6)

## <a id="1"></a>1. 复用 vs 新建总表（Phase 1/3 决策依据）

| 层 | 文件（`server/game/evo/internal/…` 除非标注） | 新游戏族是否碰 |
|---|---|---|
| **会话/上游/容灾** | `runtime/{session,vendor,manager_upstream,runner,lobby_failover,currency_minter}.go` | ❌ 不碰（与机台无关，会话由容灾自动选） |
| **一桌一实例容器** | `runtime/{instance,manager}.go` | ❌ 不碰（泛用容器，FindByTableCode/StartTableByTableCode） |
| **上游三路连接** | `runtime/{game_upstream,video_upstream,video_hops,video_descrambler,video_token,chat_upstream}.go` | ❌ 不碰（通用连接层，只把 raw 喂 Processor） |
| **大厅自建** | `runtime/{lobby,lobby_upstream,lobby_hub,lobby_snapshot,lobby_redis,lobby_proxy,lobby_singleton,table_config}.go` | ❌ 不碰（allowlist 从 DB enabled 自动刷新，新桌插 DB 即被订阅） |
| **下游网关** | `gateway/{game_ws,game_user_conns,game_events,routes,video_ws,chat_ws,lobby_ws,client_proxy}.go` | ❌ 不碰（按 `:tableId`/`:gameType` 动态分发，per-user 改写自动触发） |
| **HTTP 端点** | `gateway/{api_config,api_aux,history_api,history_render,report_api,locale}.go` | ❌ 不碰（通用 buildEvoConfigResponse / 历史隔离 / 报表 JSON） |
| **运维桥** | `gateway/{adminapi,admin_*,sync_progress}.go`、`runtime/admin_exports.go` | ❌ 不碰（除非新族要新运维动作） |
| **资金（common 层）** | `game/common/runtime/handlers`（SubmitBets/SettleUsersSeamless）、`game/common/merchantclient`、`game/common/runtime/events` | ❌ 不碰（vendor 无关，照调） |
| **货币配置** | `gateway/{admin_currency_sync,admin_currency_upsert,admin_currency_retry}.go`、`runtime/limits_config.go` | ⚠️ 不改代码，但**必须为新桌预存 `b_table_currency_configs`**（/config 按 tableID+currency 查） |
| **游戏逻辑（evocore）** | `games/<gametype>/<gametype>core/*.go` | ✅ **新族从零建一套**（§4 模板） |
| **限额/赔付** | `games/<gametype>/{odds.go,bet_limits.go}` | ✅ 新族建（betCode 体系 / 赔付参数：roulette 号码赔率 · game show 段倍率（每局上游下发）· 牌型赔率 / 限红） |
| **工厂注册** | `factory/instance_factory.go` | ✅ 改（switch case + implementedTables，约 3 行 + buildXxxInstance） |
| **报表前端页** | `client/reports/<evo_table_id>/index.html` | ✅ 新建（一桌一份，自包含） |
| **DB** | `b_tables` 行 + `b_table_currency_configs` | ✅ 插（vendor_type='evo', code='evo'+id, original_id=裸 id, enabled=true） |

> **复用既有 core（reuse_core != none）**：又一张 roulette 桌 = 仅「factory case + DB 行 + 报表页 + 限额/per-user 差异核对」，evocore 一行不写。

## <a id="2"></a>2. 三层架构（资金本地，per-user 分发）

```
        下游玩家(连我方)              我方 game-evo 进程                         真 EVO / CDN
       ┌──────────────┐      ┌────────────────────────────────────┐      ┌──────────────────┐
浏览器  │ EVO 前端 JS   │◄────►│ HTTP /config /setup /history(我方实现)│      │                  │
(我方托管)│ wsHost→我方  │      │ game_ws → EvoInstance(一桌一个)        │      │ /public/<gt>/    │
       │ game ws ─────┼─────►│   ├ gameRoom ◄── 公共桌态广播 ────┐    │      │  player/game ws  │
       │  ▲广播       │      │   │  GameUpstream(1 会话) ─────────┼────┼─────►│ (mirror-feed)    │
       │  │下注betAction─────►│   ├ per-user 改写 → SendToUser ───┘    │      │                  │
       │ 余额/win◄────┼──────┤   │  Processor.HandleUpstream/Downstream │      │                  │
       │ video ───────┼──────┼─ VideoUpstream(egcvi 三跳+解扰) ────────┼─────►│ egcvi.com H264   │
       │ chat ────────┼──────┼─ ChatUpstream ────────────────────────┼─────►│ /public/chat ws  │
       └──────────────┘      └────────────────────────────────────┘      └──────────────────┘
  资金: 商户 seamless wallet ◄── handlers.SubmitBets / SettleUsersSeamless（common 层，vendor 无关）
```

**资金铁律（与 PP 同）**：上游对我方只是「游戏广播源 + 视频源」。下注/扣款/派彩/余额全部我方本地处理。上游渠道 USD `balanceUpdated`/`betsAccepted` **一律 drop**，按 EVO 协议格式用**商户余额** per-user 重发。

**分发两条路（与 PP 同结构，但 per-user 路远比 PP 重）**：

| 类别 | 帧（roulette / game show 范例） | 分发 | 来源 |
|---|---|---|---|
| 公共桌态 A | 纯直转：`recentResults`(roulette)/`spinHistory`(gs)/`appInfo`/`dealer`。🔴 `winnersList`/`bettingStats`(gs) 名为公共帧但**须先合并我方再播**（winnersList 注我方中奖者按 payout 重排、bettingStats 叠我方计数，见 B8/B11） | `gameRoom.BroadcastJSON` 一对多 | 上游一会话拉 → 直转 / 合并我方后广播 |
| **A2 communal 演出**（game show） | `wheelSpinning`/`wheelStopping`/`wheelResult`/`bonus` 全桌开奖动画 | `BroadcastJSON` 直转、不缓存 | 上游广播 → 直转 |
| **per-user（EVO 大头）** | roulette `tableState.betState`(剥离+回填)/`win`；game show `<gt>.bets.state`(剥离+回填) + `balanceUpdated` | `events.SendToUser` / `BroadcastToTablePerUser` 定向 | **我方本地合成（余额=商户钱包，按连接寻址）** |

## <a id="3"></a>3. per-user 数据构造全模式（EVO 的灵魂，PP 没有）

### 3.1 为什么需要
真 EVO 是 **per-player 连接**：每个玩家一条会话，服务端只把**该玩家自己**的注/余额/Rebet 推给他。我方是 **一条上游会话广播给多个下游**（代理账号模型）。若把上游帧整帧广播 → 所有下游收到代理账号的 per-session 数据（别人的注显示在自己板面、Rebet 变成代理的注、余额串账）。**修法：广播前剥离会话私有字段，下发时按连接 userId 还原本人数据。**

> 🔴 **per-user 锚帧名随族而异**（机制照抄、帧名/字段从 capture 取）：roulette 在 `tableState.betState.{bets,lastGameChips,history}`；game show(IceFishing) 在 **`<gt>.bets.state.{status,chips,acceptedBets,rejectedBets,repeat,history}`**（一帧合并了 roulette 的 betState + 受理回执 `betsAccepted` + 派彩 `win` 三职能，`chips`≈bets、`repeat`≈lastGameChips、`acceptedBets[code].payout` 是 Settled 派彩）。但不要把这些 type 当规则；新族必须比较 message/message-nobet 的同名帧 shape。若结果/终局/状态帧同时含公共字段和个人下注/派彩子对象，它就是 **混合帧**：公共字段可沿用上游，个人字段按连接注入，无注连接保留公共 shape。**找 per-user 帧靠计数悬殊+per-session 字段+shape diff，不靠 type 集合差**（game show 集合差为空，见 phase-0 §2A）。

### 3.2 会话私有下注态 剥离 + 回填（`roulettecore/per_user_betstate.go`；roulette=`tableState.betState`，game show=`<gt>.bets.state`，新族照抄机制换锚帧名）
roulette 的 `tableState.betState.{bets, lastGameChips, history}` 是会话私有（game show 同理换帧名/字段名）。三个函数：

- **`stripTableStateBetState(raw)`**（:34）— 广播前剥 `bets/lastGameChips/history`，只留公共桌态。解析失败回退原帧（不破坏转发）。
- **`personalizeTableState(raw, currentBets, lastGameChips)`**（:51）— 把某用户的当前注 + 上局 Rebet 注注入一帧公共 tableState，供 init 回放定向发该连接。两者皆空原样返回。
- **`broadcastTableStatePerUser(state, stripped, betsByUser)`**（:81）— 按连接 userId 改写下发：有注用户注入本局 `betState.bets`（修 **1007 LateBet**：客户端 BETS_CLOSED 读本帧 bets 与本地注对账，封盘前后逐帧都带本人注，含 GAME_RESOLVED）；BETS_OPEN 帧额外注入上局 `lastGameChips`（rebet「重复上局」）；无注/匿名连接收公共剥离版。底层走 `events.BroadcastToTablePerUser(tableID, func(userID) []byte)`。

### 3.3 🔴 快照时序铁律（最易错）
`broadcastTableStatePerUser` 的 `betsByUser` 由调用方在**「触发结算清 Redis 之前」**用 `userBetsSnapshot(tableID, gameID)`（:101）抓取。因为 GAME_RESOLVED 帧在 `handleTableState` 内触发结算清注，**若 per-user 下发时现查 Redis 会读空、丢失本局注**（真 EVO 的 GAME_RESOLVED 是带注的）。新族结算锚帧同理：**先 snapshot 再清，不可颠倒**。

### 3.3.1 混合帧改写规则（公共结果 + 个人字段）
部分族的终局/结果/状态帧不是纯公共帧：同一帧里既有全桌开奖结果，也可能在有下注会话夹带本人的下注快照、受理结果或派彩。实现规则：
- `DecodeUpstream` 仍把它列为 handle（驱动结算/状态机），但转发不能裸广播原帧。
- 结算或状态处理必须产出 `map[userID]私有状态`，然后用 `BroadcastToTablePerUser` 构造每条连接的 payload。
- 有私有状态的用户注入该用户字段；无注、匿名、结算失败或没有证据的连接返回原始公共帧，保持 nobet shape。
- 对 standalone per-user 注态帧仍可继续 `SendToUser`，但若 capture 证明终局帧也夹带同一状态，两个 wire contract 都要补齐。
- 单测要覆盖 JSON wire：未中项也要保留协议要求的显式 0/false 字段，不能被 `omitempty` 吞掉。

### 3.4 lastGameChips rebet（`userLastGameChips`，:125）
查该用户在本桌最近一局的下注（betCode→amount，从 `b_game_transactions` 按 `table_code+user_id` 倒序取最近 gameId 的全部行），供客户端 Rebet。DB 不可用/无记录一律返 nil（best-effort，不阻断 init）。

### 3.5 balanceUpdated drop + 商户余额 per-user 重发
- 上游 `balanceUpdated`（渠道 USD；roulette 渠道帧或带 playerId，🔴 **game show 无 playerId**——args 仅 `balance/balances[]/currencyCode/tableId`）→ `DecodeUpstream` 判 `DispDrop`（`upstream_dispatch.go:167`）。
- 我方用**商户余额**按**下游连接**（per-connection，**非帧内 playerId**）重发：余额源 `runtime.PlayerBalance`（玩家会话缓存的商户余额），工厂 `proc.SetBalanceSource(runtime.PlayerBalance)` 注入（`instance_factory.go:62`）。**缺余额源恒 0 → 客户端 LOW BALANCE**。
- init 序列必发一帧 balanceUpdated（商户余额），客户端 **~6s 收不到即超时重连**。

### 3.6 个人派彩 per-user + 裸 tableId
结算后 `events.SendToUser(table_code, userID, frame)` 定向推（只给本局有注用户）。**派彩帧 shape 随族而异**：roulette = 独立 `win` 帧（winSpots{betCode→{amount/payout}} + totalWin + netCash）；game show(IceFishing) = 复用 per-user `<gt>.bets` 帧、`state.status` 转 `Settled` + `acceptedBets[code].payout` 带派彩。🔴 **派彩/余额帧的 `tableId` 字段必须填裸 EVO tableId（PPTableID），不是 b_tables.code**——客户端按 URL 里的 table_id 匹配，填 code 判「未收到」→ 重连。

### 3.7 events 总线 API 全集（`gateway/game_events.go` 注册，`common/runtime/events` 定义）
新族在 evocore 里只调这些抽象，不直接碰连接：

| API | 用途 | 注册回调 |
|---|---|---|
| `events.BroadcastJSON(tableCode, data)` | 公共桌态一对多 | `inst.GetGameRoom().BroadcastJSON` |
| `events.SendToUser(tableCode, userID, data)` | per-user 定向（win/balance） | `gameUserConns.SendToUser`（CAS 防重连误删） |
| `events.BroadcastToTablePerUser(tableCode, fn(userID)[]byte)` | 逐连接改写下发（tableState） | 遍历 `gameUserConns` |
| `events.BroadcastToTableByCurrency(tableCode, byCur)` | 按观众币种分组广播（多币种 winnersList/余额） | 按会话币种集合 |
| `events.CurrencySet(tableCode)` | 当前活跃观众币种集合 | 结算前收集 |

### 3.8 /config /setup per-user 改写（`gateway/api_config.go` + `routes.go`，通用层，新族不改但要懂）
- **`/setup`**（`patchSetupSession`）：改写 session_id/user_id/player_id/currencyCode/lang(evo_locale)/chat.serverHost → 我方值。
- **`/config`**（`buildEvoConfigResponse`）：改 serverHost/wsUrl/table_id(=我方 code)/playerId → 我方；生成自签 wrapper_token + video.token.issuer（占位 JWT，payload 编我方值）；改所有视频 host → 我方；`video.stream.name`=`app/<N>/<我方 code>`；**`scrubUpstreamSecrets` 全量扫描剥上游机密**（防残留 evo-games.com / 上游 EVOSESSIONID）。

> ⚠️ 注意 ID 反差：`/config` 的 `table_id` 字段返**我方 code**（前端 game ws 连我方用），但 game ws 内**下发帧**的 `tableId`（win/balance/subscribe channel）用**裸 EVO tableId**。两处不同，别混。

## <a id="4"></a>4. roulettecore 18 文件逐文件模板（新族从零建照此结构）

> 路径 `games/roulette/roulettecore/`（赔率/限额在父目录 `games/roulette/{odds.go,bet_limits.go}`）。
> 新族建 `games/<gametype>/<gametype>core/`，文件名/职责照搬，**只换协议解析 + 状态机 + 结算规则**；per-user/Redis/window/资金骨架机制不变。
>
> ⚠️ **下表是 roulette 一族的 shape，不是 EVO 通用契约**。建包前先从 capture 实证 6 轴（SKILL.md「新游戏族协议 shape 必须从 capture 自推导」铁律）：① 状态机（`tableState.state` 5 态枚举 vs 离散事件帧序列，IceFishing 7 帧无枚举）② 下注模型（`betAction` 增量+UNDO 栈 vs `placeChips` chips 全量快照无 UNDO）③ betCode（数字 vs 字符串段名，结算侧前缀如 `IF_`）④ 赔付（号码 odds vs segment 倍率）⑤ betstats（roulette 无 / game show `<gt>.bettingStats` 有）⑥ A2 演出帧 / restore（roulette 无 / game show 有）。下面"新族要改什么"列即按这些轴。

| 文件 | 职责 | 新族要改什么 |
|---|---|---|
| `enum.go` | 事件 type 常量 / 状态机（roulette=`State*` 枚举；离散事件型=`Evt*` 事件常量）/ action 类型（roulette PLACE/REMOVE/MOVE/UNDO；game show 模式 `Place`/`Repeat`+独立 `undo`/`undoAll`/`gameCancelled` 事件）/ errorCode / Redis key | 先抽 type 全集判状态机 kind，再换族前缀 + 状态/事件常量 + 错误码 |
| `models.go` | 强类型 JSON 信封 `Envelope{id,type,args,time}` + 各 `ArgsXxx` struct（**禁 map[string]interface{}**） | 按新族 capture 帧逐字段建 struct |
| `processor.go` | `Processor`（一桌一单例）+ `Variant`{TableID,PPTableID,GameType,TableLabel} + `betStacks`(per-user UNDO 栈，**仅增量下注协议需要**) + initFrames 缓存 + 锁/窗口状态 | 嵌同样骨架，换业务状态字段；**全量快照下注（game show placeChips）不建 betStacks/stacksMu** |
| `upstream_dispatch.go` | `DecodeUpstream(raw)→DispatchResult{Type,Disposition,Args}`：解信封 → switch type → 标 Broadcast/**A2 communal 演出**/Handle/Drop（含无 type 的 root-key 帧 dealer/subscribe/time） | 按 §2A 四类填 switch；game show 加 A2 演出帧（wheel/bonus 直转）；业务关键帧解析失败必报错不静默 |
| `upstream_handlers.go` | `HandleUpstream`：状态机驱动（开窗/关窗/结算触发）+ per-user 改写调用 + init 帧缓存 | 换状态机锚点（roulette `tableState.state`；离散事件型锚 `<gt>.betsOpen/betsClosed/gameResolved` 等独立帧）；保留 snapshot-before-settle 时序 |
| `downstream_dispatch.go` | 下游消息路由：`raw==nil` 新连接发 init 序列 / `raw!=nil` 按 type 分发 | 换下游 type 分发 |
| `downstream_bet.go` | 解下注帧 → CheckBet → applyBet 落 Redis（**不扣款**）+ 合成受理回执 | 换下注协议（roulette `betAction{action:{type,value}}` 增量；game show `placeChips{chips:map,betAction:"Place"/"Repeat",betTags}` 全量快照覆盖 Redis、撤注走独立 `<gt>.undo/undoAll`）；保留 fail-closed |
| `downstream_init.go` | 新连接 init 序列：subscribe(channel=`table-<裸 tableId>`) → balanceUpdated(商户余额) → 个人注态回填 → 缓存帧回放 | 换 init 帧集；game show 个人注态走 `<gt>.bets`(+`restore.begin/end` 重连恢复包)，非 `tableState.betState` |
| `downstream_settle.go` | 下游侧结算帧合成辅助 | 按新族结算帧改 |
| `bet_actions.go` | （增量协议）PLACE/REMOVE/MOVE/UNDO 状态变换栈操作 → 合并 bets | **仅增量下注协议需要**；全量快照族此文件可省（直接覆盖 Redis） |
| `bet_redis.go` | per-user canonical bets 读写 Redis；`GetRedisUserBets(tableID,gameID,requireAccepted)` fail-closed 闸门 | 几乎照抄（Redis key 换族；UserBets shape 含本族字段如 chips/acceptedBets payout） |
| `bet_window.go` | 内存下注窗口：MarkBetsOpen/Closed + 兜底 timer；`IsBetsOpen`/`CanBet`（Redis 异常返 false 宁拒不放） | 照抄机制，换窗口锚（roulette state 枚举；离散事件型锚 `<gt>.betsOpen`(可用 args.timeRemaining 设兜底 timer)/`<gt>.betsClosed`） |
| `check_bet.go` | `CheckBet` override：窗口 + 币种 + 限额 fail-closed | 换限额规则（roulette SafeBetPct 覆盖率玩法是 roulette 专属，game show 无覆盖率概念） |
| `per_user_betstate.go` | **§3 全套**：strip/personalize/broadcastPerUser/snapshot/lastGameChips | 照抄机制（核心 EVO 资产），换**锚帧名**（roulette `tableState.betState` → game show `<gt>.bets.state`）+ 字段名 |
| `settle.go` | `OnGameResult`：解结算锚 → 写 `b_game_rounds` → 读 Redis bets(requireAccepted,fail-closed) → 算派彩 → `SettleUsersSeamless`(/result) → per-user 派彩+余额 SendToUser → **`OnRoundSettled` 必调** | 换结算锚解析（roulette `winNumber`/`winSpots`；game show `gameResolved.{result,<seg>Multipliers,totalMultiplier}`）+ 派彩调用；留 `gameCancelled` 取消路径 |
| `payout.go` | 纯派彩计算（含本金）；保持纯函数易单测 | 赔付公式因族而异：roulette `amount×(odds+1)`（号码集→odds）；game show `amount×倍率`（押中 segment×`<seg>Multiplier`，未中=0）；baccarat 牌型赔率。**从 roundDetail json `.data.data.participants[].bets[].{code,stake,payout}` 反推，禁假设 odds 制** |
| `recent_results.go` | 历史走势缓存/回放（roulette `recentResults`；game show `<gt>.spinHistory`） | 换历史帧名 + 格式 |
| `reconcile.go` | 孤儿局恢复：从历史走势帧兜底补结算（漏帧自愈，fail-closed 走 requireAccepted） | 照抄机制，换补结算源帧名 |

父目录：`odds.go`（**赔付参数源，按族**：roulette=betCode→号码集+固定赔率，单零欧轮从 EVO bundle 逆向单测过、新 roulette 桌直接复用；game show=无固定赔率表，倍率每局上游 `gameResolved` 下发，odds.go 退化为 betCode 全集+segment 映射；其他族按 capture 定。⚠️ **betCode 双命名空间**：协议帧裸名 `Leaf1` vs roundDetail/history `IF_Leaf1`，须建双向映射）、`bet_limits.go`（按 betType/段/币种取限额，runtime 注入支持 per-currency override）。

## <a id="5"></a>5. 资金链路复用（common 层，vendor 无关，照调不重写）

一局链路（新族同构，只换协议解析锚点）：

```
玩家 betAction → downstream_bet 解析 → CheckBet(窗口Redis) → applyBet 落 Redis（暂存，不扣款）
状态机=关窗 ──────────────────────────────► go handlers.SubmitBets(tableID,gameID,OnMerchantBetResult) → 商户 /bet 扣款
                                              OnMerchantBetResult accepted 分支 → MarkBetAccepted + echo betsAccepted
状态机=开奖{result} ──► settle.OnGameResult → RouletteCalcPayout 算赢 → handlers.SettleUsersSeamless(/result) 派彩
                         └─► SendToUser(win + balanceUpdated 商户余额, tableId=裸id) → OnRoundSettled
```

**关键不变量（红线，新族逐条守，与 known-pitfalls C/J 对应）**：
1. 下注窗口 Redis SET(TTL30s)/`betsopen`→SET、`betsclosed`→DEL；Redis 异常 `CanBet` 返 false。
2. `betAcceptedAt` 校验：`GetRedisUserBets(...,requireAccepted=true)`——只对已 /bet accepted 的注派彩。
3. **`/result` 必先有成功 `/bet`**（`handlers.SettleUsersSeamless::hasSuccessfulBetDebit` 通用闸门）。
4. **`OnRoundSettled` 必调**（settle 成功），否则下一局误标 cancelled + 重复退款。
5. 商户钱包出向只走 `common/merchantclient`，**禁止 game-evo 自己 HTTP 调商户**。

## <a id="6"></a>6. 注册链路（新族 + 新桌）

**新桌（含新族首桌）三步**：
1. `factory/instance_factory.go`：`implementedTables()` 加 `"evo<tableId>": true`；`newGameInstance` switch 加 `case "<裸 tableId>": return buildXxxInstance(table)`；新族写 `buildXxxInstance`（造 Variant + LoadLimits + NewProcessor + SetBalanceSource(runtime.PlayerBalance) + SeamlessBetService + runtime.NewEvoInstance）。
2. `b_tables` 插行：`vendor_type='evo'`、`code='evo'+裸id`、`original_id=裸id`、`game_type`、`enabled=true`、`failover_group_id`。大厅 allowlist 自动从 DB 刷新订阅，**不改大厅代码**。
3. `b_table_currency_configs` 预存该桌各币种限额（/config 按 tableID+currency 查；缺 → 限红/兜底错）。

**报表**：`client/reports/<裸 tableId>/index.html` 自包含一页，fetch 通用 `/gameHistory/report` JSON 渲染，对照 `roundDetail/<rid>.{html,json}` ≥90% 还原。一桌一份，**不共享 _assets**。

**bootstrap 零改**：`bootstrap/run.go` 经 `import _ "hab/game/evo/internal/factory"` 触发 init() 自动注册，新族包被 factory import 即生效。
