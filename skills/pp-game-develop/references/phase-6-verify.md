# Phase 6 — verify 全量验收（AI 自检指南）

> 触发：Phase 5 整体 codex review fix 完成。
> 14 项验收（5 确定性 + I9/I10a/I10b/V8/V9 语义判断 + V10-V13 生产 bug 复盘闸门 + V14 赢钱反推验证）。
> 阶段：❌ 禁止向用户提问；失败首次 Claude 自修；≥2 次走 codex_decide 根因分类。

## AI 执行步骤

```
1. cd <worktree>
2. 按顺序跑 13 项验收（详见 §2 起）
3. 任一项失败：
   - 首次：Claude 自修（小问题）+ 重跑该项
   - ≥2 次：调 codex_decide.sh 根因分类（见 codex-collab.md D5）
   - 决策不收敛：调 codex_discuss.sh ≤ 2 轮（S3）
4. 全 13 项 PASS → 进 Phase 7 归档
5. 全程不停问用户
```

## 13 项验收

### V1. go build

```bash
cd <worktree>/server && go build ./...
```

PASS 标准：退出 0 + 无 stderr 报错。

### V2. go vet

```bash
cd <worktree>/server && go vet ./...
```

PASS 标准：退出 0 + **无新增 warning**（与 base 分支对比）。

### V3. go test -race

```bash
cd <worktree>/server && go test -race -count=3 ./game/pp/internal/games/<gametype>/<tableId>/...
```

PASS 标准：3 次全 PASS + 无 race detected。

### V4. cover ≥ 25%

```bash
cd <worktree>/server && go test -cover ./game/pp/internal/games/<gametype>/<tableId>/...
```

PASS 标准：coverage 输出 `25.0%` 及以上。

不达标时 AI 按 `<repo>/docs/integration-experience/common/test-design-guide.md` 补单测（F1：payout_test ≥ 4 capture 真帧 / 边注断言 / 不参与字段忽略断言）。

### V5. policy-pr

```bash
cd <worktree>
git diff --name-only --diff-filter=ACMR <base_branch>...HEAD | node scripts/ci/policy-pr.mjs --stdin
```

PASS 标准：单文件 ≤ 500 行 + 嵌套 ≤ 3 层。

超限时 AI 按职责拆文件（参考既有 commit 风格，如 dragontiger 的拆法）。

### V6. I9 双向协议矩阵（语义判断，AI 跑）

**目的**：客户端 → server 的所有 XML 帧（capture send）vs server 端 ClientCommand struct 字段；server → 客户端的所有帧 vs 客户端 socketHandler case 标签。

**AI 检查步骤**：

```bash
# A. 客户端→server XML 帧 → 抽出所有 root tag + 属性
jq -s -r '.[]|select(.dir=="send")|.payload' tmp/<tid>/message.txt | grep -oE '<[a-zA-Z]+[^/]*>' | sort -u

# B. server 端 ClientCommand struct → grep
grep -rE 'type Client[A-Z][a-zA-Z]*Cmd' <worktree>/server/game/pp/internal/games/<gametype>/<tableId>/

# C. 输出对照表：每客户端帧 → server 是否能解析
# D. server→客户端帧 → grep xml.Marshal / json.Marshal 发出的帧
# E. 客户端 main.js → socketHandler case 标签
# F. 输出对照表：每 server 帧 → 客户端是否消费
```

**PASS 标准**：每客户端发的 XML root tag 在 server 有 struct 对应；每 server 主动发的帧在 main.js socketHandler 有 case。

**FAIL 处理**：如 dragontiger 历史教训 — 客户端发 `<placeBet>` 单数但 server 仅识别 `<lpbet>` 复数 → 走 default 默默 ack 不落库 → 协议不通。任一行 ❌ → 必须修。

### V7a. I10 BuildGameDetail 真 XML 单测（语义判断，AI 跑）

