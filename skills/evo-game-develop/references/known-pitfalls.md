# EVO 协议铁律（精华版）

> EVO 对接横跨各游戏族的共性陷阱。每条源自实测 / codex 审查 / 上线复盘。
> 与 PP 的本质区别：**PP 多数帧直转，EVO 大量帧 per-session 会话私有、必须 per-user 改写**——B 节是 EVO 灵魂。
> 视频（V 节）+ 大厅/会话/容灾（L 节）是 EVO 独有、PP 没有的大块。

## 🔍 怎么用这份文件：**按块查，不要通读**

本文件是**查询手册不是教材**。全文 200+ 行，一次读完等于把 40 条铁律摊平进上下文、每条都记不牢。
正确用法：**做到哪一块，只读那一块对应的几条**（下表），做完那块再查下一块。

> ⚠️ **两套 L 编号别混**：左列的 `L1`-`L5`/`L4.3` 是 **AIU 的 Layer**（开发分层）；右列的 `〔L节〕L1`-`L7` 是**本文件「大厅/会话/容灾」节**的铁律编号。凡右列出现 L 都加了〔L节〕前缀。

| 你正在做的块（Layer） | 只读这几条铁律 | 配套 reference |
|---|---|---|
| **Phase 0** 协议分类 / capture 验收 | A1-**A5**、B0、B13 | `phase-0-acceptance.md` |
| **Phase 1** 复用边界判定（建新 core？） | **I11、I2** | SKILL.md「复用边界三分」 |
| **L1** DICT / enum / 协议常量 | A4、B0、E、**I2** | `phase-3-aiu-L1.md` |
| **L2** MODELS / RULES / 限额 | E、G1-G5、I2 | `phase-3-aiu-L2.md` |
| **L3** UPSTREAM 分流 | B6、B10、B12、B13、B16、**B17**、**E2**、D | `phase-3-aiu-L3.md` |
| **L3** PER_USER（⭐ 工作量大头） | **B0-B4**（含 **B1.1** 内部 key）、B13、B16、**E2** | **`per-user-frame-fidelity.md` 全文** |
| **L3** SETTLE / 结算锚 | **C1-C16**、K5、K7、B14.2、**B18** | `phase-3-aiu-L3.md` |
| **L3** CHECK_BET / 下注校验 | C1-C4、**C16**、G1-G6 | `phase-3-aiu-L3.md` |
| **L3** WINNERS 合并 | **B8、B15、E2** | L4 末「WINNERS 处理」 |
| **L4.1** PAYOUT | B14.2、**B14.3**、**C15**、G3、G4、G5 | `phase-3-aiu-L4.md` |
| **L4.2** HISTORY_RECENT / reconcile | C7、C12、C13、C14 | `phase-3-aiu-L4.md` |
| **L4.3** HISTORY_DETAIL（render） | **H1-H7**、I8、**B19** | **`phase-3-game-record-render.md`** |
| **L4.4** REPORT_PAGE | **H4**（架构已更正）、H5、B14.2 | `phase-3-aiu-L4.md` |
| **L4.5** CURRENCY_CONFIG | G4、G5、G6、〔L节〕L3 | `phase-3-aiu-L4.md` |
| **L4.6** BETSTATS（条件） | B11 | `phase-3-aiu-L4.md` |
| **交互式 bonus**（有选择帧才做） | **K0-K8**、B14、B14.1、**B14.3**、**B19** | `phase-3-aiu-L3.md` |
| **下注受理 / 撤注 / UNDO** | **K8**（全量快照零回执）、K6、A4、C3、C4、**C16** | `phase-3-aiu-L3.md` |
| **L5** FACTORY 注册 | B1、**B1.1**（双 ID 口径） | `phase-3-aiu-L5.md` |
| 视频（后置，可不做） | V1-V5 | — |
| 大厅 / 会话 / 容灾（基本不碰） | 〔L节〕L1-L8 | `evo-platform-primer.md` |
| **提交前 / 每层收尾** | F1-F6、R1、D、**E2** | `phase-3-layer-review.md` |

**🔴 无论做哪块都先扫一眼的五条**（不是某块专属，是全程判据）：
**A4**（capture 是下限、客户端代码是上限——「capture 没有」≠「协议没有」）、
**B0**（per-user 是通用律但帧名逐族不同，勿照搬 roulette）、
**C10/C11**（`/result` 必先 `/bet`；`OnRoundSettled` 必调——凭空给钱 / 重复退款的两个总闸）、
**E2**（强类型 struct 是隐式白名单，改写帧会静默吃掉未声明字段——跨 4 族复发）、
**K8**（全量快照下注协议受理必须零回执——跨 3 族复发，当前最高频 bug class）。

> 📌 **本表 2026-07-21 据近 3 个月 69 个 EVO commit + 63 个 issue 复盘更新**：新增 K8 / E2 / C15 / C16 / B1.1 / B14.3 / B18 / B19 / I2 / I8 / I11 / L8 / B17；**更正** H4（报表页架构与实现相反）、B1+L7（balanceUpdated 有反例）。
> **跨族复发排行**（说明旧 skill 没拦住，新族务必一次到位）：E2 丢字段 **4 族** > K8 受理回执 **3 族** > B1.1 双命名空间 **3 子系统** > C16 在飞写 **5 族**。

## A. 信息源边界

**A1**：协议事实只从 capture（message/message-nobet/config/gameDetail/roundDetail）+ `clientResources/frontend/` bundle。禁参考老项目 `/Users/luca/work/ppgame`。
**A2**：`docs/evo-explore/` 设计文档是**实现前方案**，与 as-built 代码有出入（per-user 帧 / 视频解扰 / flipbook / currency 都是落地后改的）。**以 `server/game/evo/` 实际代码 + roulettecore 为准**。
**A3**：capture 是事实下限非协议上限。稀有帧（betValidationError / canceled / 特殊货币 / 大奖）可能从不出现 → 结合 bundle + roulette 既有实现反推。
**A4 capture 是「已被操作过的下限」，客户端代码才是协议上限（CrazyTime 撤注实证）**：capture 只录到录制时实际触发的帧——撤注没按就无 undo 帧、单子下注模式没用就无 Chip 帧，**「capture 没有」≠「协议没有」**。判协议全集（尤其下注 action / 撤注 / 罕见帧）必须 grep `clientResources/frontend/evo/mini/js/` 业务 bundle 的 type/action 常量 + reducer，**客户端代码权威**。行为分歧用**三方实证**坐实：① capture（真 EVO 行为）② 客户端 bundle（协议定义）③ **连我方服务端录一份 capture（我方实际行为）**。CrazyTime 撤注/单子下注 bug 就是靠「客户端代码露出 Chip/Undo action + 连我方服务端实测放 2000 筹码回 chips#0(注没记上)」坐实的——首份 capture 没按撤注、只用 SetChips 全量模式，误判无 bug。⚠️ **一个游戏可能有多套下注模式**（CrazyTime：SetChips 全量快照 vs Chip/BulkBet/Undo 增量，客户端 flag 决定），服务端须把 bundle 里所有 action 都处理，不能只按一份 capture 实现。**Monopoly 又一实证**：grep bundle `sendPlaceChipMessage({name:...})` 全集见客户端发 6 种 action（Chip/BulkBet/Repeat/Undo/**Double/UndoAll**），我方只处理前 4 种、漏 Double(翻倍)/UndoAll(清空) → 玩家点加倍/清空落 default 被拒单、功能失效（capture 只录了 4 种）。反过来 SetChips/Move 只在 enum 定义、`sendPlaceChipMessage` 从不发送 → 不处理也对，**以「实际 send 的 action」为准、非 enum 全集**。**roulette 族第三次实证（RedDoorRoulette 对接时发现，已修 commit f1a4d34e）**：`roulettecore` 只定义 PLACE/REMOVE/MOVE/UNDO 四个 action，漏 **`UNDO_ALL`**（客户端「清除全部筹码」按钮，bundle 有 `action:{type:"UNDO_ALL"}` / `"bets/UNDO_ALL"` / `CLIENT_PRESSED_UNDO_ALL`）→ 落 switch `default` 回 `ErrCodeInternalServer`、**Redis 注单原封不动** → 玩家以为已清空、封盘照扣全额本金。当年 `vctlz` 的 capture 只录到 `PLACE`（录制时没点撤销）故未暴露；而其余 5 族（crazytime/funkytime/icefishing/monopoly/monopolybigballer）**全都处理了 UndoAll，roulette 是唯一遗漏**。→ **新族对接第一件事：把 bundle 的 action 全集与既有同族实现做集合差，差集就是候选 bug**。

