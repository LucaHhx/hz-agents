# EVO 协议铁律（精华版）

> EVO 对接横跨各游戏族的共性陷阱。每条源自实测 / codex 审查 / 上线复盘。
> 与 PP 的本质区别：**PP 多数帧直转，EVO 大量帧 per-session 会话私有、必须 per-user 改写**——B 节是 EVO 灵魂。
> 视频（V 节）+ 大厅/会话/容灾（L 节）是 EVO 独有、PP 没有的大块。

## A. 信息源边界

**A1**：协议事实只从 capture（message/message-nobet/config/gameDetail/roundDetail）+ `clientResources/frontend/` bundle。禁参考老项目 `/Users/luca/work/ppgame`。
**A2**：`docs/evo-explore/` 设计文档是**实现前方案**，与 as-built 代码有出入（per-user 帧 / 视频解扰 / flipbook / currency 都是落地后改的）。**以 `server/game/evo/` 实际代码 + roulettecore 为准**。
**A3**：capture 是事实下限非协议上限。稀有帧（betValidationError / canceled / 特殊货币 / 大奖）可能从不出现 → 结合 bundle + roulette 既有实现反推。
**A4 capture 是「已被操作过的下限」，客户端代码才是协议上限（CrazyTime 撤注实证）**：capture 只录到录制时实际触发的帧——撤注没按就无 undo 帧、单子下注模式没用就无 Chip 帧，**「capture 没有」≠「协议没有」**。判协议全集（尤其下注 action / 撤注 / 罕见帧）必须 grep `clientResources/frontend/evo/mini/js/` 业务 bundle 的 type/action 常量 + reducer，**客户端代码权威**。行为分歧用**三方实证**坐实：① capture（真 EVO 行为）② 客户端 bundle（协议定义）③ **连我方服务端录一份 capture（我方实际行为）**。CrazyTime 撤注/单子下注 bug 就是靠「客户端代码露出 Chip/Undo action + 连我方服务端实测放 2000 筹码回 chips#0(注没记上)」坐实的——首份 capture 没按撤注、只用 SetChips 全量模式，误判无 bug。⚠️ **一个游戏可能有多套下注模式**（CrazyTime：SetChips 全量快照 vs Chip/BulkBet/Undo 增量，客户端 flag 决定），服务端须把 bundle 里所有 action 都处理，不能只按一份 capture 实现。**Monopoly 又一实证**：grep bundle `sendPlaceChipMessage({name:...})` 全集见客户端发 6 种 action（Chip/BulkBet/Repeat/Undo/**Double/UndoAll**），我方只处理前 4 种、漏 Double(翻倍)/UndoAll(清空) → 玩家点加倍/清空落 default 被拒单、功能失效（capture 只录了 4 种）。反过来 SetChips/Move 只在 enum 定义、`sendPlaceChipMessage` 从不发送 → 不处理也对，**以「实际 send 的 action」为准、非 enum 全集**。**roulette 族第三次实证（RedDoorRoulette 对接时发现，已修 commit f1a4d34e）**：`roulettecore` 只定义 PLACE/REMOVE/MOVE/UNDO 四个 action，漏 **`UNDO_ALL`**（客户端「清除全部筹码」按钮，bundle 有 `action:{type:"UNDO_ALL"}` / `"bets/UNDO_ALL"` / `CLIENT_PRESSED_UNDO_ALL`）→ 落 switch `default` 回 `ErrCodeInternalServer`、**Redis 注单原封不动** → 玩家以为已清空、封盘照扣全额本金。当年 `vctlz` 的 capture 只录到 `PLACE`（录制时没点撤销）故未暴露；而其余 5 族（crazytime/funkytime/icefishing/monopoly/monopolybigballer）**全都处理了 UndoAll，roulette 是唯一遗漏**。→ **新族对接第一件事：把 bundle 的 action 全集与既有同族实现做集合差，差集就是候选 bug**。

## B. per-user 数据构造（⭐ EVO 灵魂，PP 无）

**B0 「per-user 帧」是 EVO 通用律，但帧名/shape 逐族不同（从 capture 推导，勿照搬 roulette 名字）**：通用律 = 会话私有帧（本人注/余额/个人受理/个人派彩）广播前剥离、按下游连接回填。**roulette 的具体载体**：`tableState.betState`/`betActionResponse`+`betsAccepted`/`winSpots`/5 态 `tableState.state`。**game show(IceFishing) 的载体不同**：per-user 注帧 = `<gt>.bets`(`state.{status,chips,acceptedBets,rejectedBets,repeat,history}`，status `Idle→Open→Accepted→Settled`，**合并了 roulette 的 betState+受理 betsAccepted+派彩 win 三职能**，无独立 betActionResponse/betsAccepted/win 帧)，结算锚=`<gt>.gameResolved`，开/关窗=离散 `<gt>.betsOpen`/`betsClosed`。**下面 B1-B9 帧名是 roulette 实例，新族先从 capture 找到对应载体再套同一律**（找 per-user 帧靠**计数悬殊+per-session 字段**，不靠 type 集合差——game show 集合差为空）。

**B1 下发帧 tableId 用裸 EVO tableId（PPTableID），不是 b_tables.code**：真 EVO 客户端按 URL 里的 table_id 匹配桌态/余额。`win`/`balanceUpdated`/`tableState`/`subscribe` 下发填 code → 客户端判「不属本桌 / 余额未收到」→ 重连。索引/路由才用 code。**EVO 无 PP 的 B1 字节替换（bytes.ReplaceAll）**——EVO 是 per-user 合成帧时直接填正确裸 tableId。