**目的**：机台内 `history_test.go` 用 `tmp/<capture_dir>/gameDetail.txt` 真 XML 跑 BuildGameDetail，断言关键字段非空。

**AI 检查步骤**：

```bash
DIR=<worktree>/server/game/pp/internal/games/<gametype>/<tableId>
# 1. 取真 XML 样本
head -1 tmp/<capture_dir>/gameDetail.txt > /tmp/sample.xml
# 2. 找 history_test.go 是否有真 XML 测试（机台内，不是 runtime/）
grep -rE 'gameDetail.txt|TestBuildGameDetail.*real|os.Open.*gameDetail' "$DIR"/history_test.go
# 3. 跑测试
cd <worktree>/server && go test -v -run "TestBuildGameDetail" "./game/pp/internal/games/<gametype>/<tableId>/..."
```

**PASS 标准**：
- 单测含至少 1 个用真 XML 的测试函数
- 断言关键字段非空：gameResult / multiplier / payout / bc / 机台特化（如 olympusRouletteDetails）等
- I8：multiplier/payout 缺数据填 "0" 不空串

**FAIL 处理**：gameDetail.txt 在 capture 中为 0 条（玩家未点详情）→ 构造样本（开发期可接受）；≥ 1 条但单测未用真 XML → 🔴 must-fix 立即改测试。

### V7b. BuildGameReport 真 HTML 单测（语义判断，AI 跑）

**目的**：机台内 `report_test.go` 用 `tmp/<capture_dir>/roundDetail/*.html` 真 HTML 跑 BuildGameReport，断言生成 HTML 的关键 DOM 节点 / SVG 元素 / 字段值与 capture 一致。

**AI 检查步骤**：

```bash
DIR=<worktree>/server/game/pp/internal/games/<gametype>/<tableId>
# 1. capture roundDetail 文件齐全
ls tmp/<capture_dir>/roundDetail/*.html
# 2. 找 report_test.go 是否有真 HTML 视觉对齐测试
grep -rE 'roundDetail|TestBuildGameReport|gameHeader|playerSummary|<svg' "$DIR"/report_test.go
# 3. 跑测试
cd <worktree>/server && go test -v -run "TestBuildGameReport" "./game/pp/internal/games/<gametype>/<tableId>/..."
```

**PASS 标准**：
- 含至少 1 个用真 capture HTML 的测试
- 断言生成 HTML 含 `<table id="gameHeader">` / `<table id="gameResult">` / `<table id="playerSummary">` / `<table id="playerDetails">` / `<div id="modal">` / `<form id="hiddenForm">` 等关键骨架节点
- 断言 SVG 元素存在（轮盘机台必须 Game Result `<svg>` + viewBox + winNumber + 邻号；Bonus / Multipliers 也要 SVG 卡片）
- 断言字段值对齐（玩家汇总金额 / 玩家明细每笔 Description / Payout / Status="Settled" / EUR 列计算正确）
- 视觉相似度 ≥ 90%（PASS / FAIL 由人工目测 + 自动 DOM 节点 diff 联合判定）
- **自包含 HTML**：grep 输出 HTML 不含 `<link rel=stylesheet href="/"`（所有 CSS 内联，0 外部依赖）

**FAIL 处理**：缺关键 table id → 补 `write*Table` 函数；缺 SVG → 实现 `gor*SVG` helper；视觉相似度低 → 比照 capture 调样式 + 字段补齐。

### V8. 消息流时机对照（PP capture vs server 实际行为，AI 跑）

**目的**：把我方 server 实际处理消息流的**时间序列**与 PP 真服 capture 实测序列做差分，
确认 server 主动发的帧（subscribe ack / bet echo / win / betstats rewrite 等）时机正确。
**jackpotwheel 历史教训**：
- bet echo 错时机 — 我方 lpbet 即时回 echo，PP 真服实测 betsclosed 后 1.4s 才发（商户落账确认时）
- subscribe ack 漏发 — PP 上游建连时发 1 次，多 client fan-out 必须各自合成；漏发导致客户端永不发 ping
- win 帧 seq=0 — PP 真服 seq 单调递增（44/70/101），server 自合成帧必须用 instance 级 atomic counter

