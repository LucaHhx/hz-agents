# 项目级跳过项

以下问题与 crystalroul / sweetbonanza / baccarat 等**所有机台一致**，是项目级架构问题，**单机台不修**。codex review 报这些时直接跳过 + 在 design.md 标"已知项目级问题"。

## 5 项项目级问题（写死，每次对接一致）

### 1. handlers.SubmitBets 幂等锁缺失

**问题**：上游重复推送 `betsclosed` 帧 + `go handlers.SubmitBets(...)` 异步提交 + `bet_submit.go` 用随机 UUID reference → 同一 Redis 注单会用不同 reference 重复扣商户余额。

**位置**：`server/game/common/runtime/handlers/` + `server/game/common/merchantclient/bet_submit.go`

**正确解法（项目级）**：per `(tableID, gameID, userID)` 或 per round 的 `SETNX` 提交锁，或改成确定性 reference（如 `<tableID>:<gameID>:<userID>`）。

**单机台为什么不修**：crystalroul / sweetbonanza / baccarat 都共用 `handlers.SubmitBets`；改了影响所有机台，必须统一在通用层做。

---

### 2. /bet 异步 vs gameresult 顺序 race

**问题**：`betsclosed` 后 `go handlers.SubmitBets(...)` 异步发起；`gameresult` 到达时 settle.go 立即扫 Redis 注单 + 调商户 `/result`。若商户 `/bet` 拒绝/超时回调晚于 `gameresult`，被拒注单仍可能进入 `/result` 派彩 → "未确认扣款的注单白派彩"。

**位置**：每个机台的 `upstream_dispatch.go`（betsclosed → SubmitBets）+ `upstream_handlers.go` (OnGameResult → settle)

**正确解法（项目级）**：Redis 注单加 `/bet accepted` 状态标记；结算只处理已确认成功的 bet；超时/未确认进入人工/重试路径。

**单机台为什么不修**：与 #1 同 — 通用层 race，单机台只能"假设 /bet 永远先返回"。

---

### 3. settle_persist.go 通用层缺陷

**问题**：`server/game/common/runtime/handlers/settle_persist.go:59` 结算时如 Redis session 已过期或缺商户信息 → 只 warn 后继续 → 该用户 `SettleErr` 仍为空 → 后面会清 Redis bet key（`settle_persist.go:98`）→ 成功扣款后的中奖 `/result` 丢失且无重试入口。

**位置**：`server/game/common/runtime/handlers/settle_persist.go`

**正确解法（项目级）**：下注落 Redis 时同步保存 operator/externalPlayerID；或在缺商户信息时标记 `SettleErr` 并保留 key + 入人工任务。

**单机台为什么不修**：通用层基础设施 bug，不在某机台代码内修。

---

### 4. BGameRounds.GameId 未走 NamespaceGameId

**问题**：`server/model/gameData/bGameRounds.go` 中 `GameId` 字段标 `gorm:"uniqueIndex"`，意味着跨表唯一。但每个机台的 OnGameResult 直接用 PP 原始 `gr.ID` 写入 — 不同 PP 桌的 gameId 在不同时间可能重复，理论上有跨桌冲突风险。

`DEVELOPMENT.md` 第 0.3 节规范要求用 `enum.NamespaceGameId(tableCode, ppGameId)` 命名空间化（如 `"42_13992118019"`）。

**位置**：`server/model/gameData/bGameRounds.go` + 每个机台的 `upstream_handlers.go`

**正确解法（项目级）**：要么改 `BGameRounds` 字段约束（去掉 uniqueIndex 或改成复合 unique），要么所有机台统一改用 NamespaceGameId（涉及 Redis betKey / b_game_transactions / handlers.SubmitBets / SettleUsersSeamless 等多处联动）。

**单机台为什么不修**：crystalroul / sweetbonanza 都直接用 PP gameId；baccarat 单独命名空间化会破坏与其他机台的一致性 — Redis betKey 一边命名空间化一边不化 → 通用层 handlers 函数无法兼容。

---

### 5. payout 用 float64 不用 decimal

**问题**：所有机台的 payout 计算用 `float64`：

```go
payout := amount * grPayoutMultiplier(field, gr)
```

高倍率（如 PerfectPair 25:1 + Amazing8s 200x）+ 多笔注累加可能有累积浮点误差。现状用 `fmt.Sprintf("%.2f", payout)` 在落 DB / 商户协议时归一化截尾，但累加时仍是 float64。

**位置**：每个机台的 `payout.go` / `settle.go`

**正确解法（项目级）**：统一改 `decimal.Decimal`（github.com/shopspring/decimal）；或者证明 float64 在 8 位边注 × 4 位倍率内绝对安全。

**单机台为什么不修**：crystalroul / sweetbonanza 全用 float64；单机台改 decimal 会让 settle.UserSettlement 等通用结构有混合类型 → 无法对齐。

---

## codex review 时的处理流程

每个 codex finding（🔴 / 🟡）按以下顺序判断：

```
finding 命中本表 5 项之一？
├── 是 → 跳过（不修）+ 在 design.md 标"已知项目级问题 #N"
└── 否 → 本机台修
        ├── 修复后实时记录到 docs/integration-experience/<gametype>/<tableId>.md 第 7 节
        └── 跑下一轮 codex 验证修复无副作用
```

## 何时该重新评估这 5 项

下列情况触发**全机台联动改造**（不是单 skill 决策）：

- 出现资金事故（如重复扣款 / 漏派彩）→ Owner: 通用层维护者
- 开新机台时发现项目级问题导致的 bug 影响该机台业务
- 项目根 issue tracker 有 P0 标记

新对接发起者**不要**主动改这 5 项；如发现新增的项目级问题，**追加**到本表（修改 skill），但不在单机台 commit 修。
