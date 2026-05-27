# Layer 3 AIU — 依赖 L2（6 并行）

> 进入 L3 前确保 L2 全部完成 + 层间审查通过。
> L3 是业务核心：上游 lifecycle / 下游下注 / 结算 / **历史 XML（BuildGameDetail）** / **报表 HTML（BuildGameReport）** / 投注校验。
> HISTORY 拆两 AIU：DETAIL 走 PP `cgibin/.../audit/game.jsp` XML 数据源，REPORT 走 PP `gameHistory/game.jsp?token=...` HTML 报表数据源。

## L3.1 — UPSTREAM

**产物**：
- `upstream_dispatch.go`
- `upstream_handlers.go`
- `upstream_cache.go`

**分析输入**：
- L2 MODELS / PROCESSOR
- L1 ENUM 事件名 / DICT 全集
- `tmp/<tid>/message.txt` recv 帧时序（lifecycle 顺序）
- 协议决策表参考（known-pitfalls B 节 + 既有机台经验）
- **方法论必读**：`<repo>/docs/integration-experience/common/upstream-frame-handling.md`
  —— 按"用途/作用"归类上游帧（跨机台 key 变体对应）+ verdict / 缓存 init 回放 /
  本地合成三维度决策 + 帧角色归类表

**实现内容**：
- **tableId 字节替换 (B1)**：`HandleUpstream` 入口 `bytes.ReplaceAll(raw, ctx.PPTableID, ctx.TableID)`
- **orderKeysByPriority (B3)**：单帧多 key 按 gameresult > winners > betsclosed > betsclosingsoon > betsopen > 其他
- **verdict 分流**：每事件 pass / drop / rewrite（按 capture 实证 + L1 DICT + 既有机台默认）。⚠️ 上游 `seat` 一律 **drop**（J5）；缓存 / 回放按帧时效语义二分（J2）—— `disablesidebets` / `timer` 等时效状态帧不缓存；`<statistic>` / `<ShoeSummary>` 等每局重发的全量快照帧必须缓存并在新连接回放；`<statisticLA>` 增量帧不缓存
- **init cache + server 自合成 init —— 严格遵守"最少 + 最必要 + 尽量自合成"**：

  init 序列**只发 L1 DICT `init_frame_sequence` 列出的帧**（已经过客户端 main.js
  状态机反向分析最小化），**不要**多发无关帧（playersCount / betstats 等进入游戏
  后才需要的不在 init 序列）。

  **优先级**：C（自合成） > B（rewrite 重放） > A（pass ReplayCache）。
  能用 ctx.TableID / state.CurrentGameID / DB 配置 / 常量构造的，**都走 C 类**。
  只有 PP 上游独有数据（如真实 dealer.id UUID）才回退 A/B。这样：
  - 多 client fan-out 时不依赖上游帧到达时序
  - server 启动早期客户端连入也能拿到完整 init
  - 易单测（纯函数构造，无需 mock 上游）

  按 L1 DICT 分类执行：
  - **A pass（最少用）**：上游来的帧缓存 → 客户端连入时 ReplayCache 重放
  - **B rewrite**：betstats / table（tableId 字节替换）需 enrich 后重放
  - **C 自合成（首选）**：server 用 state/常量构造。jackpotwheel 历史教训：缺
    `subscribe ack` 自合成 → 客户端 isTableSubscribed 永远 false → 永不发 ping → 卡死。
    typical 自合成清单：
    - `{"subscribe":{"channel":"table-<code>","table":"<code>","status":"success","seq":<auto>}}`
    - `{"table":{"newTable":"false","openTime":"","seq":<auto>,"value":"<MOW13 或机台短名>"}}`
    - `{"game":{"id":"<state.CurrentGameID>","table":"<tableCode>","seq":<auto>,...}}`
    - `{"timer":{"id":"<state.CurrentGameID>","table":"<tableCode>","seq":<auto>,"value":"<state.Countdown>"}}`
    - 其他按 L1 DICT `init_frame_sequence` 标注 C 类的帧

  实现位置：`handleConnect` 内顺序为 — JoinRoom → 按 init_frame_sequence 顺序逐帧
  send（C 优先 / B 次 / A 最后兜底）→ RegisterConn。**严格按 L1 DICT 序列**，
  不增不减。

  **seq 字段**：所有 C 类自合成帧用 instance 级 `frameSeq atomic.Int64` 分配
  （单调递增，跨 conn 共享）。多 client 视角 seq 一致；与上游帧 seq 不冲突
  （客户端只要求单帧 seq 单调，不要求与上游对齐）。