**AI 检查步骤**：

```bash
# 1. PP capture 真服时间序列（recv + send 按 ts 排序）
jq -s -r '.[] | "\(.ts) \(.dir) \(.payload[0:120])"' tmp/<tid>/message.txt > /tmp/pp_seq.txt

# 2. 对每个回合做关键事件时序提取（betsopen → 客户端 lpbet → betsclosingsoon →
#    betsclosed → bet echo 序列 → gameresult → winners → win 帧 → 下一局 game）
grep -E 'betsopen|<lpbet|betsclosingsoon|betsclosed|"bet":\{|gameresult|winners|"win":\{|^[0-9]+ send <ping' /tmp/pp_seq.txt | head -50

# 3. 关键时序断言（写到 state.json verify_results.V8_message_timing）：
#    - bet echo 出现在 betsclosed 之后（dt > 0）— 跨多局看一致性
#    - 我方 win 帧出现在 winners 帧之后（WinnersBroadcastDelay 内）
#    - subscribe ack: PP 上游 → server 发 1 次；我方 server → 多 client 各发一次

# 4. 启动 server 本地实测（如有条件）：
#    用 Python WS client 连接（参考 phase-7 经验文档 §9 中的 capture-replay 模板）
#    打点 server → client 帧序列 → 比对 capture 时间序列
```

**PASS 标准**：
- 各阶段事件顺序与 capture 一致（dt 误差容忍 ± 200ms）
- server 主动合成帧的"触发点"明确（不是 lpbet 即时回 → 必须 OnMerchantBetResult 触发）
- server 主动合成帧 seq 单调递增（非零）

**FAIL 处理**：
- bet echo 在 lpbet 立即回 → 改走 `pendingBetEcho` 缓存 + `OnMerchantBetResult` accepted echo
- subscribe ack 不发 → 加 `sendSubscribeAck` 合成（handleConnect 内）
- win 帧 seq=0 → 加 instance 级 `frameSeq atomic.Int64`

### V9. 客户端 GameType enum 字符串实证（I11，AI 跑）

**目的**：history list 返回的 `type` 字段与 client `m.d.MEGAWHEEL`（或类似）enum 字符串值
**必须 toUpperCase 后匹配**，否则 history 详情显示"无法预期的错误"。

**AI 检查步骤**：

```bash
# 1. grep client main.js / chunk 找 GameType enum 字典
MAIN=$(find tmp/<tid>/clientResources/apps/<gameLoaderKey> -name 'main.js' | head -1)
grep -oE '\b[A-Z_]+:"[A-Z_]+"' "$MAIN" | sort -u | head -30

# 例如 jackpotwheel main.js @592176:
#   MEGAWHEEL:"MEGAWHEEL", BACCARAT:"BACCARAT", ...
# 关键：client switch case 用 m.d.<KEY> 比较，值是大写常量字符串

# 2. 看 history_parse.go gameTypeMap 是否含 <DB game_type> → <PascalCase> 映射
grep -A 20 'gameTypeMap' server/game/pp/runtime/history_parse.go

# 3. 必须确保 DB game_type 经 gameTypeToClientType 转换后，
#    client toUpperCase 能匹配到 enum：
#      DB "jackpotwheel" → "Megawheel" → toUpperCase "MEGAWHEEL" = m.d.MEGAWHEEL ✓
#      DB "jackpotwheel" → "Jackpotwheel"（fallback） → toUpperCase "JACKPOTWHEEL" ≠ "MEGAWHEEL" ❌
```

**PASS 标准**：
- gameTypeMap 含本机台 `<dbGameType>: "<PascalCase>"` 映射
- toUpperCase 后的字符串与 client main.js GameType enum 字典 key 一致

