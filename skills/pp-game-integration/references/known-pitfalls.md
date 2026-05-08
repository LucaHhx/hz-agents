# 共性陷阱（铁律 — 单一权威来源）

PP 对接横跨各机台的共性陷阱。**所有机台通用**；每条都源自实际对接 + codex 审查的真实发现。**对接前必读**。

具体某机台的特殊字段命名 / 协议偏差 → 写到 `<repo>/docs/integration-experience/<gametype>/<tableId>.md`，不在本文件。

## 目录

- [A. 信息源边界](#a-信息源边界)
- [B. 协议处理铁律](#b-协议处理铁律)
- [C. 资金路径 fail-closed](#c-资金路径-fail-closed)
- [D. 静默错误清单（必加 zap log）](#d-静默错误清单必加-zap-log)
- [E. 结构序列化铁律](#e-结构序列化铁律)
- [F. 测试 / 规范铁律](#f-测试--规范铁律)
- [G. 客户端-后端一致性](#g-客户端-后端一致性)
- [H. 游戏记录展示一致性](#h-游戏记录展示一致性)

---

## A. 信息源边界

### A1. 不参考老项目 ppgame
`/Users/luca/work/ppgame`（Node.js）禁止作为协议事实参考。所有协议字段**只**从 main.js 字面量 + capture 实际样本得出。

### A2. translations-help 不是单机台事实
`<gametype>.json` 是**游戏类型最大规则集**。单机台只启用其中一个子集。
- 赔率以本机台 `gameresult` 字段实际值为准
- 激活 betCode 集合以 `tableConfig` + `disablesidebets` 推送 + 客户端 UI 渲染为准
- 限额阈值以 `tableConfig.params` 或上游推送为准

### A3. 区分开发资料 vs 运行时配置
**开发资料**（手动从 main.js / capture / lobby 提取）：gameType / lpbet 格式 / betCode 表 / 错误码 / 上下游事件 / capture 帧
**运行时配置**（InstanceManager 启动自动拉，**不**手动准备）：chip_amounts / ws_address / placeBetType / `b_tables.config` 全 PP tableConfig

---

## B. 协议处理铁律

### B1. tableId 字节级替换（必须）
`HandleUpstream` 入口必须把 PPTableID 替换为 `ctx.TableID`：
```go
raw = bytes.ReplaceAll(raw, []byte(ctx.PPTableID), []byte(ctx.TableID))
```
**不替换的症状**：客户端 `subscribe` channel 校验失败、`isTableSubscribed` 永远 false、10 秒后断连。

### B2. 上游 winners 必须完全丢弃 PP 测试账号视角
上游 `winner[]` 是 PP 测试账号视角。**完全丢弃** `upstream.Winner`，只复用 `gId/seq/table` 元信息。**不要**写"同 userId 用我方覆盖"这种合并逻辑（会泄露 PP 视角虚假用户）。

### B3. 多事件单帧顺序保证
Go map 遍历不保证顺序 — 必须 `orderKeysByPriority` 显式排序。优先级：
```
gameresult > winners > betsclosed > betsclosingsoon > betsopen > 其他
```
单帧多 key 时按 verdict 单独保留/丢弃，**不能**"一个 drop 整帧 drop"误丢透传内容。

### B4. baccarat 系列不发 winningBetCodes / betSpotWin
baccarat 客户端 main.js 对这两个字符串**0 命中** → 服务端**不合成**（roulette 系列才需要）。
**新对接前必须 grep main.js 验证**该机台是否需要这两类帧。

### B5. lpbet `gm` 字段动态拼接
形式：`${session.gametype}_${desktop|mobile}`。

main.js 出现的 `<gametype>_desktop` 字面量可能是 `pbdealnow` / `playerUnsub` / `playerCardPeel` 等**特殊命令**的固定值，**不是 lpbet 的 gm**。新机台 grep 时必须区分调用上下文。

### B6. ping 单/双引号兼容
PP 客户端历史踩坑：部分老版本用单引号发 ping。`extractXMLAttr` 必须先试双引号再试单引号，单测要覆盖两种。

### B7. EnrichBetstats 返回完整 envelope
`events.EnrichBetstats(...)` 返回 `{"betstats":{...}}` **整 envelope**，不是内层。rewrite 链路必须 `unwrapEnvelope` 解出内层后存到 `dispatchAction.data`，否则会变成 `{"betstats":{"betstats":{...}}}` 双信封。

### B8. Bonus 边注主投注前置
押 PlayerBonus / BankerBonus / EitherBonus 等"奖励边注"通常须先押对应主投注。
- 押 PlayerBonus（如 betCode 12）→ 同局必须押 Player（betCode 0），否则返 `1059 PlayerBonusBetWithoutMainBet`
- 押 BankerBonus（如 betCode 13）→ 同局必须押 Banker（betCode 1），否则返 `1060 BankerBonusBetWithoutMainBet`

具体 betCode 数值 / 错误码命名按字典实际值；本铁律**只规定模式**。

### B9. BetValidationError 字段必须含 7 个
main.js BetValidationError process 读取 `betCode/code/extendedErrorCode/optExtErrorCode/optExtErrorMsg/category/severity` 共 7 个字段。后 4 个虽 omitempty 但商户错误信息透传必须能填入。
**只**写前 3 个字段时商户错误信息无法透传给客户端 toast。

### B10. switch 帧必须含 wsAddress + httpAddress
main.js Switch.process: `e&&"string"==typeof e.httpAddress&&"string"==typeof e.wsAddress` 才触发 `setGameServer`。**两个字段都是 string** 才生效；只写 `wsAddress` 客户端不切上游。

### B11. FreeChip / 其他未实现路径必须 fail-closed 显式拒绝
客户端发送的 `<bet bcode="..." bettype="FB" ...>` 等 FreeChip 子节点，如果服务端未实现该路径：
- **禁止**静默跳过（→ parseBetTags 返回空 → `len(bets)==0` → 客户端误以为下注成功）
- **必须**显式发 `betValidationError` 拒绝（如 `5000 FreeChipUnknownError`）+ command err

---

## C. 资金路径 fail-closed

### C1. CanBet Redis 异常返回 false
`bet_window.go:CanBet` 在 Redis 错误时**必须返回 false**（铁律：宁拒不放）。CheckBet hook 应**双重 fail-closed**：检查内存窗口 + Redis 窗口，任一异常即拒。

### C2. applyBet fail-closed
`ctx.BetSvc == nil || ctx.UserID == "" || gameID == ""` 时**返回明确错误**，不能静默成功（fail-open = 客户端误以为下注成功但 Redis 没落）。

### C3. 空 lpbet 清 Redis 必须先窗口校验
玩家发空 lpbet（取消下注）→ 必须先 `CheckBet` 校验窗口 → 通过才清 Redis。**关窗后撤单 = 资金风险**（旧注已发商户 /bet，撤了客户端不显示但实际扣款）。

### C4. 整批拒清 Redis 仅限非窗口类
整批 lpbet 校验失败时清 Redis 同步状态（避免"界面已撤、实际扣款"）。**但**窗口类拒绝（`ErrBetNotOnTime`）**不**清 — 否则等同 C3 的关窗后撤单。

### C5. BC Atoi 错误显式拒绝
Redis 中非法 BC 字符串解析失败时**不能** `_ = err`（会按 0 = Player 错赔）。必须显式跳过该投注 + ERROR log。

### C6. bets JSON 解析失败跳过用户
Redis hash 字段 `bets` JSON 解析失败时**不能**仍 append 空 BetData（按 0 金额结算 + 清 key 丢失重试入口）。必须 `continue` 跳过该用户。

### C7. GetRedisUserBets 故障 fail-closed
Redis SCAN/HGetAll 失败时**不能**返回 nil 当作"无下注"。必须返回 error，OnGameResult **不调** OnRoundSettled，保留未结算状态 + ERROR log。

### C8. payout_cap 必须接入
per-user round payout max + `handlers.CapUserPayout` 等比缩放每条 Payout>0 的 txn + 设 `MCap=true`。

### C9. context 必须超时
Redis SCAN/HGetAll 用 `context.WithTimeout(... 5s)` 而非 `context.Background()`。

---

## D. 静默错误清单（必加 zap log）

业务关键路径**禁止** `_ = err`（违反 `feedback_no_silent_fallback.md`）。下列必加 `global.HAB_LOG.Error/Warn` + `zap.Error(err)`：

- `OnGameResult` 整体失败
- `UpsertRoundWithDealer` 失败（b_game_rounds 写入）
- `SettleUsersSeamless` 失败（商户 /result）
- `json.Unmarshal(winners)` / `json.Unmarshal(bets in Redis)` 失败
- `OnMerchantBetResult` 早期 return（fail-closed log）
- `AssertActiveSession` 失败
- `CollectOurWinners` 失败
- `LookupRoundPayoutMax` 失败（降级为不封顶时 warn）

---

## E. 结构序列化铁律

**禁止 raw 字符串拼接 JSON**（违反 `feedback_struct_only.md`）。所有 JSON 帧必须 struct + `json.Marshal`：

```go
// ❌ 错
data := []byte(`{"session":{"session":"offline"}}`)

// ✅ 对
env := EnvelopeSession{Session: JSONSession{Session: "offline"}}
data, _ := json.Marshal(env)
```

例外：XML 拼接 helper（lpbet / ping / pong / command）允许字符串模板（XML 不像 JSON 有标准库）。

---

## F. 测试 / 规范铁律

### F1. payout 单测必须覆盖 capture 真实样本
- ≥ 4 个不同结果场景的 capture 样本
- ≥ 1 项边注断言
- 必须显式断言**不参与结算的字段**（如 baccarat 的 bnc/pnc/bg/sm；其他类型机台类似）值无关结果

### F2. 字典 parity 测试必备
BC* 数量 / GR 反查表 / 错误码值 / 桌台元数据全部 vs main.js 抽取。任何修改触发断言失败。

### F3. race detector
`go test -race -count=3 ./...` 跑 3 次确认无 race。

### F4. policy-pr 硬上限
- 单文件 ≤ 500 行
- 控制流嵌套 ≤ 3 层
- 超 → 自由拆（按职责，参考既有 commit 风格）

### F5. CLAUDE.md 注释最少铁律
- 默认不写注释；只在 WHY 非显然时写**一行**
- 禁止解释 WHAT
- 禁止引用当前任务 / 调用者 / 历史 commit
- 禁止写 worker 编号 / TODO 占位

### F6. 关联项目禁忌
`/Users/luca/work/ppgame` 老项目**绝对禁止**作为代码 / 协议参考。代码或注释里**不允许**残留指向老项目的引用。

---

## G. 客户端-后端一致性

**核心原则**：客户端展示给玩家的每一个**约束类**数值/规则（限额、封顶、赔率、合法投注），后端必须用同一字段、同一来源、同一兜底默认值做 enforce。两边对不上 = 玩家看到一个承诺、后端按另一个承诺放行 = 资金风险或客诉。

### G1. 对接前必做：客户端展示项与后端 enforce 项交叉审查

每个机台 Phase 4（协议设计）阶段必须列一张表，**逐项**核对：

| 客户端面板/弹窗显示项 | 数据来源（main.js 字段） | 后端是否 enforce | 后端字段 | 缺失/不一致 |
|---|---|---|---|---|
| 6 行 / N 行单注 min/max | `*_bet_min` / `*_bet_max` | ❓ | 同字段 | 有 → P0 |
| 总投注台限 | `table_bet_min/max_limit` | ❓ | 同字段 | 有 → P0 |
| "X 倍 / €Y" 最高支付 | `maxMultiplier` / `euro_table_payout_max` | ❓ | 同字段 | 有 → P0 |
| 单注派彩 cap | `payout_bet_max_limit` | ❓ | 同字段 | 有 → P1 |
| 赔率列字面量 | 客户端硬编码 | n/a | n/a | n/a |
| 翻译文案 | translations-ui 翻译键 | n/a | n/a | n/a |

**禁止**：只看翻译键就当"标签问题"跳过；只要数值由 tableConfig.params 决定，就一定是后端 enforce 范畴。

### G2. 后端默认值必须与客户端 fallback 完全一致

客户端 main.js 大量 `?? <default>` / `|| <default>` 兜底（举例）：
```js
u?.maxMultiplier ?? 2e4              // 缺则 20000
u?.euroTablePayoutMax ?? 5e5         // 缺则 500000
parseFloat(e.one_bet_min) || 0.2     // 缺则 0.2 (EUR)
parseFloat(e.one_bet_max) || 1000    // 缺则 1000 (EUR)
```

后端 helper / 校验入口必须 export 同名常量并使用同值：
```go
const (
    DefaultMaxMultiplier      = 20000.0  // 与 main.js `?? 2e4` 一致
    DefaultEuroTablePayoutMax = 500000.0 // 与 main.js `?? 5e5` 一致
)
```

**禁止**："缺配置 = 不封顶 / 不校验"——这等价于客户端给玩家承诺一个上限，后端把上限当 +∞ 放行。

### G3. payout cap 必须按客户端文案语义"取先到者最小"

客户端文案 `MAXIMUM_PAYOUT_V3` = "**X 倍 或 €Y，以先达到者为准**"，**双条件取最小**：
- A. 倍数 cap：`maxMultiplier × 该用户单局总下注本金`
- B. EUR 等值 cap：`Convert(euro_table_payout_max, "EUR", currency)`
- C. 本币硬封顶（可选）：`table_payout_max`

后端最终 cap = `min(A, B, C)`，缺 A/B 时用 G2 的默认值，缺 C 时忽略不引入额外默认。

**禁止**：只读 `table_payout_max` 一个字段（这是 PP 给运营预算用的本币硬限，**不**等于客户端那条"€500,000 取先到者"的承诺）。

### G4. EUR 换算依赖：`b_currency_rates` 必须含 EUR 行

任何 EUR 等值 cap 都需要 `configCache.Default.CurrencyRates.Convert(amount, "EUR", playerCurrency)`：
- `b_currency_rates` 必须有 `currency='EUR'` 且 `enabled=1` 的行（`rate` 语义见 `service/configCache/caches/currency_rate_cache.go:131`：1 USD = rate[CCY] CCY）
- 同时核查所有玩家可能用到的币种 / USDT 等稳定币是否齐全
- 换算失败必须 **fail-closed**（拒绝放行结算/下注），不能默认"不封顶"

部署 / 运营 checklist SQL：
```sql
-- 玩家币种是否都有汇率行
SELECT DISTINCT g.currency
FROM b_game_users g
LEFT JOIN b_currency_rates r ON r.currency = g.currency AND r.enabled = 1
WHERE r.id IS NULL;
```

### G5. 客户端硬编码 vs tableConfig 动态值的边界判定

只在 main.js 是字面量、与 tableConfig 无关的，才是"客户端硬编码"，可不进后端校验：
- 行结构 / 行序（`name:1,2,5,...`）
- 静态赔率字面量（`"1:1"` / `"2:1"`）
- 翻译键（`<T tk="BUBBLE_SURPRISE"/>` 等）
- "奖励游戏" 这类静态标签（`BONUS_GAME` 翻译键）

只要数值/限额来自 `r.params.xxx`，就必须做 G1 审查。

### G6. tableConfig 同步链路 + 配置发布双校验

新机台首次同步落 `b_table_currency_configs` 时（`api/v1/business/vendor_sync_currency.go::extractTableIndependentFields`），按 G1 列表对**关键限额字段**做 audit log（不要硬性失败，避免运营换币种时阻塞）：
```go
auditMissing := []string{}
for _, k := range []string{"maxMultiplier", "euro_table_payout_max", "table_payout_max",
    "table_bet_min_limit", "table_bet_max_limit"} {
    if params[k] == nil {
        auditMissing = append(auditMissing, k)
    }
}
if len(auditMissing) > 0 {
    global.HAB_LOG.Warn("tableConfig 缺关键限额字段，将走默认值兜底",
        zap.String("tableID", tableCode), zap.String("currency", ccy),
        zap.Strings("missing", auditMissing))
}
```

后台"发布"按钮触发 `configCache.Publish` 时同样过一遍 audit，便于运营盘点。

### G7. 经验文档必须列"客户端-后端一致性矩阵"

`docs/integration-experience/<gametype>/<tableId>.md` 第 5 节"协议处理决策表"之外，**新增专门一节**列 G1 的交叉审查表（具体字段名 + 是否 enforce + 默认值），便于后续机台对接时复制粘贴并核对差异。

---

## H. 游戏记录展示一致性

**核心原则**：玩家投注后从 PP 客户端打开"我的历史 / 单局详情 / 大势趋势 / 个人余额"等任何记录类入口，渲染所需的数据全部由后端提供。任意字段缺失 → 玩家弹窗空白 / 渲染报错 / 看到错误金额 → 客诉。

新机台 Phase 4（协议设计）必须按下列流程审查"展示链路 ↔ 落盘链路"。

### H1. 对接前必查：客户端调了哪些 history endpoint

每个机台 main.js 都要 grep 一遍：

```bash
grep -oE "/api/[a-zA-Z0-9/_-]*[Hh]istory[a-zA-Z0-9/_-]*|/api/ui/statisticHistory|fetchRoundHistory|fetchBonusHistory|/cgibin/[a-zA-Z/.]*audit[a-zA-Z/.]*" \
  server/game/pp/client/apps/<gametype>/<ver>/main.js | sort -u
```

观察到的 PP 标准接口（按出现频率）：

| 客户端调用 | 用途 | 后端 handler 现状 |
|---|---|---|
| `/api/ui/history/summary` | 玩家"我的历史"主页（按日盈亏汇总） | `api_history.go::GameHistorySummary` 已实现（聚合 `b_game_transactions`）|
| `/api/ui/history/dayWise?date=M/D/YYYY` | 玩家某天所有局列表 | `api_history.go::GameHistoryDayWise` 已实现 |
| `/cgibin/usermanagement/audit/game.jsp?game_id=X&format=xml` | 单局详情弹窗（"详情"按钮，**XML 格式**） | `api_history.go::GameHistoryGameDetail` 已实现（`b_game_rounds` + `b_game_transactions` + 机台专属解析器）|
| `/api/ui/statisticHistory?tableId=X&numberOfGames=500` | 机台公开开奖序列（连接时下推 + 客户端 fetch） | `api_history.go::GameStatisticHistory` 透传 Redis http key |
| `/api/fetchRoundHistory` | 玩家最近 N 局简表 | ⚠️ `api_proxy.go:65` 兜底返回 `{"rounds":[]}` —— **未实现** |
| `/api/v2/fetchRoundHistoryByWS` | WS 推送最近局 | ⚠️ 同上兜底空 |
| `/api/.../bonusHistory` 等机台特殊 | 奖励局历史 | 视机台而定，须逐个 grep |

**首次接触新 gametype 时必须**：列出客户端实际调到的 endpoint → 对照后端是否实现 → 标出"哪些走兜底空数据"。**禁止**默认"通用历史接口已经够用"。

### H2. `b_game_rounds` 必须落盘机台特有结构化字段

PP 客户端单局详情弹窗按 gameType 渲染不同节点（XML `<sweetbonanza>` / `<rouletteDetails>` / 等），渲染依赖 `round.Extra`（结构化 JSON）+ `round.RawData`（gameresult 整帧兜底）：

```go
round := gameData.BGameRounds{
    GameId:     gr.ID, TableId: ctx.TableID, GameType: ctx.GameType,
    Variant:    TableID,
    Result:     gr.ResultSummary(),     // 人类可读，列表展示
    ResultCode: gr.RC,                  // 结构化结果码
    BonusType:  mapBonusType(&gr),      // candy_drop / sweet_spins / ...
    Multiplier: parseFloat(gr.Mul, 1),  // 本局倍率
    Extra: gtype.Map[string, any]{      // **机台专属字段必须落这里**
        "gr": gr.GR, "payouts": ..., "sbmul": ..., 
    },
    RawData:   string(ctx.Raw),         // 老局兜底解析
    SettledAt: now,
}
```

**禁止**：只写 `Result`/`ResultCode`，把机台特殊字段（如 sweetbonanza 的 `multipliers` / `payouts` / `gr`）只留在 RawData 里。RawData 兜底解析路径性能差且有版本漂移风险——新数据必须走 Extra。

### H3. `b_game_transactions` 必须填齐结算冻结字段

历史 list 列依赖 transactions 聚合，每行必填：

```go
txn := gameData.BGameTransactions{
    UserId:         rBet.UserId,
    GameId:         gameId,
    TableId:        tableId,
    BetCode:        b.BC,
    BetAmount:      b.Amount,
    Description:    betCodeDescription(b.BC),  // ⚠️ 必须按 gameType 本地化（H6）
    Result:         resultStr,
    Payout:         payout,
    NetCash:        payout - b.Amount,
    IsWin:          &isWin,
    TableLabel:     rBet.TableLabel,
    GameType:       rBet.GameType,
    SettledAt:      &now,
    Currency:       rBet.Currency,             // ⚠️ 本局会话币种（issue #66/#90）—— 不是 user.Currency
    BoosterEnabled: rBet.Booster,              // 机台特殊状态（sweetbonanza Sugar Bomb）
    Stake:          stake,                     // 该用户本局总下注（含 Booster 费）
    GameNetCash:    gameNetCash,               // 本局总盈亏（用户级单值）
    MaxCapped:      mCap,                      // issue #64：是否触发封顶
}
```

**禁止**：
- 用 `user.Currency`（用户全局默认）代替 `rBet.Currency`（本局会话币种）—— 老用户换币种重玩会按旧币种计算
- 不写 `Stake` / `GameNetCash` / `BalanceAfter`，让 history dayWise 依赖某条 txn 兜底
- `SettledAt` 用 `now()` 而不是结算事件时间—— history 列表时间排序错位

### H4. history 详情 XML 节点必须严格匹配客户端解析期望

PP 客户端 history 详情面板按 XML 节点路径直接解构（main.js 里 `<gametype>Details = additional.<gametype>` 等），节点名 / 字段名 / 大小写**任意一个不一致**就渲染失败。

每个 gameType 必须有对应 XML struct + parser：

```go
// server/game/pp/runtime/history.go
type SweetBonanzaXML struct {
    BubbleSurprise      string   `xml:"bubbleSurprise"`        // ⚠️ 大小写敏感
    GR                  string   `xml:"gr"`
    Multipliers         []string `xml:"multipliers,omitempty"` // 多个同名节点
    Payout              string   `xml:"payout"`
    RC                  string   `xml:"rc"`
    SBBooster           string   `xml:"sbBooster"`
    SugarBomb           string   `xml:"sugarBomb"`
    SugarBombBet        string   `xml:"sugarBombBet"`
    TotalAnteMultiplier string   `xml:"totalAnteMultiplier"`
    TotalMultiplier     string   `xml:"totalMultiplier"`
}
```

新对接 gameType 时必须 grep main.js 确认全部字段名：

```bash
# 假设 gametype = sweetbonanza，找客户端从 history XML 读哪些字段
grep -oE "additional\.<gametype>\.[a-zA-Z]+|<gametype>Details\.[a-zA-Z]+" main.js
# 然后对照本机台 XML struct 是否齐全
```

### H5. `b_game_rounds.StartedAt` 必须在 betsopen 时刻写入

history 详情 XML 的 `gameStartTimestamp` 字段要求是**本局开始**而不是结算时刻。结算路径写 `SettledAt`，**额外**还要在 betsopen 事件来时写 `StartedAt`：

```go
// betsopen 时
handlers.UpsertRoundStartedAt(tableID, gameId, time.Now())
```

**禁止**：只在 settle 写 round → `StartedAt` 永远 NULL → history XML 兜底用 `SettledAt.UnixMilli()` → 客户端展示的"开始时间"实际是结算时间，会比真实开始晚 30s+。

### H6. BetCode Description 本地化

history list / 详情都展示 `betCodeDescription(bc)`，必须按 gameType 维护映射：

```go
// 每个机台 payout.go
func betCodeDescription(bc string) string {
    descs := map[string]string{
        "101": "One (1)", "102": "Two (2)", ...
    }
    if d, ok := descs[bc]; ok { return d }
    return "BC" + bc  // 兜底，但**不应**走到这里
}
```

`history_service.go::normalizeDescription(gameType, ...)` 还会按 gameType 做二次映射（如 baccarat 的"庄家"/"闲家"）。新机台必须同步加一段。

**禁止**：直接落 `BC101` 这种 raw 字符串到 DB → 历史详情玩家看到一堆数字号码而不是"押 1 / 押 2 / 泡泡惊喜"。

### H7. `b_game_user_actions` 落盘玩家局内决策

机台有"玩家选择"环节（sweetbonanza Candy Drop 选球 / blackjack hit/stand / roulette decision 等）必须把每个用户的选择落盘，否则 history 详情没法还原"该用户当时选了什么"：

```go
// 玩家做决策时
useraction.Record(useraction.Event{
    GameId: gameId, UserId: userId, ActionType: "candy_drop_decision",
    Payload: map[string]any{"dec": choiceIndex},
})
```

history XML 解析时反查（issue #55 即是修复 sweetbonanza Candy Drop 倍率展示用的是 3 颗糖求和而不是玩家选中的那颗）：

```go
dec := lookupCandyDropDecision(gameId, userId)
payout := payouts[dec]  // 玩家实际选中的倍率
```

**禁止**：把"玩家选择"只落到 RedisBetData 然后让 settle 后丢失 → history 详情只能展示"理论求和"而不是"我选了哪颗"。

### H8. `/api/fetchRoundHistory` 兜底空数组的影响审查

兜底返回 `{"rounds":[]}` 是**未实现状态**，新机台必须 grep main.js 确认：

```bash
grep "fetchRoundHistory" server/game/pp/client/apps/<gametype>/<ver>/main.js
```

如果客户端有"Recent rounds widget"/ 局间侧边栏 / 投注前提示等功能依赖此接口 → **空数组 = 玩家看到空列表**。要么实现接口（聚合 transactions），要么文档明确"该机台 fetchRoundHistory 客户端不渲染影响 UX 可接受"。

### H9. roulette 类必须输出全量默认 `<rouletteDetails>` 节点

参考 `history.go::RouletteXML` 注释：客户端解析 `g ?? u`（u 是默认值对象），如果 server 不输出 `<rouletteDetails>` 节点，部分衍生判断会走空分支报错。**即使所有字段都是默认值**也必须输出全量节点：

```go
gameEntry.RouletteDetails = newCrystalRouletteDetails()  // 全 "false" / "0.0"
gameEntry.TableVariant = "crystalroulette"
```

类似规则适用于其他 gameType 的"详情容器节点"——只要客户端 main.js 有 `additional.<gametype>?? defaultValue` 解构，server 就必须输出对应节点（即使字段全空）。

### H10. 开发期通过代码分析验证，不抓样本

机台开发阶段（Phase 4-7）**没有真实玩家数据样本可抓**，更不允许去线上 / 真实 PP 环境抓玩家局做样本。开发期验证只能基于：

1. **客户端 main.js grep**：拿到客户端期望的 XML 节点路径 / 字段名 / 解析回退分支
2. **后端代码核对**：XML struct tag、parser 函数、settle 落盘字段
3. **单元测试**：用构造的假 round 数据走 parser → 断言输出 XML 包含全部期望字段
4. **capture 样本**（如有）：Phase 2 录到的 capture 是 PP 真线下行帧，可作为 round.RawData 落盘格式参考；但 capture **不含玩家自己的 history XML 响应**

新机台对接时关于 history XML 的验证清单：

```markdown
- [ ] grep main.js 列出全部 `additional.<gametype>.<field>` 解析路径
- [ ] 对照后端 XML struct 字段是否齐全（节点名 + 字段大小写）
- [ ] settle 路径 round.Extra 是否落齐了 parser 需要的字段
- [ ] parser 函数有 Extra → RawData 兜底链路
- [ ] 单测覆盖每种 BonusType 局型（普通赢 / 各 bonus / 边界值）
```

**禁止**：在经验文档里写"待补：抓 N 种局型样本端到端验证"——这种验证不属于开发阶段范畴，应当由测试 / 灰度 / 上线后真实玩家局触发后**作为修 bug 任务**单独立项，不阻塞机台对接 PR 合并。

QA / 灰度阶段如果发现详情弹窗某节点空白 / 渲染失败 → 抓那一局 XML 样本 + 创建 issue + 走标准修 bug 流程，不回填到经验文档"待补样本"列表。

### H11. SweetBonanza Candy Drop 选球 + Booster 状态完整链路

具体到 sweetbonanza pbvzrfk1fyft4dwe，必须保证下列字段在结算时全部冻结到 DB（缺一不可）：

| 字段 | 写入位置 | 取值 | 历史详情用途 |
|---|---|---|---|
| `b_game_rounds.Extra.gr` | settle.go::buildSBExtra | sbz_gr.GR | XML `<gr>` |
| `b_game_rounds.Extra.payouts` | 同上 | gr.Payout 拆分 | Candy Drop XML `<payout>` |
| `b_game_rounds.Extra.sbmul` | 同上 | gr.SBMul 拆分 | XML `<multipliers>` 多节点 |
| `b_game_rounds.Multiplier` | settle.go round 构造 | gr.Mul | XML `<totalMultiplier>` |
| `b_game_rounds.ResultCode` | 同上 | gr.RC | Candy Drop 识别（"3"/"6"） |
| `b_game_rounds.BonusType` | mapSBBonusType(&gr) | sugar_bomb / bubble_surprise / ... | XML `<sugarBomb>` / `<bubbleSurprise>` |
| `b_game_transactions.BoosterEnabled` | applyBet → CalcSettlement | rBet.Booster | XML `<sugarBombBet>` / `<totalAnteMultiplier>` 计算 |
| `b_game_user_actions{action=candy_drop_decision}` | OnUserDecision | 玩家选中糖果 index | renderCandyDropPayout 反查（issue #55） |

**禁止**：只在 RawData 里留 sbz_gr 整帧 → 老解析路径走 raw_data，新结构化路径走 Extra；缺 Extra 时强制走 raw_data 兜底，性能差且容易因上游字段漂移失效。