**B2 个人注态帧是会话私有，广播前必剥离、下发按用户回填**（roulette `tableState.betState` / game show `<gt>.bets.state`，见 B0）：roulette `betState.{bets,lastGameChips,history}` 是这条会话玩家自己的注/上局 Rebet/逐笔历史。整帧广播 → 全桌收代理账号的注（别人的注上自己板面、Rebet 错乱）。修法（`per_user_betstate.go`，game show 换锚帧名）：
- 广播前 `stripTableStateBetState` 剥 bets/lastGameChips/history，只留公共桌态。
- per-user 下发 `broadcastTableStatePerUser` 按连接 userId 回填本人注（修 **1007 LateBet**：客户端 BETS_CLOSED 读本帧 bets 与本地注对账，封盘前后逐帧含本人注、含 GAME_RESOLVED）。
- `BETS_OPEN` 帧额外注入上局 `lastGameChips`（rebet）。无注/匿名连接收剥离版。

**B3 快照必须在结算清 Redis 之前抓（最易错）**：GAME_RESOLVED 帧在 handleTableState 内触发结算清注。per-user 回填的 `betsByUser` 必须用 `userBetsSnapshot` 在**清注之前**抓——否则现查 Redis 读空、丢本局注（真 EVO 的 GAME_RESOLVED 是带注的）。

**B4 balanceUpdated 上游 drop + 商户余额 per-connection 重发（🔴 无 playerId）**：上游渠道 USD `balanceUpdated` 一律 drop（`DispDrop`）；args = `{balance, balances[], currencyCode, tableId}`，**无 `playerId` 字段**（是「这条会话玩家自己的余额」），**按下游连接（per-connection）寻址**、非帧内 playerId。用**商户余额**（余额源 `runtime.PlayerBalance`，工厂 `SetBalanceSource` 注入）重发，`tableId` 填裸 EVO id（同 B1）。**缺余额源 → 恒 0 → 客户端 LOW BALANCE**；init 必发一帧，客户端 **~6s 收不到 → 超时重连**。（roulette 渠道帧曾带 playerId 是渠道差异，新族不可假设有 playerId。）

**B5 betsAccepted 受理快照在 BETS_CLOSED 之后下发，不在下注期定格**：下注期只回 `betActionResponse` 即时 ack（客户端知"收到、可继续放筹码"）；`betsAccepted` 最终受理集在关窗后下发。下注期逐发会把位置定格 → 玩家只能下一个位置（同 PP J10）。

**B6 无 type 的 root-key 帧（dealer/subscribe/time）不能当坏帧丢**：EVO init 期部分帧无 `type` 字段（`{"dealer":...}` / `{"subscribe":...}` / `{"time":...}`）。`DecodeUpstream` 必须 `decodeRootKeyFrame` 按顶层 key 识别（dealer→缓存+广播、subscribe→drop、time→drop）。**旧实现一律 Err 丢弃 → dealer 永不缓存 → 客户端无荷官名**。

**B7 subscribe channel = `table-<裸 EVO tableId>`**：channel 不匹配 → 客户端丢全部桌态帧。一上游 fan-out 多下游，subscribe 必须 server 自合成（C 类）。

**B8 winnersList 名为公共帧但绝不能裸直转——必须先合并我方下游中奖者再广播**（IceFishing000001 实测漏合并被用户指证：本人净中 10000 该在榜上排第二，因直转上游榜而不见自己）。上游 winnersList 只含别家赌场真实玩家（我方下注本地拦截、从不发上游 → 上游榜结构上**永不含我方玩家**）。修法（镜像 PP moneytime/jackpotwheel，icefishing `winners_broadcast.go`）：
- **拦截不直转**：`HandleUpstream` 收该帧 → 解码 → 合并 → 重 marshal **替换**原帧 `return true, merged`（1 进 1 出、**只广播一次**、不新增广播调用）；合并失败 `return false,nil`。
- **合并我方中奖者**：`handlers.CollectOurWinners(tableID, gameID)`（PP 既有能力 6，查 b_game_transactions is_win）→ `[]WinnerInfo{ScreenName(=会话 Nickname), NetWin(**含本金**，与个人 bets.payout 同口径)}` → 追加 winners 数组、按 payout 降序、**截断回上游原 len**（上游空则留我方全部）。
- **聚合字段透传**：`winnersCount`/`bettorsCount`/`totalAmount` 全场口径（远大于我方量级、币种为上游展示币种）→ **透传上游原值不动**，只插 winners 数组。
- **合并铁律（用户指证）**：先合并再广播；合并失败（DB nil / CollectOurWinners err / 解码失败）→ **整局不广播 winners**（宁缺勿错）；我方零中奖不算失败 → 原样透传上游帧。
- **EVO 条目只有 `screenName`、无 userId**（与 PP moneytime 含 userId 不同）→ **无需按 userId 去重**（上游全别家玩家、结构上不撞），直接追加排序截断。
- **时序**：依赖 winnersList 在 `gameResolved` 结算落库**之后**到达（CollectOurWinners 才查得到本局）；偶发乱序（先到）→ 退化为不含我方（不影响资金）。⚠️ winnersList 易被结算锚帧（roulette winSpots）广播扰乱时序。
- **多币种**：icefishing 单份广播即可（payout 用玩家本币 NetWin）；PP moneytime 的 EUR 归一 + per-观众币种 `BroadcastToTableByCurrency` 是该族增强，EVO 现未做、按需评估。

**B9 betValidationError code 必须客户端真识别**：拒单 code 命中 bundle 的 toast 分支；普通拒单 `extendedErrorCode` 留空（仅会话失效填）；拒单后不追发错误命令（否则落 default 通用错误弹窗）。

**B10 communal 演出帧（game show 特有，PP A2 同类）直转广播、不缓存**：game show 在关窗→结算之间有一串全桌一份开奖动画帧（IceFishing `<gt>.wheelSpinning/wheelStopping/wheelResult/bonus`，args 含 `<seg>Multipliers`/`sector`/`version`）。① A 类公共桌态，**直转广播即可（非 per-user、不剥不改）**；② 按帧时效广播、迟到的演出帧不缓存补发；③ 下游 join 时无需补这串（join 等下一局开窗）；④ 与结算锚 `gameResolved` 区分（演出只驱动动画、不碰资金）。**勿当坏帧 drop、勿当 per-user 改写**。roulette 无此类（开奖即 winSpots），故 §2A 分类要补 A2 子类。

