# 协议铁律（精华版）

> PP 对接横跨各机台的共性陷阱。每条都源自实际对接 + codex 审查的真实发现。
> 详细案例 + 历史教训：pp-game 仓库 `docs/integration-experience/common/`。
> 机台特化陷阱：`docs/integration-experience/<gametype>/<tableId>.md` 第 13 节。

## A. 信息源边界

**A1**：禁止参考老项目 `/Users/luca/work/ppgame`，所有协议事实只从 capture + main.js。
**A2**：translations-help/`<gametype>.json` 是游戏类型最大规则集，**不是单机台事实**；赔率/激活 betCode/限额必须以 capture + tableConfig + 客户端 UI 渲染为准。
**A3**：区分开发资料（手动从 main.js/capture/lobby 提取）vs 运行时配置（InstanceManager 启动自动拉，不手动准备）。

## B. 协议处理

**B1 tableId 字节级替换（必须）**：`HandleUpstream` 入口 `bytes.ReplaceAll(raw, ctx.PPTableID, ctx.TableID)`。不替换 → 客户端 subscribe channel 校验失败 → isTableSubscribed 永远 false → 10s 断连。

**B1.1 B1 必须单点执行，绝不可叠加（非幂等！线上踩过双 pp）**：`ctx.TableID = table.Code = "pp"+OriginalId`，`ctx.PPTableID = table.OriginalId`——**TableID 把 PPTableID 完整包含为子串**，所以 `ReplaceAll(raw, PPTableID, TableID)` **不是幂等的**：第二遍会把已替换出的 `pptreasureadvgt001` 里那截 `treasureadvgt001` 再替一次 → `pppptreasureadvgt001`（双 pp）→ 客户端房间不匹配，**整桌所有帧（含 winners）被丢**。**铁律：B1 只在一处做**（推荐 `HandleUpstream` 入口；单测直调也安全）。**禁止** instance.handleGameMessage 与 HandleUpstream 同时各做一遍（曾在 TI/moneytime/megasicbo 双做，注释误称"幂等兜底"）。排查现象：客户端收到的帧 `table` 字段比 b_tables.code 多一截 `pp`。

**B2 winners Model A 统一（drop 上游 + 合并我方 + per-观众币种广播）**：上游 winner[] 是真实玩家社交瀑布（含其他渠道/商户）。**不再 pass 透传**（旧默认已废弃：透传会让多币种观众看到混币种原值）。统一 drop 上游帧 → 合并我方下游中奖者（B2 上游 ppc 条目全保留、按 userId 去重）→ EUR 归一排序截断 → 按 `events.TableCurrencySet` 每观众会话币种 `BroadcastToTableByCurrency`。两条铁律：① **一局只广播一次**（rendezvous / 同步点单点 + take-once/guard，不加二次兜底）；② **合并失败（DB 不可用 / CollectOurWinners 出错）→ 整局不广播**（零中奖不算失败）。winners 早于 gameresult 的机台（megasicbo）须 stash 上游帧、等 settle rendezvous 再合并广播。资金安全独立：winner[] 仅展示，实际派彩走我方私聊 win 帧。

**B2.1 winners 合并后必须 EUR 归一排序 + 截断 100（两个症状）**：
① **混币种裸值排序**：合并后 winner[] 含多币种（USD/EUR/IDR/VND…），直接 `SortByWinDesc` 按裸 win 值排序 → 高面额币种（IDR/VND）小赢家挤掉 USD/EUR 大赢家、topWin 失真。
② **我方大奖沉榜底（TI 线上事故）**：我方注入条目是 **append 在 winner[] 末尾** 的，**不排序**则玩家中了全场最大奖也排在 108 条的最后一条，客户端按序渲染 → 看着像"没上榜"（`topWin` 已对但列表顺序错）。
**修法统一**：`handlers.SortTruncateByEUR(msg, events.WinnersListMaxLen)`（折 EUR 作排序键、缺兑率退化裸值、不改原币种，先排序再截断到 100）替代 `SortByWinDesc + TruncateToTopWinners`。自建 builder（TI 等带 mul/tiMapKeys）须自己写等价的 `sortTruncateWinnersByEUR`，且**放在 `recalcWinnersAggregate` 之后**（聚合按"我方在末尾"切片定位 oursAdded）。来源：winners Model A 改造 + TI 线上排查。

**B3 多事件单帧 orderKeysByPriority**：Go map 遍历不保证顺序。显式排序：`gameresult > winners > betsclosed > betsclosingsoon > betsopen > 其他`。单帧多 key 时按 verdict 单独保留/丢弃。

**B4 baccarat 不发 winningBetCodes/betSpotWin**：baccarat 客户端 main.js 对这两字符串 0 命中 → 服务端不合成（roulette 才需要）。新对接前必须 grep main.js 验证。

**B5 lpbet `gm` 字段动态拼接**：形式 `${session.gametype}_${desktop|mobile}`。main.js 出现的 `<gametype>_desktop` 字面量可能是 `pbdealnow` / `playerUnsub` 等特殊命令的固定值，**不是 lpbet 的 gm**。

