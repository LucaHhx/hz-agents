# Phase 4 — 服务端→客户端帧合成

不同机台类型客户端期望的合成帧不同。**先 grep main.js 确认客户端到底接收哪些帧**，再决定服务端合成什么。

> **重要**：本文件只给**通用判定方法** + **baccarat 经验默认**（仓库首个对接类型）。其他类型机台按通用判定方法重新决定，**不要**直接抄默认表。
> 协议铁律全部见 [known-pitfalls.md](known-pitfalls.md) B/E 节。

## 通用判定流程

对每个候选帧（`bets` / `winners` / `win` / `winningBetCodes` / `betSpotWin` / `command` / ...）：

1. **grep main.js 接收侧**：`rg 'qe\.b\.<FrameName>\b'` 是否有 process(e) 处理类
2. 若**无**接收处理 → 服务端**不合成**（合成了客户端也不读；known-pitfalls B4 baccarat 案例）
3. 若**有**接收处理 → 读 process(e) 体反推必填字段
4. 在 design.md 里列出"本机台必合成的帧 + 字段清单"

## 各机台类型默认合成帧（仅参考；按真实 capture + main.js grep 调整）

### baccarat 系列（baccarat / speedbaccarat / megabaccarat / fortune6 / amazingbaccarat / seotdabaccarat / squeeze / puntobanco）

> 来源：bcpirpmfpeobc199 (speedbaccarat) 对接验证 + cbcf6qas8fscb222 (baccarat6) capture 校正。其他 baccarat 子类**仍需 grep 验证**。

**必合成**：`bets`（betsclosed 触发器）/ `win`（每用户私聊派彩）

**透传或合并（不合成）**：`winners` — 上游 winner[] 是真实玩家社交瀑布（known-pitfalls B2 修正版）；选 pass 透传 或 rewrite 合并我方覆盖

**不合成**：`winningBetCodes` / `betSpotWin`（客户端 main.js 0 命中 — known-pitfalls B4）

**结算消息顺序**：
```
gameresult（透传）→ winners（pass 透传 / rewrite 合并 — 不再"完全合成丢弃"）→ 对每用户：win（私聊）
```

通过 `pendingWins` 缓存实现 win 后置：
- OnGameResult 算完每用户的 win 帧 → 入队 `pendingWins[gameID]`
- 收到上游 winners（pass 或 rewrite）后调 `flushPendingWins(gameID)` 私聊每用户

> ⚠️ **历史错误**：早期 baccarat 实现按 B2 错误版本"完全丢弃 winner[] + 合成空 winners"，导致客户端 winnersCount=N 但 winner=[] 矛盾。新对接 baccarat 桌**改 pass 透传**或合并覆盖；既有机台 follow-up issue 修。

### roulette 系列（roulette / megaroulette / autoroulette / poweruproulette / lucky6roulette）

> 待验证：仓库 crystalroul00001 实际合成清单。新 roulette 桌对接时复核。

**通常必合成**：`bets` / `winningBetCodes` / `betSpotWin` / `winners` / `win`

**结算消息顺序**：
```
gameresult（透传）→ winningBetCodes → betSpotWin → winners → 对每用户：win
```

### sweetbonanza 系列（slot 类）

> 待验证。

**通常必合成**：`bets` / `winners` / `win` + bonus 帧（candy_drop / booster 等）
**多阶段**：bonus 进入/进行/结束有专属帧，需读 main.js 反推。

## 帧字段速查（baccarat 验证版仅供参考）

> 这些字段是 bcpirpmfpeobc199 实际验证。其他机台按 main.js 接收侧 grep 反推。

### bets（信号帧 — betsclosed 时广播）

```json
{"bets": {"table": "<tableCode>"}}
```

客户端只用作触发器（`setPhase(BetsClosed)` + `placeBets()`）→ **不需要**带投注详情。

### winners（**优先 pass 透传**；如需 rewrite 合并我方覆盖按下表字段）

```json
{"winners": {
  "gId": "<ppGameId>",
  "table": "<tableCode>",
  "topWin": "7.4127",
  "totalEur": "11.6889",
  "winnersCount": "3",
  "seq": <int>,
  "winner": [
    {"megawin": "false", "currency": "USD",
     "screenName": "okdcmm", "userId": "ppc1735320811857",
     "win": "7.4127"}
  ]
}}
```

字段全部 string；`winner` 必须是数组（main.js 容忍单对象，但服务端**一律发数组**）；金额 4 位小数（PP 标准）。

**默认行为**（新对接，按 B2 修正版）：
- pass 透传上游 winner[] 让客户端展示真实玩家社交瀑布
- 不要"完全丢弃 + 合成空 winners"（之前错误做法 — known-pitfalls B2 已修正）

**可选 rewrite 模式**（合并我方覆盖）：
- 上游 winner[] 中 ppc<timestamp> 与我方 userId 映射 → 用我方 userId/screenName 替换对应条目
- 不在我方的 ppc id → 保留原条目（其他渠道真实玩家）
- 仅在需要"我方玩家在自己桌看到自己同伴"时启用；否则默认 pass

### win（私聊每用户 — winners 之后）

```json
{"win": {
  "table": "<tableCode>",
  "gameId": "<ppGameId>",
  "win": "100.00",
  "nwb": "1234.56",
  "mCap": "false",
  "megawin": "false",
  "amazingwin": "false",
  "rewardtype": "CASH",
  "seq": <int>
}}
```

字段全部 string；`win.win` 是赢钱含本金 2 位小数；`nwb` 新余额；`mCap = "true"` 触发客户端 MAX_PAYOUT_REACHED toast。

### betValidationError（拒绝下注时）

7 字段全集见 [known-pitfalls.md B9](known-pitfalls.md)。

### subscribe（连接初始化时合成）

```json
{"subscribe": {
  "channel": "table-<tableCode>",
  "table": "<tableCode>",
  "status": "success",
  "seq": <int>
}}
```

客户端只读 `e.channel`（必填），调 `setGameChannel(t)` 标记 socket 就绪。**上游 PP subscribe 帧必须 drop**，由我方在 sendInit 末尾合成。

### session（KickUser 用）

```json
{"session": {"session": "offline"}}
```

客户端 Session.process: `e.session.toLowerCase() === "offline"` → resurrect + SessionExpired popup。

## 实现铁律

详见 [known-pitfalls.md](known-pitfalls.md) B/C/E 节。