**B11 game show `bettingStats` 须按需 enrich，「EVO 无 betstats」是 roulette 过拟合**：game show 高频广播 `<gt>.bettingStats`（IceFishing 428 帧最高频，args=`{gameId,bettors,watchers}`）。直转会让在桌人数只反映上游侧、漏我方 seamless 玩家。**新族必须先 grep `bettingStats`/`stats` 帧**：需计入我方则 drop 上游 → 合并我方本局有注用户数到 `bettors`、连接数到 `watchers` → 广播。🔴 **是聚合计数、非 per-player**——只能加我方聚合计数，**不能从中取/注单个玩家注**（与 winnersList 不同）。

**B12 `restore.begin`/`restore.end` 重连恢复包（game show，per-connection 状态重放）**：(re)connect/subscribe 后上游用 `<gt>.restore.begin`…`restore.end`（args `{version}`）包住一批桌态帧重放当前快照。下游连接接入时**我方伪服务端须自合成等价 restore 包**（begin → 公共桌态 + 本连接 per-user 注帧 + 余额 + 走势 → end），否则刚接入客户端无初始态、黑屏/空板。**勿把 restore.begin/end 当未知帧 drop、勿原样转发上游 restore（含他人/影子态）**。roulette 无此帧。

**B13 公共结果帧可能夹带个人结算字段，不能只按 type 判直转**：EVO 一些族会把全桌开奖结果和本会话下注/派彩状态放在同一帧。message-nobet 的同名帧可能只有公共字段；message.txt 的同名帧在玩家下注后才出现个人子对象。判断方法必须是 `type count + args key-set + 嵌套 key-set + 字段值域` 四项对照：凡出现本人注单、受理/拒单、派彩、余额、rebet 等字段，该帧就是 **handle/B 混合帧**，必须 `BroadcastToTablePerUser` 注入本用户状态；无注连接保留公共 shape。禁止因为该帧也包含开奖结果/动画字段就裸广播。

**B14 bonus 子游戏公开帧可能缺 per-session 选择字段，结算要找权威终局倍率**：bonus 演出/结果帧可能在 nobet mirror-feed 只给公共倍率表，不给本会话选择点；有下注会话则可能多出自动选择/个人选择字段。分析时要比较同名帧 shape，并确认结算倍率来源。若终局/结算锚帧有最终 `totalMultiplier`，而 bonus 子帧缺少可用个人选择倍率，资金结算必须 fallback 到终局倍率；数字段仍按本族 odds/slot multiplier 公式，不能统一套 `totalMultiplier`。

**B14.1 🔴 倍率盘可能【完全不经 ws 下发】——对接前必须先证明「倍率盘可从 ws 取到」，否则 per-player bonus 不可做（RedDoorRoulette 实证）**：CrazyTime 的 `crazybonus.result.flappers` 是**公共广播**（nobet 影子会话也能拿全网格），这是 b1/b4 per-player bonus 能做的**前提**。**但 RedDoorRoulette 没有任何对应帧**：三 flapper 的倍率印在**实体转盘上（只在视频里）**，game ws 全程不下发——nobet 会话的 bonus 相位 `tableState` 只有 `bonusSpots:{号码:level}`；**即便是 bonus 参与者的有头会话**（收到了 `autoAssignedFlapper`）也只拿到自己的 `bonusWin.payout`，仍无倍率盘。而我方代理账号**从不向上游下注** → 生产中连 `autoAssignedFlapper` 都收不到。
- **陷阱帧 `bonusWin.finalMultiplier` 是公共值不是本人倍率**：两个 bonus 局都 = 200（= 最高倍率），nobet 无下注也收到；round2 玩家实际倍率 50 而 `finalMultiplier`=200。**拿它给所有人结算 = 超付 4~6 倍**。
- **旁路也不成立**：bonus 局 `winnersList` 赢家条目带 `multiplier`，其**值集合**确实等于倍率盘（round2 `{30,50,200}` vs Green50/Blue200/Yellow30），但①只下发前 50 名赢家、低倍率 flapper 可能无赢家而缺值 ②**无 color/position 映射**（看到 30 和 50，不知哪个是 Yellow）③到达在 bonus 结束之后 → **不可作为倍率盘来源**。
- **唯一程序化来源 = REST `roundDetail.bonusRound.flapperResults`**（color→totalMultiplier）+ `wheelSpinResults`（Initial/ReSpin 全历程）。风险：我方运营商本局在上游**无参与者**，hall B2B `evo/rounds/{rid}/detail` 是否仍返回该局，**离线无法验证、须 live 探针**。
- **Phase 0/1 就要跑这个判据**（别等 L3 才发现）：`jq -rs '.[]|select(.dir=="recv")|.payload|fromjson|select(.type|test("bonus|result"))|.args' message-nobet.txt` 找 per-flapper/per-cell 倍率网格。**找不到 → 该 bonus 是「代理模型无源」**，与 Lightning Storm HotSpot 同类（那次决定放弃）。要么接 REST 兜底 + fail-closed，要么放弃该机台。

**B14.2 🔴 bonus 派彩倍率的「净 vs 总返还」口径逐族不同，照抄必错本金（RedDoorRoulette vs CrazyTime 实证）**：`crazytimecore/odds.go:149` 的 bonus 是 `stake × (m+1)`（m 是**净**倍率，+1 返本金，#429）。**RedDoorRoulette 的 flapper `totalMultiplier` 是【总返还】倍率**：`stake × TotalReturn` —— roundDetail 实证 `stake 4000, totalMultiplier 200 → payout 800000`（= 4000×200，**不是** ×201）。**照抄 CrazyTime 公式每次 bonus 中奖多付 1 倍本金。** 新族必须从 `roundDetail/*.json` 的 `participants[].bets[].{stake,payout}` 除一下坐实口径，**禁止跨族沿用派彩公式**。同理 RDR 的 bonus 是**替换**直注赔率（20×→200×）而非叠加，且**只作用直注**（同局覆盖该号码的 dozen/red 仍按标准赔率）。