**B6 ping 单/双引号兼容**：部分老版本客户端用单引号发 ping。`extractXMLAttr` 必须先试双引号再试单引号，单测覆盖两种。

**B7 EnrichBetstats 返回完整 envelope**：`{"betstats":{...}}` 整 envelope。rewrite 链路必须 `unwrapEnvelope` 解出内层后存到 dispatchAction.data，否则会变成 `{"betstats":{"betstats":{...}}}` 双信封。

**B8 Bonus 边注需任一非 Bonus 陪伴投注（同帧，不要求同侧）**：押 Bonus 类（PlayerBonus / BankerBonus 等）时同帧必须含**任一非 Bonus bet**（任意主注 / 对子 / Super6 都算合法陪伴）。**不要求同侧** —— `Tie + BankerBonus`、`PlayerNC + BankerBonus` 在真 PP 均 success。废弃"同侧耦合"假设（旧 1059/1060 同侧码）。见 J3。capture #182 实证。

**B9 BetValidationError 字段 7 个**：betCode / code / extendedErrorCode / optExtErrorCode / optExtErrorMsg / category / severity。后 4 个虽 omitempty，但商户错误透传必须能填。

**B10 switch 帧必须含 wsAddress + httpAddress**：main.js `e&&"string"==typeof e.httpAddress&&"string"==typeof e.wsAddress` 才触发 setGameServer。两个字段都是 string 才生效。

> 🔴 **历史指证：漏 `onSwitch` → 重连死循环 → 游戏帧全断（treasureisland / dragontiger 都踩过）**
> 症状（HAR/日志）：`unresolved upstream event, drop {event:"switch"}` → `PP WS 关闭 {code:1000, aliveMs:1}` → reconnecting → 循环不停，客户端收不到任何游戏帧。
> 根因：PP 负载均衡随时下发 `switch` 让客户端改连另一台 gs 服务器（服务端决定，跟我方代码无关）。机台**没把 `switch` 列入已知事件 / 没实现 `onSwitch`** → 当未知帧 drop → 不触发 `ctx.Reconnect` → 一直重连那台正在 drain 的旧服务器 → `aliveMs:1` 秒关死循环。
> 修复（每个新机台必做，照已实现机台抄）：
>   1. 事件枚举加 `switch`（JSON 机台 `EvtSwitch/TagSwitch`），并登进已知事件集（AllRecvEvents / dispatch switch case），**不能落 unresolved**。
>   2. `onSwitch/handleSwitch`：解析 `{wsAddress, httpAddress}`，B10（两者非空 + `ctx.Reconnect!=nil`）才 `ctx.Reconnect(wsAddress, recvFmt)`，verdict=drop。
>   3. 顺带检查 `canceled` 同类控制帧是否也漏（漏了作废局不关窗/不退款）。
> 参考实现：megasicbo / jackpotwheel / moneytime（JSON `onSwitch`）、megaroulette（XML `<switch>` handleSwitch）。

**B11 FreeChip 等未实现路径必须 fail-closed**：`<bet bcode="..." bettype="FB" ...>` 等 FreeChip 子节点，server 未实现 → 显式发 betValidationError 拒绝（如 5000 FreeChipUnknownError）+ command err；**禁止**静默跳过。

## C. 资金路径 fail-closed

**C1 CanBet Redis 异常返回 false**：`bet_window.go:CanBet` 在 Redis 错误时必须返回 false（宁拒不放）。CheckBet hook 双重 fail-closed（内存窗口 + Redis 窗口任一异常即拒）。

**C2 applyBet fail-closed**：`ctx.BetSvc == nil || ctx.UserID == "" || gameID == ""` 时返回明确错误，不能静默成功。

**C3 空 lpbet 清 Redis 必须先窗口校验**：必须先 `CheckBet` 校验窗口才清 Redis。关窗后撤单 = 资金风险（旧注已发商户 /bet）。

**C4 整批拒清 Redis 仅限非窗口类**：窗口类拒绝（`ErrBetNotOnTime`）**不**清 Redis（否则等同 C3）。

**C5 BC Atoi 错误显式拒绝**：Redis 中非法 BC 解析失败时**不能** `_ = err`（会按 0 = Player 错赔）。必须显式跳过 + ERROR log。

**C6 bets JSON 解析失败跳过用户**：Redis hash 字段 bets JSON 解析失败时**不能**仍 append 空 BetData。必须 continue 跳过。

**C7 GetRedisUserBets 故障 fail-closed**：Redis SCAN/HGetAll 失败**不能**返 nil 当作"无下注"。必须返 error，OnGameResult 不调 OnRoundSettled。

**C8 payout_cap 必须接入**：per-user round payout max + `handlers.CapUserPayout` 等比缩放每条 Payout>0 的 txn + 设 MCap=true。

**C9 context 必须超时**：Redis SCAN/HGetAll 用 `context.WithTimeout(... 5s)` 而非 `context.Background()`。

