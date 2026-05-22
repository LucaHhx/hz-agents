# Layer 1 AIU — 无依赖（3 并行）

> 进入 L1 前确保 Phase 0 / 1 / 2 已 done。
> L1 是整个对接的协议事实基础，下游全部依赖；ENUM 失败 = block 整层。

## L1.1 — ENUM

**产物**：`server/game/pp/internal/games/<gametype>/<tableId>/enum.go`

**分析输入**（按需读，不读全部）：
- `tmp/<tid>/message.txt` recv 帧抽事件名集 + send 帧抽 bc 集
- `tmp/<tid>/tableConfig.txt` `.betCode` 字段
- `tmp/<tid>/clientResources/.../main.js` grep `Qp` 枚举 / errorCode 字面量 / `tf`/`nf` 映射表 / 罕见事件名

**实现内容**：
- `TableID / GameType / GameLoaderKey / UpstreamGm / OperatorTheme / OperatorGameId` 常量
- 上游事件名常量（按 dict 全集）
- bc 枚举（PP `Qp` 枚举，注意可能乱序）
- face value ↔ bc 双向映射（megawheel 等需要：FaceValueToBC / BCToFaceValue）
- errorCode 全集常量（≥ 30 项典型；不 import 其他机台 — known-pitfalls I2）
- Redis key 前缀（pp:bets:`<TableID>`:`<gameId>` 等，统一走 enum）
- 默认值常量（G2：DefaultMaxMultiplier=20000 / DefaultEuroTablePayoutMax=500000）

**B5 验收**：
- `go build ./game/pp/internal/games/<gametype>/<tableId>/...` PASS
- `go vet` 无新增 warning
- 单测可后置（DICT/dictionary_test 在 L2 之后）

**下游消费**：所有后续 AIU

---

## L1.2 — DICT

**产物**：`tmp/<tableId>/dict.json`（**非代码，是分析备忘文件**）

**分析输入**：
- 全 5 capture 文件（事件名 / 字段类型全集）
- main.js 补 capture 没出现的偶发事件（canceled / session / decisionError / switch / duplicated_connection 等）

**实现内容**（JSON 结构）：
```jsonc
{
  "gametype_literal": {...},
  "upstream_events": { "betsopen": {...}, ... },  // 每事件含 _capture_evidence 或 _main_js_evidence
  "downstream_actions": [...],
  "betcodes": [...],
  "error_codes": [...],
  "lpbet_format": {...},
  "frame_envelope": {...},
  "init_frame_sequence": [...],          // 客户端 main.js 反向分析得出的 init 必发帧序列（见下）
  "client_gametype_enum": { ... },       // grep main.js GameType enum 字典（与 history list type 字段对应）
  "message_classification": { ... },     // 每事件三分类：A pass / B rewrite / C synthesize（Phase 4 Q5 数据源）
  "_sources": ["..."],
  "_conflicts": [...]   // capture 与 main.js 冲突时列出（capture 为准）
}
```

**关键步骤 — 客户端反向分析（必做，否则漏 init 帧）**：

