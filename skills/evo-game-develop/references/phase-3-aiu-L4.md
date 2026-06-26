# Layer 4 AIU — 依赖 L3（5 并行）

> 进入 L4 前确保 L3 全部完成 + 层间审查通过。
> L4 是派生产物：派彩计算 / 历史走势 + 孤儿局恢复 / 历史详情 / 报表前端页 / 货币配置。
> **与 PP L4 的差异**：EVO 无 STATS_API / TABLECONFIG_API / RTP_API 这些 AIU（统计走 `recentResults`/`spinHistory` 协议内 + 通用 `gateway/history_api.go`；tableConfig/RTP 走通用 `/config`）。核心 5 AIU：PAYOUT / HISTORY_RECENT / HISTORY_DETAIL / REPORT_PAGE / CURRENCY_CONFIG。
> 🔴 **BETSTATS 是条件 AIU，不是「EVO 没有」**：roulette 无 betstats 帧；**game show 等族有 `<gt>.bettingStats`**（IceFishing 428 帧最高频，`{bettors,watchers}` communal 聚合计数）。新族 L4 必须先 grep `bettingStats`/`stats` 帧：有则建 **L4.6 BETSTATS**（见下，直转或合并我方聚合计数；**注意是聚合计数、非 per-player，不能注单玩家注**）；无则跳过。winnersList 多为 A 直转广播（社交瀑布需合并我方中奖者按下方 WINNERS 注）。

## L4.1 — PAYOUT

**产物**：`games/<gametype>/payout.go` + `payout_test.go`（可与 odds 同目录）

**分析输入**：L1 PAYOUT_MODEL（赔付模型）/ L2 RULES（三路 cap 字段）/ L3 SETTLE 调用接口 / `roundDetail/<rid>.json`（`.data.data.participants[].bets[]{code,stake,payout}` 真样本反推公式）

**实现内容**：
- 纯函数派彩 — **含本金，公式因族而异**：roulette `amount×(odds+1)`（号码集→odds）；game show 押中 segment `stake×<seg>Multiplier`、未中=0（倍率来自结算帧 `<seg>Multipliers`/`totalMultiplier`）；baccarat 牌型赔率。**从 roundDetail json 反推，禁假设 odds 制**（IceFishing 实证 `IF_Leaf1 stake2000→payout4000`）。⚠️ betCode 双命名空间（下注帧 `Leaf1` vs roundDetail `IF_Leaf1`）反推前先映射。
- **G3 三路 cap min（用户级，非单注级）**：A=`maxMultiplier × 用户当局总下注本金`（game show maxMultiplier 在 bonus 帧实证，如 200/500）；B=`Convert(euro_table_payout_max,"EUR",currency)`；C=`table_payout_max`/`payout_limit`（本币硬封顶）；最终 `min(A,B,C)`
- `handlers.LookupRoundCap` + `handlers.CapUserPayout` 等比缩放（C8）+ `MCap=true`
- **currencyMult 进制**：派彩金额按币种进制
- `betCodeDescription(bc)` 本地化（H6，history/报表用）

**B5 验收**：build/vet/test 过 + `payout_test` ≥ 4 个 roundDetail/capture 真样本 + 三路 cap 分开断言（用户级非单注）

**下游**：SETTLE 调用

---

## L4.2 — HISTORY_RECENT（recentResults + 孤儿局恢复）

**产物**：`games/<gametype>/<gametype>core/recent_results.go` + `reconcile.go`

> EVO 走势统计在协议内（roulette `recentResults` / game show `<gt>.spinHistory` 帧），无 PP 的 /stats 端点 + 启动回填。但需缓存最新走势帧供新连接回放 + 孤儿局恢复。

**分析输入**：L2 MODELS（走势帧 struct）/ `message-nobet.txt` 走势帧（roulette `recentResults` / game show `<gt>.spinHistory{newResult,results[],version}`）/ 模板 `roulettecore/{recent_results,reconcile}.go`

**实现内容**：
- **`recent_results.go`**：缓存最新走势帧（roulette `recentResults` / game show `<gt>.spinHistory`，每局重发的全量快照，**必缓存并新连接回放**，否则走势板空白 — 同 PP J2 全量快照帧），直转广播
- **`reconcile.go`（孤儿局恢复，EVO 自愈）**：上游漏发 GAME_RESOLVED / 进程重启错过开奖时，从 `recentResults`（含历史开奖号）兜底补结算未结算局。`reconcileFromRecentResults` / `reconcileOnNewRound`：新局开窗时检查上一局是否已结算，未结算则用 recentResults 的结果补 OnGameResult。
  - 🔴 **fail-closed**：补结算同样走 `GetRedisUserBets(requireAccepted=true)` + `hasSuccessfulBetDebit`（不能凭 recentResults 给没扣款的注派彩）

