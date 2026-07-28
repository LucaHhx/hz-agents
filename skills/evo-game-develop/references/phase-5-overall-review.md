# Phase 5 — 整体循环 codex review

> 触发：Phase 3 层间审查收敛之后。模式：codex-collab review。
> 🔴 **停止条件是「连续两轮无新增 🔴」，不是固定轮数**（软上限 5 轮只作兜底）。
> 理由与实测数据见 SKILL.md「审查的收敛判据」——固定轮数会诱导「反正还能再跑一轮」，
> 而真正该停的信号是「同一条被反复换位置报出来」（此时做裁决，别再开一轮）。

## 与层间审查的差异

| 维度 | 层间审查（Phase 3 内） | 整体循环（本 phase） |
|---|---|---|
| 范围 | 本层 diff（HEAD~M..HEAD） | 全 worktree diff vs base 分支 |
| 重点 | 字段错 / struct 不匹配 / 协议铁律 | 跨层一致性 / race / silent fallback / 测试覆盖 |
| 停止条件 | 该层无新增 🔴 | **连续两轮无新增 🔴** |
| 🔴 硬要求 | — | **最后一次修完之后必须再审一轮** —— round N+1 的发现有相当比例打在 round N 的修复上（实测 round4 的三条 🟡 全部如此） |

## 调用模板

```bash
WT=$(jq -r .worktree_path tmp-evo/<dir>/state.json); BASE=$(jq -r .base_branch tmp-evo/<dir>/state.json)
for round in 1 2 3 4 5; do
    bash $CODEX_COLLAB/scripts/codex_review.sh -d "$WT" -l "overall-round-${round}" \
        -- "$(render_overall_review_prompt $round $BASE)"
    # 解析 findings → 分流（small 修 / medium-必要 修 / 其他 unresolved）；无 finding 退出
done
```

## 整体审查 prompt 重点

```
你是 EVO <gametype> 桌 <evo_table_id> Phase 5 整体循环审查者，第 <round> 轮。
只审查、不修改任何文件。按 🔴/🟡/🟢 分类输出。

【审查范围】git diff <base_branch>...HEAD —— 全 worktree 改动 vs base

【审查重点（与层间不同的部分）】
1. 跨层一致性：
   - ENUM 常量 ↔ MODELS struct tag ↔ SETTLE 调用 ↔ HISTORY(JSON) 字段；报表字段经 reportjson.extra 透传前端页
   - betCode 在 odds.go / downstream_bet / settle / payout / history 全程一致
   - errorCode 在 enum.go / downstream_bet / check_bet 引用一致
   - 🔴 **ID 双字段全程一致**：索引用 TableID(code)、协议下发帧用 PPTableID(裸 id)——grep 所有下发帧的 tableId 字段确认无填错 code
   - round.Extra schema 一致：settle 写入字段 ↔ history JSON 读取 ↔ 报表页读取（任一漏字段 = history/报表缺失）
2. per-user 一致性（⭐ EVO 重点，锚帧名按本族）：
   - 个人注态帧广播路径都经 strip（roulette `tableState.betState` / game show `<gt>.bets.state`）；per-user 下发都经 personalize
   - 🔴 snapshot-before-settle 时序无颠倒；betsByUser 来自清 Redis 前快照
   - balanceUpdated 全部商户余额（grep 确认无透传上游渠道 USD；无 playerId 按连接寻址）
   - **状态机锚一致**：开窗/关窗/结算锚帧从 L1 DICT 取（禁硬编码 roulette 5 态）；A2 演出帧直转不缓存
3. race / 并发：mu/betsMu/cacheMu/stacksMu 锁范围；betStacks(仅增量协议) per-user UNDO 栈并发安全；Redis SCAN/HGetAll context 超时（C9）
4. silent fallback：全 worktree grep `_ = err`；json.Unmarshal/Atoi 错误必须 log+skip；关键路径加 zap.Error（D 节）
5. struct 序列化：禁 raw 字符串拼 JSON；所有帧 struct + json.Marshal/Unmarshal（无 map[string]interface{} 跨边界）
6. 测试覆盖：payout_test ≥ 4 roundDetail/capture 真样本；per_user_betstate_test（strip/personalize/snapshot 时序）；reconcile_test（孤儿局 fail-closed）；settle_test（requireAccepted + OnRoundSettled）；history_test 用真 gameDetail.txt；报表无 Go 单测——前端页对照真 roundDetail/*.html ≥90%
7. 协议铁律 known-pitfalls 全节（按 EVO 版）：
   - per-user 帧改写（strip/personalize/snapshot/裸 tableId/余额来源；balanceUpdated 无 playerId 按连接）
   - 状态机锚从 capture（禁假设 roulette 5 态）/ A2 communal 演出帧直转不缓存
   - betstats（game show 有 `<gt>.bettingStats`，直转或合并我方聚合计数；**不可默认「EVO 无 betstats」**）
   - 下注模型按 capture（roulette 增量+UNDO 栈 / game show placeChips 全量快照）
   - /result 必先 /bet（SubmitBets OnMerchantBetResult + hasSuccessfulBetDebit）/ OnRoundSettled 必调 / 受理回执关窗后
   - currencyMult 进制全路径 / reconcile fail-closed
   - C1/C7/C9 Redis fail-closed / C8 payout cap / G2/G3 per-bet cap（#64 已下线 round-level）
   - 列宽 ≥ 最长显示串（H5，game show 段名+倍率串）/ 下注规则 capture 实证 / betValidationError code 客户端可识别
8. policy-pr：单文件 ≤ 500 行 / 嵌套 ≤ 3 层

【主信息源】capture 6 文件 / clientResources/frontend / roulettecore 模板 / $SKILL_DIR/references/{evo-platform-primer,known-pitfalls}.md

【输出格式】🔴/🟡/🟢 + file:line + 描述 + 修复建议 + 引用 known-pitfalls 条目
【硬规则】capture 与 bundle 冲突时 capture 为准 / 与 roulettecore 不一致但符合本族 capture → OK 不报 / 已写 unresolved 的 → 跳过不报
```