## D. 静默错误（必加 zap log）

业务关键路径禁止 `_ = err`。下列必加 `global.HAB_LOG.Error/Warn` + `zap.Error(err)`：
- OnGameResult 整体失败
- UpsertRoundWithDealer 失败
- SettleUsersSeamless 失败
- json.Unmarshal(winners / bets) 失败
- OnMerchantBetResult 早期 return（fail-closed log）
- AssertActiveSession 失败
- CollectOurWinners 失败
- LookupRoundPayoutMax 失败（降级时 warn）

## E. struct 序列化

**禁止 raw 字符串拼接 JSON**。所有 JSON 帧必须 struct + `json.Marshal`。
```go
// ❌ data := []byte(`{"session":{"session":"offline"}}`)
// ✅ data, _ := json.Marshal(EnvelopeSession{Session: JSONSession{Session: "offline"}})
```
例外：XML 拼接 helper（lpbet / ping / pong / command）允许字符串模板。

## F. 测试

**F1 payout 单测**：≥ 4 个 capture 真帧样本 + ≥ 1 项边注断言 + 显式断言不参与字段值无关结果。
**F2 字典 parity**：BC*/GR*/错误码/桌台元数据 vs main.js 抽取。
**F3 race detector**：`go test -race -count=3`。
**F4 policy-pr**：单文件 ≤ 500 行 / 控制流嵌套 ≤ 3 层。
**F5 注释最少**：默认不写，仅 WHY 非显然时一行；禁止解释 WHAT / 引用任务编号 / TODO 占位。
**F6 不引老项目**。

## G. 客户端-后端一致性

**G1 矩阵审查**：客户端展示的每个约束类数值（限额/封顶/赔率/合法投注），后端必须用同字段同来源同兜底做 enforce。

**G2 默认值与客户端 fallback 一致**：
```go
DefaultMaxMultiplier      = 20000.0   // 与 main.js `?? 2e4`
DefaultEuroTablePayoutMax = 500000.0  // 与 main.js `?? 5e5`
```
**禁止**："缺配置 = 不封顶/不校验"。

**G3 payout cap 按 `min(A,B,C)`**：
- A = `maxMultiplier × 用户单局总下注本金`（**用户级非单注**）
- B = `Convert(euro_table_payout_max, "EUR", currency)`
- C = `table_payout_max`（本币硬封顶，可选）

**G4 EUR 换算**：b_currency_rates 必须含 `currency='EUR'` 行。换算失败必须 fail-closed。

**G5 客户端硬编码 vs tableConfig 边界**：来自 `r.params.xxx` 的必须做 G1 审查；行结构/静态赔率字面量/翻译键不需要。

**G6 tableConfig 同步**：首次同步落 b_table_currency_configs 时 audit log 关键限额字段缺失。

**G7 经验文档列矩阵**：第 5 节"协议处理决策表"之外新增"客户端-后端一致性矩阵"。

## H. 游戏记录展示一致性

**H1 history endpoint 必查**：每机台 grep main.js 列 `/api/ui/history/*` / `/cgibin/.../audit/*` / `/api/ui/statisticHistory` / `fetchRoundHistory` 等调用。

**H2 b_game_rounds.Extra 落盘 — 前瞻性原则**：

机台所有特色协议字段必须落 Extra（结构化 JSON），不只留 RawData。判定"是否落"的标准 **不是** "当前 capture 是否触发"，而是 **"后续 BuildGameDetail（XML）/ 报表前端页（经 `reportjson.extra` 透传）是否可能渲染"**。

凡是上游下发的、与玩法 / 倍率 / 子序列 / 触发位 有关的字段都要落：

- 任何机台特色帧（`gorXxx` / `bonusXxx` / `tumbleXxx` / `cascadeXxx` / `accumulatedXxx` 等）→ **全量落**
- 子序列帧（如 bonus / tumble / cascade 每步）→ 按 **"全帧序列 [] + spinNo→末值 map"** 两份落
  - 序列保完整可回溯（`spinEndsRaw`）；map 给 history XML 渲染直接用（`spinAccumulatedMultipliers`）
- gameresult 三路辨识位（`winType` / `luckyWin` / `finalMultiplier`）→ 全落，普通局 `winType=0` `finalMultiplier=` 不省略
- gorRng 三种特殊位族 → `bonusNo` / `luckyMul[]`（嵌套不展平）/ `superBoosterMul` 都落

**反例**：gatesofolympus01 初版 `spinAccumulatedMultipliers` 落 string 空字符串（误判 capture 普通局空 = 永远空），bonus 局触发后无数据可吐 → 客户端 NaNx + 派彩按基础 21× 退化。**回头补 3 个 PR**（issue #220 历史 NaNx / #222 派彩少给 / #226 Bonus Game Result 网格）才完整。开发新机台 L3.3 SETTLE 时必须按本节"前瞻性"清单一次性落齐，避免后续多次补 PR。

