# Layer 4 AIU — 依赖 L3（6 并行）

> 进入 L4 前确保 L3 全部完成 + 层间审查通过。
> L4 是派生产物：派彩计算 / betstats 增强 / winners 广播 / 3 个 HTTP 接口。

## L4.1 — PAYOUT

**产物**：`payout.go` + `payout_test.go` + `payout_cap_test.go`

**分析输入**：
- L1 ENUM（bc / face / 默认值常量）
- L2 RULES（bet_limits 三路 cap 字段）
- L3 SETTLE 调用接口
- `tmp/<tid>/message.txt` <gametype>gameresult 真帧（payout_test 4 样本来源）

**实现内容**：
- `Calculate(amount, face, megaMul)` 纯函数 — **payout 含本金**（不是只净赢）
- **G3 三路 cap min**（用户级，**不是单注级**）：
  - A = `maxMultiplier × totalUserStake`（用户当局总下注本金，**非单注**）
  - B = `Convert(euro_table_payout_max, "EUR", currency)`
  - C = `table_payout_max`（本币硬封顶，可选）
  - 最终 = `min(A, B, C)`
- `handlers.LookupRoundCap` 拿 cap → `handlers.CapUserPayout` 等比缩放（C8）
- `mCap=true` 触发条件 + 缩放
- `betCodeDescription(bc)` 9 段位本地化（H6）
- 单注 cap 走 `LookupPayoutBetMax`（如 `payout_bet_max_limit`）

**B5 验收**：build/vet/test 过 + payout_test 至少 4 个 capture 真帧样本 + payout_cap_test 单注 + 用户级三路 cap 分开断言

**下游**：BETSTATS / SETTLE 调用

---

## L4.2 — BETSTATS

**产物**：`betstats_enrich.go`

**分析输入**：
- L2 MODELS（betstats struct）
- L1 ENUM bc 全集
- `tmp/<tid>/message.txt` 实际 betstats/betResultStats 帧（验证 bucket key）

**实现内容**：
- `EnrichBetstats` 函数（参考 dragontiger `enrichDTBetstats`）
- 按 9 段位（或对应 bc）enrich：每段位 total + count
- 货币换算 EUR（`configCache.CurrencyRates.Convert`）
- **B7 完整 envelope 返回**：`{"betstats":{...}}` 整 envelope，rewrite 链路必须 `unwrapEnvelope` 解出内层
- bucket key 与 main.js client 实测 key 一致（如 megawheel 用 "1"/"2"/.../"40" 数字字符串，不是 "One"/"Two"）

**B5 验收**：build/vet 过 + 单测覆盖 1-2 case（构造 Redis bets → enrich → 断言 bucket）

**下游**：UPSTREAM dispatch 调用（rewrite betstats 帧）

---

## L4.3 — WINNERS（**默认 Model A：drop 上游 + 合并我方 + per-观众币种广播**）

**产物**：`winners_broadcast.go`

**分析输入**：
- L2 MODELS（winners struct；注意 winner[] 是否带机台专属字段：`mul` / `tiMapKeys` / `topWinMultiplier`）
- `tmp/<tid>/message.txt` winners 真帧（含外渠道真实玩家结构）
- main.js setWinners 客户端渲染逻辑
- 上游帧序：winners 与 gameresult 谁先到（决定合并时点，见下）

**Model A 标准实现**（所有机台统一，旧"pass 透传"已废弃）：
1. dispatch 把上游 winners 帧 **drop**（`verdictDrop`，不透传含混币种原值的上游帧）。
2. **合并我方下游中奖者**：`handlers.CollectOurWinners(tableID, gameID)` 取本局中奖用户，用真实
   userId/screenName/本币 win 追加进 winner[]（B2 上游 ppc 条目全保留，按 userId 去重我方覆盖）。
   > **金额口径（必懂）**：`CollectOurWinners.NetWin = sum(payout where is_win=true)` = **中奖金额**
   > （含本金，与个人 win 帧一致），**不是这一局的输赢（game_net_cash）**。玩家某注中 2000、整局其它注净亏
   > （game_net_cash<0）也要以 **2000** 上榜——合并时筛 `NetWin>0`（中奖金额>0），**不要**用 net cash 筛。
3. **EUR 归一排序截断**（铁律）：`handlers.SortTruncateByEUR(msg, events.WinnersListMaxLen)`
   替代 `SortByWinDesc + TruncateToTopWinners`。**先排序、再截断到最多 100 条**（`WinnersListMaxLen=100`）。
   ⚠️ 我方条目是 **append 在 winner[] 末尾** 的——**不排序就会沉在榜底**，客户端按序渲染时大奖看似"没上榜"
   （线上真实事故）。修混币种裸值排序 bug 同此调用，见 known-pitfalls。