**A5 🔴 部分桌的 game socket 是加密的，capture 先验「解没解开」再谈协议分析（2026-07 新变量）**：EVO 自 2026-07-15→07-21 起**逐桌**给 game socket 启用二进制加密帧（AES+RC4+zstd），由上游 `/config` 的 `ws_encryption:"1:3"` 协商驱动 → 客户端 game ws URL 追加 `encrypted=true&nonce=`。**不是所有机台都加密，且 EVO 在逐张切、会隔夜突变**——同一张桌 07-21 录的 capture 明文、07-24 已加密（`leqhceumaq6qfoug` 实证）。加密**只在 game socket**，chat 明文、视频是另一套加扰。判据两个（应一致，不一致说明 capture 不可信）：`config.txt` 有非空 `ws_encryption` / `message*.txt` 的 `ws` open 事件行带 `encrypted:true`。
- **现行 `evo_fetch.mjs` 已自动解密**（复用服务端同款 sidecar + 我方 encpart bundle 解回明文再落盘），所以 **`payload` 仍是明文 JSON 字符串、与明文桌完全同构，§2/§2A 的全部 jq 命令原样可用**，只是加密桌的帧多一个 `enc:true` 标记。**明文桌产物零变化**。
- 🔴 **拒收判据一：有 `decryptError` 的帧**（该帧只落了 base64 `raw`，没有 `payload`）→ capture 缺帧且缺得看不出来，**必须查因重录**，不能"先凑合分析"。头号原因是真客户端 `client_version` 与我方 bundle 版本脱节（脚本会打 WARN），按 `docs/evo-crypto/03` 重同步 `fec/encpart` bundle 后重抓。
- 🔴 **拒收判据二：`payload` 里成片 U+FFFD（�）乱码** = 这份 capture 是**旧版脚本**（无解密层）录的加密桌——二进制帧被按 UTF-8 硬解，**信息已不可逆销毁**，任何分析都是在读噪声。只能重录，禁止硬着头皮解读。
- ⚠️ **解密后数值被 JS 规范化**（`330000.00` → `330000`）：这是 sidecar `JSON.parse`→`stringify` 的必然结果，且**我方 Go 运行时在加密桌上收到的同样是这个形态**（同一条管线），所以口径是对的。但**别拿它当协议事实**去推"该族金额无小数"——要逐字节原文时用 `evo_fetch.mjs --keep-raw` 留 base64 密文离线重放。
- 与对接实现的关系：**加密是上游连接层的事，已由 `game_upstream*.go` + `crypto_sidecar.go` 落地，新族对接不碰**（同视频/大厅/容灾）。本条只影响 Phase 0 的输入验收。

## B. per-user 数据构造（⭐ EVO 灵魂，PP 无）

**B0 「per-user 帧」是 EVO 通用律，但帧名/shape 逐族不同（从 capture 推导，勿照搬 roulette 名字）**：通用律 = 会话私有帧（本人注/余额/个人受理/个人派彩）广播前剥离、按下游连接回填。**roulette 的具体载体**：`tableState.betState`/`betActionResponse`+`betsAccepted`/`winSpots`/5 态 `tableState.state`。**game show(IceFishing) 的载体不同**：per-user 注帧 = `<gt>.bets`(`state.{status,chips,acceptedBets,rejectedBets,repeat,history}`，status `Idle→Open→Accepted→Settled`，**合并了 roulette 的 betState+受理 betsAccepted+派彩 win 三职能**，无独立 betActionResponse/betsAccepted/win 帧)，结算锚=`<gt>.gameResolved`，开/关窗=离散 `<gt>.betsOpen`/`betsClosed`。**下面 B1-B9 帧名是 roulette 实例，新族先从 capture 找到对应载体再套同一律**（找 per-user 帧靠**计数悬殊+per-session 字段**，不靠 type 集合差——game show 集合差为空）。

**B1 下发帧 tableId 双口径【逐帧逐族 grep 客户端门控坐实】**：桌态/派彩帧（`win`/`tableState`/`subscribe`/PBS/resolved）用**裸 id**——客户端按 URL 里的 table_id 匹配，填 code 判「不属本桌」→ 重连；但 **`balanceUpdated` 反过来用我方 code**——客户端余额中间件按 `getTableId()===payload.tableId` 门控，`getTableId()` 取自 `/config.table_id`，而 config 被 `api_config.go` 改写成了 code，所以 balanceUpdated 填裸 id 会被静默丢弃、表现为「派彩后余额不刷新 / ~6s 判未收到重连」（dice #495 坐实、baccarat 复证；PROJECT-MEMORY『帧里的 tableId 分两种口径』）。**记法：balanceUpdated 与 /config.table_id 同源（=code），其余桌态帧用裸 id。** 索引/路由用 code。**EVO 无 PP 的字节替换（bytes.ReplaceAll）**——per-user 合成帧时直接填正确 id。
- 🔴 **反例（#495，dice 族 balanceUpdated 必须填我方 code）**：sicbo/lightningdice 共用的客户端 bundle 模块 15451 对 `balanceUpdated` 有严格相等门控 `t === v.getTableId()`，而 `v.getTableId()` 读的是 `/config` 的 `table_id` ——**这个字段被我方 `api_config.go` 改写成了 code**（`evoSuperSicBo000001`）。填裸 original_id 恒不相等 → **稳态余额帧被静默丢弃、UI 冻结在进桌值**（不影响真实扣派款，但是资方/客诉风险）。修法：`sicbocore/per_user_betstate.go` 把 `outboundTableID()`（桌态帧，裸 id）与 `balanceTableID()`（balanceUpdated，我方 code）**拆成两个函数**，别整族共用一个。
- **为何 roulette 不暴露**：其 handler 是 `isAAMS() && !tableId || dispatch(...)`——非 AAMS **恒无条件更新、根本不看 tableId**，init 首帧另靠 `renewBalance` 放行。所以「裸 id 全对」是**该族客户端不校验的偶然结果**，不是 EVO 协议规定。真 EVO 自己无此坑（它的 config.table_id == 帧 tableId，没有双命名空间）。
- **新族做法**：接入任何按桌维度的字段/门控前，拿**本族** bundle grep 该帧的门控条件 + 对照本族 `/config` 实际返回的 `table_id`，逐帧决定填哪个。**禁止整族套用一个取值函数，禁止照搬 roulette 结论或隔壁代码**。

**B1.1 🔴 双命名空间不止在协议帧内容——我方【内部跨子系统 key】同样会静默错位（三次独立事故）**：B1 讲的是帧内容；而这三起事故的根源都在**我方自己写的 key**：① 大厅镜像用 `original_id` 存储、游戏侧返回时自报 `physicalId=code` → 查不到桌、误弹「桌子暂时无法使用」（#405，修法 `runtime/lobby_idmap.go` 入口统一改写成 code）；② 下注计数 `IncrBetCount` 写 key 用 `ctx.TableID`(=code)、聊天发言门控 `Evaluate` 读 key 用 `originalID` → 计数永远判不达标、**发言被永久拦截**（#525，修法 `gateway/chat_send.go:89` 改用 tableCode 对齐写侧）；③ 即上面 B1 的 #495。
- **通用律**：新族只要新增任何**以 tableId 为 key 的内部状态**（限流计数器 / 镜像存储 / 缓存 / 统计 / 告警去重），必须**显式核对读写两端用的是同一个命名空间**，不能想当然套用某段既有代码的写法。这类 bug 编译测试全绿、现象离根因很远（「发言被拦」看不出是下注计数 key 错位）。

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

