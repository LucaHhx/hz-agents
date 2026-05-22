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

## L4.3 — WINNERS

**产物**：`winners_broadcast.go`

**分析输入**：
- L2 MODELS（winners struct）
- `tmp/<tid>/message.txt` winners 真帧（含外渠道真实玩家结构）
- main.js setWinners 客户端渲染逻辑

**实现内容**：
- **B2 winners pass 透传**（默认；known-pitfalls B2 修正版，**不是丢弃**）
- 可选 rewrite 合并模式：`CollectOurWinners` 用我方真实 userId/screenName 替换 ppc<timestamp>
- `ConvertWinnersByCurrency`（按观众币种）
- 不在我方的 ppc id → 保留原条目（PP 全网真实玩家）

**B5 验收**：build/vet/test 过 + winners_test 覆盖 pass + rewrite 两种模式

**下游**：UPSTREAM dispatch 调用

---

## L4.4 — STATS_API

**产物**：`server/game/pp/internal/gateway/api/api_stats_<gametype>.go`

**分析输入**：
- L3 SETTLE writer 写入的 record 字段
- `tmp/<tid>/statisticHistory.txt` 真 records
- **main.js `Object.keys(tf)` 客户端实测 key**（如 megawheel 是 `["1","2",..."40"]` 数字字符串，非 `"One"..."Forty"`）
- 既有 api_stats.go 路由分支机制

**实现内容**：
- 在既有 `api_stats.go` 加 gametype 分支（不破坏其他 gametype）
- 从 Redis `pp:stat_history:http:<tableCode>` 拉 records
- 按 `gameResult` 字段累计 bucket 命中率 / 总局数 × 100
- 响应 shape：`{"errorCode":"0","betResultStats":{<key>:<pct>,...}}`
- **key 严格按 main.js 实测**（数字字符串还是命名，确认后才写）
- **不带 data 包装**（与 roulette 形态显著不同；按 main.js 实测调整）

**B5 验收**：build/vet/test 过 + api_stats_<gametype>_test 覆盖 1-2 case（构造 Redis 假数据 → 调 handler → 断言 shape）

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
- B2 winners pass 透传（不丢）
- B7 betstats 完整 envelope
- C8 payout cap
- G2/G3 三路 cap min + 用户级（非单注）
- H6 BetCode Description 本地化