**B15 winnersList 金额必 per-currency 换算、不止合并（#431，Monopoly 唯一漏接实证）**：B8 只讲合并我方中奖者，但 winnersList communal 广播、下游玩家币种各异——上游 winnings 是**帧流货币**（`frameCcy`，sniff 自上游 `balanceUpdated.currencyCode`；🔴 用 frameCcy 而非重采样容灾组 active 会话，否则 failover/重连窗口取错币种 → 金额数量级偏高），我方注入的赢家是各自本币。必须 `convertUpstream`（上游从 frameCcy 换）+ `convertOurs`（我方从 `w.Currency` 换）**归一到每个观众货币** + `events.BroadcastToTableByCurrency` 分组下发（`handlers.ConvertDisplayAmount` best-effort、失败保原值不阻断）。裸 communal 广播原值 → 非基准货币玩家金额错乱 + 与上游 winnings 混排排序错。**新族 winners_broadcast 必查是否接 frameCcy per-currency**——Monopoly 是 6 族里唯一漏的（communal 广播 NetWin），照 icefishing/crazytime 补齐（processor sniff + 4 段换算 + factory `SetUpstreamCurrencySource`）。

**B16 bonus 演出帧逐帧夹带 per-user 金额，必按连接注入 bonusWin（Monopoly boardWalk/boardState/cashPrize 实证，用户指证「进 bonus 没金额」）**：monopoly bonus（2/4 Rolls 棋盘）演出帧不只公共动画——boardWalk（每步）/boardState（重连态）/cashPrize（Chance 现金奖）各带 `bonusWin{betAmount,winAmount,totalWinAmount}` 个人金额（= 玩家触发段 `spinResult.result` 押注 × 该步 `multiplier` / 累计 `totalMultiplier`）。上游影子会话不下注 → 这些帧 bonusWin 空/缺，裸广播 → 玩家进 bonus 全程看不到自己赢额增长。判据同 B13（逐帧 `args|paths(scalars)` diff bet vs nobet、找**仅 bet 有**的字段），出现 bonusWin 类个人字段就必须 per-user 注入、不能裸广播；演出帧不涉资金故解析失败裸广播保底。⚠️ 别被 B10「communal 演出帧直转」误导——同一族的演出帧也可能夹带个人金额，**必须逐帧 diff、不能整类当 communal**。

## C. 资金路径 fail-closed（同 PP，EVO 照守）

**C1** CanBet Redis 异常返 false（宁拒不放，防开奖后补投）。
**C2** applyBet `ctx.BetSvc==nil || UserID=="" || gameID==""` 返明确错误不静默成功。
**C3** 撤单（REMOVE/UNDO 清注）必须先 CheckBet 校验窗口才改 Redis（关窗后撤单=资金风险）。
**C4** 整批拒清 Redis 仅限非窗口类（窗口拒绝不清，防"界面已撤实际扣款"）。
**C5/C6** BC Atoi 失败显式跳过 + ERROR log；bets JSON 解析失败 continue 跳过用户（不 append 空 BetData）。
**C7** GetRedisUserBets SCAN/HGetAll 失败返 error **不返 nil**（否则被当无下注 → 漏结算/漏退款）。
**C8** payout_cap 接入：per-user round payout max + `handlers.CapUserPayout` 等比缩放 + MCap=true。
**C9** Redis SCAN/HGetAll 用 `context.WithTimeout(5s)` 非 Background。
**C10 /result 必先有成功 /bet**：`onBetsClosed` 必 `go handlers.SubmitBets(ctx.TableID, gameID, p.OnMerchantBetResult)`；`MarkBetAccepted` 只在 `OnMerchantBetResult` accepted 分支（**绝不**在 betAction/applyBet）；`SettleUsersSeamless::hasSuccessfulBetDebit` 通用闸门兜底（无 bet 流水 fail-closed）。漏调 SubmitBets = 无扣款派彩（凭空给钱）。
**C11 OnRoundSettled 必调**（settle 成功），否则下一局误标 cancelled + 重复退款。
**C12 reconcile 孤儿局补结算同样 fail-closed**：从 recentResults 补结算的注也走 requireAccepted + hasSuccessfulBetDebit，不给没扣款的注派彩。
**C13 孤儿局 pending 态必用 `pendingsettle.Tracker` 五件套（勿自写 pending 字段）**：Mark on 扣款 / Clear on 结算（**compare-and-clear**：退款只走「原子赢得清标记」路径，防 sweep×帧驱动并发双退款）/ `NextOrphanRound` 帧驱动 / `SweepStaleSettle` 可选接口（settle_sweeper 60s 扫 5min 龄期——game-ws 长期死时帧驱动永不触发，无 sweep = 本金永扣的最大敞口）/ `RecoverPendingSettle` 跨重启载回（终态守卫防双退款）。另加 `PendingSettleStatus()` 监控可选接口（看板资金安全面孤儿局数据源），缺了 = 运维盲区。详见 phase-3-aiu-L4 §L4.2。🔴 **新族必查**：grep `pendingsettle` 确认接入五件套（Monopoly 曾是 6 族里唯一漏接的，自写 `pendingGameID` 缺 sweep/跨重启/监控，运维看板读不到其孤儿局）。🔴 **sweep maxAge 须 > 最长 bonus 演出局**：game show 长 bonus 局是分钟级（实测 monopoly 2/4Rolls 关窗→结算 192s、crazytime 大转盘 100s），旧 5min 会把**正常长局**误判孤儿退款 → 随后真结算再派彩 = 退款+派彩双付；已全局改 2h（`settle_sweeper.go`，远超最长演出局、只退真搁浅局）。「健康桌 pending 秒级清除」这个 sweep 立论对普通局成立、对长 bonus 局不成立。