- **核心 handler**：
  - `onBetsOpen` → `MarkBetsOpen` + `UpsertRoundStartedAt`（H5）
  - `onBetsClosed` → `MarkBetsClosed` + 异步 `SubmitBets`（**注意**：`SubmitBets` 第 3 参
    必须传 `p.OnMerchantBetResult`，**不是 nil** — 否则注单永远不 MarkBetAccepted 导致
    settle 阻断；jackpotwheel 历史 P0 教训）
  - `on<gametype>GameResult` → 结算锚（调 SETTLE 接口）
  - `onCanceled` → DEL Redis 下注窗口
  - `onSwitch` → ctx.Reconnect（B10：wsAddress + httpAddress 都必须 string）
  - `onDealer` → 解析 `dealer.value` 写入 Processor.dealerName 缓存（settle 落
    b_game_rounds.dealer_name 用；漏存导致 history XML `<seat><name>` 缺失）
  - `onSeat` → **drop**（J5：上游 `seat` 按 PP 代理账号广播、含其它会话的 idle/timeout，
    透传给下游客户端会误弹 Inactivity 遮罩 + 强制断 WS；Inactivity 改由我方 per-user
    `IdleWatcher` 自管，阈值取 `b_tables.activity_check_interval`，0 = 禁用不 fallback）

**B5 验收**：build/vet/test 过 + dispatch_test 覆盖多事件单帧顺序 + tableId 替换 +
**ReplayCache + 自合成 init 序列**（与 L1 DICT init_frame_sequence 对齐）

**下游**：SETTLE / BETSTATS / WINNERS

---

## L3.2 — DOWNSTREAM_BET

**产物**：
- `downstream_dispatch.go`
- `downstream_bet.go`
- `xml_util.go`

**分析输入**：
- L2 MODELS（ClientLpbet 等） / BETPROTO（incremental/batch 判定） / RULES
- `tmp/<tid>/message.txt` send 帧（含 lpbet 实例）
- main.js client switch 分支 + B6 ping 单/双引号
- **方法论必读**：
  - `<repo>/docs/integration-experience/common/bet-confirmation-frames.md` —— bet/bets
    确认帧两类形态、三种下发时序（**必须在商户 /bet 成功之后**）、客户端清盘风险、
    六机台矩阵与对接 checklist
  - `<repo>/docs/integration-experience/common/client-rules-analysis.md` —— 客户端规则
    分析方法论，产出"客户端-后端一致性矩阵"

**实现内容**：
- ping/subscribe/command 路由（subscribe 是我方合成，不是上游来）
- lpbet/placebet/pbet 解析（按 L2 BETPROTO 判定的协议形态）
- **协议形态按 L2.2 BETPROTO 判定**：batch / 全量快照 → 按 bc 唯一直接覆盖 Redis（**不 merge**）；incremental (I6) → `loadExistingBets` + `mergeBets` + 同 bc 累加。⚠️ `lpbet` 几乎必为快照，`ck` 不可作去重键、同帧重复 bc fail-closed（J1）
- **partial-accept (I7)**：accepted 落库 + bet echo（B5/I5）；rejected 各发 betValidationError
- **betValidationError 7 字段全填 (B9)**：betCode / code / extendedErrorCode / optExtErrorCode / optExtErrorMsg / category / severity
- ⚠️ extendedErrorCode 仅 InvalidToken 等踢下线场景填 9018（**I3 dragontiger 教训**），普通错误必须留空
- **error code 必须客户端真识别 (J4)**：拒单 `code` 必须命中客户端 main.js `betValidationError` / `rejectBet` switch 真有 toast 的分支（被禁 betCode 用 `20602` BET_NOT_ALLOWED，**不要用** `1028` / `1059` / `1060`，否则落 default 弹"请联系客服"通用错误）；拒单后**不要追发** `command status=error`
- **FreeChip / 特殊 bettype fail-closed (B11)**：如 `bet.Nc != ""` / `lpbet.Bcode/Bettype 非空` → 返回 `ErrCodeFreeChipUnknownError`
- **空 lpbet 撤单防御 (C3)**：必须先 CheckBet 校验窗口才清 Redis
- `xml_util.go` `extractXMLAttr` 单/双引号兼容 + `xmlRootTag` helper