1. **init 帧序列 — 最少 + 最必要 + 尽量自合成（核心三原则）**：

   `init_frame_sequence` **不是**把 capture 上游 burst 全列进去，**是按客户端 main.js 状
   态机反向推导得出的"客户端启动必须依赖的最小集"**。多发无害但污染日志、增加渲染抖动；
   少发会卡死客户端。三条规则都不能违背：
   - **最少**：不在客户端启动状态机里的帧（如 playersCount / betstats 这些进入游戏后才更
     新的）**不列入 init 序列**；首连重放只发"开局必须"的
   - **最必要**：客户端解锁 ping / 渲染桌面 / 启用下注前等待的所有状态变量对应的帧**必须
     全部覆盖**（subscribe ack / table / dealer / game / timer / 必要的回合状态如
     enableSubmit / startDealing 等，**视客户端状态机而定**）
   - **尽量自合成（C 类）—— 不依赖上游缓存**：每个 init 帧优先标 C 类（server 用 DB /
     state / 配置 / 常量自己构造），仅当字段确实只从 PP 上游能拿到（如真实 dealer.id
     UUID）才退回 A pass + ReplayCache。多 client fan-out 架构下 A 类 ReplayCache 不可
     靠（上游帧只到达一次，server 启动早期可能尚未收到；多客户端同时连入时序也不稳定）。
     **优先 C 类**给一致性 + 与 instance 解耦更强 + 易单测。jackpotwheel 经验：subscribe
     ack / 部分 init 帧完全可以 server 用 ctx.TableID + state.CurrentGameID 自构造。

   分析步骤：
   ```bash
   MAIN=tmp/<tid>/clientResources/apps/<gameLoaderKey>/<ver>/main.js
   # a. 找客户端启动状态机变量（不同框架不同名）
   grep -oE 'isTableSubscribed|firstConnection|isFirstFrame|onSubscribeSuccess|onTableReady|readyForBets|tableReady|gameReady' $MAIN | sort -u
   # b. 找 redux state.config / state.game 中 init 状态字段
   grep -oE 'config\.session|config\.tableConfig|game\.initialized|table\.subscribed' $MAIN | sort -u
   # c. 找客户端首发上行帧的触发条件（通常 isTableSubscribed=true 才开始发 ping）
   grep -B 3 -A 3 'isTableSubscribed\s*=\s*true' $MAIN | head -20
   # d. 找 subscribe / dispatcher 入口看每个事件 case 对应的 state 切换
   grep -B 1 -A 5 'case ?"(table|dealer|game|timer|subscribe)"' $MAIN | head -40
   ```
   把结果**最小化**记入 `init_frame_sequence`：仅"客户端**等待**才解锁后续动作的帧"。

   **每帧必须标"在客户端的作用"**（不理解作用就贸然加帧 / 删帧都会出问题）：

   ```jsonc
   "init_frame_sequence": [
     {
       "event": "subscribe",
       "class": "C",                  // A pass / B rewrite / C synthesize
       "client_role": "PP 上游 server-side 新连接时主动发；客户端收到 status:success 后置 isTableSubscribed=true，解锁 ping/视频/桌面渲染。我方 1 上游 fan-out N client 必须各自合成。",
       "trigger_state": "isTableSubscribed",
       "evidence_main_js": "@<offset>",
       "evidence_capture": "msg seq=10",
       "fields": ["channel","table","status","seq"]
     },
     {
       "event": "table",
       "class": "C 优先 / A 兜底",
       "client_role": "客户端 setTable reducer：渲染桌面背景 + 桌名。无此帧 → 桌面灰屏。",
       ...
     },
     {
       "event": "dealer",
       "class": "C 优先 / A 兜底",
       "client_role": "客户端 setDealer reducer：渲染荷官头像 + 名字 + 灯光。无此帧 → '无荷官'。",
       ...
     },
     // ... game / timer / 必要的回合状态帧
   ]
   ```

   **jackpotwheel 教训**：缺 `subscribe ack` 导致 isTableSubscribed 永 false / 客户端永不发 ping。
   背后规律：**每个帧都对应客户端某个 redux state 字段或某个 UI 状态切换**。L1 必
   须把每帧的"客户端作用"写清楚（main.js evidence 行号 + state 字段名）。L3.1 实现
   时按此清单逐帧实现，缺一不可。

2. **GameType enum 字典**：grep client main.js GameType 字面量（影响 history list type 字段）：
   ```bash
   grep -oE '\b[A-Z_]{4,}:"[A-Z_]{4,}"' $MAIN | grep -E 'MEGAWHEEL|BACCARAT|DRAGONTIGER|ROULETTE|SWEETBONANZA' | sort -u
   # 例: MEGAWHEEL:"MEGAWHEEL", BACCARAT:"BACCARAT", ...
   # 拿到 client enum 字符串值（大写常量），记入 client_gametype_enum
   ```
   **jackpotwheel 教训**：DB game_type="jackpotwheel" → fallback PascalCase "Jackpotwheel"
   → client `toUpperCase()` = "JACKPOTWHEEL" ≠ "MEGAWHEEL" → history default ERROR_TITLE。
   **必须**在 `history_parse.go:gameTypeMap` 加显式映射 `"jackpotwheel": "Megawheel"`。

3. **消息三分类预判**（Phase 4 Q5 输入）：每个事件先打 A/B/C 三类标签：
   - A 上游 → 直接转发（pass）
   - B 上游 → server 修改后转发（rewrite，如 betstats EnrichBetstats / table B1 tableId 替换）
   - C 上游不发 → server 自合成（synthesize，如 subscribe ack / bet echo / win 私聊 / betValidationError）

**B5 验收**：JSON 合法 + jq parse 过 + 关键字段非空 + `init_frame_sequence` ≥ 4 项（最少
table/dealer/game/timer） + `client_gametype_enum` 含本机台 enum 值 + `message_classification`
含全部 P0 事件分类

**下游消费**：codex review prompt 数据源 + 经验文档第 4 节

---

## L1.3 — ERRCODE

**产物**：`tmp/<tableId>/error_codes.md`（**非代码，是分析文档**）