**H3 b_game_transactions 字段**：填齐 Currency（本局会话币种，**不是 user.Currency**）/ Description（H6 本地化）/ Stake / GameNetCash / MaxCapped / BoosterEnabled / SettledAt（事件时间）。

**H4 history 详情 XML 节点严格匹配**：客户端按 XML 节点路径直接解构（`<gametype>Details`），节点名 / 字段名 / 大小写**任一不一致**就渲染失败。

**H5 b_game_rounds.StartedAt 在 betsopen 时刻写入**（不是 settle 时）：history XML gameStartTimestamp 要求是本局开始时刻。

**H6 BetCode Description 本地化**：history list/详情都展示 `betCodeDescription(bc)`，按 gameType 维护映射。

**H7 b_game_user_actions 落盘**：机台有"玩家选择"环节（candy_drop 选球 / hit-stand / decision）必须把每个用户的选择落盘。

**H8 fetchRoundHistory 兜底空数组的影响**：客户端"Recent rounds widget"依赖此 → 空数组 = 玩家看空列表。

**H9 roulette 必须输出全量默认 `<rouletteDetails>` 节点**：客户端解析 `g ?? u`，server 不输出节点会走空分支报错。

**H10 开发期通过代码分析验证，不抓样本**：单测构造假 round 走 parser → 断言输出。capture 有 gameDetail.txt 时改为真 XML 单测。

**H11 statisticHistory record 的 `gameResult` 必须是展示值，不是 rc 码**：
SETTLE 的 `appendStatHistory` 写 Redis stat_history 时，`gameResult` 必须落**客户端展示值**——固定段=面值字符串（"1"/"2"/"5"/"10"）、bonus 段=bonus 名（"John Silver's Loot"）、roulette=`"22 Black"`，对齐 capture `tmp/<tid>/statisticHistory.txt` 的 `gameResult` 实证值；**禁止**落 raw rc 数字码（"5".."8"）。客户端"最近使用"strip 用 `gameResult` 给 bonus 局取图标，落 rc 码取不到 → **空白圆圈**。
- 现成 helper：用 settle 的 `resultDesc(rc)` 同源映射（face value / bonus 名），不要直接 `rec.GameResult = evt.RC`。
- 来源（本仓库实证）：treasureisland 初版 `GameResult: evt.RC` → bonus 局图标全空白，改 `settleResultDesc(evt.RC)` 修复。

**H12 统计端点选择 + 启动回填（两个独立必做项，缺一面板就坏）**：
- **端点**：从 capture `statisticHistory.txt` 每行 `_endpoint` 字段判断客户端走 `/api/ui/statisticHistory`（通用 `history[]`）还是 `/api/ui/stats`（WheelGames 族 `betSpotPercentage`/`winningBetOccurrenceStat`/`<gametype>GameStatisticHistory`）。走 /stats 必须在 api_stats.go 加 gametype 分支，否则 fall through 轮盘默认 0-36 shape → 面板空白。详见 L4.4 ①。
- **game_type 大小写**：`resolveStatsGameType` 已 ToLower；switch case 写全小写即可，DB 录入大小写无所谓。来源：treasureisland DB `game_type="TreasureIsland"` ≠ 小写 case → 走轮盘分支、面板空白。
- **回填**：/stats 族机台 Processor 必须实现 `OnStatisticHistoryHTTP` + `StatHistoryHTTPEndpoint()→("/api/ui/stats","noOfGames")`，否则只有开机后逐局攒、面板不足 500。两端点读同一 Redis key，回填记录与 settle 自落记录须**字段同构**（H11 同约定）。详见 L4.4 ②。
- 来源（本仓库实证）：treasureisland 漏接回填 → `numberOfGames` 长期 <500；回填 fetcher 原硬编码 `/api/ui/statisticHistory`，对只调 /stats 的机台打错端点。

## I. 协议保真度（防"抄既有机台模板"）

**I1 客户端业务模块在 `assets/<gametype>/<gametype>.js`**（PIXI 业务模块），不是 chunk-EQLH3F6G.js（Angular 主框架共享）。Phase 3 协议字典分析必须优先 grep 业务模块。

**I2 错误码常量独立定义，禁止跨机台 import**：跨包耦合 + 语义漂移；本机台 enum.go 独立。

**I3 sessionTimeout 触发器独立验证**：`<betValidationError extendedErrorCode="非空">` 立即弹 9018 会话超时弹窗 + return。**仅 InvalidToken 等踢下线场景应填**，普通错误必须留空。dragontiger 历史教训：dict.json 误以为"extendedErrorCode 多余字段是协议噪声" → server 每条 betValidationError 都填值 → 任何下注失败都弹"会话超时"。

**I4 边界归一化原则**：
- `parseBets` 解析 → `BetItem.BC` 保留原始数字字符串（betValidationError echo 必须 echo 原始）
- `applyBet → BetSvc.PlaceBet` 写 Redis → 归一化命名 BC（settle/betstats 按命名匹配）

