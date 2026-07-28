# Layer 4 AIU — 依赖 L3（5 并行）

> 进入 L4 前确保 L3 全部完成 + 层间审查通过。
> L4 是派生产物：派彩计算 / 历史走势 + 孤儿局恢复 / 历史详情 / 报表前端页 / 货币配置。
> **与 PP L4 的差异**：EVO 无 STATS_API / TABLECONFIG_API / RTP_API 这些 AIU（统计走 `recentResults`/`spinHistory` 协议内 + 通用 `gateway/history_api.go`；tableConfig/RTP 走通用 `/config`）。核心 5 AIU：PAYOUT / HISTORY_RECENT / HISTORY_DETAIL / REPORT_PAGE / CURRENCY_CONFIG。
> 🔴 **BETSTATS 是条件 AIU，不是「EVO 没有」**：roulette 无 betstats 帧；**game show 等族有 `<gt>.bettingStats`**（IceFishing 428 帧最高频，`{bettors,watchers}` communal 聚合计数）。新族 L4 必须先 grep `bettingStats`/`stats` 帧：有则建 **L4.6 BETSTATS**（见下，直转或合并我方聚合计数；**注意是聚合计数、非 per-player，不能注单玩家注**）；无则跳过。winnersList 多为 A 直转广播（社交瀑布需合并我方中奖者按下方 WINNERS 注）。

## L4.1 — PAYOUT

**产物**：`games/<gametype>/payout.go` + `payout_test.go`（可与 odds 同目录）

**分析输入**：L1 PAYOUT_MODEL（赔付模型）/ L2 RULES（per-bet cap 字段：maxMultiplier / euro_table_payout_max；#64 后无 round-level）/ L3 SETTLE 调用接口 / `roundDetail/<rid>.json`（`.data.data.participants[].bets[]{code,stake,payout}` 真样本反推公式）

**实现内容**：
- 纯函数派彩 — **含本金，公式因族而异**：roulette `amount×(odds+1)`（号码集→odds）；game show 押中 segment `stake×<seg>Multiplier`、未中=0（倍率来自结算帧 `<seg>Multipliers`/`totalMultiplier`）；baccarat 牌型赔率。**从 roundDetail json 反推，禁假设 odds 制**（IceFishing 实证 `IF_Leaf1 stake2000→payout4000`）。⚠️ betCode 双命名空间（下注帧 `Leaf1` vs roundDetail `IF_Leaf1`）反推前先映射。
- **G3 payout cap = per-bet**（🔴 issue #64 于 2026-05-14 把 round-level 整套反转为 per-bet，`LookupRoundCap` / `CapUserPayout` / `table_payout_max` / `MCap` **一并下线**，见 `handlers/round_cap.go:1-12`）：调 `handlers.LookupPerBetCap` 取两路 `min(A,B)`——A=`maxMultiplier × `**本笔注额**（per-bet 单注，**非**用户当局总注；game show maxMultiplier 在 bonus 帧实证，如 200/500）；B=`Convert(euro_table_payout_max,"EUR",currency)`（EUR 换算失败 fail-closed）。game show 若有 per-betcode `payout_limit` 是族特有额外一路，按 capture 定。**别再调 LookupRoundCap/CapUserPayout（已不存在）**。
- **currencyMult 进制**：派彩金额按币种进制
- `betCodeDescription(bc)` 人类可读描述（H3，落 `b_game_transactions.description` 供报表/对账）。🔴 **落库值恒为英文、语言无关**（稳定标识，不随玩家 locale 变）；**玩家历史详情的注名不读这个字段**，而是 render 侧从 `betCode` 重算 + `tr()` 翻译（H7 / L4.3）——想「直接拿 DB description 显示」就永远是英文且不可译。两条路径都要有，别合并。

**B5 验收**：build/vet/test 过 + `payout_test` ≥ 4 个 roundDetail/capture 真样本 + per-bet cap 分开断言（A=maxMultiplier×**本笔注额**、B=euro；#64 后无 round-level/用户级）

**下游**：SETTLE 调用

---

## L4.2 — HISTORY_RECENT（recentResults + 孤儿局恢复）

**产物**：`games/<gametype>/<gametype>core/recent_results.go` + `reconcile.go`

> EVO 走势统计在协议内（roulette `recentResults` / game show `<gt>.spinHistory` 帧），无 PP 的 /stats 端点 + 启动回填。但需缓存最新走势帧供新连接回放 + 孤儿局恢复。