**C14 局资金终态机 settle_state（已根治双付+本金永扣，common 层全托管，新族零接线自动生效）**：曾有两类跨族资金 bug——① fail-closed 局 persistRound 已写 SettledAt、`HasTerminalRound` 靠它判终态 → 重启误清 pending → 本金永扣；② 结算(/result R+rid)与取消退款(/refund F+rid)幂等空间被前缀隔开互不感知 → 跨端点双付。根治：`b_game_rounds.settle_state`（''/settling/settled/cancelled）单一真相源 + DB CAS 原子抢占（`handlers/settle_state.go`），`SettleUsersSeamless` 入口 claim（已取消局返 `ErrRoundCancelled` → 机台走既有 abortSettleTopLevel 不派彩）、`OnRoundCancelled` 退款前 claim（已结算/结算中跳过退款）、`HasTerminalRound` 只认 settle_state、refund_worker 三类 task 复检（refund_timeout 是 **per-user** 查 result 流水——局 settled 但该用户恰 /bet 超时未派彩仍须退他本金）。设计全文 `docs/资金终态机/DESIGN.md`。**新族注意**：结算必须走 `handlers.SettleUsersSeamless`、取消必须走 `p.OnRoundCancelled`（common 唯一实现），就自动在终态机保护内——绕开自调 wallet = 脱保；SettledAt 只是开奖展示时间，**永远不要拿它判资金终态**。

## D. 静默错误（必加 zap log）
业务关键路径禁 `_ = err`。必加 `global.HAB_LOG.Error/Warn + zap.Error`：OnGameResult / UpsertRound / SettleUsersSeamless / json.Unmarshal(bets/winSpots) / OnMerchantBetResult 早期 return / per-user snapshot 失败（warn）/ 视频三跳失败。

## E. struct 序列化
**禁 `map[string]interface{}` 跨边界**。所有 JSON 帧 struct + `json.Marshal`/`Unmarshal`（含 root-key 帧用具名 struct）。禁 raw 字符串拼 JSON。

## F. 测试
**F1** payout/odds 单测 ≥ 4 个 `roundDetail/<rid>.json` 真样本（EVO 结构化 outcomes，比 PP html 好对）。
**F2** **per_user_betstate 单测必有**（strip 后无私有字段 / personalize 回填 / snapshot-before-clear 时序）——EVO 核心资产。
**F3** reconcile 单测（漏 GAME_RESOLVED → recentResults 补结算 fail-closed）。
**F4** race：`go test -race -count=3`（betStacks per-user UNDO 栈并发）。
**F5** policy-pr：单文件 ≤500 行 / 嵌套 ≤3 层。
**F6** 注释最少（仅 WHY 一行）；不引老项目。

## G. 客户端-后端一致性 + 进制
**G1** 客户端展示的约束类数值（限额/封顶/赔率/合法投注）后端必须同字段同来源 enforce。
**G2** 默认值与客户端 fallback 一致（缺配置 ≠ 不封顶）。
**G3** payout cap `min(A,B,C)`：A=`maxMultiplier×用户当局总注`（用户级非单注）/ B=`Convert(euro_table_payout_max,EUR,currency)` / C=`table_payout_max`。EUR 换算失败 fail-closed。
**G4 🔴 currencyMult 进制全路径**：EVO 金额是进制制（IDR÷20000、BRL×5、INR×100，config.currencyMult）。下注校验 / 结算 / payout / 限额比较 / 显示**全部按币种乘系数**，漏一处金额错乱。限额与下注金额必须同进制比较。

**G5 🔴 限额/封顶必须 per-currency 取，禁止静默回落 USD**（2026-07-10 HAR 实证，6 族全中）：`b_table_currency_configs` 逐币种存限额，同桌 `straight_bet_max` USD=2000 / IDR=4000万（差 mult 倍）。三条硬规矩：
- **建实例时装配的 `p.limits` 只是机台默认（factory 按 USD 读）**，一切校验/封顶必须走 `limitsFor(currency)` 按玩家币种取。曾 roulette 的 `CheckBet` 直读 `p.limits.ValidateBets`（虽然 `BetCheckEvent.Currency` 已填好）→ IDR 玩家合法注全判 `1048`；该码在客户端属**静默组**（只 wipe chip 不弹 toast），玩家只见「下注全部被撤回」无提示。
- **`p.limits` 直读点要 grep 干净**，不止 `CheckBet`：`settle.go` 的 `payoutCapLookup`（少付玩家）、per-user 帧的展示值（MBB `per_user_playerstate.go` 的 `payoutLimit`）都曾漏改。
- **loader 内部不许回落 USD 原值**。缺该币种行时按 `limit(cur) ≈ limit(USD) × currencyMult(cur)`（USD mult 恒 1，含 `$$BaseCurrency=EUR` 的 game show 桌）重建；`currencyMult` 是**币种属性跨桌恒等**，可从任意桌该币种 config 读。拿不到 mult / USD 基准行也缺 → 返 error：下注侧 fail-closed 拒单，结算侧 cap=0 不封顶 + `ERROR` 告警（注单已扣款，结算不能拒）。**绝不可用 `b_currency_rates.rate`（市场汇率）代替 mult** —— IDR 15800≠20000、INR 83≠100、EUR 0.92≠1，用它放大会系统性少封顶＝少付玩家。同源教训见 PP issue #64（`GetRouletteLimitsByCurrency` 缺配置返 error）。
  - ⚠️ **该恒等式不处处精确，重建是安全兜底而非真值复刻**：live 全量比对 281 个金额键 → 275 精确、6 个真实值 **>** 重建值（全是 FunkyTime IDR 的 per-segment max，上游放宽 2×）、**0 个真实值 < 重建值**。故重建只会偏保守（误拒大额合法注），绝不放行超限注；min 与 payout_limit 全库精确。真值永远靠命中本币种行（scale=1）拿到，重建分支只在配置缺口时兜底并 warn 催补齐。**若某天出现「真实值 < 重建值」，重建就会放行超限注 —— 那时必须改回纯 fail-closed，不要调 scale 迁就数据。**验证 SQL 与例外断言见 `runtime/limits_scale_test.go`。