**B5 验收**：build/vet/test 过 + parse_test 覆盖三种引号 + placebet_incremental_test 验证 I6（连续两次发不同 bc 验证合并）+ partial-accept test

**下游**：CHECK_BET 协作

---

## L3.3 — SETTLE

**产物**：`settle.go`（+ 可选 `settle_block.go`）

**分析输入**：
- L2 MODELS（<gametype>GameResult struct）
- L1 ENUM FaceValueToBC
- `tmp/<tid>/message.txt` <gametype>gameresult 真帧字段
- 既有机台参考：dragontiger / sweetbonanza settle.go

**实现内容**：
- `OnGameResult` 入口
- **face_value → bc 映射**（如 megawheel value="10" → BCTen）
- 全用户结算循环
- `b_game_rounds.Extra` 落盘字段（每真帧字段都落盘：multiplier / rngSlot / gameResult / sector 等）
- `b_game_rounds.RawData` 兜底（整帧 JSON / XML）
- `queuePendingWin` 缓存 + `flushPendingWins` 在 winners 后私聊（baccarat6 + dragontiger 模式）
- **statisticHistory writer**：调 `events.AppendHTTPStatHistory` 写 Redis stat_history http key
- **fail-closed log (D)**：UpsertRound 失败 / GetRedisUserBets 失败 / SettleUsersSeamless 失败全部 `zap.Error`

**B5 验收**：build/vet/test 过 + payout_test ≥ 4 真帧样本（capture 取） + cover ≥ 25%

**下游**：PAYOUT / BETSTATS / WINNERS / STATS_API（数据源）

---

## L3.4 — HISTORY_DETAIL（BuildGameDetail / XML 历史详情）

> **架构改进（jackpotwheel 后引入）**：旧 fallback 模式（runtime 公共 GameEntryXML +
> switch by gameType）**已废弃**；新机台**强制**走 `historyreg.DetailProvider` registry。
> 每个机台在自己的 internal 包内产出 `history.go`，自定义最小标准 XML struct，**与
> instance 完全解耦**。dragontiger / sweetbonanza / baccarat6 / crystalroulette 等旧
> 机台保留旧 fallback 路径，不强制迁移。
>
> **L3.4 唯一职责**：实现 `BuildGameDetail` 接口（PP `cgibin/usermanagement/audit/game.jsp` XML
> 历史详情；玩家点客户端"我的历史"按钮触发）。报表 HTML（`gameHistory/game.jsp?token=...`）由
> 独立的 **L3.5 HISTORY_REPORT** 负责，两者数据源 / 产物 / 单测全分离。

**产物**：
- `server/game/pp/internal/games/<gametype>/<tableId>/history.go`（**新建，机台内部**）
- `server/game/pp/internal/games/<gametype>/<tableId>/history_helpers.go`（policy-pr 500 行闸门时拆出）
- `server/game/pp/internal/factory/history_factory.go` 加一行注册（**集中注册，与 instance_factory.go 同模式**）

**分析输入**：
- **`tmp/<capture_dir>/gameDetail.txt` 真 XML**（字段名 100% 权威，逐字段对照）
- **方法论必读**：`<repo>/docs/integration-experience/common/history-display-analysis.md`
  —— 客户端历史记录展示分析方法论（5 类入口 + 字段映射 + 单测）
- main.js 中 client XML→JSON 转换（通常在某个 chunk 内，grep `e.games.game.<field>`）
- 既有 registry 实现参考：
  - `jackpotwheel/md500q83g7cdefw1/history.go`（首个 registry 范例）
  - `roulette/gatesofolympus01/history.go`（roulette 系列 + olympusRouletteDetails 独有节点）