**分析输入**：
- `tmp/<tid>/message.txt` 实际触发的 betValidationError 帧（通常 2-5 个组合）
- main.js grep 所有 errorCode 字面量（30-50 个全集）
- main.js client switch 分支（rejectBet 清筹码 / sessionTimeout 弹窗 / generic alert / 静默）
- `extendedErrorCode` 触发器（**仅 9018 InvalidToken 触发 SESSION_TIMEOUT** — known-pitfalls I3 dragontiger 教训）

**实现内容**（3 节 markdown）：
1. **errorCode 全集表**：码值 / 名称 / 客户端 switch 分支 / extendedErrorCode 触发关系
2. **客户端展示形式表**：rejectBet / sessionTimeout / generic alert / 静默
3. **后端调用路径建议表**：
   - `parseBets` 失败 → `ErrCodeInvalidBetFormat`
   - 窗口关闭 → `ErrCodeBetNotOnTime`
   - BC 不在白名单 → `ErrCodeUnknownBetCode`
   - 单注超限 → `ErrCodeBetTooLow/TooHigh`
   - 台限超 → `ErrCodeTableLimitExceeded`
   - InvalidToken → `ErrCodeInvalidToken` + `extendedErrorCode="9018"`
   - FreeChip 未实现 → `ErrCodeFreeChipUnknownError`（B11）

**B5 验收**：3 节齐全 + 至少 30 项 errorCode 列出

**下游消费**：DOWNSTREAM_BET / SETTLE / CHECK_BET 调用错误码时参考

---

## AIU prompt 模板（按 L1 通用，每 AIU 各替换）

```
你是 AIU-<NAME>（Layer 1），做 PP 机台 <tableId> (<gametype>) 对接的"分析 + 实现 <产物>"工作单元。

## 工作区
- worktree: <worktree_path>（cd 保持，不切分支）
- 当前分支: <worktree_branch>
- HEAD: <head_sha>（worker-1 起点）
- 主仓库: <repo_root>

## 分析阶段（in-context）

### 输入（按 source 优先级读，**不读全部**）
1. capture（事实最高权威）：
   - <list 本 AIU 需要的具体文件 + 读哪部分>
2. main.js（capture 缺失时补）：
   - 关键 grep：<具体命令>
3. 上游 AIU 产物：L1 无上游
4. 既有 server 骨架参考：
   - <dragontiger / baccarat6 对应文件>

### 分析任务（具体 1-3 个问题）
<本 AIU 特化的任务>

## 实现阶段

### 目标文件
<具体路径>

### 实现要点
<本 AIU 实现内容清单>

### 实现约束
1. 单文件 ≤ 500 行（超就拆，但仍属本 AIU）
2. 注释最少（默认不写，仅 WHY 非显然时一行）
3. 不读 /Users/luca/work/ppgame 老项目
4. 协议铁律遵守（B/C/G/I 节）

### 验收
1. go build PASS
2. go vet 无新增 warning
3. 本 AIU 需要的单测 PASS（若有）
4. policy-pr ≤ 500 行
5. git commit

## 完成回报（B5 契约）
1. commit sha
2. git show --stat HEAD
3. build/vet/test 结果
4. 关键决策（与既有骨架差异 / 与 capture 验证情况）

最后一句："等待主 claude 验收并启动 Layer N+1"
```

---

## L1.4 — CLIENT_FRAME_EFFECTS（**新增，L2.1 MODELS 强依赖**）

> **设计动机**（jackpotwheel 教训）：L2.1 MODELS 写 struct 字段类型 / omitempty /
> 嵌套对象时，**必须理解每个字段在客户端的作用**才能正确决策。比如
> `jackpotwheel_rng.slot` 不能扁平化是因为客户端按嵌套对象 `{number, multiplier}`
> 解构；`bet.megawin` 是字符串 `"true"`/`"false"` 不是 bool 是因为客户端严格字符串
> 比较。这些都必须先做客户端反向分析才知道。
>
> L1.4 把"每帧客户端表现 + 每字段在客户端如何用"沉淀成手册，L2.1 / L3 / L4 全程
> 引用，Phase 7 归档时直接进经验文档 §16（后续相同 gameType 机台对接复用）。

**产物**：`tmp/<tableId>/client_frame_effects.md`（**非代码，下游 AIU 共用数据源**）

**分析输入**：
- L1 DICT 输出（事件全集）— 边做边参照
- main.js + lazy chunks（reducer / action / state 字段定义）
- L1 ENUM 输出（事件常量名 — 标准化命名）
- capture 真帧（字段实际类型 / 值范围）

**实现内容**（markdown 结构，按 server→client 帧分类）：