**G6 🔴 非 USD 币种必须实测，USD 账号一路绿灯**：G5 那类 bug 对 USD 玩家完全不可见（mult=1，回落 USD 等于没回落）。新族验收至少跑一个 IDR/INR 账号下注 + 中奖派彩。另：缺币种配置的玩家本就进不了桌（`merchant launch` 的 `errEvoCurrencyConfigMissing` + EVO `/config` 404 `currency not supported`），所以 `CheckBet` 的 fail-closed 是**纵深防御**不是唯一防线 —— 但新加进桌入口时必须同步补这道闸。

## H. 历史 / 报表（EVO JSON，非 PP XML）
**H1** history 是 **JSON**（`gateway/history_api.go` 通用）：token→玩家→按 `vendor_type='evo'` filter（防 PP 局窜入）→按玩家时区分组 YYYYMMDD；`/day` 元素带玩家时区偏移；接口可能是裸数组。
**H2** b_game_rounds.Extra 前瞻落盘：所有族特色字段（winNumber/倍数/bonus/子序列）凡 history/报表可能渲染都落，**禁因本局 capture 未触发而省略**。
**H3** b_game_transactions 字段齐：Currency（本局会话币种）/ Description（BetCodeDescription，下注点）/ Stake / Payout / SettledAt / MaxCapped。**投注类型(description) 与开奖结果(result) 各自独立逐笔保存，绝不混用**。
**H4** 报表前端页 `client/reports/<裸 id>/index.html` **一桌一份、不共用、不引共享 _assets**；fetch 通用 `/gameHistory/report` JSON 渲染，对照 `roundDetail/<rid>.{html,json}` ≥90%。前置：UPSTREAM archiveCurrentRaw 落 messages + SETTLE 落 round/extra。
**H5** b_game_rounds 显示串列宽 ≥ 协议族最长值（直接 varchar(200)），否则超长一条整局丢库（同 PP J12）。game show 的 result 是字符串段名+倍率（`result:"Leaf2"`/`totalMultiplier`/`<seg>Multipliers` 嵌套 JSON），Extra/Description 列宽须容纳多段倍率序列化串，**勿沿用 roulette winNumber 数字宽度**。
**H6 历史详情渲染方式逐机台不同（render SSR vs 结构化 data.data），对接前必看 gameDetail 实际结构**：真 EVO 多数机台（crazytime/icefishing/funkytime/monbigballer）历史详情响应 `data.render`（SSR HTML，我方 `gateway/renders/<gt>.go` 生成）；少数局面复杂的（Monopoly Live/RedDoorRoulette）响应结构化 `data.data`（`result.outcome{type,wheelResult,boardMoves,reSpins}`+`participants`，客户端 `<gt>.history` chunk React 渲染棋盘走位）。**对接前必 grep gameDetail.txt 顶层 data 是 `render` 还是 `data`、按实际选路径**——发错（该 data.data 却发 render）客户端走 CommonHtml 兜底、复杂局面渲染不出。data.data 路径需结算时把局面数据落 `b_game_rounds.Extra`（monopoly `boardMoves`/`reSpins` 从 boardWalk/rollResult/multiplier 帧采集），`history_api.go` **只对该 gameType 分支切 data.data、其他族维持 render 不动**。🔴 前端字段契约要核对（reSpins 前端无条件 `forEach` → 恒非 nil 禁 null；BonusRound 必带 boardMoves 数组）；上游 game-ws 无源字段（monopoly `boardState.upgrades`/`timesPassedGo`/`index`）是硬缺口 → 承认并置空/省略（确认前端缺该字段不崩，别硬造）。

## V. 视频中转（egcvi，EVO 独有大块，不碰钱但易花屏/重连）

> 视频不阻塞资金主线，可后置/前端直连兜底；但要做服务端代理须守以下。落点 `runtime/video_*.go` + `gateway/video_ws.go`。

**V1 三跳取流 + token 自签**：manifest-ws2.json(hop1，videoToken HS256 secret=videoSessionId 自身) → 边缘 manifest(hop2，vvt) → websocketstream2(hop3) fMP4。`videoSessionId = userId-session_id-tableId-hash6(sha1)`；videoToken HMAC key=videoSessionId（无隐藏密钥，后端可复现）。**hop3 连上先发 PLAY 命令 + header `Origin=casinoHost`**（缺 Origin → 1006）。vvt 含 ccip/vcip IP 绑定 → 三跳与连流须同出口 IP（同进程满足）。
**V2 逐会话加扰（坑 -12909/花屏根因）**：egcvi 流逐会话加扰（只动 IDR，length-preserving）。客户端 bundle 自带 descrambler.wasm 自解。服务端解扰广播可行，但**正解 = 外层 `descrambler.wasm` 完整 wasm-bindgen 链路 + `create_descrambler(页面域名 location)` + 异步驱动（generateRequestId 预热 + 帧间 await）+ jsdescrambler_descramble，必须 Node 运行时（不能纯 Go）**。⚠️ 抽内层模块单独调得「恒等」是假象（缺外层域名初始化）。默认转发加扰流让客户端自解最省。
**V3 关键帧判定（防每秒重连风暴）**：按**整帧字节 EMA 动态基线**判（IDR 是大帧 GOP≈24，约 P 帧 4×；ratio=4/alpha=0.125 实测无漏检）。⚠️ `sample_flags` 恒 sync、比 P 帧大小 都已证伪（恒 sync → gate 失效 → 每秒重连）。**不缓存关键帧**；下游 join 等下一个实时关键帧瞬间加入。上游必发 **1.5s PING** 保活。
**V4 下游 PLAY_STATUS/PONG/AUTH_RESULT 须回显 inReplyTo**：缺 inReplyTo → 客户端命令 promise 不 resolve → 首帧看门狗 ~4s 超时反复重连画面不出（非关键帧问题）。修在 `gateway/video_ws.go`。
**V5 flipbook 兜底流（dual=fMP4+flipbook）**：cookie 鉴权 / `0-wc-wallclock` 握手 / 每帧回发对齐 µs 戳拉帧（回毫秒戳即停推）/ 帧 `rfid==fid` 为关键帧；join 须从关键帧起，需 flipbook 专用 VideoBuffer 模型。