**B5 验收**：build/vet/test 过 + `reconcile_test` 覆盖"漏 GAME_RESOLVED → 新局用 recentResults 补结算" + recentResults 缓存回放

**下游**：UPSTREAM 接入（recentResults 缓存 + 新局 reconcile 钩子）

---

## L4.3 — HISTORY_DETAIL（玩家历史详情）

**产物**：机台 `history.go`（若通用 `gateway/history_api.go` 不够覆盖新族 detail shape）+ 确认 SETTLE 落盘字段齐

> EVO history 是 **JSON**（非 PP cgibin XML），玩家"我的历史"走 `gateway/history_api.go`（通用：token→玩家→按 vendor_type='evo' filter→按时区分组）+ `/game/{id}` 详情。⚠️ **数据源结构**：列表/详情字段在 `gameDetail.txt .data`（单对象，含 `gameType/status/startedAt` + **`render`=server-rendered HTML 详情串**，非逐字段结构化）；**结构化结算体在 `roundDetail/<rid>.json .data.data`**（`participants[].bets[].{code,stake,payout}` + `result`）。逐字段对账以 roundDetail 为准。

**分析输入**：
- **`tmp-evo/<dir>/gameDetail.txt` 真 JSON**（`.data` 单对象；含 `render` HTML）
- `roundDetail/<rid>.json`（`.data.data` 单局结算体 participants/bets/result）
- 通用 `gateway/history_api.go` + `history_render.go` 看新族 detail 是否需扩展
- L3 SETTLE 落盘字段（b_game_rounds + b_game_transactions）

**实现内容**：
- 核对通用 history 接口能否渲染本族详情；不够则补 per-family detail 映射（结构化 JSON，**禁 raw 字符串拼**）
- **持久化字段完整性**（L3 SETTLE 配合）：`b_game_rounds.{dealer_name, round_id, game_type, extra, result}` + `b_game_transactions.{description=BetCodeDescription(bc), currency=本局会话币种, stake, payout, settled_at, max_capped}` 完整落（H3）
- **投注类型 vs 开奖结果各自独立逐笔保存**（H/J7：bet.description 是下注点、result 是开奖，绝不混用）

**B5 验收**：build/vet/test 过 + `history_test` 用真 `gameDetail.txt` JSON 做 fixture 断言关键字段 + 投注类型/开奖结果分离

**下游**：API 层调用（通用 handler，与 instance 解耦）

---

## L4.4 — REPORT_PAGE（商户报表前端页）

**产物**：`server/game/evo/client/reports/<裸 evo_table_id>/index.html`（自包含一桌一份）

> 后端只出通用 JSON（`gateway/report_api.go` 的 `/gameHistory/report`，所有机台共用，无 per-machine Go）。
> 🔴 **一机台一份、不共用、不共享 `_assets`**；即便同 gameType 多桌也各写各的（同 PP report 重构铁律）。

**前置依赖**：L3 UPSTREAM `archiveCurrentRaw` 落 `b_game_rounds.messages`（漏 = messages 空）+ L3 SETTLE 落 round/extra。

**分析输入**：
- **`roundDetail/<rid>.html`** —— 玩家可直开报表页基线 DOM（视觉对照）
- **`roundDetail/<rid>.json`** —— 结构化结算体（**EVO 比 PP 多这份，报表字段直接对照，比 PP 只有 html 更好对**）
- 既有 `server/game/evo/client/reports/vctlz20yfnmp1ylr/index.html`（roulette 范例）+ `_assets/{report.css,report.js,index.template.html}`（公共模板参考，但新桌内联自包含不引用）

**实现内容**：自包含 HTML：内联 `<style>` + 内联 `<script>`（取 query token → `fetch('/gameHistory/report?token=...')` → 渲染 1:1 DOM，对照 roundDetail）。**结果可视化按族**：roulette Game Result 行用 SVG 指示牌（邻号弧+落点居中红描边，roulette 专属）；game show 按 roundDetail 的 segment+倍率盘+bonus 结构复刻（**无号码弧 SVG**）。

**B5 验收**：`node --check`（内联 JS 拆出）语法过 + 用真 `/gameHistory/report` JSON mock fetch 视觉对照 `roundDetail/<rid>.html` ≥ 90%（roulette 含 SVG；game show 按本族结果元素）+ 一桌一份不共用 + 前置（messages 非空 / round·extra 齐）满足

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
- **铁律 reminder**：G3 三路 cap min 用户级 / currencyMult 进制 / H6 描述本地化 / 报表一桌一份不共用 / per-currency 配置必种 / reconcile fail-closed
