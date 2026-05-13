# Phase 6 — verify 全量验收（AI 自检指南）

> 触发：Phase 5 整体 codex review fix 完成。
> 9 项验收（5 确定性 + I9 + I10 + V8 时序 + V9 GameType 映射 — 后 4 项为语义判断）。
> 阶段：❌ 禁止向用户提问；失败首次 Claude 自修；≥2 次走 codex_decide 根因分类。

## AI 执行步骤

```
1. cd <worktree>
2. 按顺序跑 7 项验收（详见 §2-§8）
3. 任一项失败：
   - 首次：Claude 自修（小问题）+ 重跑该项
   - ≥2 次：调 codex_decide.sh 根因分类（见 codex-collab.md D5）
   - 决策不收敛：调 codex_discuss.sh ≤ 2 轮（S3）
4. 全 7 项 PASS → 进 Phase 7 归档
5. 全程不停问用户
```

## 7 项验收

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
jq -s -r '.[]|select(.dir=="send")|.payload' tmp/<tid>/message.jsonl | grep -oE '<[a-zA-Z]+[^/]*>' | sort -u

# B. server 端 ClientCommand struct → grep
grep -rE 'type Client[A-Z][a-zA-Z]*Cmd' <worktree>/server/game/pp/internal/games/<gametype>/<tableId>/

# C. 输出对照表：每客户端帧 → server 是否能解析
# D. server→客户端帧 → grep xml.Marshal / json.Marshal 发出的帧
# E. 客户端 main.js → socketHandler case 标签
# F. 输出对照表：每 server 帧 → 客户端是否消费
```

**PASS 标准**：每客户端发的 XML root tag 在 server 有 struct 对应；每 server 主动发的帧在 main.js socketHandler 有 case。

**FAIL 处理**：如 dragontiger 历史教训 — 客户端发 `<placeBet>` 单数但 server 仅识别 `<lpbet>` 复数 → 走 default 默默 ack 不落库 → 协议不通。任一行 ❌ → 必须修。

### V7. I10 真 XML 单测（语义判断，AI 跑）

**目的**：history_<gametype>_test.go 用 `tmp/<tid>/gameDetail.txt` 真 XML 跑 parser，断言关键字段非空。

**AI 检查步骤**：

```bash
# 1. 取真 XML 样本
head -1 tmp/<tid>/gameDetail.txt > /tmp/sample.xml

# 2. 找 history_<gametype>_test.go 是否有真 XML 测试
grep -rE 'gameDetail.txt|TestParse<Gametype>.*real|os.Open.*gameDetail' <worktree>/server/game/pp/runtime/history_<gametype>_test.go

# 3. 跑测试
cd <worktree>/server && go test -v -run "TestParse<Gametype>" ./game/pp/runtime/...
```

**PASS 标准**：
- 单测含至少 1 个用真 XML 的测试函数
- 断言关键字段非空：gameResult / multiplier / payout / bc 等
- I8：multiplier/payout 缺数据填 "0" 不空串

**FAIL 处理**：如 gameDetail.txt 在 capture 中为 0 条（玩家未点详情）→ 退化为构造样本（I10 H10：开发期可接受）；如 ≥ 1 条但单测未用真 XML → 🔴 must-fix 立即改测试。

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
jq -s -r '.[] | "\(.ts) \(.dir) \(.payload[0:120])"' tmp/<tid>/message.jsonl > /tmp/pp_seq.txt

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
    "V7_I10_real_xml_test": "PASS",
    "V8_message_timing": "PASS — bet echo @ OnMerchantBetResult / win @ WinnersBroadcastDelay / subscribe ack 自合成",
    "V9_gameType_enum_map": "PASS — gameTypeMap[<dbGameType>] = <PascalCase> 经 toUpperCase 匹配 client enum"
  },
  "verify_failures": [
    // {"item": "V4_cover", "round": 1, "value": "18%", "fixed_by": "添加 payout_test", "round_2": "27%"}
  ]
}
```

进 Phase 7 归档。