**I5 server 主动合成帧**：bet echo / betstats enrich（我方平台金额）/ winners 合并 / logout。

**I6 incremental vs batch 协议**：
- 整批 / 全量快照协议（客户端每次发本局完整 bet 集合，如 baccarat6 / crystalroulette / megaroulette 的 `lpbet`）→ 按 bc 唯一、直接用当次快照覆盖 Redis；**不做 loadExistingBets / mergeBets**
- 增量协议（客户端只发新增 1 条，如 dragontiger `<placeBet>` 单数）→ **必须 loadExistingBets + mergeBets**
- 判定（两步，缺一不可）：
  1. `lpbet`（复数语义）帧名 → **几乎必为全量快照**；`<placeBet>` 单数才倾向增量
  2. 取一个 Rebet（"重复下注"恢复多点位）capture 样本，看该帧是否含**本局全部 bet** → 含全部 = 快照；只含 delta = 增量
- ⚠️ 单看 `grep e.bets.push` 前是否 `e.bets=[]` **不可靠**（megaroulette 因此误判为增量 → #193，见 J1）

dragontiger 历史教训：增量协议但 server 走整批覆盖 → 玩家先下龙 2000 + 后下和 2000 → Redis 整个替换为 `[{tie,2000}]` → 龙的 2000 消失。
megaroulette 反向教训：全量快照协议被误判为增量 + 用 `ck` 做去重键 → Rebet 多点位共享同一 `ck` 互相覆盖 → 见 J1。

**I7 partial-accept 协议**：客户端按 `totalBetsRejected === totalBetsSent` 判 BETS_REJECTED；server batch-all-or-nothing 完全相反。改逐 bet 校验：accepted 落库 + bet echo；rejections 各发 betValidationError。

**I8 history 详情 score/multipliers/payouts 不能空串**：客户端 history 渲染直接用字段值显示，缺数据填 `"0"`，**不是空串**。

**I9 worker 必须做"协议对照矩阵"自检**：客户端 → server 的所有 XML 帧 vs server ClientCommand struct；server → 客户端的所有帧 vs 客户端 socketHandler case。任一行 ❌ → 协议不通，verify 阶段拦截。

**I10 资金/UX 完整性必查清单（verify 必跑）**：
1. 下注落库 BC 字段（Redis SCAN 验证）
2. betstats enrich 命中（dragon.total 增量等于 amount × rate）
3. winners 合并（winner[] 含我方 userId）
4. InvalidToken 触发 KickUser（logout XML）
5. 一般 betValidationError 不弹 sessionTimeout
6. history score 非空（cgibin/audit/game.jsp 返 XML 有值）

## J. 生产 bug 复盘铁律（issue 实证）

> 来源：pp-game 仓库已对接机台的**上线后真实 bug** issue 复盘，每条对应 ≥1 个 fixing commit。
> 与 A-I 区别：A-I 来自对接期 codex 审查；J 是 verify 阶段漏网、上线才暴露的 ——
> 对接新机台时优先级最高，verify（phase-6 V10-V13）逐条闸门。

**J1 `lpbet` 是全量快照协议，禁止用 `ck` 做去重键**（修正 I6）
PP 客户端每帧 `lpbet` 重发本局全部 bet。**按 `bc` 唯一、incoming 全量快照直接覆盖 Redis**，不 merge。
- `ck` 不是 per-bet 唯一 ID，是"该批 bet 发送时的时间戳"。点"重复下注"一次恢复多点位时这些 bet **共享同一个 `ck`** → 用 `ck` 去重会互相覆盖（封盘后 `<bets>` 确认帧返回重复条目）。
- 同一帧出现重复 `bc` = 帧损坏 → fail-closed 拒整帧。
- betCode 解析必须规范化（堵前导零等绕过）。
crystalroul / jackpotwheel / sweetbonanza / baccarat 全是纯覆盖模型，新轮盘机台必须对齐。
来源：#193 / commit `b7149478`。

**J2 上游帧时效语义二分法**（缓存 / 回放决策）
对每类上游帧标注时效语义再决定缓存与回放 —— 两个方向相反的 bug 同一根因（没区分帧时效语义）：
- **时效状态帧**（`disablesidebets` / `seat` / `timer` 等）：**不缓存、不回放**。回放会与上游真实状态脱节。状态由后端按权威数据自算（如边注禁用按缓存的 `ShoeSummary.totalGames` 算 `round`，随每帧实时刷新、新靴自然解禁；无权威数据时 fail-closed 全禁）。
- **每局重发的全量快照帧**（`<statistic>` 走势 5 路 / `<ShoeSummary>` 等）：**必须缓存最新一帧并在新连接 `initFrames` 回放**，否则走势板 / 统计空白（`#NaN` / `undefined`）。下一帧 live 自我纠正，过期风险可接受。
- **增量帧**（`<statisticLA>` 等）：**不缓存** —— 内容已被全量快照覆盖，回放会重复追加。
来源：#178（过期 `disablesidebets` 回放 → 提前禁边注）、#169（走势帧不回放 → 走势板空白）/ commits `ad02b6e9` `326ab9c4`。