**B14.3 🔴 全局叠加倍率（顶槽/连击）与 per-player 网格倍率并存时，「哪些帧已烘焙、哪些没有」逐帧不同，必须实证——CrazyTime 曾系统性少赔**：CrazyTime 顶槽命中 CashHunt/CrazyBonus 段时玩家少赔（该局顶槽 3x，应赔 15x=5×3，实赔 5x）。根因：`bonusMultiplierResolver` 只取 `grid[pick]` 没乘顶槽；**而同一族的 b2/b3（Pachinko/CoinFlip）上游已把顶槽烘焙进 `totalResult`/`multiplier`，再乘就超付**——四个 bonus 段口径不一致。
- **修法**：`crazytimecore/bonus_perplayer.go:160-181` 的 `perPlayerTopSlotFactor` 只对 **per-player 网格**乘顶槽，注释写明 b2/b3 已烘焙。
- **判据（对 capture 逐帧核）**：看结算帧的 `resolved.totalMultiplier` 究竟等于 `grid[at]` 还是 `grid[at] × topSlot`。**漏乘少赔、错乘超付，两个方向都是资金事故**，且同族内不能整类套用。
- **通用性**：任何 game show 只要「全局叠加倍率」与「per-player 选点网格」并存就会重演。与 B14.2（净 vs 总返还）是同一家族的两个正交维度。

**B15 winnersList 金额必 per-currency 换算、不止合并（#431，Monopoly 唯一漏接实证）**：B8 只讲合并我方中奖者，但 winnersList communal 广播、下游玩家币种各异——上游 winnings 是**帧流货币**（`frameCcy`，sniff 自上游 `balanceUpdated.currencyCode`；🔴 用 frameCcy 而非重采样容灾组 active 会话，否则 failover/重连窗口取错币种 → 金额数量级偏高），我方注入的赢家是各自本币。必须 `convertUpstream`（上游从 frameCcy 换）+ `convertOurs`（我方从 `w.Currency` 换）**归一到每个观众货币** + `events.BroadcastToTableByCurrency` 分组下发（`handlers.ConvertDisplayAmount` best-effort、失败保原值不阻断）。裸 communal 广播原值 → 非基准货币玩家金额错乱 + 与上游 winnings 混排排序错。**新族 winners_broadcast 必查是否接 frameCcy per-currency**——Monopoly 是 6 族里唯一漏的（communal 广播 NetWin），照 icefishing/crazytime 补齐（processor sniff + 4 段换算 + factory `SetUpstreamCurrencySource`）。

**B16 bonus 演出帧逐帧夹带 per-user 金额，必按连接注入 bonusWin（Monopoly boardWalk/boardState/cashPrize 实证，用户指证「进 bonus 没金额」）**：monopoly bonus（2/4 Rolls 棋盘）演出帧不只公共动画——boardWalk（每步）/boardState（重连态）/cashPrize（Chance 现金奖）各带 `bonusWin{betAmount,winAmount,totalWinAmount}` 个人金额（= 玩家触发段 `spinResult.result` 押注 × 该步 `multiplier` / 累计 `totalMultiplier`）。上游影子会话不下注 → 这些帧 bonusWin 空/缺，裸广播 → 玩家进 bonus 全程看不到自己赢额增长。判据同 B13（逐帧 `args|paths(scalars)` diff bet vs nobet、找**仅 bet 有**的字段），出现 bonusWin 类个人字段就必须 per-user 注入、不能裸广播；演出帧不涉资金故解析失败裸广播保底。⚠️ 别被 B10「communal 演出帧直转」误导——同一族的演出帧也可能夹带个人金额，**必须逐帧 diff、不能整类当 communal**。

**B17 帧时效语义二分 → 决定「缓存回放」还是「不缓存」（新连接白板 / 演出错乱的总判据）**：我方是伪服务端，下游玩家随时 join，而上游只在自己的节奏发帧。每个 A 类广播帧都必须先判一句：**「这一帧迟到 30 秒送到，对刚进桌的玩家还有意义吗？」**
- **有意义 = 全量快照帧** → **缓存最新一帧，新连接 init 时回放**。典型：走势帧（`recentResults`/`<gt>.spinHistory`，每局重发全量）、`dealer`、`appInfo`、裸 `tableState`(binding)、限红/配置类。**漏缓存 = 新玩家进桌走势板空白/无荷官名**，而老玩家正常——**测试和 codex 都抓不到，只有真正新开一个连接才暴露**。
- **无意义 = 时效帧** → **直转不缓存**，迟到自然丢弃，新连接等下一个自然帧。典型：A2 演出帧（`wheelSpinning`/`wheelStopping`/`wheelResult`/`bonus`，见 B10）、心跳/ping、bettingStats 瞬时计数。**误缓存 = 新玩家进桌看到上一局的开奖动画**。
- ⚠️ **同一族里两类都有**，按帧判不按族判；拿不准就看该帧是否「每局重发完整集合」——是则快照类。
- 与 B12 的关系：game show 的 `restore.begin/end` 就是把这批**快照类**帧打包重放的协议化形式；我方自合成 restore 包时，装进去的正是这里判定为「缓存回放」的那些帧。

**B18 结算后的衍生广播（余额 / 走势 / 统计）必须晚于结算锚帧下发，不能在 `OnGameResult` 里当场推**：真 EVO 帧序是**结算广播恒先于 `balanceUpdated`**。我方若在 `OnGameResult` 里直接推余额（最直觉的写法），客户端此时状态机仍判「本局进行中」，会**把这条余额更新吞掉** → 派彩成功但余额数字不刷新，直到下一局或手动刷新（SuperSicBo 实证）。
- **修法**：`OnGameResult` **只收集不发送**（返回 `balances []balancePush`），发送点收敛到结算广播之后（`sicbocore` 的 `broadcastDiceStateResolvedPerUser` → 再 `sendSettleBalances`）。
- **通用律**：结算相关的多帧存在**顺序依赖**，不能假设可任意穿插。与 K7（结算锚不一定是终局状态帧）、B15（winnersList 依赖结算落库先完成）同属「结算时序」家族——新族把这三条一起过一遍。

**B19 per-player bonus 的「本人落在哪一项」必须结算当下落库，事后靠倍率值反推必然失真**：bonus 是「多候选项各自独立倍率、玩家或系统落在其中一项」形态时（CrazyTime flapper / FunkyTime 选杯选色），**两个候选项倍率相同就无法反推**——曾靠倍率反推取首个匹配，同值时高亮错色；报表页干脆写死「the private player choice is not stored」。
- **根因**：选择只存在内存态（`Processor.bonusPicks[gameID][userID]`），`forgetResultContext` 一清即永久丢失。
- **做法（FunkyTime #469 / CrazyTime 2026-07-22，两族均已落地）**：结算成功路径调 `persistBonusChoices` 把 `{segment,choice}` 写 `b_game_user_actions`（`ActionType` 各族一个常量），详情 `history_api.bonusChoiceFor` + 报表 `renderers/<gt>.js` 的 `playerChoice(report)`（读 `report.userActions`，**后端零改动**——`roundReportUserActions` 不按 actionType 过滤）按 `(tableCode,gameId,uuid,actionType)` 精确取，取不到才退回反推（旧局兼容）。
- 🔴 **落库值必须与结算 resolver 同源**（同一份 picks，含 auto 代选）：否则高亮的那一项 ≠ 给玩家派钱的那一项。**把这条写成单测**（`crazytimecore/bonus_choice_persist_test.go` 的 `TestBuildBonusChoiceActions_MatchesSettlementPick`：断言 `grid[落库choice] == resolver(user)`）。
- **纯展示不阻断结算**：装配拆成纯函数便于单测，写库失败只 `Warn`；非 per-player 段（共享单值/数字段）一条都不落，否则详情会高亮一个并不存在的"选择"。
- **与 L4.3「bonus 内部局面落库」的分工**：那条讲**公共网格数据**要落库，本条讲**玩家落在哪一项**这个正交维度——公共网格 + 事后反推 ≠ 记录选择。

## C. 资金路径 fail-closed（同 PP，EVO 照守）

