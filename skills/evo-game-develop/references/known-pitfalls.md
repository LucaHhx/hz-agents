# EVO 协议铁律（精华版）

> EVO 对接横跨各游戏族的共性陷阱。每条源自实测 / codex 审查 / 上线复盘。
> 与 PP 的本质区别：**PP 多数帧直转，EVO 大量帧 per-session 会话私有、必须 per-user 改写**——B 节是 EVO 灵魂。
> 视频（V 节）+ 大厅/会话/容灾（L 节）是 EVO 独有、PP 没有的大块。

## A. 信息源边界

**A1**：协议事实只从 capture（message/message-nobet/config/gameDetail/roundDetail）+ `clientResources/frontend/` bundle。禁参考老项目 `/Users/luca/work/ppgame`。
**A2**：`docs/evo-explore/` 设计文档是**实现前方案**，与 as-built 代码有出入（per-user 帧 / 视频解扰 / flipbook / currency 都是落地后改的）。**以 `server/game/evo/` 实际代码 + roulettecore 为准**。
**A3**：capture 是事实下限非协议上限。稀有帧（betValidationError / canceled / 特殊货币 / 大奖）可能从不出现 → 结合 bundle + roulette 既有实现反推。

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

**B8 winnersList 多币种按观众币种广播**：roulette 等纯展示直转或 `BroadcastToTableByCurrency`（多币种观众各看本币）。新族社交瀑布需注入我方中奖者：drop 上游 → 合并我方 → EUR 归一排序截断 100 → per-观众币种广播（一局只播一次、合并失败不广播）。⚠️ winnersList 易被 winSpots 广播扰乱时序。

**B9 betValidationError code 必须客户端真识别**：拒单 code 命中 bundle 的 toast 分支；普通拒单 `extendedErrorCode` 留空（仅会话失效填）；拒单后不追发错误命令（否则落 default 通用错误弹窗）。

**B10 communal 演出帧（game show 特有，PP A2 同类）直转广播、不缓存**：game show 在关窗→结算之间有一串全桌一份开奖动画帧（IceFishing `<gt>.wheelSpinning/wheelStopping/wheelResult/bonus`，args 含 `<seg>Multipliers`/`sector`/`version`）。① A 类公共桌态，**直转广播即可（非 per-user、不剥不改）**；② 按帧时效广播、迟到的演出帧不缓存补发；③ 下游 join 时无需补这串（join 等下一局开窗）；④ 与结算锚 `gameResolved` 区分（演出只驱动动画、不碰资金）。**勿当坏帧 drop、勿当 per-user 改写**。roulette 无此类（开奖即 winSpots），故 §2A 分类要补 A2 子类。

**B11 game show `bettingStats` 须按需 enrich，「EVO 无 betstats」是 roulette 过拟合**：game show 高频广播 `<gt>.bettingStats`（IceFishing 428 帧最高频，args=`{gameId,bettors,watchers}`）。直转会让在桌人数只反映上游侧、漏我方 seamless 玩家。**新族必须先 grep `bettingStats`/`stats` 帧**：需计入我方则 drop 上游 → 合并我方本局有注用户数到 `bettors`、连接数到 `watchers` → 广播。🔴 **是聚合计数、非 per-player**——只能加我方聚合计数，**不能从中取/注单个玩家注**（与 winnersList 不同）。

**B12 `restore.begin`/`restore.end` 重连恢复包（game show，per-connection 状态重放）**：(re)connect/subscribe 后上游用 `<gt>.restore.begin`…`restore.end`（args `{version}`）包住一批桌态帧重放当前快照。下游连接接入时**我方伪服务端须自合成等价 restore 包**（begin → 公共桌态 + 本连接 per-user 注帧 + 余额 + 走势 → end），否则刚接入客户端无初始态、黑屏/空板。**勿把 restore.begin/end 当未知帧 drop、勿原样转发上游 restore（含他人/影子态）**。roulette 无此帧。

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

## H. 历史 / 报表（EVO JSON，非 PP XML）
**H1** history 是 **JSON**（`gateway/history_api.go` 通用）：token→玩家→按 `vendor_type='evo'` filter（防 PP 局窜入）→按玩家时区分组 YYYYMMDD；`/day` 元素带玩家时区偏移；接口可能是裸数组。
**H2** b_game_rounds.Extra 前瞻落盘：所有族特色字段（winNumber/倍数/bonus/子序列）凡 history/报表可能渲染都落，**禁因本局 capture 未触发而省略**。
**H3** b_game_transactions 字段齐：Currency（本局会话币种）/ Description（BetCodeDescription，下注点）/ Stake / Payout / SettledAt / MaxCapped。**投注类型(description) 与开奖结果(result) 各自独立逐笔保存，绝不混用**。
**H4** 报表前端页 `client/reports/<裸 id>/index.html` **一桌一份、不共用、不引共享 _assets**；fetch 通用 `/gameHistory/report` JSON 渲染，对照 `roundDetail/<rid>.{html,json}` ≥90%。前置：UPSTREAM archiveCurrentRaw 落 messages + SETTLE 落 round/extra。
**H5** b_game_rounds 显示串列宽 ≥ 协议族最长值（直接 varchar(200)），否则超长一条整局丢库（同 PP J12）。game show 的 result 是字符串段名+倍率（`result:"Leaf2"`/`totalMultiplier`/`<seg>Multipliers` 嵌套 JSON），Extra/Description 列宽须容纳多段倍率序列化串，**勿沿用 roulette winNumber 数字宽度**。

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