4. **per-观众币种分发**：`events.TableCurrencySet(tableID)`（兜底加 "USD"）→
   `handlers.ConvertWinnersByCurrency(tableID, msg, ccys)` 每币种 marshal 一份 →
   `events.BroadcastToTableByCurrency(tableID, perCurrency, perCurrency["USD"])`。
   rate cache 未加载 → 退化单份原值广播。

**合并时点（看帧序）**：
- **gameresult 先于 winners**（moneytime / jackpotwheel / TI）：settle 已完成 → onWinners/BroadcastWinners
  里**同步合并广播**，再延迟 `WinnersBroadcastDelay` flush 私聊 win（保 gameresult→winners→win）。
- **winners 先于 gameresult**（megasicbo）：winners 到达时 settle 未完成 → **stash 上游帧**，由
  settle 入队后的 rendezvous（winnersSeen↔pendingReady 握手）合并广播；一局只在 rendezvous 广播一次。

**两条铁律（用户指证，必须遵守）**：
- **一局只向客户端广播一次** winners（rendezvous / 同步点单点广播 + take-once / broadcasted guard；
  `BroadcastToTableByCurrency` 每连接只发本币一份）。**不要播两遍**，不加兜底定时器二次广播。
- **先合并我方数据再广播；合并失败（DB 不可用 / CollectOurWinners 出错）→ 整局不广播 winners**。
  我方零中奖不算失败（CollectOurWinners 成功返回空），照常广播上游瀑布。

**机台专属字段（mul / tiMapKeys / topWinMultiplier）**：通用 `events.Winner` 不支持 mul/tiMapKeys
（TI bonus 局 per-user）。这类机台**自建 per-currency builder**（TI 范式：用机台自己的 Winners/WinnerEntry
结构换算 win/currency 时透传 mul/tiMapKeys，totalEur(EUR)/winnersCount 货币无关各 variant 一致、topWin
按该币种重算），**不复用** `events.WinnersMessage`。topWinMultiplier 是 PP 全局倍率，原值透传不重算。

> **自建 builder 易漏的两步（TI 线上踩过）**：
> 1. **合并后必须自己排序+截断**（`events.WinnersMessage` 有 `SortTruncateByEUR`，自建结构没有 → 自己写
>    `sortTruncateWinnersByEUR([]WinnerEntry, 100)`，按 EUR 归一降序、保留 mul/tiMapKeys）。漏了大奖沉榜底。
> 2. **排序必须在 `recalcWinnersAggregate` 之后**：聚合按"我方条目在末尾"切片定位 `oursAdded`（`winner[len-oursAdded:]`），
>    先排序会打乱这个切片 → winnersCount/topWin/totalEur 算错。顺序固定：**合并 → recalcAggregate → 排序截断 → 分币种广播**。

**B5 验收**：build/vet/test 过 + winners_test 覆盖（合并去重 + **我方大奖排榜首 + 截断 100** + EUR 排序 +
每币种 marshal 字段映射 + 合并失败不广播 + 机台专属字段透传）。

**下游**：UPSTREAM dispatch 调用（winners → `verdictDrop` + side-effect 广播）。

---

## L4.4 — STATS_API（统计面板 + 启动回填）

**产物**：`server/game/pp/internal/gateway/api/api_stats_<gametype>.go`（仅当客户端走 /api/ui/stats）
+ 机台 Processor 的启动回填 hook（`OnStatisticHistoryHTTP` / `StatHistoryHTTPEndpoint`）

**分析输入**：
- L3 SETTLE writer 写入的 record 字段
- `tmp/<tid>/statisticHistory.txt` 真 records —— **先看每行 `_endpoint` 首字段**判断客户端走哪个端点（脚本已标注）
- **main.js `Object.keys(tf)` 客户端实测 key**（如 megawheel 是 `["1","2",..."40"]` 数字字符串，非 `"One"..."Forty"`）
- 既有 api_stats.go 路由分支机制 + game_instance_base.go 回填断言

### ① 先定端点（决定后续全部实现形态）

客户端统计面板有两个**互斥**上游端点，从 capture `statisticHistory.txt` 每行 `_endpoint` 判断本机台走哪个：

| 端点 | 顶层形态 | 谁走 | 服务端实现 |
|---|---|---|---|
| `/api/ui/statisticHistory` | `{numberOfGames, history[]}` | roulette / sweetbonanza 等通用历史机台 | **无需写 handler**（api_history.go 通用透传） |
| `/api/ui/stats` | `betSpotPercentage` / `winningBetOccurrenceStat` / `<gametype>GameStatisticHistory` | WheelGames 族（jackpotwheel/moneytime/treasureisland） | **必须**在 api_stats.go 加 gametype 分支 |

- **两端点读同一 Redis key** `pp:stat_history:http:<tableCode>`，区别只在客户端调哪个 URL + 响应 shape。
- 走 /stats 却没加分支 → fall through 轮盘默认分支，返回 0-36 shape，客户端 reducer 解析失败 → **面板空白**。
- **game_type 路由大小写**：`resolveStatsGameType` 已 `ToLower`；DB game_type 录入大小写（"TreasureIsland"/"moneyTime"）不影响匹配，但 switch case 必须**全小写**。