**FAIL 处理**：
- 加映射到 `history_parse.go:gameTypeMap`（jackpotwheel → "Megawheel"）

### V10. Rebet 全量快照去重（J1，AI 跑）

**目的**：确认下注协议被正确判定为全量快照、按 `bc` 去重、**无 `ck` 去重逻辑** —— megaroulette #193 根因是误判增量 + 用 `ck` 当去重键（`ck` 是批次时间戳，Rebet 多 bet 共享同一 ck）。

**AI 检查步骤**：

```bash
DIR=<worktree>/server/game/pp/internal/games/<gametype>/<tableId>
# 1. 协议判定文档结论
grep -E 'batch|快照|incremental' tmp/<tid>/bet_protocol.md | head -5
# 2. 代码不得用 ck 做 map key / 去重键（仅可作 echo 透传字段）
grep -rnE '\bck\b' "$DIR"/downstream_bet*.go
# 3. 单测覆盖同帧重复 bc fail-closed + Rebet 多点位无重复 bc
grep -rE 'Test.*(Dup|Rebet|Snapshot)' "$DIR"
```

**PASS 标准**：`bet_protocol.md` 明确判 batch / 全量快照；代码无 `ck` 去重；单测覆盖"同帧重复 bc → fail-closed 拒整帧"。

**FAIL 处理**：误判增量 → 改纯覆盖模型（按 bc 唯一直接覆盖 Redis）；用 `ck` 去重 → 改按 `bc`。

### V11. betValidationError code 客户端可识别（J4，AI 跑）

**目的**：每个拒单 `code` 在客户端 main.js `betValidationError` / `rejectBet` switch 有对应 toast 分支；否则落 default 弹"请联系客服"把普通拒单放大成系统故障（#161 / #181 / #182）。

**AI 检查步骤**：

```bash
MAIN=$(find tmp/<tid>/clientResources/apps/<gameLoaderKey> -name 'main.js' | head -1)
DIR=<worktree>/server/game/pp/internal/games/<gametype>/<tableId>
# 1. 客户端识别的 error code 全集（main.js switch case 标签）
grep -oE 'case ?"?[0-9]{3,5}"?' "$MAIN" | grep -oE '[0-9]{3,5}' | sort -u
# 2. server 用的拒单 code 常量
grep -rnoE 'ErrCode[A-Za-z]+|"[0-9]{4,5}"' "$DIR"/enum.go
```

**PASS 标准**：server 每个拒单 `code` ∈ 客户端识别集；普通拒单 `extendedErrorCode` 留空（仅 InvalidToken 填 9018）；拒单后无追发 `command status=error`。

**FAIL 处理**：换成客户端识别的 code（被禁 betCode 用 `20602` BET_NOT_ALLOWED）。

### V12. seat drop + 帧时效分类审查（J2 / J5，AI 跑）

**目的**：上游 `seat` 一律 drop；`upstream_cache` 只缓存"每局重发的全量快照帧"，不缓存时效状态帧。

**AI 检查步骤**：

```bash
DIR=<worktree>/server/game/pp/internal/games/<gametype>/<tableId>
# 1. seat 必须 drop
grep -nE 'seat|Seat' "$DIR"/upstream_dispatch.go
# 2. 缓存集合不得含 disablesidebets / timer / seat 等时效状态帧
grep -nE 'cache|Cache' "$DIR"/upstream_cache.go
```

**PASS 标准**：`seat` → drop；`upstream_cache` 缓存集合仅含 init 类（table / dealer）+ 每局重发的全量快照帧（走势 `<statistic>` / `<ShoeSummary>`）；时效状态帧（`disablesidebets` / `timer`）不在缓存集。

**FAIL 处理**：seat 透传 → 改 drop；缓存了时效状态帧 → 移除，状态改后端按权威数据自算。

### V13. DB-config 前置 + post-merge live-launch checklist（清单交付，AI 填）