**gameDetail.txt 字段抽取 step-by-step**：
```bash
# 1. 取一条真 XML 样本
head -1 tmp/<capture_dir>/gameDetail.txt > /tmp/sample.xml
# 2. 抽 <games><account> 9 字段（capture 实证）：currencyBefore / currencyCode /
#    currencySymbol / firstName / fullName / lastName / rowCount / screenName / userId
grep -oE '<account>.*</account>' /tmp/sample.xml | xmllint --xpath 'string()' - | head
# 3. 抽 <game> 字段（按字母序，capture 实证完整列）：
#    bet[] / currency / dataTimeStart / entireGameCancelled / freeBet /
#    fullyRefunded / gameCancelled / gameId / gameStartTimestamp / label /
#    maxcap / netAmount / <游戏特化子节点> / roundId / seat / stake /
#    tableType / tableVariant / totalPayoff
# 4. 抽 <bet> 子字段（PP 各机台不同！jackpotwheel 9 字段 vs gatesofolympus 10 字段）
# 5. <roundId> 是 15 位数字 hall round_id，与业务 RoundId 一致
```

**实现内容**（机台 history.go 4 部分）：

```go
package <tableId>

import (
    "encoding/xml"
    "hab/game/pp/runtime/historyreg"
    "hab/model/gameData"
)

// 1. NewHistoryProvider 工厂函数（由 factory.history_factory.go 集中注册，
//    与 instance_factory.go 同模式：机台 internal 不自 init() 注册）
func NewHistoryProvider() historyreg.DetailProvider {
    return &historyProvider{}
}

// 2. provider 实现
type historyProvider struct{}

func (p *historyProvider) BuildGameDetail(
    round *gameData.BGameRounds,
    txns []gameData.BGameTransactions,
    user historyreg.User,
) (any, error) {
    // 按 PP 真服 capture + curl 字段精确构造
    return &<gametype>HistoryDoc{Account: ..., Game: ...}, nil
}

// 3. 机台自定义最小标准 XML struct（按 PP 真服字段顺序与名称）
// 字段按字母序（PP 标准），不复用 runtime 公共 GameEntryXML
type <gametype>HistoryDoc struct {
    XMLName xml.Name `xml:"games"`
    Account <gametype>Account `xml:"account"`
    Game    <gametype>GameEntry `xml:"game"`
}
type <gametype>Account struct {
    CurrencyBefore bool `xml:"currencyBefore"`   // PP 真服必填
    CurrencyCode   string `xml:"currencyCode"`   // padded 41 字符
    CurrencySymbol string `xml:"currencySymbol"` // padded 41 字符
    FirstName      string `xml:"firstName"`
    FullName       string `xml:"fullName"`
    LastName       string `xml:"lastName"`
    RowCount       int    `xml:"rowCount"`       // 真服必填，通常 0
    ScreenName     string `xml:"screenName"`
    UserId         string `xml:"userId"`
}
// ... <gametype>GameEntry / <gametype>Bet / <gametype>Seat / 机台特化嵌套节点
```

**强制要求**：

1. **gameDetail.txt capture 字段对照**：开发完成后用 `tmp/<capture_dir>/gameDetail.txt` 真 XML 与机台 `BuildGameDetail` 输出做 diff，**字段名 / 字段顺序 / 字段集**必须一致（缺字段或多字段都可能让客户端报错）。

2. **bet 节点禁止盲目继承通用 GameBetXML**：PP 真服各机台 bet 节点字段不同。
   **jackpotwheel 历史教训**：通用 GameBetXML 含 `partiallyRefunded`，但 PP 真服 jackpotwheel `<bet>` **无此字段**，导致客户端解析时多余字段。机台自定义 struct 时**精确按 PP 真服字段集**。

3. **客户端 GameType enum 映射**（与 L1 DICT 输出对应）：history list `type` 字段必须经
   `gameTypeToClientType` 转 PascalCase 后，`toUpperCase()` 能匹配 client main.js 中 `m.d.<GAMETYPE>` 字符串值。
   **必须**在 `server/game/pp/runtime/history_parse.go:gameTypeMap` 加一行：
   ```go
   "<dbGameType>": "<PascalCase>",  // 如 "jackpotwheel": "Megawheel"
   ```
   否则 history 详情显示"无法预期的错误"。