**C1** CanBet Redis 异常返 false（宁拒不放，防开奖后补投）。
**C2** applyBet `ctx.BetSvc==nil || UserID=="" || gameID==""` 返明确错误不静默成功。
**C3** 撤单（REMOVE/UNDO 清注）必须先 CheckBet 校验窗口才改 Redis（关窗后撤单=资金风险）。
**C4** 整批拒清 Redis 仅限非窗口类（窗口拒绝不清，防"界面已撤实际扣款"）。
**C5/C6** BC Atoi 失败显式跳过 + ERROR log；bets JSON 解析失败 continue 跳过用户（不 append 空 BetData）。
**C7 「Redis 读失败 ≠ 无下注」这条规则适用于【每一个】读 bet key 的代码路径，不止 `GetRedisUserBets`**：SCAN/HGetAll 失败必须返 error **不返 nil**（否则被当无下注 → 漏结算/漏退款）。🔴 **易漏点**：`/bet` 提交路径是完全独立的一段代码（`common/merchantclient/bet_submit.go:444-466` 的 `getAllBetsForGame`），当初 SCAN 失败 `return nil,nil`、HGetAll 失败 `continue` → **部分用户被扣款、部分用户注单被静默吞掉**，且结算侧读同一批 key 也读不到 → 两边 `failedKeys` 都空 → **整局被当正常结算关闭**。修法：失败一律 append `FailedSnapshotKey{Reason: reasonRedisScanError}`，调用方见非空即整局不提交 `/bet` + 落人工介入。**新族/新功能只要自己写了一次 SCAN+HGetAll（提交/报表/监控都可能各写一次），就要重新过一遍这条**，不会因为结算路径守住了就自动免疫。
**C8** payout cap 接入 = **per-bet**（🔴 issue #64 已下线 round-level：`CapUserPayout` / `MCap` / per-user round payout max 全废）：调 `handlers.LookupPerBetCap` 对**每笔 bet** 取 `min(maxMultiplier×本笔注额, Convert(euro_table_payout_max,EUR,currency))`，EUR 换算失败 fail-closed。详见 G3。
**C9** Redis SCAN/HGetAll 用 `context.WithTimeout(5s)` 非 Background。
**C10 /result 必先有成功 /bet**：`onBetsClosed` 必 `go handlers.SubmitBets(ctx.TableID, gameID, p.OnMerchantBetResult)`；`MarkBetAccepted` 只在 `OnMerchantBetResult` accepted 分支（**绝不**在 betAction/applyBet）；`SettleUsersSeamless::hasSuccessfulBetDebit` 通用闸门兜底（无 bet 流水 fail-closed）。漏调 SubmitBets = 无扣款派彩（凭空给钱）。
**C11 OnRoundSettled 必调**（settle 成功），否则下一局误标 cancelled + 重复退款。
**C12 reconcile 孤儿局补结算同样 fail-closed**：从 recentResults 补结算的注也走 requireAccepted + hasSuccessfulBetDebit，不给没扣款的注派彩。
**C13 孤儿局 pending 态必用 `pendingsettle.Tracker` 五件套（勿自写 pending 字段）**：Mark on 扣款 / Clear on 结算（**compare-and-clear**：退款只走「原子赢得清标记」路径，防 sweep×帧驱动并发双退款）/ `NextOrphanRound` 帧驱动 / `SweepStaleSettle` 可选接口（settle_sweeper 60s 扫 5min 龄期——game-ws 长期死时帧驱动永不触发，无 sweep = 本金永扣的最大敞口）/ `RecoverPendingSettle` 跨重启载回（终态守卫防双退款）。另加 `PendingSettleStatus()` 监控可选接口（看板资金安全面孤儿局数据源），缺了 = 运维盲区。详见 phase-3-aiu-L4 §L4.2。🔴 **新族必查**：grep `pendingsettle` 确认接入五件套（Monopoly 曾是 6 族里唯一漏接的，自写 `pendingGameID` 缺 sweep/跨重启/监控，运维看板读不到其孤儿局）。🔴 **sweep maxAge 须 > 最长 bonus 演出局**：game show 长 bonus 局是分钟级（实测 monopoly 2/4Rolls 关窗→结算 192s、crazytime 大转盘 100s），旧 5min 会把**正常长局**误判孤儿退款 → 随后真结算再派彩 = 退款+派彩双付；已全局改 2h（`settle_sweeper.go`，远超最长演出局、只退真搁浅局）。「健康桌 pending 秒级清除」这个 sweep 立论对普通局成立、对长 bonus 局不成立。
🔴 **反模式（曾真实发生）**：`pendingsettle.Clear` 的调用点必须**唯一收敛在结算成功路径内部**。`reconcileFromRecentResults` 原实现在末尾**无条件**调 `clearPendingSettle(orphan)`——不管 `OnGameResult` 成功还是 fail-closed 都清，于是 Redis 读失败走兜底分支时 pending 也被抹掉 → sweep 与跨局退款双双失效、**本金永久卡住且无人工介入入口**。修法 `roulettecore/reconcile.go:57-63` 删掉该行，注释写明「pending 清理由 OnGameResult 独占，此处不得再清」。**兜底 helper 里出现第二个 `Clear` 调用点本身就是坏味道**——新族写 reconcite 时最容易顺手加一行「清一下图个干净」。

**🔴 C13 更正（2026-07-28，andarbahar L4/L5 审查实证，覆盖上面 C13 的两条具体建议）**
上面 C13 推荐的「用 `pendingsettle.Tracker` 五件套」和「compare-and-clear：退款只走原子赢得清标记的路径」，
在下面两种情形下**本身就是资金 bug 的来源**。两条都有可达序列与代码位置，不是理论风险。

- **① 单槽 `Mark` 无条件覆盖未闭合的前一局**（`pendingsettle/tracker.go:56`：`t.gameID=gameID; t.since=now; t.orphanRounds=0`）。
  可达序列 `G0 close-out → Mark(G0) → G1 开局 deferred → G1 close-out → Mark(G1)`：
  G0 的本金**已扣**，标记一丢就同时退出 sweep / 帧驱动 / 跨重启恢复 / 监控看板的全部入口。
  → **只要本族存在「两局可同时未闭合」的时序，五件套就装不下**，必须换**族内耐久多槽账**
  （先例：`baccarat/baccaratcore/orphan_ledger.go`，`andarbahar/andarbaharcore/orphan_ledger*.go`）。
  ❌ **不要去改 `pendingsettle` 本身** —— 11 个族共用，改共享层正是 andarbahar 前两次整批作废的主因。
  三条不变量照抄：只增不删 / 容量到顶 fail-close 新下注（**绝不**丢弃最旧条目）/ 带真实结果的局永不被合成取消。
  另外两条别漏：store 三个方法都要**返回 error**（旧 `pendingsettle.Store` 全是无返回值，一次写失败被吞掉
  = 进程一崩敞口消失）；**锁内只返回决策**，DB 与商户往返全在锁外。

- **② clear-before-refund 会造成永久少退**。`cancelOrphan` 先 `clearPendingSettle` 再入队退款，
  崩在中途或入队失败 → `RecoverPendingSettle` 见到 `cancelled` **只清标记、不补建退款任务**
  （`handlers/pending_recover.go`）→ 不可逆。
  而退款入队**本来就是幂等的**：`merchantclient/cancel_refund.go` 用 `OnConflict{DoNothing}` 撞
  `uk_callback_task(operator_id, callback_type, reference)` 唯一键，重复尝试**零成本**。
  「重复入队」与「永久少退」两边代价不对称 → **顺序必须是「先形成耐久退款覆盖，再 compare-and-clear」**。
  拿 `CancelRoundRefund` 的 error 当「覆盖已形成」的证明（它内部会逐笔核对「已退成功 或 有可执行 pending task」）。

- ⚠️ **影响面（逐个 grep 确认过，不是推测）**：`crazytime` / `dragontiger` / `fantan` / `funkytime` /
  `icefishing` / `monopoly` / `monopolybigballer` / `roulette` / `sicbo` **9 个族的 `cancelOrphan` 首个动作
  仍是 `clearPendingSettle`**，且 `markPendingSettle` 全是无守卫直通 `Tracker.Mark`。
  `icefishing/reconcile.go` 另有一处：claim 失败后重新 `Mark` 恢复标记，而 `Mark` 会把龄期归零 →
  每次 stale 触发失败就再推迟一个 maxAge(2h)。
  **「代码形状相同」已确认；「那条序列在每个族里都真能跑到」只逐帧追过 andarbahar** ——
  其余族要各自追一遍相位流才能定性，别直接当成 9 个已确认的 bug 去报。