## L. 大厅 / 会话 / 容灾（EVO 独有，新族基本不碰但要知边界）

**L1 Akamai 反爬**：entry（evo-games.com）卡 TLS+HTTP2 双指纹 → 必须 `bogdanfinn/tls-client` Chrome profile；取 config 必须用**会话 tls-client**（标准库 403）。lobby/game ws 走 Akamai **UA 黑名单**（非指纹）→ 用普通 UA `evo-client/1.0`，认证靠 URL query EVOSESSIONID。**真凶 tlssha1**：go<1.25 标准库 ClientHello 带 SHA1 被判 bot → 修 `//go:debug tlssha1=0`；cookie jar 重试须复用 `_abck`（`primeAkamaiJar` 预热，建会话一次成功）。
**L2 大厅复合 key tableId:vtId**：部分桌（FunkyTime/blackjack）lobby key 是 `{tableId}:{vtId}`，configs/filterAttr/thumbnails/categories 复合、playersCount/history 纯；写镜像剥离+记 vtKey，下发 configs 用复合 key，否则桌不渲染。**取 config 复合 key 须剥纯 tableId。**
**L3 货币 config 真 per-currency**：换 showCurrency 后 /config 限红按 currencyMult 换算（USD1/BRL5/INR100，上游算好），可照 PP 逐货币换 session 同步落 `b_table_currency_configs`。
**L4 语言 per-玩家个性化不可广播**：POST `locale-override {value:locale}`(204) 持久化 + 带新 locale 重跑 setup/字符串包（软重载）；静态串包/清单可 CDN。语言偏好 EVO 用 `Params.evo_locale`(BCP-47)、PP 用 `Params.language`(短码)，格式不同分开存。桌名翻译自建 `b_tables.name_translations`，下发按 evo_locale 改写 title（回退 译名→name→上游原文）；49 locale 全集 `web/src/utils/evoLocales.js`。
**L5 entry currency×geo 拒入**：IDR 会话从非印尼 IP 打开被拒 `incorrect-currency-for-geo-location` → 换匹配出口 IP。
**L6 永不死线容灾（四路上游）**：panic recover 防进程崩 / 死会话 `Invalidate` 防 8min livelock / 读超时防半开静默 / 有界 mint（30s 超时）防冻全线 / 会话缓存 8min TTL 防高频 mint 触发限流(6007)。新族不碰容灾（基础设施层 `runner.go`+`lobby_failover.go`），但**结算依赖 game-ws 帧、无兜底是最大资金风险缺口**——新族 SETTLE 须有 reconcile 兜底（C12）。
**L7 game ws balanceUpdated tableId 必须裸 original_id**（同 B1）：重连根因之一。

## K. 交互式 bonus + 撤注（game show 玩家选择型；FunkyTime/CrazyTime 实证，codex+用户实测复盘）

> game show 的 bonus 轮里玩家要做选择（Bar 选杯 / StayinAlive 选色 / CashHunt 选格…），**选择决定 per-player 倍率**。这是 FunkyTime 反复踩坑的根因，roulette / 纯数字 game show 无。新族**有交互 bonus（先抽 capture 看有无 `<gt>.chooseColor`/`setChoice`/`playerChoiceMade`/`colorChoice` 这类选择帧）则本节逐条对照**。前置：bonus 倍率盘全上游广播可复现（无则像 Lightning Storm HotSpot 那样代理无源 → 评估跳过）。

**K0 🔴 参与门控的判据逐族不同，必须 grep 客户端 selector 实证，不可套用别族结论**：K1 描述的 `isParticipating = isBetConfirmed(status) + 押中该 bonus 段` 是 **FunkyTime/game show 的形态**。**RedDoorRoulette 完全不同**：其 `La(G)`（`roulette.47a5cd75.js:251699`）= `betState.bets` 存在 && `bets[开奖号的直注 betCode]` 存在，**与 `betsAccepted`/status 无关**，且在 `BONUS_GAME_INITIALIZING` **首帧一次性判定并锁定**。→ 对 RDR 的正确修法不是「betsClosed 提前发 Accepted」，而是**从 bonus 首帧起逐帧向该连接注入本人 `betState.bets`**；漏了则押中开奖号的玩家看不到选 flapper 界面。旁证：`autoAssignFlapperInMs`（选择倒计时）在 nobet 与 bet 会话**都出现 = 公共计时**，不是门控信号，构造 per-user betState 时**不能当私有字段剥掉**。**新族做法**：grep 客户端里控制 bonus UI 显隐的 selector，把它的入参逐个回溯到帧字段，再决定 per-user 注入什么。

**K1 交互 bonus 参与 UI（选择框/机会数 lives/选色盘）被客户端 `isParticipating` 门控 → 须在 betsClosed 即发 Accepted（🔴 否则整块 bonus UI 不显示）**：客户端 `isParticipating = isBetConfirmed(status∈{Closed,Accepted,…}) + 押中该 bonus 段`。真 EVO 在 `betsClosed` **就**发 `<gt>.bets{status:Accepted}`（capture 实证 Open→Accepted→Settled，在 wheelResult/bonus 之前）。我方原模型只在**异步商户 /bet 完成后**才发 Accepted → wheelResult 触发参与判定时 status 仍 Open → 不判参与 → **机会数/选色/选杯整块不显示**。修：betsClosed 时 `broadcastBetsClosedPerUser` 立即按连接发 Accepted（用 Redis 注；钱仍异步 /bet、失败走拒单纠正、/result 仍受 hasSuccessfulBetDebit 闸门 → **无资金风险**）。lives/bettingStats 是 communal 广播（已正常转发），根因在参与门控、不在转发。icefishing/crazytime 也是异步发 Accepted，但其 bonus 不依赖参与时序故未暴露。

