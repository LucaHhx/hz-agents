# Capture 数据验收指标

## 目的

PP 机台 capture 数据由**用户**手动录制后提供（AI 不再自动跑 fetch_client.mjs）。本文件定义 4 份产物文件的验收指标，决定 capture 是否足以驱动 Phase 3 ~ Phase 7 全流程。

## 适用阶段

Phase 2 — 用户提供 capture 后，AI 调 `scripts/capture_verify.sh <tableId> <gametype>` 跑一遍指标：

| 退出码 | 含义 | 主流程动作 |
|---|---|---|
| 0 | P0 全过 + P1 警告 ≤ 2 项 | 写 state.phase=2 status=done → 自动进 Phase 3 |
| 1 | P0 任一未过 | **拒收** + 列具体补救建议 + 停（不进 Phase 3，不让 agent-5 反推） |
| 2 | P1 警告 > 2 项 | 写 state.phase=2 status=degraded → 让用户决定是否补录或硬走（不默认继续） |

## 4 份必备文件

| 文件 | 内容 | 产生方式 |
|---|---|---|
| `tmp/<tableId>/message.jsonl` | game WS 双向帧（recv + send），JSONL 每行一条 | fetch_client.mjs 录制 |
| `tmp/<tableId>/tableConfig.jsonl` | tableConfig API 响应 body，JSONL | 同上 |
| `tmp/<tableId>/statisticHistory.jsonl` | statisticHistory API 响应 body，JSONL | 同上 |
| `tmp/<tableId>/gameDetail.txt` | game.jsp 单局详情 XML，每行一条压缩 XML | 同上（玩家点"详情"才触发） |
| `tmp/<tableId>/clientResources/apps/<gametype>/<ver>/main.js` | 客户端 main.js + chunks | 同上（资源落盘） |

## 验收指标分级

### 🔴 P0 — 必须通过（任一不达标 = 拒收）

| # | 指标 | 阈值 | 检测命令 | 不通过含义 / 补救 |
|---|---|---|---|---|
| 1 | 4 个文件齐全 | message.jsonl / tableConfig.jsonl / statisticHistory.jsonl 必须存在 + 非空；gameDetail.txt 可空 | `[[ -s message.jsonl && -s tableConfig.jsonl && -s statisticHistory.jsonl ]]` | 缺核心数据，无法进 Phase 3 |
| 2 | 客户端资源齐全 | `clientResources/apps/<gametype>/<ver>/main.js` 存在 | `find clientResources -name main.js \| head -1` | 反推 main.js 静态字面量都做不了 |
| 3 | **上行 send 帧 ≥ 5** | 验证 anti-bot 通过、客户端真发包 | `jq -s '[.[]\|select(.dir=="send")]\|length' message.jsonl` | **0 帧 = headless 被 anti-bot 拦** → 改 headed 或加 stealth 注入重抓 |
| 4 | **上行 lpbet ≥ 2** | I6 incremental 协议至少 2 次连续下注样本 | `jq -s -r '.[]\|select(.dir=="send")\|.payload' message.jsonl \| grep -c lpbet` | 无法验证 incremental vs 全量；I6 是 dragontiger 资金 P0 教训。补救：下两笔不同段位/不同金额的注 |
| 5 | 关键 4 事件齐全 | `betsopen` / `betsclosed` / `<gametype>gameresult` 或 `gameresult` / `winners` 各 ≥ 1 | 4 次 grep | 协议决策表 §2 没样本验证；result/winners 缺失 = 资金路径无样本 |
| 6 | **≥ 2 局完整循环** | `betsopen → betsclosed → gameresult → winners` 严格按时序至少出现 2 次 | timestamp 排序 + 状态机扫描 | 单局不足以验证一轮稳定性；连贯样本 ≥ 2 局才能写 payout_test 4 个样本（F1） |
| 7 | 4 事件数量对齐 | betsopen / betsclosed / gameresult / winners 计数相等 | 4 次 grep + 比较 | 不对齐 = capture 起点切在局中 / 漏录中段；补录前检查 fetch_client.mjs 是否在局间启动 |
| 8 | tableConfig.jsonl ≥ 1 | 至少一次完整推送 | `wc -l tableConfig.jsonl` | §7 一致性矩阵 enforce 列没数据源 |

### 🟡 P1 — 应该通过（不通过 → 警告，> 2 项时停）

| # | 指标 | 阈值 | 检测命令 | 不通过含义 |
|---|---|---|---|---|
| 9 | 总帧数 ≥ 100 | 5min capture 应在 100~500 帧间 | `wc -l message.jsonl` | 帧太少 = 客户端没真正进游戏 / WS 早断 |
| 10 | 帧时间跨度 ≥ 60s | recv 第一帧到最后一帧 timestamp 跨度 | `jq -s 'map(.ts) \| max - min' message.jsonl` | 跨度小 = capture 中途客户端断了 |
| 11 | statisticHistory.jsonl ≥ 1 | 初始化时客户端会拉一次历史 | `wc -l statisticHistory.jsonl` | 没拉 = 客户端没真正完成 init / anti-bot 拦截 |
| 12 | send ping ≥ 3 | 10s 一次心跳，5min 应有 ~28 次 | grep '<ping ' | ping 少 = WS 中途断了 |
| 13 | 机台特化关键事件 | 按 gametype 而定（见下表） | grep gametype-specific | 协议决策表 §2 该机台核心 verdict 无样本 |
| 14 | tableConfig 含核心限额字段 | 顶层有 `params` + 9 个/N 个 `<segment>_bet_min/max`（按 gametype） | jq 取字段 + 计数 | enforce 列字段名校对没数据 |