4. **持久化字段完整性**（L3.3 SETTLE 配合）：history XML 需要的字段必须在 settle 时**完整落到 b_game_rounds + b_game_transactions**：
   - `b_game_rounds.dealer_name` ← `Processor.dealerName`（cacheDealer 内解析 `dealer.value`）
   - `b_game_rounds.round_id` ← `evt.ID + "008"`（PP 标准格式）
   - `b_game_rounds.game_type` ← `ctx.GameType` 空时用 `enum.GameType` 兜底
   - `b_game_rounds.extra` ← multiplier / rngSlot / value / face / sector / maxcapValue 等机台特化字段
   - `b_game_transactions.description` ← `payout.BetCodeDescription(bc)`（face value 字符串如 "1"/"5"/"40"，**不是** "Face X" 长字符串）

**B5 验收**：
- build/vet/test 过
- history.go + history_test.go 覆盖 4+ 局型（megawin / mCap / normal / 边界），**测试用真 gameDetail.txt XML 做 fixture**（不是构造数据）
- 机台 internal 导出 `NewHistoryProvider() historyreg.DetailProvider` 工厂函数
- factory/history_factory.go 加 `<gametype>.TableID: <gametype>.NewHistoryProvider()` 一行
- gameDetail.txt capture 字段对照通过（单测断言关键字段值匹配）
- gameTypeMap 加映射 + L1 dict.json `client_gametype_enum` 一致

**下游**：API 层 `tryHistoryRegistry` 调用（与 instance 完全解耦，不依赖 instance 状态）

---

## L3.5 — HISTORY_REPORT（BuildGameReport / 报表 HTML）

> **L3.5 唯一职责**：实现 `BuildGameReport` 接口（PP `gameHistory/game.jsp?token=...` HTML 报表
> 页面；商户后台 / 玩家"局详情"按钮触发）。
>
> **核心 KPI**：HTML 与 PP 真服 capture 视觉相似度 **≥ 90%**。不仅字段对齐，**HTML 骨架 / 标签 ID /
> class / 内嵌 SVG 都要按 PP 真服样式实现**。

**产物**：
- `server/game/pp/internal/games/<gametype>/<tableId>/report.go`（**新建，独立于 history.go**；含 BuildGameReport 方法 + buildGorReportHTML 入口 + write*Table 函数 + SVG 卡片 helper + round.Extra 反序列化 helper + 内联 CSS 常量）
- 共用 history.go 已注册的 historyreg provider（同一 historyProvider struct 实现 BuildGameDetail + BuildGameReport 两个接口）
- 注意：旧 `history_helpers.go` 拆分模式**不再使用**，所有 round.Extra 反序列化 helper 合并到 report.go（policy-pr 500 行内容纳得下，避免 helper 文件碎片化）

**分析输入**：
- **`tmp/<capture_dir>/roundDetail/<rid>.html`** —— PP SPA 渲染完成后的基线 DOM（含 gameHeader / gameResult / playerSummary 三张表 + Bonus/Multipliers/Game Result SVG 行）
- **`tmp/<capture_dir>/roundDetail/<rid>-Details-<userId>.html`** —— 点 Details 按钮后的 modal 内容（含玩家逐笔下注 7 列：Bet Desc / Status / Bet currency / Bet / Payoff / Bet EUR / Payoff EUR）
- 既有实现参考：`roulette/gatesofolympus01/report_html.go`（首个完整 90%+ 还原 + SVG 嵌入范例）

**roundDetail HTML 字段抽取 step-by-step**：
```bash
# 1. 看基线 HTML 全局结构
python3 -c "
import re
with open('tmp/<capture_dir>/roundDetail/<rid>.html') as f:
    h = f.read()
for tr in re.finditer(r'<tr[^>]*>(.*?)</tr>', h, re.DOTALL):
    cells = re.findall(r'<t[hd][^>]*>(.*?)</t[hd]>', tr.group(1), re.DOTALL)
    print([re.sub(r'<[^>]+>', '', c).strip()[:80] for c in cells if c])
"
# 2. 看 Details modal 内容（玩家明细 7 列）
grep -oE '<table[^>]*id="modalTable"' tmp/<capture_dir>/roundDetail/<rid>-Details-*.html
# 3. 抽 PP 真服 CSS 引用清单
grep -oE '<link[^>]*href="[^"]+"' tmp/<capture_dir>/roundDetail/<rid>.html
# 通常 3 个：/css/admin.css /audit/game.css /script/style/modal.css
# 4. 抽 PP 内嵌 SVG（capture 实证 base64 编码用 SVG 渲染 Bonus number / Multipliers / Game Result）
grep -oE 'data:image/svg[^"]+' tmp/<capture_dir>/roundDetail/<rid>.html | head -3
```