**分析输入**：L2 MODELS（走势帧 struct）/ `message-nobet.txt` 走势帧（roulette `recentResults` / game show `<gt>.spinHistory{newResult,results[],version}`）/ 模板 `roulettecore/{recent_results,reconcile}.go`

**实现内容**：
- **`recent_results.go`**：缓存最新走势帧（roulette `recentResults` / game show `<gt>.spinHistory`，每局重发的全量快照，**必缓存并新连接回放**，否则走势板空白——帧时效语义二分见 B17），直转广播
- **`reconcile.go`（孤儿局恢复，EVO 自愈）**：上游漏发 GAME_RESOLVED / 进程重启错过开奖时，从 `recentResults`（含历史开奖号）兜底补结算未结算局。`reconcileFromRecentResults` / `reconcileOnNewRound`：新局开窗时检查上一局是否已结算，未结算则用 recentResults 的结果补 OnGameResult。
  - 🔴 **fail-closed**：补结算同样走 `GetRedisUserBets(requireAccepted=true)` + `hasSuccessfulBetDebit`（不能凭 recentResults 给没扣款的注派彩）
- **🔴 pending 态必用 `pendingsettle.Tracker`（common 层统一收敛，勿自写 pending 字段）**——「已扣本金未结算」孤儿局标记的单一真相源，五件套照抄既有 5 族（icefishing/monopolybigballer/funkytime/roulette/crazytime 的 `reconcile.go`）：
  1. **Mark on 扣款**：`onBetsClosed` 提交 `/bet` 后 `p.pending.Mark(gameID)`（有扣款才标）。
  2. **Clear on 结算**：settle 成功 `p.pending.Clear(gameID)`；**compare-and-clear**——`Clear` 返回 bool，退款路径只有「原子赢得清标记」的那条才发退款（`cancelOrphan` 先 `clearPendingSettle(orphan)` 不通过即 return），杜绝 sweep 与帧驱动/结算并发对同一孤儿局双退款。
  3. **帧驱动**：`reconcileOnNewRound` 用 `p.pending.NextOrphanRound(newGameID)` 推进跨局计数，≥`OrphanRoundThreshold` 取消局退款。
  4. **sweep 兜底（game-ws 长期死，最大资金敞口）**：实现可选接口 `SweepStaleSettle(tableDBID uint, maxAge time.Duration)`（进程级 settle_sweeper 60s 扫、5min 龄期退款）——帧驱动依赖「下一帧」，game-ws 整条线死则永不触发，没有 sweep 玩家本金被永久扣住。
  5. **跨重启**：构造时 `pendingsettle.New(variant.TableID)`（Redis 持久化）+ `handlers.RecoverPendingSettle(p.pending, variant.TableID)` 载回（内置终态守卫：已 settled/cancelled 的局不载入，防重启后 sweep 双退款）。
  - **监控接口**：`PendingSettleStatus() (string, time.Time, bool)`（返回 `p.pending.Pending()`）——运维看板资金安全面的孤儿局数据源（evoMachineReporter 经可选接口读取），新族必加否则看板盲区。

**B5 验收**：build/vet/test 过 + `reconcile_test` 覆盖"漏 GAME_RESOLVED → 新局用 recentResults 补结算" + recentResults 缓存回放 + Tracker 五件套接线（Mark/Clear/sweep/Recover/PendingSettleStatus 缺一即打回）

**下游**：UPSTREAM 接入（recentResults 缓存 + 新局 reconcile 钩子）

---

## L4.3 — HISTORY_DETAIL（玩家历史详情：结果区局面 1:1 render）

> 🔴 **EVO 与 PP 的根本不同**：PP 的 detail 是 cgibin XML、逐字段结构化、靠通用接口拼字段；**EVO 的 detail 局面区是 EVO 服务端 SSR 出的一段 HTML（`gameDetail.txt .data.render`），客户端 `dangerouslySetInnerHTML` 直插**。所以本 AIU 不是"通用接口够不够、不够补字段映射"（那是 PP 思路），而是**每个新族必产一份 `render`**——把局面区（结果 UI + bet 表）做成与真实 EVO **逐字节一致**。早期把 `render` 降级成纯文字（只塞段名）是 bug，不是方案。

