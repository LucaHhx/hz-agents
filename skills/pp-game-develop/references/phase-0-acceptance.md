# Phase 0 — 用户输入验收（AI 自检指南）

> AI 自检模式：根据 gametype 动态选择关键事件清单和 tableConfig 字段清单，跑 17 项通用指标 + 机台特化检查，综合判断后写 state.json。**不用脚本**，AI 直接 bash/jq/grep。
> 阶段允许问用户：✅ 验收失败时可向用户列具体补救建议。

## 1. AI 执行步骤

```
1. 进入仓库根：cd $(git rev-parse --show-toplevel)
2. 定位 capture 目录（关键，目录名 != PP tableId）：
   - 用户给的 ID 可能是 PP tableId（"gatesofolympus01"）或 capture 目录名（"2244"，hall external_code）
   - 先试 tmp/<INPUT_ID>/ 是否存在且含 tableConfig.txt
   - 不存在则扫 tmp/*/tableConfig.txt 反查 .tableId == INPUT_ID 的目录
   - 找到后：capture_dir = 目录名（数字 / external_code），pp_table_id = tableConfig.tableId（真实 PP 字符串）
   - 两者一致时（罕见，老 capture）按 input 直接当目录用
3. 确认 6 文件齐全：tmp/<capture_dir>/{message.txt, tableConfig.txt, statisticHistory.txt, gameDetail.txt, roundDetail/, clientResources/} 都存在
4. 跑通用指标（§2）
5. 推断 gametype（先 grep clientResources/apps/ 路径 + release.json + translations-help 文件名）
6. 按 gametype 跑特化检查（§3）
7. 综合 P0/P1/P2 判断（§4）
8. 抽元信息（§5，注意区分 capture_dir 和 pp_table_id）
9. 写 state.json（§6 模板）
10. 输出报告
11. 失败时给用户具体补救建议（§7）
```

## 2. 17 项通用指标速查表

### 🔴 P0 必须通过（任一未过 = 拒收）

| # | 指标 | AI 检测命令 |
|---|---|---|
| 1 | 3 个数据文件齐全 + 非空（内容 JSONL） | `[[ -s tmp/<capture_dir>/message.txt && -s tmp/<capture_dir>/tableConfig.txt && -s tmp/<capture_dir>/statisticHistory.txt ]]` |
| 2 | main.js 存在 | `find tmp/<capture_dir>/clientResources/apps -maxdepth 3 -name main.js \| head -1` |
| 3 | 上行 send 帧 ≥ 5 | `jq -s '[.[]\|select(.dir=="send")]\|length' tmp/<capture_dir>/message.txt` |
| 4 | 上行 lpbet ≥ 2 | `jq -s -r '.[]\|select(.dir=="send")\|.payload' tmp/<capture_dir>/message.txt \| grep -c '<lpbet '` |
| 5 | 4 关键事件齐全 | 按 gametype 查（见 §3）|
| 6 | ≥ 2 局完整循环 | 取 betsopen/closed/result/winners 计数最小值 ≥ 2 |
| 7 | 4 事件数量对齐 | 4 个计数应相等 |
| 8 | tableConfig.txt ≥ 1 | `wc -l tmp/<capture_dir>/tableConfig.txt` |

### 🟡 P1 应该通过（> 2 项警告 → degraded 询问用户）

| # | 指标 | AI 检测 |
|---|---|---|
| 9 | 总帧数 ≥ 100 | `wc -l tmp/<capture_dir>/message.txt` |
| 10 | 时间跨度 ≥ 60s | `jq -s '(map(.ts)\|max-min)/1000' tmp/<capture_dir>/message.txt` |
| 11 | statisticHistory ≥ 1 | `wc -l tmp/<capture_dir>/statisticHistory.txt` |
| 12 | send ping ≥ 3 | `jq -s -r '.[]\|select(.dir=="send")\|.payload' ... \| grep -c '<ping '` |
| 13 | 机台特化关键事件 | 按 gametype 查（见 §3）|
| 14 | tableConfig 含核心限额字段 | 按 gametype 查（见 §3）|

### 🟢 P2 可选

| # | 指标 | AI 检测 |
|---|---|---|
| 15 | gameDetail.txt ≥ 1（**BuildGameDetail 数据源**） | `grep -c '^<' tmp/<capture_dir>/gameDetail.txt` |
| 16 | roundDetail/ ≥ 1 完整对（**BuildGameReport 数据源**） | `ls tmp/<capture_dir>/roundDetail/*.html 2>/dev/null \| wc -l`（≥ 1 含基线 + Details） |
| 17 | 罕见事件样本 | grep `canceled\|session\|decisionError` |
| 18 | 跨段位 lpbet | grep `bc="..."` 抽不同值 ≥ 2 |