**C14 局资金终态机 settle_state（已根治双付+本金永扣，common 层全托管，新族零接线自动生效）**：曾有两类跨族资金 bug——① fail-closed 局 persistRound 已写 SettledAt、`HasTerminalRound` 靠它判终态 → 重启误清 pending → 本金永扣；② 结算(/result R+rid)与取消退款(/refund F+rid)幂等空间被前缀隔开互不感知 → 跨端点双付。根治：`b_game_rounds.settle_state`（''/settling/settled/cancelled）单一真相源 + DB CAS 原子抢占（`handlers/settle_state.go`），`SettleUsersSeamless` 入口 claim（已取消局返 `ErrRoundCancelled` → 机台走既有 abortSettleTopLevel 不派彩）、`OnRoundCancelled` 退款前 claim（已结算/结算中跳过退款）、`HasTerminalRound` 只认 settle_state、refund_worker 三类 task 复检（refund_timeout 是 **per-user** 查 result 流水——局 settled 但该用户恰 /bet 超时未派彩仍须退他本金）。设计全文 `docs/资金终态机/DESIGN.md`。**新族注意**：结算必须走 `handlers.SettleUsersSeamless`、取消必须走 `p.OnRoundCancelled`（common 唯一实现），就自动在终态机保护内——绕开自调 wallet = 脱保；SettledAt 只是开奖展示时间，**永远不要拿它判资金终态**。

**C15 🔴 出账金额一律【向下去尾】不许四舍五入；且整局 Total 必须【原始精度求和后再去尾一次】，不是逐笔去尾再相加**：我方是庄家，`math.Round` / `fmt.Sprintf("%.2f")` / 裸 `float64 +=` 隐含的四舍五入会把 1.316… 抬成 1.32，**系统性多付**。
- **两个维度都要对**：① **方向**——floor 不是 round；② **顺序**——真 EVO 是「逐笔按原始高精度(6 位)累加 → 对总和去尾到分」，**不是**「逐笔去尾到分 → 相加」。两者差 1 分且都是真实业务行为：FanTan 3 笔 SSH 应得 15799.99，逐笔去尾累加得 15799.98（**少付**），四舍五入得 15800.00（**多付**）。展示用的逐笔金额单独去尾到分，**局 Total 另走原始精度那条路**。
- **工具（common 层已备，直接用）**：`handlers.FloorPayoutToRaw`（6 位，供求和）/ `handlers.FloorPayoutToCents`（2 位，供出账展示），内部走 `decimal.Truncate` 而非 `math.Floor(v*100)`（避开 IEEE-754 表示误差）。范例 `fantancore/payout.go:53,75-77,116`。`BetOdds` 等展示倍率要用**去尾前**的 payout 反算。
- 🔴 **新族 L4.1 必做的核对**：看本族赔率表有没有**非终止小数**（分母含 2/5 之外的质因子，如 FanTan SSH 的 79/60）。有 → 必须全程走上面两个 helper；无 → round 与 floor 结果相同，**但仍建议接入**，因为赔率表会随新玩法变。
- ⚠️ **现状（已知未消风险，别误以为全局已修）**：`FloorPayout*` **目前只有 fantan 接入**，其余 8 族的 payout 仍是裸 `float64 +=`（恰好赔率都是有限小数故未暴露）；展示层 `renders/money.go:38` 的 `moneyCurrency` **内部仍是 `math.Round`**。**「展示可 round、出账必 floor」是两条独立路径**——出账的去尾必须在 payout 计算层完成，不能指望展示层。

**C16 🔴 关窗必须排空「已过窗口校验、尚未落 Redis」的在飞下注写（late-bet 资金竞态，4 族已有、roulette 第 5 次才补）**：EVO 架构下「下游 betAction 写入」和「上游关窗/结算抓快照」**必然跑在不同 goroutine**（下游 WS 读循环 vs 上游读循环）。betAction 过了 `IsBetsOpen` 布尔校验、还没写完 Redis 时，BETS_CLOSED 已经抓走结算快照 → 该笔注**既没扣款也没参与结算**（或反向少扣多派），客户端却显示「已受理」。
- **修法（样板代码，新族照抄）**：Processor 加 `betWritesWG sync.WaitGroup`；`beginBetWrite()` 在 `betsMu` **读锁内** `Add(1)`（窗口已关则返 false 拒单）/ `endBetWrite()` `Done()` 配对；`MarkBetsClosed` 关窗后 **`betWritesWG.Wait()` 排空再让调用方抓快照**；`handleBetAction` 用 `beginBetWrite` + `defer endBetWrite` 包住**全部** `applyBet` 落库。范例 `roulettecore/{processor.go:70-74, bet_window.go:73-97, downstream_bet.go:62-66}`。
- **为何新族必踩**：这是纯样板代码，「只做 `IsBetsOpen` 布尔检查」看起来完全正确、编译测试全绿，**只有 `-race` + 精确时序才暴露**。icefishing 等 4 族早有此模式，roulette 作为最老的族反而漏了、直到 `0f7481c9` 才补——**新族从零写 `downstream_bet.go` 没有「抄别族」这一步，不会自动带上**。F4 的 race 测试必须覆盖这条。

## C-meta. 关于「怎么验证一条资金修复」（AndarBahar000001 沉淀，比单条铁律更常用）

**变异反验是硬要求**（注入缺陷 → 确认变红 → 还原），但它有三种失效形态，实测各踩过一次：

1. **变异没打进生效路径** —— perl 少写 `/g` 只改到注释、`-run` 正则没覆盖到目标用例。
   → 变异「存活」时**先 diff 确认注入位置**，再判定测试弱。
2. **变异被另一处同契约的实现兜住** —— 两道防线互为备份，只改一处不会红。
   → 每道防线**分别**单独注入。
3. 🔴 **变异转红了，但红在不相干的行** —— 被更早的前置断言短路，真正的资金断言被遮住。
   → 变异红了之后**看一眼红在哪一行**；不是那条资金断言就说明**测试结构**有问题。
   把「前置成立」和「钱到底派没派」拆成两条用例。

**测试本身的三类假绿**（编译测试全绿、codex 也未必看得出）：
- 真实样本恰好无法区分正确与错误实现（23/23 局里超付实现与正解逐笔相同）；
- 断言恒真（Go 的 `float64(37)` 也序列化成 `37`，「断人数是 5 不是 5.0」永远通过）；
- **用例根本没走到被测分支**（条目要落进 hold 必须先有 `HasResult`，而用例里走的是别的分支）。
  → 给每个场景用例加一条**前置断言**：断言「本用例确实进入了要测的那个分支」。

**并发测试**：`-race` **抓不到逻辑竞态**（两次操作各自都加了锁，但组合起来失配）。
写并发测试时**写清它假设了什么**——那个假设本身就是待验证项
（实测：既有测试假设「每个 userID 只有一个 writer」，而顶号窗口下这个前提不成立）。

## D. 静默错误（必加 zap log）
业务关键路径禁 `_ = err`。必加 `global.HAB_LOG.Error/Warn + zap.Error`：OnGameResult / UpsertRound / SettleUsersSeamless / json.Unmarshal(bets/winSpots) / OnMerchantBetResult 早期 return / per-user snapshot 失败（warn）/ 视频三跳失败。

## E. struct 序列化

**E1 禁 `map[string]interface{}` 跨边界**。所有 JSON 帧 struct + `json.Marshal`/`Unmarshal`（含 root-key 帧用具名 struct）。禁 raw 字符串拼 JSON。