**职责切分（先认清，避免误改基础设施）**：
- **通用、复用、不碰**：`gateway/history_api.go`（token→玩家→`vendor_type='evo'` filter→按时区分组的 `/days` `/day` `/game/:id` 端点，并已从玩家档案取好 `evo_locale` 传下来）+ `/frontend/*` 资源代理 + `renders/loc.go`（官方串包本地化层）+ `renders/money.go`（币种符号/小数位）。新族**不写** per-machine `history.go`、**不写**取包/翻译/金额格式化代码。
- **每族必写**：`gateway/renders/<gametype>.go` + `assets/<gametype>/` 模板（`render` 的局面区装配）+ **本族文案 key 映射**。`history_api.go` 的 `EvoHistoryGame` 已统一调 `renders.BuildRoundRender(gameType, gameID, tableDBID, txns, symbol, decimals, bonusChoice, locale)`，新族只在 `renders/render.go` 的 switch 加一个 case。

**产物**：`gateway/renders/<gametype>.go`（查 round/txns + 模板装配 + 段码→官方 key 映射表）+ `assets/<gametype>/*.html`（从 capture 字节级抽出的 SSR 片段）+ `render.go` 分发加 case + `<gametype>_test.go`（结构断言 + key 映射表驱动核对 + 非英文 locale 渲染）；并确认 L3 SETTLE 落盘字段齐（render 的数据源）。

**分析输入**：
- **`tmp-evo/<dir>/gameDetail.txt` 真 JSON**：`.data.render` = 局面区 SSR HTML（**1:1 复刻的权威基线**，逐字节对比就比它）；`.data.{gameType,status,startedAt}` = 详情头部字段（通用 handler 已处理）。
- `roundDetail/<rid>.json`（`.data.data` 结构化结算体 participants/bets/result）—— **报表页**逐字段对账用（L4.4），detail render 不依赖它。
- L3 SETTLE 落盘字段（`b_game_rounds` + `b_game_transactions`）—— render 用我方结算数据回填模板。

**实现内容**：
- 🔴 **结果区局面 1:1 复刻（本 AIU 核心）**：从 `.data.render` 字节级抽模板 + Go 装配 + **字节对比验收**，覆盖该族每种结果形态（数字/各 bonus/miss/带倍率…）。**完整四步法 + 逆向硬细节 + 资源代理 + bonus 帧落库模式见 `references/phase-3-game-record-render.md`**（roulette/crazytime/icefishing 已落地范例）。
- 🔴 **文案位 key 化（与 1:1 复刻同等必做，漏了全族返工过一次）**：render 里玩家可读的文字（表头/注名/段名/bonus 标题）一律走 `tr(key, 英文字面量)`，key 取自 EVO 官方串包 `history.json` 的**本族**命名空间——命名空间名 ≠ gameType，必须实搜（铁律 known-pitfalls **H7**；找键三步法 + 表驱动测试见 `phase-3-game-record-render.md` §2）。
- **bonus 内部网格**（game show 常有：flapper 转盘 / cash hunt 网格 / pachinko / coin flip）：要 1:1 需先把完整 bonus 结果帧落 `b_game_rounds.Extra["bonusResult"]`（纯展示、不碰资金：cache-before-settle + marshal-fail 不阻断 + OnRoundSettled 时序不变）。落库前先核 result 帧数据齐全度（部分缺 per-zone/另一币，需另抓 setup 帧）。
- **持久化字段完整性**（L3 SETTLE 配合，render 数据源）：`b_game_rounds.{dealer_name, round_id, game_type, extra, result}` + `b_game_transactions.{description=BetCodeDescription(bc), currency=本局会话币种, stake, payout, settled_at, max_capped}` 完整落（H3）。
- **投注类型 vs 开奖结果各自独立逐笔保存**（H3：bet.description 是下注点、result 是开奖，绝不混用）。

**B5 验收**：build/vet/test 过 + **每种结果形态与 `gameDetail.txt .data.render` 字节级 diff 通过**（归一空白 + mask 随机 UUID）+ `<gametype>_test.go` 留结构断言（关键 class / 资产路径 / 倍率规则 / 金额精度无浮点尾巴）+ 投注类型/开奖结果分离 + 资源经 `/frontend` 代理三路 200 + 🔴 **文案全 key 化且非英文 locale 实跑通过**（`zh-Hans` 渲染出中文、无英文残留、开奖号/金额不变；只跑 en-US 等于没测，三种故障对英文玩家全不可见）。

**下游**：API 层 `EvoHistoryGame` 调用 `renders.BuildRoundRender`（通用 handler，与 instance 解耦）。

---

## L4.4 — REPORT_PAGE（商户报表前端页）

**产物**：`server/game/evo/client/reports/<裸 evo_table_id>/index.html`（**14 行引导 stub**）+ 按需 `_assets/renderers/<gametype>.js` + `_assets/report.js` 的 `RENDERER_BY_TABLE` 加一行映射