**HTML 骨架（必须复刻；自包含 0 外部依赖，CSS 全内联）**：

> 不引外部 `/css/admin.css` / `/audit/game.css` / `/script/style/modal.css`。pp-game 客户端不一定
> 能 fetch 到这些 PP 真服资源，且离线打开 HTML（如调试 / 商户后台下载）也要可读。所有视觉关键
> 样式（表格 border / .firstCell label / .money 右对齐 / .goo-game-final 限宽 160px /
> .goo-game-bonus-numbers inline-flex / SVG margin）全部 **内联到 `<style>` 块**。

```html
<!DOCTYPE html><html><head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
<title>Game Details</title>
<style>/* 内联 PP 真服样式关键子集，自包含 */</style>
</head><body>
<div id="loader" class="loaderBG" style="display: none;"><div><div class="loader"></div></div></div>
<center><div id="dataTable">
  <table id="gameHeader">...Game started/Table name/GameId/RoundId/Dealer name...</table>
  <table id="gameResult">
    <tr><td class="firstCell">Bonus Number</td><td colspan="7">{bonus SVG / 文本}</td></tr>
    <tr><td class="firstCell">Multipliers</td><td colspan="7">{multipliers SVG 卡片组}</td></tr>
    <tr><td class="firstCell">Game Result</td><td colspan="7">{轮盘 SVG 三号码弧形}</td></tr>
  </table>
  <table id="playerSummary">...10 列汇总（Nick name/User id/.../EUR/Action[Details]）...</table>
  <table id="playerDetails">...modal 内容静态展开 7 列...</table>
</div></center>
<div id="modal" class="modal" style="display: none;"><div class="modal-content"><table id="modalTable"></table></div></div>
<form action="game.jsp" method="post" id="hiddenForm">...</form>
</body></html>
```

**SVG 实现要点（PP 真服 Game Result 行轮盘指示牌实证）**：

PP 真服 capture 样例（gatesofolympus01 winNumber=16）：
```svg
<svg xmlns="http://www.w3.org/2000/svg" fill="#F5F5F5" viewBox="0 0 111 60" font-weight="600" text-anchor="middle">
  <!-- 左侧弧（左邻号 24，黑底斜放） -->
  <path fill="#001211" d="M.3 47.4a61 61 0 0 1 53-35l1 29.7A31.3 31.3 0 0 0 27.1 60L.3 47.3z"/>
  <text x="-12.7" y="50.7" fill-opacity="0.5" transform="rotate(-45)">24</text>
  <!-- 右侧弧（右邻号 33） -->
  <path fill="#001211" d="M55.4 12.4a61 61 0 0 1 55.2 35L83.8 60.2a31.3 31.3 0 0 0-28.4-18z"/>
  <text x="91.7" y="-28.3" fill-opacity="0.5" transform="rotate(45)">33</text>
  <!-- 底中心半圆（落点 16，红底红描边） -->
  <path fill="#780404" d="M27.8 19c17.5-9 38-8.8 55.4 0L69.6 45.6a31.6 31.6 0 0 0-28.4 0C36.5 36.9 32.6 27 27.8 19Z" stroke="#FF0000" stroke-linejoin="round" stroke-width="2"/>
  <text x="55" y="33.4" fill="">16</text>
</svg>
```

**SVG 实现规则**：
- 轮盘机台必须有 `rouletteOrder` 数组（37 号顺时针欧式单零）取邻号：
  ```go
  var rouletteOrder = []int{
      0, 32,15,19,4,21,2,25,17,34,6,27,13,36,11,30,
      8,23,10,5,24,16,33,1,20,14,31,9,22,18,29,
      7,28,12,35,3,26,
  }
  ```
- 颜色 hex：`red → "#780404"` / `black → "#001211"` / `green(0) → "#006400"`
- winNumber 居中 + 红描边（`stroke="#FF0000" stroke-width="2"`）突出；邻号 fill-opacity="0.5" 灰显
- 非轮盘机台（jackpotwheel / sweetbonanza）SVG 模板从 capture roundDetail HTML 内嵌 base64 提取，**不照搬轮盘模板**