**E2 🔴🔴 强类型 struct 做「解码→改写→重编码」时，struct 就是一张隐式白名单：未声明的字段会被静默吃掉（8 天内两族同款事故，跨 4 族复发）**：只要走 `Unmarshal 进具名 struct → 改几个字段 → Marshal 广播` 这条路（B8 的 winnersList 合并、`stripTableStateBetState` 剥离、per-currency 换算改写…），**凡 struct 里没声明的字段，哪怕你根本不想动它、只想原样透传，都会在往返中消失**。
- **实际事故**：① 中奖广播列表整块空白——`winnersList` 漏建模 `totalAmount`/`winnersCount`/`bettorsCount`，客户端按 `winnersCount>0` 门控整个 widget 是否渲染（**#463 FunkyTime 07-13 → #497 FanTan 07-21，同款事故 8 天内两次**；FanTan 的 `models.go` 注释原话：「曾因对接文档误记『无聚合字段』而漏建模」）；② XXXtreme 闪电轮盘**红色雷击特效消失**——`stripTableStateBetState` 强类型重编码把 `luckyChains`/`luckySplits` 剥没了（#485）；③ 手工构造新 struct 字面量时漏拷贝已声明的 `Multiplier`（#432 CrazyTime，姊妹变体）。
- **修法**：补齐字段（`fantancore/models.go:94-97`、`funkytimecore/models.go:156-166`），**纯透传的未知/易变字段用 `json.RawMessage` 兜住**（`roulettecore/models.go:50-56` 的 `LuckyChains`/`LuckySplits`）。
- 🔴 **验收硬要求**：每个「拦截-改写-重转发」的帧写一个 **round-trip 完整性单测**——真实上游样例帧 `Unmarshal → 我方 struct → Marshal`，与原始帧 **diff 出的 key 集合必须为空**（故意丢弃的逐个在注释写明原因）。**只断言「我方要用的字段还在」查不出这类 bug**，这正是它跨 4 族复发的原因。
- ⚠️ **字段清单不能凭对接文档**（#497 就是文档误记害的），必须拿 capture 真帧逐字节核对。

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
**G3** payout cap **per-bet 两路** `min(A,B)`（🔴 issue #64 于 2026-05-14 把 round-level 整套反转为 per-bet，`LookupRoundCap`/`CapUserPayout`/`table_payout_max` **一并下线**，见 `handlers/round_cap.go:1-12` + `baccarat/payout.go:26-37` 坐实——旧文档的「用户级/当局总注/三路 min/C=table_payout_max」已过时）：A=`maxMultiplier×`**本笔注额**（per-bet 单注，**不是**用户当局总注）/ B=`Convert(euro_table_payout_max,EUR,currency)`。EUR 换算失败 fail-closed。
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
**H4 报表前端页 = 「每桌一个 14 行 stub + 按 gameType 共享 renderer」，不是一桌一份自包含**（⚠️ 本条 2026-07 更正：早期文档写的「一桌一份、内联自包含、不引共享 `_assets`」是 PP 旧铁律，EVO 从第一个报表 commit 起就不是这样，照旧文字做会重新发明一套、维护量暴增）：
- **实际结构**：`client/reports/<裸 tableId>/index.html` 只是引导 stub（14 行：两个 `<link>` + `<div id="ppreport-root">` + `<script src="/reports/_assets/report.js">`，**无内联 CSS/JS**）；渲染逻辑在 `_assets/renderers/<gametype>.js`（当前 8 个：crazytime / crystalroulette / fantan / funkytime / icefishing / lightningdice / monopoly / sicbo）；`_assets/report.js` 的 **`RENDERER_BY_TABLE` 映射表**把 tableId → renderer 名。
- **新族做法**：先查 `RENDERER_BY_TABLE`——**同协议桌大概率直接复用已有 renderer**（`247dc9a6` 一次把 12 张欧轮 + 5 张 SicBo 全指向同一个 renderer）；确需新渲染形态才加 `_assets/renderers/<新族>.js`。**每桌仍必须有自己的 index.html 目录**（防串桌、URL 即桌），但它只是 stub。
- 不变的部分：fetch 通用 `/gameHistory/report` JSON 渲染，对照 `roundDetail/<rid>.{html,json}` ≥90%。前置：UPSTREAM archiveCurrentRaw 落 messages + SETTLE 落 round/extra。
- 🔴 **报表 renderer 是与 Go render 完全独立的第二条计算路径**：同一个倍率/金额在 `renders/<gt>.go`（详情）和 `renderers/<gt>.js`（报表）里各算一次，**L4.1 结算算对了不代表这两处会读到对的值**，各自都要对照 `roundDetail` 核（实证见 B14.2 末尾）。
**H5** b_game_rounds 显示串列宽 ≥ 协议族最长值（直接 varchar(200)），否则超长一条整局丢库（同 PP J12）。game show 的 result 是字符串段名+倍率（`result:"Leaf2"`/`totalMultiplier`/`<seg>Multipliers` 嵌套 JSON），Extra/Description 列宽须容纳多段倍率序列化串，**勿沿用 roulette winNumber 数字宽度**。
**H6 历史详情渲染方式逐机台不同（render SSR vs 结构化 data.data），对接前必看 gameDetail 实际结构**：真 EVO 多数机台（crazytime/icefishing/funkytime/monbigballer）历史详情响应 `data.render`（SSR HTML，我方 `gateway/renders/<gt>.go` 生成）；少数局面复杂的（Monopoly Live/RedDoorRoulette）响应结构化 `data.data`（`result.outcome{type,wheelResult,boardMoves,reSpins}`+`participants`，客户端 `<gt>.history` chunk React 渲染棋盘走位）。**对接前必 grep gameDetail.txt 顶层 data 是 `render` 还是 `data`、按实际选路径**——发错（该 data.data 却发 render）客户端走 CommonHtml 兜底、复杂局面渲染不出。data.data 路径需结算时把局面数据落 `b_game_rounds.Extra`（monopoly `boardMoves`/`reSpins` 从 boardWalk/rollResult/multiplier 帧采集），`history_api.go` **只对该 gameType 分支切 data.data、其他族维持 render 不动**。🔴 前端字段契约要核对（reSpins 前端无条件 `forEach` → 恒非 nil 禁 null；BonusRound 必带 boardMoves 数组）；上游 game-ws 无源字段（monopoly `boardState.upgrades`/`timesPassedGo`/`index`）是硬缺口 → 承认并置空/省略（确认前端缺该字段不崩，别硬造）。

**H7 render 文案走 EVO 官方串包 key，禁写死英文、禁自建翻译资产（9 族已全 key 化，新族照做）**：`renders/<gt>.go` 里凡玩家可见的文字（表头 / 注名 / 段名 / bonus 标题）一律 `tr(key, 英文字面量)`，不能硬编码——客户端界面本身已按玩家 locale 显示，历史详情是全客户端里唯一由我方 SSR 的一块，写死即成英文孤岛。基础设施 `renders/loc.go` 已建好（**通用、不碰**），新族只做「找本族的 key」这一件事，方法见 `phase-3-game-record-render.md` §2。
- **翻译源 = 官方串包 `/frontend/loc/strings/<locale>/history.json` 的 `history` 命名空间**，即 EVO 自己 SSR 用的同一套 key。51 语全量、每语 3563 键（3561 条文案 + `__rules`/`__assets` 两个对象值）、结构一致 → **零翻译资产投入；加语言 = 落一个 json + `b_languages` 加一行，不改代码**。
- 🔴 **两套 key 空间并存，必须按族取键、绝不按值瞎配**：① 点号命名空间 `history.<族>.<key>`（1381 条，族名百余个）；② 大写族缩写裸键 `<PREFIX>_<Segment>`（`ROU_`361 / `MB_`600 / `FT_`28 / `FNT_`17 / `CT_`12 / `MBB_`10 / `DT_`6 / `IF_`5…）。**同一句英文在多族空间都有**——`"Small"` 同时是 `history.baccarat.small` / `history.dice.small` / `BAC_Small` / `SicBo_Small` / `FT_Small`，取错族=拿到别族行话且英文看不出来。🔴 **`FT_`=FanTan、`FNT_`=FunkyTime（易记反，已踩）**；`IF_`=IceFishing。这批前缀与 SKILL.md「betCode 变量轴」讲的结算侧前缀（`IF_Leaf1`/`FNT_Bar`）是**同一套族缩写**，段名 betCode 往往直接就是键名。
- 🔴 **命名空间名 ≠ gameType，必须去串包实搜、不可按目录名拼**：SuperSicBo 与 LightningDice 都用 `history.dice.*`（**按玩法分，不按机台族分**），DragonTiger 是驼峰 `history.dragonTiger.*`；而 `history.sicbo.*`/`history.fantan.*`/`history.icefishing.*` 各只有 1-3 条、基本用不上。表格骨架 `resultheading`/`betType`/`betheading`/`win`/`total` **无族前缀、全族共用**（印证官方共用一个渲染器）。
- 🔴 **取包必须走本服务自身 HTTP `/frontend/` 端点且带 `X-Origin-Secret`**：串包是按需资源、本地可以没有，该端点（gwstatic + evoCDNProxy）已实现「本地命中 → 回源 CDN → 落盘缓存」，客户端取串包走的就是它，render 复用同一条通道才不会与之漂移（同 R1 的媒体回源思路）。**不带 secret → live/prod 的 OriginVerifier 403 → 全语言静默退英文**，而本地无 secret 不复现。禁读文件路径、禁再写第二份取包/缓存逻辑。
- **三层回退全 fail-safe**：玩家 locale → en-US → 调用方传入的英文字面量。官方自己也漏翻（实测 de 的 `history.dice.small` 就是 "Small"），末端英文兜底不是冗余。**绝不显示 raw key、绝不空白**；加载失败**不入缓存**（否则一次网络抖动就把该语言钉死在英文直到进程重启）。
- **官方 en-US 值与我方英文字面量逐字节相同 → key 化后英文输出必须一字不变，既有字节 diff 测试即回归 oracle**（取错 key 那批测试先红）。反过来说：🔴 **英文账号一路绿灯，与 G6「USD 一路绿灯」同构**——key 取错、整包取不到、secret 没带，三种故障对 en-US 玩家全部不可见，**验收必须实跑一个非英文 locale**。
- **与桌名翻译分属两条链，别互相代替**：官方只对 8 个亚洲语言本地化**游戏名**（品牌策略非漏翻），**桌名不在官方包内** → 走我方 `b_languages.translations` 运营配置（见 L4）；render 内的文案走官方串包。

