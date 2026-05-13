# Phase 6 — verify 全量验收（AI 自检指南）

> 触发：Phase 5 整体 codex review fix 完成。
> 7 项验收（5 确定性 + I9 + I10 语义）。
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
    "V7_I10_real_xml_test": "PASS"
  },
  "verify_failures": [
    // {"item": "V4_cover", "round": 1, "value": "18%", "fixed_by": "添加 payout_test", "round_2": "27%"}
  ]
}
```

进 Phase 7 归档。