> 后端只出通用 JSON（`gateway/report_api.go` 的 `/gameHistory/report`，所有机台共用，无 per-machine Go）。
> ⚠️ **本节 2026-07 更正**：早期写的「一机台一份、内联自包含、不引共享 `_assets`」是 **PP 的铁律，EVO 不适用**——EVO 从第一个报表 commit（`8427cdfb`）起就是「共享 `report.js` 引导 + 按 gameType 一份 renderer」。照旧文字做会重新发明一套自包含页面。
> 🔴 **先查 `_assets/report.js` 的 `RENDERER_BY_TABLE`**：同协议桌大概率**直接复用已有 renderer**（`247dc9a6` 把 12 张欧轮 + 5 张 SicBo 全指向同一个）；确需新渲染形态才新建 `renderers/<gametype>.js`。每桌**仍要有自己的 index.html 目录**（URL 即桌、防串桌），但它只是 stub。

**前置依赖**：L3 UPSTREAM `archiveCurrentRaw` 落 `b_game_rounds.messages`（漏 = messages 空）+ L3 SETTLE 落 round/extra。

**分析输入**：
- **`roundDetail/<rid>.html`** —— 玩家可直开报表页基线 DOM（视觉对照）
- **`roundDetail/<rid>.json`** —— 结构化结算体（**EVO 比 PP 多这份，报表字段直接对照，比 PP 只有 html 更好对**）
- 既有 `server/game/evo/client/reports/vctlz20yfnmp1ylr/index.html`（roulette 范例）+ `_assets/{report.css,report.js,index.template.html}`（公共模板参考，但新桌内联自包含不引用）

**实现内容**：
1. **先查复用**：`_assets/report.js` 的 `RENDERER_BY_TABLE` 里本族/同协议桌是否已有 renderer → 有则只加一行映射 + 建 stub 目录，**零 JS 新代码**。
2. 确需新形态才写 `_assets/renderers/<gametype>.js`（取 query token → `fetch('/gameHistory/report?token=...')` → 渲染 1:1 DOM，对照 roundDetail）。**结果可视化按族**：roulette Game Result 行用 SVG 指示牌（邻号弧+落点居中红描边，roulette 专属）；game show 按 roundDetail 的 segment+倍率盘+bonus 结构复刻（**无号码弧 SVG**）。
3. 每桌建 `reports/<裸 tableId>/index.html` stub（照抄既有桌的 14 行）。
- 🔴 **倍率/金额是独立于 Go render 的第二条计算路径**，必须自己对照 `roundDetail` 核：① 别用 `payout/betAmount` 当倍率（那是**总返还**含本金，净倍率要 `(payout-stake)/stake`，#480 CrazyTime 15x 显成 16x）；② 别直读 round 级聚合字段当玩家倍率（`round.multiplier`/`extra.roundMult` 是**整盘候选最大值**不是本人选中项，#480 FunkyTime）——优先取本人 choice 对应盘面值，取不到才按净赢反算，**绝不回退展示未命中的最大倍率**。

**B5 验收**：`node --check` 语法过 + 用真 `/gameHistory/report` JSON mock fetch 视觉对照 `roundDetail/<rid>.html` ≥ 90%（roulette 含 SVG；game show 按本族结果元素）+ **stub 已建且 `RENDERER_BY_TABLE` 有本桌映射** + 倍率口径对照 roundDetail 逐笔核过 + 前置（messages 非空 / round·extra 齐）满足

**下游**：商户 `/roundreport` 返回 `/reports/<裸 tableId>/index.html?token=...`

---

## L4.5 — CURRENCY_CONFIG（per-currency 配置，EVO 特有必做）

**产物**：`b_table_currency_configs` 行（DB 模板，L5 FACTORY 一起落）+ 确认 `runtime/limits_config.go` / `gateway/admin_currency_sync.go` 能覆盖新桌

> EVO `/config` 按 tableID+currency 查 `b_table_currency_configs` 取限红；**缺 → 限红/兜底错 / 客户端限红空**。EVO 货币配置是 **per-currency**（实测：换 showCurrency 后 /config 限红按 currencyMult 换算，USD1/BRL5/INR100，上游算好）。

**分析输入**：
- `config.txt` 各币种限红字段 + currencyMult（capture 会话币种那一份）
- `gateway/admin_currency_sync.go`（从上游同步各币种 config 的机制）+ `admin_currency_upsert.go`
- L2 RULES bet_limits（per-currency override 入口 `runtime.Load<GameType>Limits(db,tableDBID,currency)`）