**目的**：代码 build / test 全过 **≠ 机台能跑**。jackpotwheel 上线后才暴露 12 个运行时 bug（operatorGameId 路由 / subscribe ack 漏发 / 僵尸连接 / dealer_name NULL / history chunk 加载失败），test 与 codex 都抓不到。本项把上线前后必查项**填实进经验文档第 12 节**。

**AI 填实清单**（无网络 / 无 DB，是清单交付不是自动化检查）：

- **DB 配置前置**：`b_tables` 行（`game_type` / `operator_game_id` / `activity_check_interval`）、`b_table_currency_configs`（含 G2 兜底字段 + typo 字段）、`b_currency_rates` 有启用的 `EUR` 行 + `symbol` 字段（J6）
- **gameType 字符串四处对齐**：`b_tables.game_type` ↔ 后端 `enum.GameType` ↔ `history_parse.go:gameTypeMap` ↔ 客户端 `m.d.<GAMETYPE>` enum（任一不一致 → history 详情"无法预期的错误"）
- **betCode 列长**：`b_game_transactions.bet_code` 是 `size:10`。字符串 betCode 命名 **≤ 10 字符**（dragontiger `DRAGON_BLACK` 12 字符曾致 data too long → 派彩成功但注单行丢失）→ 须有命名长度回归断言
- **post-merge live-launch 必查**（test / codex 抓不到，须真人启动验证）：operatorGameId 路由命中、subscribe ack 实发、僵尸连接清理、`dealer_name` 非 NULL、history chunk 正常加载、币种符号正确

**PASS 标准**：经验文档第 12 节填实上述四组清单；betCode 命名长度有回归断言。

### V14. 赢钱反推验证（capture 局对照算钱，AI 跑）

**目的**：从 capture message.txt 取**已结算的真实局**（含 lpbet 序列 + `<gametype>gameresult` 帧），
用机台 `payout.go::Calculate / CalcBetPayout` 函数模拟，对比 PP 真服的实际 payoff —— **同样下注 + 同样开奖结果，
我方算出的玩家赢钱必须与 PP 真服一致**，否则代码里 payout 逻辑有错。

是 verify 阶段最重最末闸门：构建 + 单测 + 协议都过了的代码仍可能在"金额"上偷偷算错（赔率漏/倍率乘错位/cap 顺序错），
肉眼 review + codex review 都难抓到。

**双数据源对照**：
- **PP 真服 payoff（ground truth）**：`tmp/<capture_dir>/roundDetail/<rid>-Details-<userId>.html` 里 modal 内的 7 列玩家明细，每笔 bet 有 `betcodeName / betAmount / **betPayoff** / betStatus`
- **我方算出的 payoff**：从同一局 message.txt 取该 user 的 lpbet 序列 + gameresult.winNumber + 该局 luckyMul[]，用 payout 函数算

**AI 检查步骤**：

```bash
DIR=<worktree>/server/game/pp/internal/games/<gametype>/<tableId>
CAPTURE=tmp/<capture_dir>
# 1. 找已结算 round（roundDetail/{rid}-Details-*.html 存在 → 一定有玩家 + 明细）
ls "$CAPTURE/roundDetail/"*-Details-*.html | head -3

# 2. 对每个有 Details 的 round，做：
#    a. 解析 roundDetail/{rid}-Details-{userId}.html 的 modal 表格 → 每笔 bet (betcodeName, betAmount, betPayoff)
#    b. 反查 message.txt 取该 round 的 gameresult（winNumber / mul / sector 等）+ gorRng.luckyMul[]
#    c. 反查该 userId 在该 round betsopen-betsclosed 窗口内的所有 lpbet 帧
#    d. 用机台 payout 函数 Calculate(bc, betAmount, winNumber, luckyMul, ...) 算 expected
#    e. 对比 expected vs PP 真服 betPayoff，差异 > 0.01 IDR 视为 FAIL

# 3. 写 v14_payout_reverse_test.go：
#    - 用 capture HTML/message.txt 做 fixture
#    - 每个 round 一个 t.Run subcase
#    - 至少覆盖 3 局（含 megawin / 普通 / 全输 三种局型）
cd <worktree>/server && go test -v -run "TestV14PayoutReverse" "./game/pp/internal/games/<gametype>/<tableId>/..."
```