**J3 下注规则必须 capture 实证，禁凭直觉假设**
safebet / 免佣 / Bonus 前置 / 边注禁用阈值 —— 每条下注校验规则都要有 capture 样本支撑（哪个 gameId 的什么组合 success / rejected）。recurring 根因：实现者凭直觉（"对子要押同侧""全押覆盖率太高""免佣是整桌属性"）写规则，真 PP 行为完全不同。
- Bonus 前置：同帧含**任一非 Bonus bet** 即可，不要求同侧（见 B8）。
- 免佣：经独立 betCode 表达（main.js enum `Player=11 / Banker=10`），须把 NC betCode 加白名单 + 限额复用主注 + 赔付走 `gameresult.bnc/pnc` 独立字段；普通桌运行时勾选免佣也要支持，不能只按 `baccarat6` 常量推断整桌变体。
- safebet：轮盘 `SafeBetPct=0`，`betOnAll / megaChances` 等是 PP 官方高覆盖玩法、不走覆盖率拒绝；派彩失控由 settle 三路 cap 兜底（G3）。
- 禁用集 / betCode 白名单：逐项核对 `tableConfig.disableSideBets` map 完整全集，别只挑显眼的几个（#178 漏 Super6）。
来源：#161 #181 #182 #178 / commits `39f0eb0a` `44cb668b` `ad02b6e9`。

**J4 `betValidationError` 必须命中客户端真识别的 error code**（扩展 B9 / I3）
后端选了客户端 `betValidationError` / `rejectBet` switch 不识别的 code（`1028` / `1059` / `1060`），客户端落 `default` 弹"请联系客服"通用错误，把普通业务拒单放大成系统故障。
- 对接每张机台必须读客户端 main.js 的 error switch，建"我方拒单语义 → 客户端真有 toast 的 code"映射表。被禁 betCode 用客户端识别的 `20602`（`BET_NOT_ALLOWED`），不要用 `1028`。
- 普通拒单 `extendedErrorCode` **留空**（仅 InvalidToken 类填 `9018`，见 I3）。
- 拒单后**不要追发** `command status=error` —— 会把前端带到通用错误弹窗。
来源：#161 #181 #182 / commits `39f0eb0a` `44cb668b`。

**J5 上游 `seat` 事件一律 drop，Inactivity 我方自管**
上游 `seat` 事件按 PP 代理账号广播，混入其它会话的 `idle` / `timeout`，透传给下游客户端会误弹 Inactivity 遮罩 + 强制断 WS（刷新进入 ~8.8s 即触发）。
- 所有机台 `upstream_dispatch` 一律 drop 上游 `seat`。
- Inactivity 用我方 per-user `IdleWatcher`，阈值取 `b_tables.activity_check_interval`（0 = 禁用，**不 fallback 默认值**）。
- session 改固定 TTL，仅"下注被接受"触发续期。
来源：#184 / commit `1a13b55b`。

**J6 展示配置统一配置驱动，禁硬编码 / 禁散落多份**
- 币种符号走 `b_currency_rates` 配置驱动（`CurrencyRate.symbol` 字段 + `configCache.CurrencySymbol` 统一取用），禁止写死 `&#36;`；`currency` 与 `currencyCode` 必须表达同一币种。
- 同一映射禁止在多个机台各抄一份（旧代码 megaroulette / jackpotwheel 各一份 `currencySymbol`）。
- 兜底逻辑（如 `applyTableConfigParamsCompat`）必须覆盖**所有调用路径**：JSON 路径 `buildTableConfigResponse` 与 XML 路径 `writeCgibinTableConfigBody` 都要跑，新增兜底时 grep 全部调用点。
来源：#188（币种符号硬编码）#163（标题兜底漏 XML 路径）/ commits `9f8754ff` `39f0eb0a`。

**J7 历史"投注类型"与"开奖结果"是各自独立、逐笔保存的字段**
每笔交易独立保存 `description`（来自 `BetCodeDescription(bc)`，玩家实际下注点）与本局 `result`（开奖结果），二者**绝不混用**。客户端历史表渲染"投注类型"读 `bet.description` 不是 `bet.result`。
核对特殊倍率 / 奖励格结算时，触发条件是 `value == rngSlot`（特殊格正好被转中），不能拿"画面上有该格"当结算依据。
来源：#162（历史明细投注类型误显示为开奖结果，复核为无法复现但规则有效）#167（Mega Wheel 倍率格误报）。