```markdown
## §1 init 阶段帧（handleConnect 必发，"最少 + 最必要"原则）

### 1.1 `{"subscribe":{...}}`
- **分类**: C 自合成（PP 上游 server-side 新连接时发 1 次，多 client fan-out 必须各自合成）
- **客户端 reducer**: `onSubscribeSuccess` (main.js @<offset>)
- **state 字段切换**: `isTableSubscribed: false → true`
- **UI 表现**: 解锁桌面渲染 + 启动 ping 心跳 + 解锁下注 area
- **缺失影响**: 客户端 isTableSubscribed 永 false → 永不发 ping → 10s 后断连（jackpotwheel #12）
- **字段说明**:

  | 字段 | 类型 | 客户端用途 | server 填法 |
  |---|---|---|---|
  | `channel` | string | 客户端 channel 路由（消息按 channel 分发） | `"table-" + ctx.TableID` |
  | `table` | string | 校验 channel 一致性 | `ctx.TableID` |
  | `status` | string | **唯一触发解锁的值是 `"success"`**；其他值进错误分支 | 固定 `"success"` |
  | `seq` | int | 单调递增防重 | `atomic.AddInt64(&p.frameSeq, 1)` |

### 1.2 `{"table":{...}}`
...（按上述格式逐帧填）

## §2 运行时帧（订阅成功后随回合推送）

### 2.1 `{"betsopen":{...}}`
### 2.2 `{"betsclosed":{...}}`
### 2.3 `{"bet":{amount, betcode, seq}}` ← 我方 accepted echo
- **触发时机**: PP 真服 capture 实测 `betsclosed` 后 ~1.4s（商户落账确认后）
- **我方实现路径**: `pendingBetEcho` 缓存 → `OnMerchantBetResult` accepted 分支 echo
- **若错时机**（lpbet 即时回响）: 客户端可能在 betsclosed 前接收 bet，触发 UI 抖动 / 重复扣款显示（jackpotwheel #14）
...

## §3 结算帧

### 3.1 `{"<gametype>gameresult":{...}}`
### 3.2 `{"winners":{...}}` (PP 全网瀑布，B2 pass 透传)
### 3.3 `{"win":{...}}` (我方私聊，FlushPendingWins 合成)
- **触发时机**: winners 帧后 WinnersBroadcastDelay (~500ms)
- **seq 必填非 0**（jackpotwheel #15）
- **megawin "true"/"false" 严格字符串**（jackpotwheel A1 协议保真）

## §4 错误帧

### 4.1 `{"betValidationError":{...}}`
- **7 字段全填**（B9 协议铁律）
- **`extendedErrorCode` 仅 InvalidToken 触发场景填 "9018"**（I3 dragontiger 教训）

## §5 心跳

### 5.1 `{"pong":{channel, time, seq}}`
...

## §6 状态机映射总览

| 客户端 state 字段 | 触发帧 | 触发时机 | 必发? |
|---|---|---|---|
| `isTableSubscribed` | subscribe.status=success | handleConnect | ✅ |
| `state.table.value` | table.value | handleConnect | ✅ |
| `state.dealer.value` | dealer.value | handleConnect / dealerchange | ✅ |
| `state.game.currentGameId` | game.id | handleConnect + 每局 | ✅ |
| `state.game.bettingOpen` | betsopen / betsclosed | 每局 | 运行时 |
| ... | | | |
```

**实现约束**：
1. 每帧**必须**含 6 字段：`分类` / `客户端 reducer` (main.js evidence) / `state 字段切换` / `UI 表现` / `缺失影响` / `字段说明表`
2. 字段说明表每字段**必须**含：类型 / 客户端用途 / server 填法
3. 严禁泛化（"用于显示" / "客户端渲染"）— 必须具体到 reducer 名 + state 字段 + UI 元素
4. 字段类型必须 grep capture 真帧验证（如 megawin 是字符串 `"true"` 不是 bool）

**B5 验收**：
- 文档 ≥ 60 行，覆盖 init 序列 + 主要运行时帧 + 错误帧 + 心跳
- 每帧 6 字段齐全
- main.js evidence 行号实证（grep 命中行）
- 与 capture 实证对照（字段类型 / 值范围）

**下游消费**：
- **L2.1 MODELS**：写 struct 字段类型 / omitempty / 嵌套对象时必读
- **L3.1 UPSTREAM**：handleConnect init 序列实现时按本文档逐帧实现
- **L3.2 DOWNSTREAM_BET**：bet echo / betValidationError 字段时机参照
- **L3.3 SETTLE**：win 帧 / pendingWinEntry 字段参照
- **L4.2 BETSTATS / L4.3 WINNERS**：rewrite/pass 路径决策
- **Phase 7 归档**：复制进经验文档 §16 客户端帧表现手册