**Multipliers 行**（gatesofolympus 等含 luckyMul）：
- 数据源：`round.Extra["luckyMul"]` `[]GorLuckyMul{Mul, Slot, SlotId, IsBoosted}`（settle_persistence 已落，**L3.3 SETTLE 必须存**）
- 文本格式：`x{mul} {slot}` 多组用空格分隔（如 `"x50 3 x100 6 x100 7 x50 18"`）
- SVG 卡片组：每倍率一个矩形 + "x{mul}" 上 + "{slot}" 下（capture 实证；未做 SVG 时纯文本可接受降级，但视觉相似度 < 90%）

**Player Summary 表**（10 列；EUR 用 `configCache.CurrencyRates.Convert(amount, currency, "EUR")`，缺兑率留空不强行 0）：
```
Nick name | User id | Login | Casino | Native currency | Total bet amount | Total payoff | Total bet amount EUR | Total payoff EUR | Action
```
Action 列：`<input type="button" value="Details" onclick="game.getPlayerDetails('{uuid}')">`（pp-game 没 ajax 后端，按钮静态存在用于视觉对齐）

**Player Details 表**（7 列，PP 真服 modal 内容；pp-game 静态展开直接渲染不依赖 ajax）：
```
Bet Desc | Status | Bet currency | Bet | Payoff | Bet EUR | Payoff EUR
```
Status 列固定 `"Settled"`（pp-game 写盘的 txns 都已结算）。

**B5 验收**：
- build/vet/test 过
- report.go + report_test.go，**测试用真 roundDetail/*.html capture 做 fixture 视觉对齐断言**（关键 selector / 字段值 / SVG 元素都在）
- 与 capture 视觉相似度 ≥ 90%（人工目测 + 自动 diff 关键 DOM 节点）
- 轮盘机台必含 SVG（Game Result 行不允许纯文本兜底）
- EUR 列缺兑率时留空（PP 真服 capture 实证），不返 "0"
- **自包含 HTML 输出**：不引任何外部 CSS / JS，所有视觉样式内联（离线打开也可读）

**下游**：API 层 `GameRoundReport` handler 调（与 BuildGameDetail 共用同一 historyProvider）

---

## L3.6 — CHECK_BET

**产物**：`check_bet.go`

**分析输入**：
- L2 RULES bet_limits + rules_matrix.md
- L2 INSTANCE bet_window
- L1 ENUM errorCode

**实现内容**：
- `CheckBet` hook
- **双重 fail-closed (C1)**：内存窗口 + Redis 窗口任一异常返回错误
- 9 段位（或对应 bc）单注限额校验 → 返 `ErrCodeBetTooLow/TooHigh`
- 该用户当前局总 stake + 新 bet > 台限 → 返 `ErrCodeTableLimitExceeded`
- bc 白名单校验 → 不在 → 返 `ErrCodeUnknownBetCode`
- bc 联动规则（B8 bonus 前置：同帧含**任一非 Bonus bet** 即可，**不要求同侧** — 见 J3；下注规则必须 capture 实证不凭直觉）
- **整批拒清 Redis 仅限非窗口类 (C4)**：窗口拒绝不清，防止 "界面已撤实际扣款"

**B5 验收**：build/vet/test 过 + validate_test 覆盖单注/台限/窗口/联动 4 类

**下游**：填实 L2 rules_matrix.md 的 enforce 列

---

## prompt 模板

参考 `phase-3-aiu-L1.md` 末尾通用 prompt 模板。L3 AIU prompt 额外注入：
- **铁律 reminder**：B1/B3/B5/B6/B9/B10/B11 + C1/C3/C4/C7/C8/C9 + D 全部 zap.Error + H3/H5/H6 + I3/I4/I6/I7/I8 + **J1-J7 生产 bug 复盘铁律全部**（J1 lpbet 快照 / J2 帧时效 / J3 下注规则 capture 实证 / J4 error code / J5 seat drop / J6 展示配置 / J7 历史字段）
- 上游 AIU 已 commit sha + 产物路径（来自 state.aiu_progress.L1.commits + L2.commits）