**K2 选择窗口锁（🔴 资金，防超付）**：玩家选择影响自己倍率 → 可等倍率盘广播后再改选最高倍率超付。必须在**倍率盘揭晓前**的「选择阶段结束」事件（DecisionFinished/ChoosingFinished）`closeBonusChoice` 锁定；之后 `recordBonusChoice` 拒绝改选、回显已锁选项。上游 readLoop 串行调 HandleUpstream → 结算先于 gameCleared，下游选择写由 bonusMu 保护，无 race。

**K3 未选玩家 = auto 随机选一个（匹配 EVO，不是 minByValue 取最小）**：玩家不操作时真 EVO **帮随机选一个**（capture 实证 `colorChoice{auto:true}`/`playerChoiceMade{manual:false}` 选项变化、非固定默认），玩家拿那个选项倍率。**勿用最小倍率兜底**（亏待玩家、与 EVO 不一致——曾因 fund-safe 过度保守误用）。用**确定性伪随机**（seed=`gameID|userID`，固定选项集 fnv 哈希）→ 对玩家公平、不同玩家选项各异、且回执与结算取同一选项。

**K4 自动选择回执（窗口结束发，让客户端高亮系统帮选的）**：选择窗口关闭时为押中该段、未手动选的在线玩家发 `colorChoice{auto:true}`/`playerChoiceMade{manual:false}`（`events.SendToUser` 定向；用固定选项集算选项——窗口结束时倍率盘未揭晓也能算）。🔴 **须在 closeBonusChoice 之前 record+发**（窗口锁后 recordBonusChoice 拒绝）。

**K5 倍率盘缺失 fail-closed（🔴 资金）**：bonus 段倍率盘不完整（缺盘/缺项/非正）且有人押中该段 → **绝不按 0 结算**（会把中奖当未中、清 key、误派 0）。须 fail-closed（落人工介入入口、保留 bet key、不调 OnRoundSettled）等重试。仅在「有人押中该 bonus 段」时阻断（letter/number bettor 不受影响）。reconcile 孤儿局补结算同样走此校验。

**K6 撤注 = 服务端快照栈（🔴 资金，game show undo 不重发 placeChips）**：game show 客户端撤注（独立 `<gt>.undo`/`undoAll` 帧，或 `<gt>.bet` 的 Undo/UndoAll action）**只发撤注信号、不重发 placeChips 全集**（非 client-authoritative，客户端本地维护 betHistory 栈），UI 以服务端 bets 回执为准重同步。服务端原只回完整态 → 撤注被回执覆盖（"无效果"）+ 残留注 betsClosed 照 /bet 超扣。修：维护 per-user 快照栈（key=`gameId|userId`）——每次下注受理压栈、undo 弹栈恢复上一快照覆盖 Redis 回缩减态、undoAll 清栈清 Redis、MarkBetsClosed 清栈、窗口关 undoGuard 拒撤注。镜像 `icefishingcore`/`monopolybigballercore`/`funkytimecore`/`crazytimecore` 的 `bet_undo.go`。⚠️ 全量快照下注族（funkytime placeChips）也需此栈——撤注同样是独立帧。与 C3「撤单先 CheckBet 校验窗口」配套。

**K7 🔴 结算锚不一定是「开奖/终局状态帧」，且 bonus 局可能两段派彩（RedDoorRoulette 实证）**：直觉会把 `GAME_RESOLVED`（或同名终局态）当结算锚，**RDR 会错**。真锚是 **`bonusStart==false` 的那条 `winSpots`**：
- 普通局只有 1 条 `winSpots`（`bonusStart=false`），在 `GAME_RESOLVED` **之后** ~0.4s。
- bonus 局有 2 条：`#1{bonusStart:true}`（无 `bonusWin`，在 bonus 子状态机**之前**）→ `#2{bonusStart:false, bonusWin{...}}`（在 `CELEBRATING` 期间，**早于** `GAME_RESOLVED` ~7s）。**时序相对 GAME_RESOLVED 会翻转**，靠状态帧定锚必错。
- 🔴 **`winSpots#1` 不含押中 bonusSpot 号码的直注**：round 18c046a7（开 12）的 `#1` betCode 集 = `{46,48,43,47,42}`（无直注 `15`），`#2` 才有 `{15:800000,...}`（已 ×200）。**按 `#1` 结算会漏掉直注的本金 + 整个 bonus 派彩。**
- 方法论：结算锚 = **携带 per-user 派彩明细的那一帧**，用「有下注会话 vs nobet 会话」逐帧 diff 找它，别按帧名/状态名想当然；并确认是否存在「中间态派彩帧」这种半成品。

## R. 仓库/部署：client 资源 git 治理（EVO 全游戏共性，省 ~18MB/桌族）

**R1 vendored client 媒体不进 git，回源 CDN cache-through**：`server/game/evo/client/frontend/` 每族会涨 vendored 媒体（webm 声音/png/webp/jpg 图片/woff2 字体/mp3/svg，约占一半体积）。运行时 `gateway/client_proxy.go(evoCDNProxy)` 在 `/frontend/*` 本地缺失时回源 `tmbge.evo-games.com` + cache-through 落盘 → 媒体**无需 git 跟踪**。`.gitignore` 忽略 `frontend/**/*.{webm,png,webp,jpg,jpeg,mp3,woff2,ogl,svg}`，**例外保留 `game-render-assets/**`**（我方自产 render 资源、不在 EVO CDN）+ `reports/`。**只 git 固定 js/json/html/css**（代码+协议+manifest+样式，须版本一致）。与 PP 的 `client/apps/*/` 同思路。
- **版本一致天然保证**：content-hash 资源名不可变（`wheelsprit.10a145df.webp`），git 固定的 js/json 引用特定哈希 URL → 各服务器回源拉到的字节永远一致。
- **依赖**：生产须能访问 tmbge CDN（出口受限环境需预热缓存或保留媒体）。
- **历史回收**：`git rm --cached` 只停未来跟踪；`.git` 历史里的体积需 `git filter-repo` 重写（破坏性，另议）。