**J8 capture 目录命名跟随 hall external_code，不等于 PP tableId**
hall-for-live 上游不支持长 PP gameId 直接取启动链接，`scripts/game_dev/fetch_client.mjs` 用 hall `external_code`（数字，如 `2244`）命名 capture 目录；但 PP 真实 tableId 仍是字符串（如 `gatesofolympus01`），机台目录 / `enum.TableID` / `instance_factory` 注册键全部用 PP tableId 而非 capture 目录名。
- **AI 永远从 `tmp/<dir>/tableConfig.txt` 第一条记录的 `tableId` 字段反查**真实 PP tableId，不可拿目录名当 tableId 用。
- state.json 必须同时记录 `capture_dir`（数字目录名）+ `tableId`（PP 字符串）两个字段，所有 `tmp/<...>/` 路径用 `capture_dir`，所有代码 / 配置 key 用 `tableId`。
- 不区分两者的常见 bug：机台目录名误用数字（破坏 PP 协议）/ enum.TableID 误填数字（运行时桌台路由失败）/ 老 capture 路径冲突。
来源：scripts/game_dev/fetch_client.mjs 改造引入（hall round_detail_failed 排查时发现路径差异）。

**J9 历史详情（Go XML）与商户报表（前端页）是两套独立机制**
旧 fallback 模式 `server/game/pp/runtime/history_<gametype>.go` 已废弃；旧 `BuildGameReport`（Go server-render HTML）+ `report.go` + `reporthtml` 已删除（report 重构）。
- **历史详情**：`history.go::BuildGameDetail` —— PP `cgibin/usermanagement/audit/game.jsp` XML（客户端"我的历史"）；数据源 `tmp/<capture_dir>/gameDetail.txt`；机台 internal 包实现，`factory/history_factory.go` 注册 `DetailProvider`。
- **商户报表**：后端只出通用 JSON（`/gameHistory/report` + `reportjson.Report`，**所有机台共用、无 per-machine Go 代码**）；前端每机台一份**自包含**页 `client/reports/<tableId>/index.html`（fetch JSON 渲染，≥ 90% 还原 `roundDetail/*.html`，SVG / 样式内联本页）。
  - 🔴 **目录铁律**：一机台一份、**不共用**；**禁止共享 `_assets/` bundle / `RENDERER_BY_TABLE` 派发**（旧共享模式弃用）。即便同 gameType 多桌也各写各的。
  - 前置：L3.1 `HandleUpstream` 调 `archiveCurrentRaw` 落 `b_game_rounds.messages`（报表 `messages` 源）；L3.3 SETTLE 落 `round`/`extra`。
来源：jackpotwheel 后引入 registry + report 重构（PR #272）确立 JSON + 前端页 + 一机台一份。

**J10 bet/bets 确认帧永远在 betsclosed 后批量发，绝不 lpbet 期间逐发**
症状：客户端只能下一个位置——收到 `bet` 确认帧即把该位置定格，无法继续放筹码。
真实 PP 时序（capture 实测）：`lpbet` 全程只回 `command status:success` ack；`bet`/`bets` 确认帧只在 `betsclosed`（窗口关闭）后 ≈1.2~1.4s **批量下发最终快照**（最后一帧 lpbet 的下注集，per-user 私聊）。
🔴 **关键反例（treasureadvgt001 踩过）**：AIU 误推"下注落库成功即权威 → 立即 echo"。这是**理由偷换**——即时 echo 的危害**与商户 ack 无关**，而是客户端定格。所以 bet echo 永远在 betsclosed 后。
正确实现（与 jackpotwheel 同）：lpbet handler 只覆盖 Redis 快照 + `command` ack（**不 echo bet、不 MarkBetAccepted**）；`onBetsClosed` 异步 `SubmitBets(...,p.OnMerchantBetResult)` → 商户 /bet → `OnMerchantBetResult` accepted 分支 `MarkBetAccepted` + `echoBetsAfterMerchantAck` 逐用户 `events.SendToUser` echo `{"bet":{amount,betcode,seq}}`（amount 用最短 string `'f',-1`：1000→"1000"、0.1→"0.1"）。**echo 在 betsclosed 之后、商户 /bet 落账后发，时序天然满足。**
来源：treasureadvgt001 上线前用户发现"只能下一个位置"，对照 capture 时序定位（lpbet 期间 0 个 bet echo，全在 betsclosed 后 batch）。

**J11 每次 `/result` 派彩前必须有成功的 `/bet` 扣款（seamless wallet 资金铁律，违反即资金漏洞）**
症状：`b_wallet_transactions` 只有 `type=result` 行、无 `type=bet` 行 → 玩家从没被扣本金却照常派彩（输局白嫖、赢局多给一份本金 = 凭空给钱）。V14 只验派彩金额对不对，**验不出本金有没有扣**。
根因（treasureadvgt001 踩过）：`onBetsClosed` 漏调 `handlers.SubmitBets`、在 lpbet 直接 `MarkBetAccepted`，settle 只调 `/result`（金额=含本金毛派彩）。错误注释把"不向 PP **上游**下注"混淆成"不向**下游商户** /bet 扣款"——`SubmitBets` 扣的是下游商户本金，与是否向 PP 上游下注无关（**所有 mirror-feed 机台同样必须 SubmitBets**）。
铁律：① `onBetsClosed` 必须 `go handlers.SubmitBets(tableID, gameID, p.OnMerchantBetResult)`；② `MarkBetAccepted` 只在 `OnMerchantBetResult` accepted 分支标，禁止 lpbet/finishLpbet 直接标；③ 通用闸门 `handlers.SettleUsersSeamless::hasSuccessfulBetDebit`——`/result` 前查无本局该用户成功 `bet` 流水即 fail-closed（`ErrMissingBetDebit`，保留 Redis bet key 待人工），漏调 SubmitBets 的机台会在结算时被拦（玩家不被超付，但 settle 阻断 → 必须修 wiring，不能靠闸门兜底跑）。verify 见 phase-6 V16。
来源：treasureadvgt001 上线前用户发现"只有 result 无 bet"，溯源 onBetsClosed 漏 SubmitBets；修复同时给 SettleUsersSeamless 加通用 bet-debit 闸门（pp-game 06-merchant-protocols.md 2026-06-04 指证）。

