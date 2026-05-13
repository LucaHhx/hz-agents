# Phase 7 — 经验文档归档

> 触发：Phase 6 verify 全 PASS（或 partial 含 unresolved）。
> 产物：`<repo>/docs/integration-experience/<gametype>/<tableId>.md`（worktree 内）。
> 阶段：❌ 禁止向用户提问；commit 到 worktree 子分支，不 PR。

## 13 节 + 2 节扩展模板

```markdown
# <tableId> 对接经验（<gametype> / <PP 机台名>）

> 对接日期：<ISO> · base 分支：<live/live-dev/...> · worktree 分支：worktree/<base>/<gametype>-<tail>

## 1. 机台基本信息

| 字段 | 值 |
|---|---|
| tableId | <tableId> |
| PP 机台名 | <name from lobby> |
| gameType | <gameType> |
| gameLoaderKey | <gameLoaderKey> |
| operatorGameId | <operatorGameId> |
| 客户端版本 | apps/<gameLoaderKey>/<ver>/ |
| 协议形态 | 上行 XML / 下行 JSON envelope (或 XML) |
| capture 帧数 | total / recv / send |
| 抓 capture 日期 | <YYYY-MM-DD> |

## 2. 协议事实速查（capture 实证）

主要上游事件（来自 message.jsonl recv）：
- `betsopen`: N 次，样本字段 `{table, game, seq}`
- `betsclosed`: N 次
- `<gametype>gameresult`: N 次，**关键字段** `{value, multiplier, ..., seq}`
- `winners`: N 次
- `<机台特化事件>`: N 次

主要下游事件（来自 message.jsonl send）：
- `<ping channel="..." time="..."/>` × N
- `<command channel><lpbet gm="<gametype>_desktop" ...><bet amt bc/></lpbet></command>` × N

## 3. 一轮生命周期（来自 capture 真帧时序）

```
betsopen → betsclosingsoon → betsclosed → <startDealing/mwDealing> → <jackpotwheel_rng>?
→ <gametype>gameresult → winners → 私聊 win 帧
```

## 4. 字典（来自 dict.json）

- bc 全集：<bc 数> 个（如 megawheel: 101..109 — 注意 Qp 枚举乱序 Eight=107/Fifteen=108/Thirty=109）
- errorCode 全集：<N> 项（典型如 ErrCodeBetNotOnTime / ErrCodeInvalidToken 等）
- face↔bc 映射（如有）

## 5. 协议处理决策表（vs verdict 推导）

| 事件 | verdict | 业务 | 理由（capture/main.js 实证） |
|---|---|---|---|
| betsopen | pass + 业务 | MarkBetsOpen + UpsertRoundStartedAt | ... |
| betsclosed | pass + 业务 | MarkBetsClosed + SubmitBets | ... |
| <gametype>gameresult | pass + 业务 | OnGameResult + 结算 | 结算锚 |
| winners | pass 透传 | flushPendingWins | known-pitfalls B2 |
| bet/bets/win/winningBetCodes/betSpotWin/command/pong | drop | 自合成 | 客户端 main.js 0 命中（B4） |
| switch | drop + 业务 | ctx.Reconnect | B10 |
| ... | | | |

## 6. 服务端→客户端帧合成清单

必合成：
- subscribe（B1 channel）
- bet echo（B5 placebets ack）
- betstats（rewrite + enrich B7）
- win（每用户私聊，winners 后 flush）
- betValidationError（7 字段 B9）
- logout（KickUser InvalidToken）

不合成：
- winningBetCodes / betSpotWin（如 main.js 0 命中）

结算消息顺序：
```
<gametype>gameresult（pass）→ winners（pass）→ 对每用户私聊 win
```

## 7. 遇到的问题 + 解决方案（Phase 3 层间审查 + Phase 5 整体循环修复记录）

每 finding 一条：

#### N. <一句话标题>
- **症状**：codex 描述
- **根因**：分析
- **修复**：`commit <sha>` — <一句话解决方案>
- **依据**：引用 known-pitfalls.md 哪条 / capture 哪个样本 / main.js 哪个函数

## 8. 资金安全清单（known-pitfalls C 节逐项）

- [x] C1 CanBet Redis 异常返回 false
- [x] C2 applyBet fail-closed
- [x] C3 空 lpbet 撤单防御
- [x] C4 整批拒清 Redis 仅限非窗口类
- [x] C5 BC Atoi 错误显式拒绝
- [x] C6 bets JSON 解析失败跳过用户
- [x] C7 GetRedisUserBets 故障 fail-closed
- [x] C8 payout_cap 接入
- [x] C9 context.WithTimeout(5s)

## 9. 测试策略

测试文件：
- `dictionary_test.go` — F2 字典 parity
- `parse_test.go` — XML 解析往返
- `payout_test.go` — F1 4 capture 真帧样本
- `payout_cap_test.go` — G3 三路 cap
- `placebet_incremental_test.go` — I6 incremental
- `validate_test.go` — 窗口/边界/联动
- `history_<gametype>_test.go` — I10 真 XML 单测

capture 5 文件作 fixture 路径：
- `tmp/<tableId>/message.jsonl`
- `tmp/<tableId>/tableConfig.jsonl`
- `tmp/<tableId>/statisticHistory.jsonl`
- `tmp/<tableId>/gameDetail.txt`
- `tmp/<tableId>/clientResources/.../main.js`

coverage: <X>%

## 10. 项目级跳过状态

引用 pp-game `docs/integration-experience/common/project-level-skips.md`。本机台跳过项：
- handlers.SubmitBets 幂等锁缺失（项目级，与既有机台一致）
- ... （第 1 次提及时一次性记入）

## 11. 与其他机台对比

| 维度 | 本机台 | dragontiger | sweetbonanza | baccarat6 |
|---|---|---|---|---|
| 协议形态 | <...> | XML / XML | JSON envelope / JSON | XML / XML |
| 结算事件 | <gametype>gameresult | dragontiger_gameresult | sweetbonanzagameresult | gameresult |
| 下注协议 | incremental / batch | incremental | batch | batch |
| bc 形式 | 数字字符串 / 命名 | 命名 | 数字 | 数字 |

## 12. 部署前 checklist

- [ ] `b_tables` SQL 模板插入（含 lobby 元信息）
- [ ] `b_table_currency_configs` 默认值（含 G2 兜底 / typo 字段）
- [ ] `b_currency_rates` 有 EUR 行
- [ ] factory 注册（已由 L5 完成）
- [ ] worktree 子分支 merge 到 base（用户决定时机）

## 13. 必看注意事项（本机台新坑）

总结 Phase 3-6 学到的本机台特殊知识，给后续相同 gametype 机台对接参考：
- <如 megawheel：协议形态混合（上 XML 下 JSON envelope）>
- <如 fourty typo 字段>
- <如 jackpotwheel_rng.slot 嵌套对象>

## 14. 自问审查补充（来自 self-review.md）

引用 `tmp/<tableId>/self-review.md` 综合汇总：
- 总问题数：N
- ✅ 已修：M
- ⏭️ 写 unresolved：K
- ⚠️ codex 失败待人工：L

用户扩展自问（self-review-checklist.md §5+）的回答摘录：
- <如有>

## 15. unresolved 摘要（用户后续审视）

来自 `state.unresolved[]`：

| id | phase | category | 一句话描述 | 建议动作 |
|---|---|---|---|---|
| unresolved-<uuid> | 3 | medium-non-essential | <...> | <跨机台联动 / 缺 capture 待生产数据 / ...> |
| unresolved-<uuid> | 4 | self-review-deferred | <...> | <codex 判定可延后，理由 ...> |
| unresolved-<uuid> | 5 | round-cap-leftover | <...> | <scope cap 10 轮硬顶达到> |

用户决定（流程外）：
- 建 issue 跟进
- 排期到下个 sprint
- 忽略（确认非必要）
```

