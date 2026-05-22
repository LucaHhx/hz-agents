# Layer 2 AIU — 依赖 L1（5 并行）

> 进入 L2 前确保 L1 全部完成 + 层间审查通过。
> L2 提供 struct / 协议格式 / 限额规则 / 处理器骨架 / 实例骨架，是业务实现的脚手架。

## L2.1 — MODELS

**产物**：`server/game/pp/internal/games/<gametype>/<tableId>/models.go`

**分析输入**（**`client_frame_effects.md` 必读**，写 struct 前必须先看每帧客户端表现）：
- **L1.4 `tmp/<tid>/client_frame_effects.md`** ← **强依赖**，决定字段类型 / omitempty / 嵌套结构
- L1 enum.go（常量参考）
- `tmp/<tid>/message.txt` 真帧逐字段（**字段类型严格按真帧**）
- `tmp/<tid>/tableConfig.txt` / `statisticHistory.txt` 字段
- `tmp/<tid>/gameDetail.txt` XML 节点（如 ≥ 1 条）
- main.js 补罕见事件 struct

**写 struct 前必须理解每字段的客户端表现**（L1.4 client_frame_effects.md 已沉淀）：
- 字段类型选择：`megawin` 是字符串 `"true"`/`"false"` 不是 bool（客户端严格字符串比较）
- 嵌套 vs 扁平：`jackpotwheel_rng.slot` 是嵌套对象 `{number, multiplier}`（客户端按对象解构）
- omitempty 决策：客户端 reducer 必读字段不能 omitempty；可选 UI 字段才 omitempty
- 数字 vs 字符串：PP 协议常把数字下发为字符串（如 "1000.0"），struct 用 string 防 Number 转换丢精度

**实现内容**：
- 上游事件 Envelope + payload struct（`Envelope<EventName>` / `<EventName>` 各一）
- ⚠️ **嵌套对象不要扁平化**（如 jackpotwheel_rng.slot 是 `{number, multiplier}` 对象，不是 string）
- send 帧 struct（ClientCommand / ClientPing / ClientLpbet — XML 解析用）
- `JSONStatisticHistoryRecord struct` (statisticHistory writer 写 Redis 用)
- 字段 tag 严格（json + xml）；omitempty 仅可选字段
- 不预设 capture 没出现的字段
- **新增字段**（jackpotwheel 教训）：
  - `Winners.TopWinMultiplier`（capture 真帧实测含）
  - `JSONStatisticHistoryResponse.NumberOfGames`（statisticHistory 顶层必有）
  - `ClientBet` FreeChip/Bonus attrs（`bcode/bettype/cv/cn/bonusId/betsubtype/rid` 全 omitempty，**L3 解析到任一非空必须 fail-closed 拒绝 B11**）
  - `Win.Seq` 字段（**不可缺**，L3.3 FlushPendingWins 用 instance.frameSeq 填非 0）

**B5 验收**：
- build PASS + vet 干净
- struct 字段数与真帧字段数一一对照
- **每个 Envelope struct 在 client_frame_effects.md 都有对应章节**（双向闭环）
- 字段类型与 client_frame_effects.md "字段说明表" 一致

**下游**：UPSTREAM / DOWNSTREAM_BET / SETTLE / HISTORY_PARSER

---

## L2.2 — BETPROTO

**产物**：`tmp/<tableId>/bet_protocol.md`（分析文档，下游 worker 读）

**分析输入**：
- L1 DICT bc 全集
- `tmp/<tid>/message.txt` send 帧 lpbet/placebet/pbet 实例
- main.js 客户端下注代码 grep `e.bets.push` / `placeBet` / `placebets`

**实现内容**（4 节）：
1. **上行 XML 模板**：`<command channel><lpbet gm gId uId ck><bet amt bc ck/></lpbet></command>` 各字段含义 + 字段值实例
2. **bc 全集表**：bc 数值 / 名称 / face_value（如有）
3. **协议模式判定（两步，缺一不可 — 见 known-pitfalls I6 / J1）**：
   - `batch / 全量快照`（客户端每帧发本局完整 bet 集合，如 `lpbet`）— server 按 bc 唯一直接覆盖 Redis，**不 merge**
   - `incremental`（客户端只发新增 1 条，如 `<placeBet>` 单数）— **server 必须 loadExistingBets + mergeBets**（I6）
   - 判定：① `lpbet`（复数语义）帧名 → 几乎必为全量快照；② 取一个 Rebet（"重复下注"恢复多点位）样本看是否含本局全部 bet。⚠️ 单看 `grep e.bets.push` 前是否 `e.bets=[]` **不可靠**（megaroulette 因此误判为增量 → #193）
   - ⚠️ `bet.ck` 是该批发送时间戳、**不是 per-bet 唯一 ID**（Rebet 多 bet 共享同一 ck），禁止用作去重键；按 `bc` 去重；同帧重复 bc = 损坏帧 fail-closed（J1）