## 3. 机台特化检查清单（**AI 按 gametype 选**）

### gametype = `jackpotwheel` (megawheel)

**P0 #5 关键事件**：
- `betsopen` / `betsclosed` / `megawheelgameresult` / `winners` 各 ≥ 1

**P1 #13 机台特化事件**：
- `jackpotwheel_rng` ≥ 1（MEGA_MULTIPLIER 子事件）
- `mwDealing` ≥ 1（开始旋转事件）

**P1 #14 tableConfig 核心字段**：
- 顶层：`tableId` / `operatorGameId` / `params`
- 9 段位限额：`one_bet_min/max` / `two_bet_min/max` / `five_*` / `eight_*` / `ten_*` / `fifteen_*` / `twenty_*` / `thirty_*` / **`fourty_bet_min/max`** ⚠️ PP typo
- 总台限：`table_bet_min_limit` / `table_bet_max_limit`
- 派彩封顶：`maxMultiplier` / `euro_table_payout_max` / `table_payout_max`

### gametype = `baccarat` 系列（含 speedbaccarat / amazingbaccarat / megabaccarat / fortune6 等）

**P0 #5 关键事件**：
- `betsopen` / `betsclosed` / `gameresult` / `winners`

**P1 #13 机台特化事件**：
- `card` 或 `cardinc` ≥ 1（发牌帧）
- `ShoeSummary` ≥ 1（牌靴）
- `disablesidebets` ≥ 1（边注禁用）

**P1 #14 tableConfig 核心字段**：
- 主投注限额：`banker_bet_min/max` / `player_bet_min/max` / `tie_bet_min/max`
- 边注限额（如有）：`player_pair_bet_*` / `banker_pair_bet_*` / `dragon_bet_*` / etc.
- 总台限 / 派彩封顶同 megawheel

### gametype = `roulette` 系列（含 megaroulette / autoroulette / poweruproulette / lucky6roulette / crystalroulette）

**P0 #5 关键事件**：
- `betsopen` / `betsclosed` / `gameresult` / `winners`

**P1 #13 机台特化事件**：
- `winningBetCodes` ≥ 1（中奖号码）
- `betSpotWin` ≥ 1（每注派彩，roulette 系列必发）

**P1 #14 tableConfig 核心字段**：
- 直注 / 列 / 行 / 红黑 / 单双等限额（按 roulette 子类）
- `straight_up_bet_*` / `column_bet_*` / `dozen_bet_*` 等

### gametype = `sweetbonanza` (slot 类)

**P0 #5 关键事件**：
- `betsopen` / `betsclosed` / `sweetbonanzagameresult` 或 `gameresult` / `winners`

**P1 #13 机台特化事件**：
- `candy_drop` 或 `enableSubmit` ≥ 1（bonus 阶段触发）
- `sbz_gr` 或类似 slot 结果字段

**P1 #14 tableConfig 核心字段**：
- `bet_min` / `bet_max`（slot 总单注）
- bonus 触发倍率 / freespin 倍率
- `sbBooster` 相关

### gametype = `dragontiger`

**P0 #5 关键事件**：
- `betsopen` / `betsclosed` / `dragontiger_gameresult` / `winners`

**P1 #13 机台特化事件**：
- `startDealing` ≥ 1
- `card` 或 `cardinc` ≥ 1

**P1 #14 tableConfig 核心字段**：
- `dragon_bet_min/max` / `tiger_bet_min/max` / `tie_bet_min/max`
- 边注：dragon_red / tiger_odd 等

### gametype = `oneblackjack`

**P0 #5 关键事件**：
- `betsopen` / `betsclosed` / `gameresult` / `winners`

**P1 #13 机台特化事件**：
- `decision` ≥ 1（用户决策）
- `dealCard` ≥ 1（发牌）

**P1 #14 tableConfig 核心字段**：
- `bj_bet_min/max`
- 边注：perfect_pair / 21+3 等

### 未列 gametype（新对接首例）

主 AI 自行 grep main.js 提取：
- 事件名：`grep -oE '"<gametype>?[a-z]*gameresult":\|"betsopen":\|"betsclosed":' main.js | sort -u`
- tableConfig 字段：`jq -s '.[0].params | keys' tmp/<tid>/tableConfig.txt`
- 然后判断哪些是关键

## 4. P0/P1/P2 综合判断

```
P0 全过 + P1 警告 ≤ 2 → status="done"，进 Phase 1
P0 任一未过 → status="failed"，拒收 + 给用户补救（见 §7）→ 停
P0 全过 + P1 警告 > 2 → status="degraded"，向用户报告问题 → 询问是否继续（Phase 0 可问）
```

## 5. 元信息抽取（AI 用 jq）