**实现内容**：
- 为新桌预存各币种 `b_table_currency_configs`（限红 + currencyMult + chipAmounts）：① 走 `admin_currency_sync` 从上游逐货币换 session 同步（取 config 必须用会话 tls-client，标准库 403；复合 key 剥纯 tableId），或 ② capture 会话币种先种一份 + 上线补同步
- 确认 `/config` 对新桌返回正确 per-currency 限红

**B5 验收**：DB 有该桌 ≥1 币种行 + `/config?table_id=<code>` 本地起服返回限红非空 + currencyMult 正确

**下游**：L5 FACTORY DB 模板 + 部署 checklist

---

## L4.6 — BETSTATS（**条件 AIU**：仅 capture 有 `<gt>.bettingStats` 等统计帧的族建）

**产物**：`games/<gametype>/<gametype>core/betstats.go`（条件；roulette 无此帧跳过）

> game show 高频广播 `<gt>.bettingStats`（IceFishing 428 帧最高频，`args:{gameId, bettors, watchers}` communal 聚合计数）。直转会让在桌人数只反映上游侧、漏我方 seamless 玩家。

**分析输入**：L2 MODELS（`ArgsBettingStats{Bettors,Watchers}`）/ `message-nobet.txt` 该帧 / `gateway/game_user_conns` 在桌连接数

**实现内容**：
- 判断是否 enrich：① 仅展示上游聚合 → `DispBroadcast` 直转即可（不建本文件）；② 计入我方玩家 → drop 上游 → 合并我方本局有注用户数到 `bettors`、在桌连接数到 `watchers` → 广播
- 🔴 **`bettingStats` 是聚合计数、非 per-player 拆分** —— enrich 只能加我方**聚合计数**，**不能从中取/注单个玩家注**（与 winnersList 不同）

**B5 验收**：build/vet/test 过（如建）+ enrich 后 bettors/watchers = 上游 + 我方计数；或确认走纯直转

**下游**：UPSTREAM dispatch 调用（betstats → 直转或 enrich 后广播）

---

## WINNERS 处理（折入 L3 UPSTREAM，此处备注）

🔴 `winnersList` 名为公共帧但**默认必须合并我方本局中奖者再广播**——上游榜只含别家赌场玩家（我方下注不发上游 → 结构上永不含我方），裸直转会让我方玩家中大奖也不上榜（IceFishing000001 实测被用户指证：本人净中 10000 该排第二却不见自己）。**不是「按需决定」，是默认要做**。实现（icefishing `winners_broadcast.go`，镜像 PP moneytime/jackpotwheel）：
- `HandleUpstream` 拦截该帧 → 解码 → `handlers.CollectOurWinners(tableID, gameID)` 取本局我方中奖者（`ScreenName=Nickname`、`payout=NetWin` 含本金）→ 追加 winners 数组、按 payout 降序、**截断回上游原 len** → 重 marshal **替换**原帧 `return true, merged`（1 进 1 出、只广播一次）。
- 聚合字段 `winnersCount/bettorsCount/totalAmount` 全场口径 → **透传上游原值不动**，只插 winners 数组（IceFishing `winnersList{winners[{screenName,payout,multiplier}],winnersCount,bettorsCount,totalAmount}`）。
- 合并铁律：合并失败（DB nil / CollectOurWinners err / 解码失败）→ **整局不广播**；零中奖 → 原样透传。
- EVO 条目只有 `screenName`、无 userId（与 PP moneytime 含 userId 不同）→ **无需去重**，直接追加排序截断。
- 多币种是该族增强（PP moneytime EUR 归一 + per-观众币种 `BroadcastToTableByCurrency`）；icefishing 单份广播即可（payout 用玩家本币 NetWin）。详见 known-pitfalls B8。

## prompt 模板

参考 `phase-3-aiu-L1.md` 末尾通用模板。L4 AIU prompt 额外注入：
- 上游 SETTLE 落盘字段 / roundDetail json 结构
- 通用 gateway handler（history_api / report_api / api_config）的覆盖边界
- **铁律 reminder**：G3 **per-bet cap** min（#64 后无 round-level/用户级）/ currencyMult 进制 / H3 落库描述英文稳定 + H7 render 文案走官方串包 key（本族命名空间实搜、非英文 locale 实跑）/ 报表 **stub+共享 renderer**（非一桌一份自包含，H4）/ per-currency 配置必种 / reconcile fail-closed
