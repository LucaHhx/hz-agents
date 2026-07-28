# Phase 5 — 整体循环 codex review

> 触发：Phase 4 铁律核对 fix 完成。
> 软上限：5 轮。
> 模式：codex-collab review。

## 与层间审查的差异

| 维度 | 层间审查（Phase 3 内） | 整体循环（本 phase） |
|---|---|---|
| 范围 | 本层 diff（HEAD~M..HEAD） | 全 worktree diff vs base 分支 |
| 重点 | 字段错 / struct 不匹配 / 协议铁律违反 | 跨层一致性 / race / silent fallback / 测试覆盖 |
| 软上限 | 每层 ≤ 2 轮 | ≤ 5 轮 |
| 视角 | 本层独立 | 全 diff 综合 |

## 调用模板

```bash
WT=$(jq -r .worktree_path tmp/<tid>/state.json)
BASE=$(jq -r .base_branch tmp/<tid>/state.json)

for round in 1 2 3 4 5; do
    bash $CODEX_COLLAB/scripts/codex_review.sh \
        -d "$WT" \
        -l "overall-round-${round}" \
        -- "$(render_overall_review_prompt $round $BASE)"

    # 解析 findings → 分流（small 修 / medium-必要 修 / 其他 unresolved）
    # 无 finding 即退出循环
done
```

## 整体审查 prompt 重点

```
你是 PP 机台 <tableId> (<gametype>) Phase 5 整体循环代码审查者，第 <round> 轮。
只审查、不修改任何文件。按 🔴/🟡/🟢 分类输出。

【审查范围】
git diff <base_branch>...HEAD —— 全 worktree 改动 vs base 分支

【审查重点（与层间不同的部分）】
1. **跨层一致性**：
   - ENUM 常量 ↔ MODELS struct tag ↔ SETTLE 调用 ↔ HISTORY (history.go XML) 字段；报表字段经 `reportjson.extra` 透传到前端页
   - bc 在 enum.go / parse / settle / payout / history 全程一致
   - errorCode 在 enum.go / downstream_bet / check_bet 引用一致
   - **round.Extra schema 一致**：settle_persistence 写入字段 ↔ extractExtra（XML）/ 前端报表页读取字段（任意一边漏字段 = history/报表 行为缺失）
2. **race / 并发**：
   - mu / betsMu / cacheMu / pendingMu 锁保护范围
   - pendingWins 顺序保证（winners 后 flush）
   - Redis SCAN/HGetAll context 超时（C9）
3. **silent fallback**：
   - 全 worktree grep `_ = err`（违反 feedback_no_silent_fallback）
   - json.Unmarshal / Atoi 错误必须 log + skip
   - 关键路径必加 zap.Error（D 节）
4. **struct + JSON 序列化**：
   - 禁 raw 字符串拼 JSON（feedback_struct_only）
   - XML 拼接允许 string template
5. **测试覆盖完整性**：
   - payout_test ≥ 4 capture 真帧样本（F1）
   - dictionary parity（F2）
   - I6 incremental / J1 全量快照去重回归测试
   - I7 partial-accept 测试
   - history_test.go（机台内）用真 gameDetail.txt XML；报表无 Go 单测——前端页 `client/reports/<tableId>/index.html` 对照真 roundDetail/*.html 视觉验收（V7b）
6. **协议铁律 known-pitfalls A-J 全节**：
   - B1 tableId 字节替换
   - B2 winners Model A（drop 上游 + 合并我方 + per-观众币种广播；一局只播一次、合并失败不广播）
   - B3 多事件单帧顺序
   - C1/C7/C9 Redis fail-closed
   - C8 payout cap
   - G2/G3 三路 cap min
   - H3-H6 history 落盘字段
   - I3 extendedErrorCode
   - I4 边界归一化
   - I6 incremental
   - I8 history 字段非空
   - J1 lpbet 全量快照 / 禁 ck 去重
   - J2 帧时效语义二分（缓存 / 回放）
   - J3 下注规则 capture 实证
   - J4 betValidationError code 客户端可识别
   - J5 上游 seat drop
   - J6 展示配置统一驱动
   - J7 历史投注类型 / 开奖结果分离
7. **协议保真度清单（强制跑）**：逐项核对
   `<repo>/docs/integration-experience/common/protocol-fidelity-checklist.md` §1-6
   —— 双层 JS 架构 / 下注 XML 协议事实表 / 帧合成 / 错误码语义 / verify 自动断言 / 自检矩阵
8. **policy-pr**：单文件 ≤ 500 行 / 嵌套 ≤ 3 层

【主信息源】
1. capture 5 文件（事实最高权威）
2. main.js
3. 既有经验 `<repo>/docs/integration-experience/<gametype>/*.md`
4. known-pitfalls `<repo>/docs/integration-experience/common/` + `$SKILL_DIR/references/known-pitfalls.md`

【输出格式】
🔴/🟡/🟢 + file:line + 描述 + 修复建议 + 引用 known-pitfalls 条目

【硬规则】
- capture 与 main.js 冲突时 capture 为准
- 与既有机台不一致但符合本机台 capture → OK 不报
- 项目级问题（命中 project-level-skips.md）→ 跳过不报
- 已写 unresolved[] 的问题 → 跳过不报（state.unresolved[].source.finding.desc 可对照）
```

## fix 决策

同 Phase 3 层间审查（见 `phase-3-layer-review.md` §fix 决策表）。

但 Phase 5 特殊：

| 触发 | 处理 |
|---|---|
| 同 finding hash ≥ 3 次反复出现 | 调 `codex_discuss.sh` ≤ 3 轮根因（见 codex-collab.md S2） |
| 5 轮跑完仍有 finding | 全部写 `state.unresolved[]`（category="round-cap-leftover"）+ 进 Phase 6 verify |

## state.json 写入

```jsonc
{
  "phase": 5,
  "status": "done",
  "codex_reviews": [
    ..., // 含 L1-L5 层间
    {"scope": "overall", "round": 1, "findings": 5, "fixed": 3, "unresolved": 2},
    {"scope": "overall", "round": 2, "findings": 1, "fixed": 1, "unresolved": 0},
    {"scope": "overall", "round": 3, "findings": 0, "verdict": "clean"}
  ]
}
```

进 Phase 6 verify。
