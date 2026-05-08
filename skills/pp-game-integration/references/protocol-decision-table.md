# Phase 4 — 协议处理决策表

每个上游事件的 `pass / drop / rewrite` verdict 推导规则。

> **重要**：本文件只给**通用决策方法**和 **baccarat 经验默认表**（baccarat 是仓库首个对接的机台类型）。新对接其他类型机台（roulette / sweetbonanza / megaroulette / dragontiger 等）按 [decisions 推导原则](#decisions-推导原则) 重新判定，**不要**直接抄默认表。
>
> 协议陷阱铁律全部见 [known-pitfalls.md](known-pitfalls.md) B 节，本文件不重复。

## 三种 verdict 含义

| verdict | 行为 | 何时用 |
|---|---|---|
| **pass** | 字节级转发原帧给客户端（含 tableId 替换）| 客户端需要原帧 |
| **drop** | 不转发（return false, nil）| 客户端不接收 / 服务端自合成 / PP 测试账号视角 |
| **rewrite** | 用我方修改后的 payload 重新序列化转发 | betstats 增强 / 其他需要修改的字段 |

## decisions 推导原则

对每个上游事件依次问：

1. **客户端 main.js 是否有接收侧处理代码？**（grep `qe.b.<EvtName>` 或 messageName 注册）
   - 否 → drop
   - 是 → 问 ②

2. **该事件是 PP 测试账号视角还是真实玩家视角？**
   - PP 视角（如 winners）→ drop + 服务端**自合成**真实玩家版本
   - 真实玩家 / 公共帧 → pass

3. **服务端是否需要修改字段后再发？**
   - 是 → rewrite
   - 否 → pass

4. **是否需要触发服务端业务逻辑？**
   - 是（如 betsclosed 触发 SubmitBets） → pass + 业务回调
   - 否 → 仅 pass

## baccarat 经验默认表（仅供 baccarat 系参考）

> 数据来源：bcpirpmfpeobc199 (speedbaccarat) 对接经验。新对接其他 baccarat 桌（如 amazingbaccarat / megabaccarat / fortune6）**仍需 grep 该桌的 main.js 验证**事件清单 — 子类型可能有差异。

### A. 初始化序列（baccarat：缓存 + 透传）

| 事件 | verdict | 备注 |
|---|---|---|
| `table` `dealer` `game` `timer` | pass + cache | 客户端连接时回放给新连接 |
| `subscribe`（上游） | **drop** | 我方在 sendInit 末尾自合成（B2 — 不直接透传 PP 视角）|
| `betstats` | rewrite + cache | `events.EnrichBetstats` 增强；rewrite 数据是**内层 payload**（B7）|
| `card` / `cardinc` / `ShoeSummary` / `statistic` | pass + cache | baccarat 流式发牌 + 牌靴/路单统计 |
| `disablesidebets` | pass + cache + 内部解析 | 拆 value 到禁用集合 |

### B. 一轮生命周期

| 事件 | verdict | 业务 |
|---|---|---|
| `betsopen` | pass + 业务 | `MarkBetsOpen(gameId)` 开窗（内存 + Redis 双写）|
| `betsclosingsoon` | pass | 仅广播 |
| `betsclosed` | pass + 业务 | `MarkBetsClosed` 关窗 + `go handlers.SubmitBets(...)` 异步调商户 /bet |
| `startDealing` | pass | |
| `gameresult` | **pass + 业务** | OnGameResult 写 b_game_rounds + 全用户结算 + queuePendingWin |
| `winners` | **drop** + 自合成 | 详见 known-pitfalls B2 |
| `goodroad` / `playersCount` | pass | baccarat 路单 / 在线人数 |

### C. PP 测试账号视角（**全部 drop** — 见 known-pitfalls B2）

`bet` / `bets` / `win` / `winningBetCodes` / `betSpotWin` / `command` / `pong` — 我方为每用户合成。

baccarat 还要特别看：`winningBetCodes` / `betSpotWin` 在客户端 main.js 0 命中（known-pitfalls B4）。新对接 roulette 时这两类**必须合成**（与 baccarat 相反）。

### D. 控制 / 心跳

| 事件 | verdict | 业务 |
|---|---|---|
| `pong` | drop | 我方自回 pong |
| `switch` | drop + 业务 | 触发 `ctx.Reconnect`（known-pitfalls B10）|
| `enableSubmit` / `gameInit` | pass | sweetbonanza 等 bonus 阶段事件 |

### E. 其他罕见事件

session / kickedout / duplicated_connection / idleAlert / player_error / PlayerBanned / privateBCGameStatus / table_occupied / fcEligible / terminateSession / toasterMessage / remove_card / decision / decisionError / canceled / message / operatorMessage / regulationError / tableCloseNotify / table_closed / thirdpartyerror / prizedrop_win / bonuscard_win / betValidationError

→ 默认 **pass**；如 capture 出现 + main.js 有特殊处理（如 decision 用户决策）则按业务需要单独 case。

## 多 key 单帧的处理

详见 [known-pitfalls.md B3](known-pitfalls.md)。