### ② 启动回填（初始数据，必接，否则面板不足 500）

仅靠 SETTLE 每局 append 要开机后攒满 500 局才齐 → 玩家进场看到的是稀疏历史。机台 Processor **必须**实现回填 hook 拉上游近 500 局（`game_instance_base.go.Start` 在实例启动后断言调用）：

- `OnStatisticHistoryHTTP(tableCode, body)`：解析上游 body 的历史数组（RawMessage 透传即可，保留真服全字段）→ `events.SaveHTTPStatHistory` 覆盖写。
- `StatHistoryHTTPEndpoint() (path, countParam)`：**走 /api/ui/stats 的机台必须实现**，返回 `("/api/ui/stats", "noOfGames")`。不实现则默认 `/api/ui/statisticHistory?numberOfGames` —— 对 WheelGames 族打错端点拿空/异构数据（这是 treasureisland/moneytime 初版漏接回填、面板不足 500 的根因）。
- **同构不变量**：SETTLE 每局自落的 record 必须与回填的上游 record **字段同构**（同 `gameResult` 展示值约定、同字段集），二者共存同一 list；破坏 → 历史里两种形态混排，客户端按 key 取值时部分局渲染失败。
- 本地 dev 无真实 PP 会话（JSESSIONID 空）→ 回填拿空 body fail-soft 不阻断；线上接真渠道才回填。
- 参考实现：treasureisland / moneytime `settle_persistence.go`（/stats 族）；sweetbonanza / crystalroul `upstream_handlers.go`（statisticHistory 族）。

### ③ /stats handler 实现（若走 /stats）

- 在既有 `api_stats.go` 加 gametype 分支（不破坏其他 gametype）
- 从 Redis `pp:stat_history:http:<tableCode>` 拉 records，按 `gameResult`/`rc` 累计 bucket
- 响应 shape 严格对齐 capture（含/不含 `data` 包装、key 命名按 main.js 实测）
- **`gameResult` 必须是展示值**（面值 / bonus 名 / "N Color"），**不是** raw rc 码（见 known-pitfalls **H11**）

**B5 验收**：build/vet/test 过 + api_stats_<gametype>_test 覆盖 1-2 case + **curl 比对 capture shape**（phase-6 V15）

**下游**：routes.go 注册（如新接口；既有路由不动）

---

## L4.5 — TABLECONFIG_API

**产物**：`server/game/pp/internal/gateway/api/api_table_config_<gametype>.go`

**分析输入**：
- L1 ENUM（typo 字段映射）
- `tmp/<tid>/tableConfig.txt` 真响应 shape
- main.js client 读取 betLimits 代码

**实现内容**：
- 在既有 `api_table_config.go` 加 gametype 分支
- 输出对应 betLimits 形态（如 megawheel 9 键 / baccarat 主投注+边注键 / roulette 多类型键）
- **typo 兼容**：tableConfig.params 内部读 `fourty_bet_min/max`，响应给客户端 normalize 为 `Forty`
- `tableBetLimit` 顶层字段（取自 `table_bet_max_limit`）

**B5 验收**：build/vet/test 过 + 单测覆盖 typo 字段映射 + 兜底默认值

---

## L4.6 — RTP_API

**产物**：`server/game/pp/internal/gateway/api/api_rtp.go`

**分析输入**：
- main.js Help 弹窗 getRtpDetails 客户端读取逻辑（`e.description` 非 "Invalid user session" + `e.data` 是 JSON 字符串）

**实现内容**：
- GET `/api/ui/getRtpDetails` handler
- query 含 `tableVariant` / `JSESSIONID` / `operatorGameId`
- 响应：`{"description":"OK", "data":"<json string>"}`
- `data` 是字符串（客户端 JSON.parse 二次）
- 默认 RTP body 可硬编码本机台公开 RTP（如 megawheel `{"rtp":"96.50","megaMultiplier":"500x"}`）
- **避免空 body 触发客户端 JSON.parse 异常**

**B5 验收**：build/vet/test 过 + api_rtp_test 1 case 走通流程 + 断言 data 是字符串

---

## prompt 模板

参考 `phase-3-aiu-L1.md` 末尾通用模板。L4 AIU prompt 额外注入：
- 上游 SETTLE 调用接口 / b_game_rounds.Extra 落盘字段
- main.js 客户端读取代码的关键 grep
- 既有 api_*.go 路由分支机制

**铁律 reminder**：
- L4.3 winners 默认 Model A（drop 上游 + 合并我方 + per-观众币种广播；一局只播一次；合并失败不广播）
- B7 betstats 完整 envelope
- C8 payout cap
- G2/G3 三路 cap min + 用户级（非单注）
- H6 BetCode Description 本地化