## fix 决策

同 Phase 3 层间审查（见 `phase-3-layer-review.md` §fix 决策表）。Phase 5 特殊：

| 触发 | 处理 |
|---|---|
| 同 finding hash ≥ 3 次反复 | 调 `codex_discuss.sh` ≤ 3 轮根因（codex-collab.md S2） |
| 🔴 **本轮 finding 里「上一轮修复新引入的回归」占比 ≥ 50% 或连续上升** | **停止逐条打补丁——补丁在发散**。判该缺陷簇的不变量是否靠「多个 bool 标志 / 递归深度论证 / 跨函数『某路径必在某路径后』推理」维持；是 → 用并发原语（耐久队列 / `running+dirty` coordinator / 单次 CAS）做**收敛重设计**（目标净减代码，不是再叠一层）。**每轮让 codex 报「本轮 🔴 有几条是上个 commit 新引入」**。实证：baccarat 结算/重放/孤儿局回归率 0/6→1/6→4/6，到第三轮才转重设计，本可早一轮。 |
| 重写 / 重设计一段旧逻辑时 | 逐函数问「它存在的理由是什么」——旧代码里「平平无奇的两行」常是某次事故补丁（如重启 grace 重置），重写漏掉 = 把老 bug 请回来。论证「A→B 之间原子」要展开中间每个 getter（惰性初始化自带 Redis/DB I/O）+ 记住两次独立调用间 goroutine 可抢占，真原子只能靠同一临界区 / 单次 CAS。 |
| 5 轮跑完仍有 finding | 按「上线阻断 vs 可 backlog」分类（**让 codex 末轮直接判**）：阻断项（双付/双退/凭空给钱/本金悬空/中奖额丢失）**必须修完才进 Phase 6**；其余写 `state.unresolved[]`（category="phase5-no-converge"）+ 进 Phase 6。 |

## state.json 写入

```jsonc
{ "phase":5, "status":"done",
  "codex_reviews":[ ...L1-L5 层间...,
    {"scope":"overall","round":1,"findings":5,"fixed":3,"unresolved":2},
    {"scope":"overall","round":2,"findings":0,"verdict":"clean"} ] }
```

进 Phase 6 verify。