4. **特殊 bettype**：FreeChip / Bonus / Booster 等（如 main.js 含相关字段则列；如本机台无则明确写"无"）

**B5 验收**：4 节齐全 + incremental/batch 结论明确 + 配 grep 证据行号

**下游**：DOWNSTREAM_BET 实现指南；I6 incremental 协议是 dragontiger 历史 P0 教训

---

## L2.3 — RULES

**产物**：
- `server/game/pp/internal/games/<gametype>/<tableId>/bet_limits.go`
- `tmp/<tableId>/rules_matrix.md`

**分析输入**：
- L1 ENUM bc 枚举
- `tmp/<tid>/tableConfig.txt` 全字段实际值（9 段位 / total 限额 / 派彩封顶）
- main.js fallback 默认值（`?? 2e4` `?? 5e5` `?? 100`）+ typo 字段（如 megawheel `fourty`）+ bc 联动规则

**实现内容**：
- `bet_limits.go`：G2 默认值常量 + 按 bc 取限额 helper（处理 typo 字段名映射）
- `rules_matrix.md`：每行 — 客户端展示项 / tableConfig 字段名（含 typo）/ 客户端 fallback 默认 / 后端 enforce（暂留 `?` 由 L3 CHECK_BET 填）

**B5 验收**：bet_limits.go 单测覆盖默认值 + matrix 行数 ≥ 9（按 gametype）

**下游**：CHECK_BET 填实矩阵 / PAYOUT 用三路 cap 默认

---

## L2.4 — PROCESSOR

**产物**：`server/game/pp/internal/games/<gametype>/<tableId>/processor.go`

**分析输入**：
- L1 ENUM 常量
- L2 MODELS struct（forward reference）
- 参考骨架：`server/game/pp/internal/games/dragontiger/drag0ntig3rsta48/processor.go`

**实现内容**：
- `Processor struct` 嵌入 `handlers.EventHandler`
- 锁字段：`mu` / `betsMu` / `cacheMu` / `pendingMu`
- `iface.TableProcessor` 4 接口空骨架（HandleUpstream / HandleDownstream / Disconnect / KickUser；仅 stub return）
- `buildEventCtx` helper

**B5 验收**：build PASS + Processor struct 满足 iface

**下游**：UPSTREAM / DOWNSTREAM_BET / SETTLE 全部嵌入此

---

## L2.5 — INSTANCE

**产物**：
- `server/game/pp/internal/games/<gametype>/<tableId>/instance.go`
- `bet_window.go`
- `bet_redis.go`

**分析输入**：
- L1 ENUM Redis key 前缀
- 参考骨架：dragontiger 同名文件

**实现内容**：
- `Instance struct` 嵌入 `*common.GameInstanceBase`
- `New(table, vendor)` 装配函数
- `handleGameMessage` 上游消息回调 dispatch
- `bet_window.go`：`MarkBetsOpen` / `MarkBetsClosed` / **`CanBet` Redis 异常 return false**（C1）
- `bet_redis.go`：`LoadExistingBets` / `SaveBets` / `DeleteBets`，全部走 `context.WithTimeout(ctx, 5*time.Second)`（C9），SCAN 失败返 error 不返 nil（C7）

**B5 验收**：build PASS + bet_window 单测覆盖 Redis 异常分支

**下游**：UPSTREAM / DOWNSTREAM_BET / CHECK_BET 用 Redis helper

---

## prompt 模板

参考 `phase-3-aiu-L1.md` 末尾通用 prompt 模板，注入：
- 本 AIU 名称 / 产物路径 / 分析输入 / 实现要点
- 上游 AIU 已 commit 的 sha（来自 state.aiu_progress.L1.commits）

**集成铁律 reminder（注入到每个 L2 AIU prompt）**：
- B1 tableId 字节级替换
- B2 winners pass 透传（默认）
- B3 多事件单帧 orderKeysByPriority
- B5 lpbet gm 动态拼接（不是固定字面量）
- B6 ping 单/双引号兼容
- B9 betValidationError 7 字段全填
- C1 / C7 / C9 Redis fail-closed
- I2 错误码独立定义不跨包 import
- I4 边界归一化（bc 原始 vs 命名化）
- I6 incremental 协议必须 mergeBets / **J1 `lpbet` 全量快照禁用 `ck` 去重**