> ⚠️ **目录名 ≠ tableId**：`capture_dir`（hall external_code，数字）只用于 tmp/<capture_dir>/ 路径；
> `tableId`（PP 内部字符串）才是 enum.TableID / 机台目录名 / instance_factory 注册键。
> 两者必须严格区分（来源：J8）。

| 字段 | 来源 + 命令 |
|---|---|
| `capture_dir` | §1 第 2 步定位的目录名（如 "2244"），所有 tmp/ 路径用 |
| `tableId` | `jq -s -r '.[0].tableId' tmp/<capture_dir>/tableConfig.txt`（真实 PP tableId，如 "gatesofolympus01"） |
| `operatorGameId` | `jq -s -r '.[0].operatorGameId // empty' tmp/<capture_dir>/tableConfig.txt`（一般 = capture_dir） |
| `gameLoaderKey` | `ls -d tmp/<capture_dir>/clientResources/apps/*/` 取非 video/feature-flags/translations-* 之外的目录名 |
| `gameType` | 优先 release.json：`jq -r '.gametype' tmp/<capture_dir>/clientResources/apps/<gameLoaderKey>/*/release.json`；fallback `ls tmp/<capture_dir>/clientResources/apps/translations-help/latest/*/` 任一 zh 等语言下非 common.json 的文件名（去 .json） |
| `limits.min/max` | `jq -s -r '.[0].params.table_bet_min_limit, .params.table_bet_max_limit' tmp/<capture_dir>/tableConfig.txt` |
| `dealer.name` | `jq -s -r '.[]\|select(.dir=="recv")\|.payload' tmp/<capture_dir>/message.txt \| grep -oE '"dealer":\{[^}]*"value":"[^"]+"' \| head -1 \| grep -oE '"value":"[^"]+"' \| cut -d'"' -f4` |
| `dealer.location` | grep roundDetail/*.html `dealerVO.location` 字段（如 "Bucharest"）或 main.js（如有） |

## 6. state.json 写入模板

```bash
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
jq -n \
    --arg tableId "<pp_table_id>" \
    --arg capture_dir "<capture_dir>" \
    --arg repo_root "$(git rev-parse --show-toplevel)" \
    --arg ts "$TS" \
    --arg status "done|failed|degraded" \
    --arg operatorGameId "<...>" \
    --arg gameLoaderKey "<...>" \
    --arg gameType "<...>" \
    --arg dealer "<...>" \
    --arg dealerLocation "<...>" \
    --arg min "<...>" \
    --arg max "<...>" \
    --argjson p0_passed "true|false" \
    --argjson p1_warnings '["#10 跨度 58s","..."]' \
    --argjson p2_status '["#15:✓","#16:missing"]' \
    '{
        tableId: $tableId, capture_dir: $capture_dir, repo_root: $repo_root,
        phase: 0, status: $status,
        lobby: {
            tableId: $tableId, operatorGameId: $operatorGameId,
            gameLoaderKey: $gameLoaderKey, gameType: $gameType,
            limits: {min: $min, max: $max},
            dealer: {name: $dealer, location: $dealerLocation}
        },
        capture_audit: {
            p0_passed: $p0_passed,
            p1_warnings: $p1_warnings,
            p2_status: $p2_status
        },
        codex_reviews: [], codex_decisions: [], codex_discussions: [],
        unresolved: [],
        last_updated: $ts
    }' > tmp/<capture_dir>/state.json
```

## 7. 失败补救建议（按发现的具体问题动态生成）

AI **不要**硬背模板。按实际触发的 P0/P1 失败项 + 当前 capture 状态 + 机台类型综合给建议。例如：

- 「#3 send=0 + gametype=jackpotwheel」→ "PP megawheel 客户端有 anti-bot 检测，建议改 HEADLESS=false 用 headed 模式重抓"
- 「#4 lpbet=1 + 段位是 megawheel 9 段位」→ "需要补押第 2 笔不同段位（如本次押 1x，下次押 5x），用于验证 incremental 协议合并逻辑"
- 「#5 megawheelgameresult=0 + 抓了 5min」→ "可能 5min 不够 megawheel 真人桌出 1 局结算（30-45s/局），改 DURATION_MS=10*60*1000 重抓"
- 「#7 betsopen=7 betsclosed=6 result=6 winners=6」→ "capture 起点切在某局的 betsopen 之后（多一个 betsopen），尝试在客户端进入桌面 + 等下一个 betsopen 后才开始计时"
- 「#8 tableConfig=0」→ "客户端可能没拉 tableConfig（anti-bot HTTP 层拦），看 fetch_client.mjs HTTP_FILTERS 是否含 'tableConfig' 关键字 + 检查 [HTTP] 响应日志"

通用补救参考：pp-game 仓库 `docs/integration-experience/common/capture-acceptance.md` §"失败补救建议"。
