# Layer 3 AIU — 依赖 L2（5 并行）

> 进入 L3 前确保 L2 全部完成 + 层间审查通过。
> L3 是业务核心：上游 lifecycle / 下游下注 / 结算 / 历史 / 投注校验。

## L3.1 — UPSTREAM

**产物**：
- `upstream_dispatch.go`
- `upstream_handlers.go`
- `upstream_cache.go`

**分析输入**：
- L2 MODELS / PROCESSOR
- L1 ENUM 事件名 / DICT 全集
- `tmp/<tid>/message.jsonl` recv 帧时序（lifecycle 顺序）
- 协议决策表参考（known-pitfalls B 节 + 既有机台经验）

**实现内容**：
- **tableId 字节替换 (B1)**：`HandleUpstream` 入口 `bytes.ReplaceAll(raw, ctx.PPTableID, ctx.TableID)`
- **orderKeysByPriority (B3)**：单帧多 key 按 gameresult > winners > betsclosed > betsclosingsoon > betsopen > 其他
- **verdict 分流**：每事件 pass / drop / rewrite（按 capture 实证 + L1 DICT + 既有机台默认）
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
- `tmp/<tid>/message.jsonl` send 帧（含 lpbet 实例）
- main.js client switch 分支 + B6 ping 单/双引号

**实现内容**：
- ping/subscribe/command 路由（subscribe 是我方合成，不是上游来）
- lpbet/placebet/pbet 解析（按 L2 BETPROTO 判定的协议形态）
- **incremental 协议 (I6)**：`loadExistingBets` + `mergeBets` + 同 bc 累加
- **partial-accept (I7)**：accepted 落库 + bet echo（B5/I5）；rejected 各发 betValidationError
- **betValidationError 7 字段全填 (B9)**：betCode / code / extendedErrorCode / optExtErrorCode / optExtErrorMsg / category / severity
- ⚠️ extendedErrorCode 仅 InvalidToken 等踢下线场景填 9018（**I3 dragontiger 教训**），普通错误必须留空
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
- `tmp/<tid>/message.jsonl` <gametype>gameresult 真帧字段
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

## L3.4 — HISTORY_PARSER（registry 模式，机台自实现）

> **架构改进（jackpotwheel 后引入）**：旧 fallback 模式（runtime 公共 GameEntryXML +
> switch by gameType）已废弃；新机台**强制**走 `historyreg.DetailProvider` registry。
> 每个机台在自己的 internal 包内产出 `history.go`，自定义最小标准 XML struct，**与
> instance 完全解耦**。dragontiger / sweetbonanza / baccarat6 / crystalroulette 等旧
> 机台保留旧 fallback 路径，不强制迁移。

**产物**：
- `server/game/pp/internal/games/<gametype>/<tableId>/history.go`（**新建，机台内部**）
- `server/game/pp/internal/factory/history_factory.go` 加一行注册（**集中注册，与 instance_factory.go 同模式**）

**分析输入**：
- **`tmp/<tid>/gameDetail.txt` 真 XML**（字段名 100% 权威，逐字段对照）
- **PP 真服 curl 响应**（强烈推荐 — 与 capture 对照避免缩进/字段名假设错误）：
  ```bash
  # 从 capture 录制时记录的 PP 真服 URL（如 report.<region>.../audit/game.jsp）curl 一份
  curl 'https://report.<...>/cgibin/usermanagement/audit/game.jsp?JSESSIONID=...&user_id=...&game_id=<...>&format=xml'
  ```
- main.js 中 client XML→JSON 转换（通常在某个 chunk 内，grep `e.games.game.<field>`）
- 既有 registry 实现参考：`jackpotwheel/md500q83g7cdefw1/history.go`（首个 registry 范例）

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

1. **PP 真服 curl 字段对照**：开发完成后必须 curl PP 真服一份响应，与机台 `BuildGameDetail` 输出做 diff，**字段名 / 字段顺序 / 字段集**必须一致（缺字段或多字段都可能让客户端报错）。

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
- history.go + history_test.go 覆盖 4+ 局型（megawin / mCap / normal / 边界）
- 机台 internal 导出 `NewHistoryProvider() historyreg.DetailProvider` 工厂函数
- factory/history_factory.go 加 `<gametype>.TableID: <gametype>.NewHistoryProvider()` 一行
- PP 真服 curl 字段对照通过（手动 diff 或单测断言）
- gameTypeMap 加映射 + L1 dict.json `client_gametype_enum` 一致

**下游**：API 层 `tryHistoryRegistry` 调用（与 instance 完全解耦，不依赖 instance 状态）

---

## L3.5 — CHECK_BET

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
- bc 联动规则（B8 bonus 前置：押 PlayerBonus 必先押 Player）
- **整批拒清 Redis 仅限非窗口类 (C4)**：窗口拒绝不清，防止 "界面已撤实际扣款"

**B5 验收**：build/vet/test 过 + validate_test 覆盖单注/台限/窗口/联动 4 类

**下游**：填实 L2 rules_matrix.md 的 enforce 列

---

## prompt 模板

参考 `phase-3-aiu-L1.md` 末尾通用 prompt 模板。L3 AIU prompt 额外注入：
- **铁律 reminder**：B1/B3/B5/B6/B9/B10/B11 + C1/C3/C4/C7/C8/C9 + D 全部 zap.Error + H3/H5/H6 + I3/I4/I6/I7/I8
- 上游 AIU 已 commit sha + 产物路径（来自 state.aiu_progress.L1.commits + L2.commits）