**PASS 标准**：
- ≥ 3 个真实 round 的反推全部一致（差异 ≤ 0.01 货币单位）
- 至少覆盖：①普通 winNumber 直注命中 ②luckyMul 倍率命中（megawin）③全输（payout=0）三种局型
- v14_payout_reverse_test.go 用 capture HTML + message.txt 真数据做 fixture，不允许构造数据

**FAIL 处理**：
- 单注差异 → check `payout.go::Calculate(bc, amount, winNumber, luckyMul)` 赔率或 luckyMul 命中逻辑
- 全局差异（所有 bet 多 / 少同一系数）→ 三路 cap min 顺序错（G3）
- 某 bc 差异其它正确 → 该 bc 赔率常量错（与 odds.go 期望不符）

## 失败决策树

```
单项 V_N FAIL
    │
    ├─ 首次：Claude 自诊断
    │   └─ 修小问题 → 重跑 V_N
    │       PASS → 进下一项
    │       FAIL → 进入 ≥2 次分支
    │
    └─ ≥2 次失败 / 跨边界（如 V3 race + V5 policy-pr 同时）：
        调 codex_decide.sh 根因分类（见 codex-collab.md D5）
            │
            候选 A 实现 bug → 回 Phase 3 修代码
            候选 B 测试断言错 → 改测试
            候选 C policy-pr 拆文件 → 拆
            候选 D 设计遗漏 → 回 Phase 4 self-review 重审
            │
            决策不收敛：调 codex_discuss.sh ≤ 2 轮（S3）
                │
                收敛 → 按建议修
                不收敛 → 写 state.unresolved[]（category="verify-no-converge"）+ 强制进 Phase 7
```

## state.json 写入

```jsonc
{
  "phase": 6,
  "status": "done | partial",  // partial = 有 verify_no_converge unresolved
  "verify_results": {
    "V1_build": "PASS",
    "V2_vet": "PASS",
    "V3_test_race": "PASS",
    "V4_cover": "27.3%",
    "V5_policy_pr": "PASS",
    "V6_I9_protocol_matrix": "PASS",
    "V7a_I10_buildgamedetail_real_xml": "PASS",
    "V7b_buildgamereport_real_html": "PASS — 含 SVG 卡片 + 自包含 CSS / 视觉相似度 ≥ 90%",
    "V8_message_timing": "PASS — bet echo @ OnMerchantBetResult / win @ WinnersBroadcastDelay / subscribe ack 自合成",
    "V9_gameType_enum_map": "PASS — gameTypeMap[<dbGameType>] = <PascalCase> 经 toUpperCase 匹配 client enum",
    "V10_snapshot_dedup": "PASS — lpbet 判定全量快照 / 按 bc 去重 / 无 ck 去重 / 重复 bc fail-closed",
    "V11_errcode_client_recognized": "PASS — 拒单 code 全命中客户端 switch / 普通拒单 extendedErrorCode 空",
    "V12_seat_drop_frame_timeliness": "PASS — seat drop / 缓存集仅全量快照帧",
    "V13_db_config_live_launch": "DELIVERED — 经验文档 §12 填实 DB 前置 + post-merge 必查清单",
    "V14_payout_reverse_check": "PASS — N round 反推一致 / 含 megawin + 普通 + 全输 三局型"
  },
  "verify_failures": [
    // {"item": "V4_cover", "round": 1, "value": "18%", "fixed_by": "添加 payout_test", "round_2": "27%"}
  ]
}
```

进 Phase 7 归档。