## I. 包边界与复用形态（防"抄既有机台模板"抄成耦合）

> 编号与 `pp-game-develop` 的 I 节**同源对齐**（EVO 生产代码注释直接引用 `known-pitfalls I2`）。
> 此处只收 EVO 实际在用的 + EVO 独有的；PP 特有条目（I1 PIXI 模块 / I3 sessionTimeout / I6 增量协议…）见 PP skill。

**I2 🔴 betCode 集 / 赔率 / 限额 / 错误码常量必须各族独立定义，禁跨族 import**（EVO 代码 10 处引用此条）：跨包耦合会让一族改数值**静默污染**另一族，且语义会漂移（同名 code 在两族含义不同）。每族自己的 `games/<族>/{odds.go,bet_limits.go}` + `<族>core/enum.go` 写全量裸值，宁可重复也不 import 兄弟族。**即使两族数值当前完全相同也要各写一份**——它们是独立演化的业务事实，不是可 DRY 的重复代码。

**I8 history/详情字段缺数据填 `"0"` 不填空串**：客户端 history 渲染直接把字段值贴进 DOM，空串会渲染出空白格而不是 0。score / multipliers / payouts 一律给 `"0"`。

**I11 🔴 复用形态分四档，越靠前越省；fork 一份 core 是最后手段（错判 = 此后每个资金修复都要修两遍且必然漂移）**：新桌进来先自上而下套判据，能停在哪档就停在哪档。

| 档 | 判据 | 做法 | 实证 |
|---|---|---|---|
| ① **纯配置复刻** | 同族**同赔率**，只有桌名/语言/视频/限额不同 | 只加 factory case + DB 行 + 报表页，**零新代码** | #498 轮盘家族 16 台 |
| ② **nil-gated 钩子注入** | 同族同协议，**仅赔付数学有增量差异** | 既有 core 里加**可空钩子**；标准桌钩子恒 nil → 原路径零改变 | `roulettecore/lightning_hook.go`（Lightning 30× / XXXtreme 20× 降赔 + 幸运号倍率） |
| ③ **参数化共享 core** | gameType 不同但**协议逐字段同构**，只有数学层不同 | 分歧点收敛成 `GameDef`（纯函数注入 `IsBetCode`/`BetLabel`/`Parse<结果>`/`CalcPayout`）+ `BetLimits` 接口，协议层零 fork | `sicbo/sicbocore/gamedef.go`（Lightning Dice 零 fork 复用） |
| ④ **建新 core** | 上面全不成立（新状态机/新下注模型/新 per-user 载体） | 走完整 AIU DAG | 本 skill 主攻 |

- **③ 的同构判据（四条全中才算）**：同状态/相位帧 → 同下注模型（全量快照 vs 增量 + UNDO 栈形态一致）→ 同 per-user 帧载体 → 同结算锚。**只有数学层不同**（betCode 集/赔率表/限红分组/特殊门控）。
- 🔴 **② 的资金红线（照抄进任何共享层改造）**：**钩子只改赔付数字，不碰扣款 / 结算时序 / pending / reconcile / Redis 注单**。越过这条线就不再是「注入」而是改共享资金路径，必须按全族回归。
- 🔴 **② 必须 nil-gated**：标准桌两个钩子均 nil → 直接走原 `CalcPayout`，行为与改造前**逐字节一致**且零额外 Redis 读。改造后先验「老桌路径没变」，再验新桌。
- 🔴 **③ 的 `GameDef` 只能经构造函数产出（`SicBoDef()`/`LightningDiceDef()`）、字段全必填**：手工构造漏注入 → 结算路径 nil panic。**宁 crash 不静默用错族赔率**（错赔率=资金事故；crash 有 runner recover 兜底）。
- **与 I2 的分界**：共享**行为**（协议层/状态机/资金路径）✅；共享**常量**（betCode/赔率/限额数值）❌，各族独立定义。
- **改共享层的反向 oracle**：还原该共享改动后跑**两族全部**测试——耐久测试变红 = 这确实是共享层职责；全绿 = 本该放在某一族的数学层里。
- 判定时机见 SKILL.md **Phase 1「复用边界」**。

## V. 视频中转（egcvi，EVO 独有大块，不碰钱但易花屏/重连）

> 视频不阻塞资金主线，可后置/前端直连兜底；但要做服务端代理须守以下。落点 `runtime/video_*.go` + `gateway/video_ws.go`。

**V1 三跳取流 + token 自签**：manifest-ws2.json(hop1，videoToken HS256 secret=videoSessionId 自身) → 边缘 manifest(hop2，vvt) → websocketstream2(hop3) fMP4。`videoSessionId = userId-session_id-tableId-hash6(sha1)`；videoToken HMAC key=videoSessionId（无隐藏密钥，后端可复现）。**hop3 连上先发 PLAY 命令 + header `Origin=casinoHost`**（缺 Origin → 1006）。vvt 含 ccip/vcip IP 绑定 → 三跳与连流须同出口 IP（同进程满足）。
**V2 逐会话加扰（坑 -12909/花屏根因）**：egcvi 流逐会话加扰（只动 IDR，length-preserving）。客户端 bundle 自带 descrambler.wasm 自解。服务端解扰广播可行，但**正解 = 外层 `descrambler.wasm` 完整 wasm-bindgen 链路 + `create_descrambler(页面域名 location)` + 异步驱动（generateRequestId 预热 + 帧间 await）+ jsdescrambler_descramble，必须 Node 运行时（不能纯 Go）**。⚠️ 抽内层模块单独调得「恒等」是假象（缺外层域名初始化）。默认转发加扰流让客户端自解最省。
**V3 关键帧判定（防每秒重连风暴）**：按**整帧字节 EMA 动态基线**判（IDR 是大帧 GOP≈24，约 P 帧 4×；ratio=4/alpha=0.125 实测无漏检）。⚠️ `sample_flags` 恒 sync、比 P 帧大小 都已证伪（恒 sync → gate 失效 → 每秒重连）。**不缓存关键帧**；下游 join 等下一个实时关键帧瞬间加入。上游必发 **1.5s PING** 保活。
**V4 下游 PLAY_STATUS/PONG/AUTH_RESULT 须回显 inReplyTo**：缺 inReplyTo → 客户端命令 promise 不 resolve → 首帧看门狗 ~4s 超时反复重连画面不出（非关键帧问题）。修在 `gateway/video_ws.go`。
**V5 flipbook 兜底流（dual=fMP4+flipbook）**：cookie 鉴权 / `0-wc-wallclock` 握手 / 每帧回发对齐 µs 戳拉帧（回毫秒戳即停推）/ 帧 `rfid==fid` 为关键帧；join 须从关键帧起，需 flipbook 专用 VideoBuffer 模型。

## L. 大厅 / 会话 / 容灾（EVO 独有，新族基本不碰但要知边界）