**J12 写 `b_game_rounds` 的「显示/上游字符串」列宽必须 ≥ 协议族最长值，否则超长一条让整局丢库**
症状：某一类 bonus（名字最长的那个）开奖后 `b_game_rounds` 行 `extra`/`raw_data`/`messages` **三样全空**，且该 `result_code` 全表 0 行；error.log 报 `Error 1406 (22001): Data too long for column 'bonus_type'`。
根因（treasureadvgt001 踩过）：`bonus_type varchar(20)`/`result varchar(50)` 装不下 `"Captain Flint's Treasure"`(24 字符)；`persistRound → UpsertRoundWithDealer` 的 UPDATE **整条回滚**（不是只截断该列）→ extra/raw_data 没落、`settled_at` 没写 → `messagelog.persistMessages` 的 `WHERE result<>'' OR cancel_reason<>''` 不命中 → messages 也丢。其余短名 bonus(16–18 字符) < 20 侥幸不暴露 → **只有最长的那个 bonus 必丢数据**，极具迷惑性（看着像"某 bonus 不落库"）。
铁律：① round 表里凡承载「bonus 名 / 开奖摘要 / 上游显示串」的列（`bonus_type`/`result` 等），`size` 必须 ≥ 该 gametype 所有 bonus 名最长值（直接放宽到 `varchar(200)` 一劳永逸），model `gorm:size:` + 数据库 `ALTER TABLE … MODIFY` 双改；② 排查"某局数据缺失"先查 `error.log` 的 `Data too long` / `Error 1406`，再 `SELECT … WHERE game_id=…`（注意预占行 `variant` 为 NULL，别用 `variant=` 过滤把它滤掉）。一条超长字符串=**整条 round 写失败**，连带 extra/raw/messages 全丢。
来源：treasureadvgt001 上线后用户发现"中 Captain Flint's Treasure 必丢数据"，溯源列宽溢出（pp-game 2026-06-04 指证 + 经验文档第 10 节）。

**J13 互动 bonus 决策窗口锚 `tiDecisionInc` 开窗时点（板面动画之后），不是 bonus 触发帧**
症状：玩家反馈互动 bonus（逐格选择）"能操作的时间比真实 PP 少很多"，点了的格子很多没生效。
真实 PP 时序（capture 实测，CFT rc8 + BBM rc7 **完全一致**）：`tiBonus(+0s) → 板面动画 init/booster/anim 26s → tiDecisionInc 开窗(+26s) → 玩家选 14s → finalMap 关窗(+40s) → tiGr 结算(BBM +47s / CFT +80s)`。
根因（treasureadvgt001 踩过）：`onBonusTrigger(tiBonus,+0s)` 即 ①立刻发 tiDecisionInc ②设 auto-decision deadline=`now+15s` → 服务端 +15s 就封盘，比 PP 真正开窗 +26s **还早 11s**，玩家 +26s 后点的 pdec 全落在已 sealed 记录后被拒。
铁律：① tiDecisionInc **延迟「板面动画时长」（实测 26s，CFT/BBM 同）后**发，对齐 PP 开窗；② deadline = `tiBonus + (板面动画 + 选择窗口)` = +40s（PP finalMap 关窗）；③ 延迟开窗的闭包**捕获 tableID 而非 ctx**（同 FlushPendingWins/armAutoDecision，避免持过期 ctx）。seal 时机：pdec 玩家走 `armAutoDecision` 定时器在 deadline 封盘，全程未操作玩家走 settle(tiGr) `autoGenInteractivePicks` 兜底。
**附带**：CFT 是**树形向下**结构（每行选第 N 列 → 下一行只能落 N-1/N/N+1，邻列约束），auto-decision 补全**禁止 col=1 死填**（断树/跳列）；保留真人已选行后从其最后一行列继续 ±1 下潜（`cftAutoPicks(gameID,userID,existing)` 统一"没选/部分选"两场景）。
来源：treasureadvgt001 上线后用户指证"中 CFT 自动选位乱选 + 窗口时间少"（pp-game 2026-06-04 + 经验文档第 10/11 节）。