#### 机台特化关键事件清单（P1 #13）

| gametype | 必须 ≥ 1 的特化事件 | 说明 |
|---|---|---|
| `jackpotwheel` (megawheel) | `jackpotwheel_rng` / `megawheelgameresult` | RNG MEGA_MULTIPLIER 子局 + 命名 gameresult |
| `baccarat` 系列 | `card` / `cardinc` / `ShoeSummary` / `disablesidebets` | 发牌流 + 路单 + 边注禁用 |
| `roulette` 系列 | `winningBetCodes` / `betSpotWin` | roulette 必合成的两个帧 |
| `sweetbonanza` (slot) | `candy_drop` / `enableSubmit` / `sweetbonanzagameresult` | bonus 阶段事件 |
| `dragontiger` | `dragontiger_gameresult` / `startDealing` | 真人桌发牌 |
| `oneblackjack` | `decision` / `dealCard` | 用户决策 + 发牌 |

### 🟢 P2 — 可选（缺也不影响主路径）

| # | 指标 | 阈值 | 检测命令 | 说明 |
|---|---|---|---|---|
| 15 | `gameDetail.txt` ≥ 1 | 玩家手动点"我的历史详情"才触发 | `grep -c '^<' gameDetail.txt` | 0 时 history XML parser 单测只能构造样本；≥ 1 时字段名 100% 权威。**强烈推荐 ≥ 1** |
| 16 | 罕见事件样本 | `canceled` / `session` / `decisionError` / `switch` / `duplicated_connection` 等 | grep 各事件 | 无法验证罕见 verdict 但默认 pass 兜底安全 |
| 17 | send 跨段位 lpbet ≥ 2 | 不同 betCode 的 lpbet 各 ≥ 1 | grep 解析 lpbet bc 属性 | 用于验证 I7 partial-accept + 跨段位累加；单段位也能做单测 |

## 详细补救建议（按 P0 失败项分类）

### #1 #2 文件 / 资源缺失

```
补救：
  1. 检查 fetch_client.mjs 是否真的被 5min 跑完（未被 SIGINT 中途断）
  2. 检查 tmp/<tableId>/ 目录是否被误删
  3. 重抓
```

### #3 send 帧 0 (anti-bot 检测)

```
补救：
  1. 改 HEADLESS=false 用有头模式重抓（最稳）
  2. 或在 fetch_client.mjs 加 stealth 脚本注入：
     await ctx.addInitScript(() => {
       Object.defineProperty(navigator, 'webdriver', {get:()=>false});
       window.chrome = {runtime:{}};
       // ...更多反检测
     });
  3. 终极兜底：用户手动开 Chrome + 装扩展（如 SingleFile + WebSocket Capture）录
```

### #4 lpbet < 2 (incremental 协议验证不足)

```
补救：
  补录时手动下 2-3 笔不同情况的注：
  - 第 1 笔：押 1x 段位 1.00 (验证 lpbet 第一帧)
  - 第 2 笔：再押 5x 段位 1.00 (验证 lpbet 第二帧是 incremental 仅含 5x 还是全量含两段)
  - 可选第 3 笔：撤销 1x 段位 (验证空 lpbet / -1 协议)
```

### #5 #6 #7 局数 / 事件不齐

```
补救：
  1. 确保 capture 启动后等下一个 betsopen 才开始计时（5min 才稳）
  2. megawheel/baccarat 等真人桌 ~30s/局，5min 抓得到 6-10 局
  3. 如果 5min 抓到 < 2 局 → 改 DURATION_MS=10*60*1000 重抓
  4. 检查是否 capture 启动后客户端断了（看 [WS] 断开日志）
```

### #8 tableConfig 0 条

```
补救：
  tableConfig 通常初始化时拉一次，理论上必有。
  如果 0 条：
  1. 检查 fetch_client.mjs HTTP_FILTERS 是否含 'tableConfig' 关键字
  2. 检查 anti-bot 是否在 HTTP 层拦截（[HTTP] 日志看响应状态）
```

## 实现位置

**脚本**：`scripts/capture_verify.sh`（与本文件同步实现，在流程优化阶段写）
**主流程**：Phase 2 入口由 SKILL.md / workflow.md 引用，用户提供 capture → AI 调脚本 → 按退出码分流

## 与其他规范的关系

- 替代 SKILL.md / workflow.md 中 "缺关键事件 → agent-5 反推" 的 degraded 兜底路径
- 与铁律 7（`feedback_no_skip_har.md`：禁止跳过 HAR）一致：capture 不达标 = 停，不让流程往下走
- 与铁律 1（完全无人值守）的边界：capture 验收 P0 失败时 AI 停下报告**具体补救**给用户，不再尝试静态反推绕过

## 历史教训（驱动本指标的真实案例）

| 案例 | 当时做法 | 后果 | 本指标对应 |
|---|---|---|---|
| md500q83g7cdefw1 (megawheel) 首次对接 | capture 0 帧标 degraded → agent-5 main.js 反推 → 5 agent + design + 4 worker 写 6000 行代码 | codex Round 1 暴露 1 个字段名错；用户重抓后才发现 3 个反推错（gameresult.value 是数字非命名 / jackpotwheel_rng.slot 嵌套对象 / 字段不全 sector duration r 缺）+ 1 个协议形态错（下行 JSON envelope 而非 XML） | #3 anti-bot 检测 / #5 关键事件 / #7 事件对齐 |
| megawheel 验证 send lpbet 只 1 条 | 接受 1 条进 codex | 无法验证 I6 incremental → 整批覆盖 bug 可能潜在 | #4 lpbet ≥ 2 |