> ⚠️ 本节编号 **L1-L7 指大厅/会话/容灾条目**，与 AIU 的 **Layer 1-5（L1-L5）不是一回事**。引用时写〔L节〕L3 以免误读。

**L1 Akamai 反爬**：entry（evo-games.com）卡 TLS+HTTP2 双指纹 → 必须 `bogdanfinn/tls-client` Chrome profile；取 config 必须用**会话 tls-client**（标准库 403）。lobby/game ws 走 Akamai **UA 黑名单**（非指纹）→ 用普通 UA `evo-client/1.0`，认证靠 URL query EVOSESSIONID。**真凶 tlssha1**：go<1.25 标准库 ClientHello 带 SHA1 被判 bot → 修 `//go:debug tlssha1=0`；cookie jar 重试须复用 `_abck`（`primeAkamaiJar` 预热，建会话一次成功）。
**L2 大厅复合 key tableId:vtId**：部分桌（FunkyTime/blackjack）lobby key 是 `{tableId}:{vtId}`，configs/filterAttr/thumbnails/categories 复合、playersCount/history 纯；写镜像剥离+记 vtKey，下发 configs 用复合 key，否则桌不渲染。**取 config 复合 key 须剥纯 tableId。**
**L3 货币 config 真 per-currency**：换 showCurrency 后 /config 限红按 currencyMult 换算（USD1/BRL5/INR100，上游算好），可照 PP 逐货币换 session 同步落 `b_table_currency_configs`。
**L4 语言 per-玩家个性化不可广播**：POST `locale-override {value:locale}`(204) 持久化 + 带新 locale 重跑 setup/字符串包（软重载）；静态串包/清单可 CDN。语言偏好 EVO 用 `Params.evo_locale`(BCP-47)、PP 用 `Params.language`(短码)，格式不同分开存。桌名翻译自建 `b_tables.name_translations`，下发按 evo_locale 改写 title（回退 译名→name→上游原文）；49 locale 全集 `web/src/utils/evoLocales.js`。
**L5 entry currency×geo 拒入**：IDR 会话从非印尼 IP 打开被拒 `incorrect-currency-for-geo-location` → 换匹配出口 IP。
**L6 永不死线容灾（四路上游）**：panic recover 防进程崩 / 死会话 `Invalidate` 防 8min livelock / 读超时防半开静默 / 有界 mint（30s 超时）防冻全线 / 会话缓存 8min TTL 防高频 mint 触发限流(6007)。新族不碰容灾（基础设施层 `runner.go`+`lobby_failover.go`），但**结算依赖 game-ws 帧、无兜底是最大资金风险缺口**——新族 SETTLE 须有 reconcile 兜底（C12）。
**L7 game ws 下发帧 tableId 取值逐帧逐族定（⚠️ 本条已按 #495 修正）**：桌态帧用裸 original_id（同 B1，重连根因之一）；**但 `balanceUpdated` 在 dice 族必须用我方 code**——客户端对该帧有 `=== /config.table_id` 门控，而 `/config.table_id` 被我方改写成 code。**别整族共用一个 tableId 取值函数**，详见 B1 反例。

**L8 上游连接的 `instance` 参数必须 per-桌（或 per-用途）唯一，否则同账号同 gameType 二次连接互相顶号（~31s 踢线死循环）**：EVO 按 `(EVOSESSIONID, instance)` 判定「同一客户端实例」。生产 `dialUpstreamGame` 曾对同账号所有桌发同一个 `instance="hab001-<uid>-"` → `evoSpeedAutoRo00001` 与另一张轮盘桌（同 gameType）同时运行时，两条上游 game ws **每 ~31s 交替被 close 1005**。现象极具迷惑性：表现为「两桌互相断连」而非「连接失败」。
- **修法**：instance 加 `originalID` 后缀（`runtime/game_upstream.go:123,126`），对齐 `chat_upstream.go` / `lobby.go` 已有写法。探针 `game_multitable_probe_test.go`。
- **通用性**：game/chat/lobby 三处现已修复且属「新族不碰」的基础设施，**但任何未来新增的上游连接类型**（新旁路探针 / per-桌侧连接 / 新协议族的独立连接）都要显式带 per-桌或 per-用途后缀。

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

**K8 🔴🔴 全量快照下注协议：受理成功必须【零回执静默】，拒单只回【差量】（两周内三族复发，当前最高频 bug class）**：`placeChips`/`SetChips` 这类**全量快照**协议（每次上报都是累计后的全集，客户端本地乐观渲染 + 本地 `betHistory` 栈），真 EVO 在**下注窗口内对受理成功完全不下发任何帧**（capture 实证：CrazyTime 41 条上行 bet 零回执、FanTan 85 次 placeChips 零回执），`bets` 帧只在**局状态节点**（Open / Accepted / Settled）下发。
- **我方多发一帧全量 bets 的后果**：客户端把它当服务端权威快照接受 → ① 清空/覆盖本地 betHistory 栈 → **撤销按钮置灰失效**（#448 CrazyTime、#496 FanTan）；② 快速连点时多帧回执按 FIFO 到达，把面板**回滚到该请求发出时刻的旧快照**，玩家在错误基线上继续叠加 → **盘面乱跳、总额与筹码数对不上**（#531 FunkyTime，实测滞后约 6 帧）。
- **修法**：受理成功路径**彻底删掉** `sendConnBets`/回执调用（`funkytimecore/downstream_bet.go:83-94`、`crazytimecore/downstream_bet.go:91`、`fantancore/downstream_bet.go:91`）。**纠正的唯一来源是拒单 / undo 路径**——只有这两条才回帧。
- 🔴 **拒单回执必须做差量，不能整帧标 rejected**：全量协议下入参是累计全集，直接整帧标 `RejectedBets` 会把**此前已成功受理的注**一起打上错误码，客户端据此把它们全部视觉撤回（玩家逐个点击累计触顶时必现，批量下注不复现）。修法 `rejectedDelta(frame, accepted)` 只保留 `frame[code] - accepted[code] > 0` 的正增量（`funkytimecore/downstream_bet.go:201-220`）。资金侧 Redis 是对的，但「客户端所见 ≠ 实际扣款」等价于一次严重一致性事故。
- **与 B5 的分界**：B5 讲的是 **ack 式增量协议**（roulette `betsAccepted` 不能在下注期定格位置）；本条讲**全量快照协议**（下注期一帧都不发）。**两类协议规则不同，先判本族属哪类再套**。
- **与 K6 的关系**：K6 是撤注要维护服务端快照栈，本条是受理不能发回执——同一份全量协议的两条互补铁律，K6 之外还要过这一条。
- **三次实证**：#448 CrazyTime(07-08) → #496 FanTan(07-16) → #531 FunkyTime(07-21)。每次都被当新 bug 单独修，**新族务必一次到位**。

## R. 仓库/部署：client 资源 git 治理（EVO 全游戏共性，省 ~18MB/桌族）

**R1 vendored client 媒体不进 git，回源 CDN cache-through**：`server/game/evo/client/frontend/` 每族会涨 vendored 媒体（webm 声音/png/webp/jpg 图片/woff2 字体/mp3/svg，约占一半体积）。运行时 `gateway/client_proxy.go(evoCDNProxy)` 在 `/frontend/*` 本地缺失时回源 `tmbge.evo-games.com` + cache-through 落盘 → 媒体**无需 git 跟踪**。`.gitignore` 忽略 `frontend/**/*.{webm,png,webp,jpg,jpeg,mp3,woff2,ogl,svg}`，**例外保留 `game-render-assets/**`**（我方自产 render 资源、不在 EVO CDN）+ `reports/`。**只 git 固定 js/json/html/css**（代码+协议+manifest+样式，须版本一致）。与 PP 的 `client/apps/*/` 同思路。
- **版本一致天然保证**：content-hash 资源名不可变（`wheelsprit.10a145df.webp`），git 固定的 js/json 引用特定哈希 URL → 各服务器回源拉到的字节永远一致。
- **依赖**：生产须能访问 tmbge CDN（出口受限环境需预热缓存或保留媒体）。
- **历史回收**：`git rm --cached` 只停未来跟踪；`.git` 历史里的体积需 `git filter-repo` 重写（破坏性，另议）。
