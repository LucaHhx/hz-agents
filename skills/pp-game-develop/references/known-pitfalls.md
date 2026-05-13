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

**B2 winners pass 透传（默认）**：上游 winner[] 是真实玩家社交瀑布（含其他渠道/商户），**不是测试视角**。**完全丢弃** → 客户端 winnersCount=N 但 winner=[] 矛盾 + 丢失社交体验。资金安全独立：winner[] 仅展示，实际派彩走我方私聊 win 帧。

**B3 多事件单帧 orderKeysByPriority**：Go map 遍历不保证顺序。显式排序：`gameresult > winners > betsclosed > betsclosingsoon > betsopen > 其他`。单帧多 key 时按 verdict 单独保留/丢弃。

**B4 baccarat 不发 winningBetCodes/betSpotWin**：baccarat 客户端 main.js 对这两字符串 0 命中 → 服务端不合成（roulette 才需要）。新对接前必须 grep main.js 验证。

**B5 lpbet `gm` 字段动态拼接**：形式 `${session.gametype}_${desktop|mobile}`。main.js 出现的 `<gametype>_desktop` 字面量可能是 `pbdealnow` / `playerUnsub` 等特殊命令的固定值，**不是 lpbet 的 gm**。

**B6 ping 单/双引号兼容**：部分老版本客户端用单引号发 ping。`extractXMLAttr` 必须先试双引号再试单引号，单测覆盖两种。

**B7 EnrichBetstats 返回完整 envelope**：`{"betstats":{...}}` 整 envelope。rewrite 链路必须 `unwrapEnvelope` 解出内层后存到 dispatchAction.data，否则会变成 `{"betstats":{"betstats":{...}}}` 双信封。

**B8 Bonus 边注主投注前置**：押 PlayerBonus（如 betCode 12）必先押 Player（betCode 0），否则返 1059 PlayerBonusBetWithoutMainBet。具体码值按字典实际值。

**B9 BetValidationError 字段 7 个**：betCode / code / extendedErrorCode / optExtErrorCode / optExtErrorMsg / category / severity。后 4 个虽 omitempty，但商户错误透传必须能填。

**B10 switch 帧必须含 wsAddress + httpAddress**：main.js `e&&"string"==typeof e.httpAddress&&"string"==typeof e.wsAddress` 才触发 setGameServer。两个字段都是 string 才生效。

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

**H2 b_game_rounds.Extra 落盘**：机台特殊字段（multiplier/payouts/sbmul 等）必须落 Extra（结构化 JSON），不只留 RawData。

**H3 b_game_transactions 字段**：填齐 Currency（本局会话币种，**不是 user.Currency**）/ Description（H6 本地化）/ Stake / GameNetCash / MaxCapped / BoosterEnabled / SettledAt（事件时间）。

**H4 history 详情 XML 节点严格匹配**：客户端按 XML 节点路径直接解构（`<gametype>Details`），节点名 / 字段名 / 大小写**任一不一致**就渲染失败。

**H5 b_game_rounds.StartedAt 在 betsopen 时刻写入**（不是 settle 时）：history XML gameStartTimestamp 要求是本局开始时刻。

**H6 BetCode Description 本地化**：history list/详情都展示 `betCodeDescription(bc)`，按 gameType 维护映射。

**H7 b_game_user_actions 落盘**：机台有"玩家选择"环节（candy_drop 选球 / hit-stand / decision）必须把每个用户的选择落盘。

**H8 fetchRoundHistory 兜底空数组的影响**：客户端"Recent rounds widget"依赖此 → 空数组 = 玩家看空列表。

**H9 roulette 必须输出全量默认 `<rouletteDetails>` 节点**：客户端解析 `g ?? u`，server 不输出节点会走空分支报错。

**H10 开发期通过代码分析验证，不抓样本**：单测构造假 round 走 parser → 断言输出。capture 有 gameDetail.txt 时改为真 XML 单测。

## I. 协议保真度（防"抄既有机台模板"）

**I1 客户端业务模块在 `assets/<gametype>/<gametype>.js`**（PIXI 业务模块），不是 chunk-EQLH3F6G.js（Angular 主框架共享）。Phase 3 协议字典分析必须优先 grep 业务模块。

**I2 错误码常量独立定义，禁止跨机台 import**：跨包耦合 + 语义漂移；本机台 enum.go 独立。

**I3 sessionTimeout 触发器独立验证**：`<betValidationError extendedErrorCode="非空">` 立即弹 9018 会话超时弹窗 + return。**仅 InvalidToken 等踢下线场景应填**，普通错误必须留空。dragontiger 历史教训：dict.json 误以为"extendedErrorCode 多余字段是协议噪声" → server 每条 betValidationError 都填值 → 任何下注失败都弹"会话超时"。

**I4 边界归一化原则**：
- `parseBets` 解析 → `BetItem.BC` 保留原始数字字符串（betValidationError echo 必须 echo 原始）
- `applyBet → BetSvc.PlaceBet` 写 Redis → 归一化命名 BC（settle/betstats 按命名匹配）

**I5 server 主动合成帧**：bet echo / betstats enrich（我方平台金额）/ winners 合并 / logout。

**I6 incremental vs batch 协议**：
- 整批协议（baccarat6 lpbet 客户端每次发完整集合）→ 直接传当次 bets
- 增量协议（dragontiger placeBet 客户端只发新增 1 条）→ **必须 loadExistingBets + mergeBets**
- 判定：grep main.js `e.bets.push(a)` 前是否 `e.bets = []` 清空

dragontiger 历史教训：增量协议但 server 走整批覆盖 → 玩家先下龙 2000 + 后下和 2000 → Redis 整个替换为 `[{tie,2000}]` → 龙的 2000 消失。

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
