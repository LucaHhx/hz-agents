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
- **init cache**：table/dealer/game/timer/disablesidebets 等首连重放
- **核心 handler**：
  - `onBetsOpen` → `MarkBetsOpen` + `UpsertRoundStartedAt`（H5）
  - `onBetsClosed` → `MarkBetsClosed` + 异步 `SubmitBets`
  - `on<gametype>GameResult` → 结算锚（调 SETTLE 接口）
  - `onCanceled` → DEL Redis 下注窗口
  - `onSwitch` → ctx.Reconnect（B10：wsAddress + httpAddress 都必须 string）

**B5 验收**：build/vet/test 过 + dispatch_test 覆盖多事件单帧顺序 + tableId 替换

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

## L3.4 — HISTORY_PARSER

**产物**：
- `server/game/pp/runtime/history.go`（新增 `<Gametype>XML struct`，注意是已有文件，**append 不修改既有 struct**）
- `server/game/pp/runtime/history_<gametype>.go`（新建）
- `server/game/pp/runtime/history_service.go` (添加 `case "<gametype>"` 分支)
- `runtime/history_<gametype>_test.go`

**分析输入**：
- L2 MODELS struct
- **`tmp/<tid>/gameDetail.txt` 真 XML**（字段名 100% 权威，逐字段对照）
- main.js grep `additional.<gametype>.<field>` 解析路径补真 XML 没出现的字段
- 既有 parser 参考：`history_dragontiger.go` / `history_sweetbonanza.go`

**实现内容**：
- `<Gametype>XML struct` 字段名严格匹配 gameDetail.txt 真 XML（大小写敏感 H4）
- `parse<Gametype>Detail(round, txns)` 函数
- 每用户视角抽 BC（payout 最大者）+ aggregate BetAmount/Win/mCap（H3）
- `<multiplier>` / `<payout>` 缺数据填 `"0"` **不空串**（I8 dragontiger 教训）
- `history_service.GetGameDetail` 加 case 分支
- 单测用真 XML（gameDetail.txt）跑 parser，断言关键字段非空

**B5 验收**：build/vet/test 过 + history_<gametype>_test 覆盖 4+ 局型（megawin / mCap / normal / 边界）

**下游**：无（API 层 GetGameDetail 调用）

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