## commit + 索引更新

```bash
# 1. 写到 worktree 内
WT=$(jq -r .worktree_path tmp/<tid>/state.json)
GAMETYPE=$(jq -r .lobby.gameType tmp/<tid>/state.json)
TABLE_ID=$(jq -r .tableId tmp/<tid>/state.json)

DOC="$WT/docs/integration-experience/$GAMETYPE/$TABLE_ID.md"
mkdir -p "$(dirname "$DOC")"
# Claude 按 13+2 节模板填实写入 $DOC

# 2. 更新索引（如 docs/integration-experience/README.md 含目录则补一行）

# 3. commit
cd "$WT"
git add docs/integration-experience/
git commit -m "docs(integration-experience): $GAMETYPE/$TABLE_ID 对接经验

13 节经验文档 + 自问审查摘要 + unresolved 列表。

capture 5 文件作 fixture，main.js 路径见第 9 节。"
```

## 最终输出（流程结束摘要）

```
✅ <gametype>/<tableId> 对接完成

worktree:        worktree/<base>/<gametype>-<tail>
commits:         <N>
新增文件:         <N>
测试覆盖率:       <X.X>%
codex review 轮: <N> (L1-L5 层间 + 整体循环)
codex decide:    <N> (自问审查 + 路径决策等)
codex discuss:   <N> (卡死诊断)
unresolved:      <N> 项（详见经验文档第 15 节）
经验文档:        docs/integration-experience/<gametype>/<tableId>.md
自问审查报告:    tmp/<tableId>/self-review.md

未做：PR / 部署（用户决定时机；铁律：不 PR）
```

## state.json 写入

```jsonc
{
  "phase": 7,
  "status": "done",
  "experience_doc_path": "<repo>/docs/integration-experience/<gametype>/<tableId>.md",
  "final_summary": {
    "commits": N,
    "coverage": "X.X%",
    "codex_reviews": M1,
    "codex_decisions": M2,
    "codex_discussions": M3,
    "unresolved_count": K
  }
}
```

流程结束。
