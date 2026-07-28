# Phase 7 — 经验文档归档

> 触发：Phase 6 verify 全 PASS（或 partial 含 unresolved）。
> 产物：`<repo>/docs/integration-experience/<gametype>/<tableId>.md`（worktree 内）。
> 阶段：❌ 禁止向用户提问；commit 到 worktree 子分支，不 PR。

## 经验文档模板（16 节，全部必填）

> **完整性铁律**：§1-§16 **全部必填**。某节无内容写 `无 / N/A` 并一句话说明原因，
> **禁止整节省略**（已对接机台曾省略"客户端-后端一致性矩阵 / 历史链路审查"节，
> 导致后续相同 gameType 对接无参照）。节号固定，新机台直接 fork 本模板，不自行增删节号。

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

主要上游事件（来自 message.txt recv）：
- `betsopen`: N 次，样本字段 `{table, game, seq}`
- `betsclosed`: N 次
- `<gametype>gameresult`: N 次，**关键字段** `{value, multiplier, ..., seq}`
- `winners`: N 次
- `<机台特化事件>`: N 次

主要下游事件（来自 message.txt send）：
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
| winners | drop + 重广播 | 合并我方 + per-观众币种 BroadcastToTableByCurrency + flushPendingWins | known-pitfalls B2（Model A；一局只播一次、合并失败不广播） |
| bet/bets/win/winningBetCodes/betSpotWin/command/pong | drop | 自合成 | 客户端 main.js 0 命中（B4） |
| switch | drop + 业务 | ctx.Reconnect | B10 |
| seat | drop | Inactivity 我方自管 | known-pitfalls J5 |
| ... | | | |

### 5.1 客户端-后端一致性矩阵（G7 强制节）

客户端展示的每个约束类数值（限额 / 封顶 / 赔率 / 合法投注），后端必须用同字段同来源同兜底 enforce：

| 客户端展示项 | 来源字段（含 typo） | 客户端 fallback | 后端 enforce 位置 | 一致? |
|---|---|---|---|---|
| 单注上下限 | `tableConfig.params.xxx` | `?? 100` | check_bet 段位校验 | ✅ |
| 派彩封顶 | `euro_table_payout_max` 等 | `?? 5e5` | payout 三路 cap（G3） | ✅ |
| maxMultiplier | `tableConfig.params.xxx` | `?? 2e4` | payout cap A 路 | ✅ |
| ... | | | | |

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

测试文件（机台 internal 包内，**runtime/history_<gametype>_test.go 已废弃**）：
- `dictionary_test.go` — F2 字典 parity
- `parse_test.go` — XML 解析往返
- `payout_test.go` — F1 4 capture 真帧样本
- `payout_cap_test.go` — G3 三路 cap
- `placebet_incremental_test.go` — I6 incremental
- `validate_test.go` — 窗口/边界/联动
- `history_test.go` — V7a I10 BuildGameDetail 用真 gameDetail.txt XML（机台内，不是 runtime/）
- `client/reports/<tableId>/index.html` — V7b 报表前端页（非 Go，无 report_test.go）：自包含一机台一份，渲染对照真 roundDetail/*.html，4 表 id / SVG / 视觉 ≥ 90%
- `v14_payout_reverse_test.go` — V14 赢钱反推（capture 真局 + roundDetail 玩家明细对照算 payoff）

capture 文件作 fixture 路径（注意目录名是 hall external_code 即 `<capture_dir>`，非 PP tableId）：
- `tmp/<capture_dir>/message.txt`
- `tmp/<capture_dir>/tableConfig.txt`
- `tmp/<capture_dir>/statisticHistory.txt`
- `tmp/<capture_dir>/gameDetail.txt`
- `tmp/<capture_dir>/roundDetail/<rid>.html` + `<rid>-Details-<userId>.html`
- `tmp/<capture_dir>/clientResources/.../main.js`

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

## 14. 铁律核对补充（来自 self-review.md）

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

## 16. 客户端帧表现手册（**强制节，从 L1.4 输出复制 + Phase 3-6 实测补全**）

> 数据来源：`tmp/<tableId>/client_frame_effects.md`（L1.4 AIU 产出，Phase 3-6 实测迭代）。
> 归档时整段复制到此节，让后续相同 gameType 机台对接**直接照抄**调整（最大价值）。

每个 server→client 帧含 6 字段：
1. **分类**：A pass / B rewrite / C synthesize
2. **客户端 reducer**：main.js / chunk evidence 行号
3. **state 字段切换**：哪个 redux state 字段被设置
4. **UI 表现**：实际看到什么变化
5. **缺失影响**：不发会怎样（必含具体卡死路径，如"isTableSubscribed 永 false → 不发 ping → 10s 断连"）
6. **字段说明表**：每个字段的类型 / 客户端用途 / server 填法

按帧分组：
- §16.1 init 阶段帧（handleConnect 必发的最小集）
- §16.2 运行时帧（订阅成功后随回合推送）
- §16.3 结算帧
- §16.4 错误帧
- §16.5 心跳
- §16.6 状态机映射总览（client state 字段 ↔ 触发帧矩阵）

具体内容直接复制 `tmp/<tableId>/client_frame_effects.md`。

**最大价值**：后续相同 gameType 机台对接时，**L1.4 直接 fork 本节**作为起点，
只调差异字段，省 80% 客户端反向分析工作。
```

## commit + 索引更新

```bash
# 1. 写到 worktree 内
WT=$(jq -r .worktree_path tmp/<tid>/state.json)
GAMETYPE=$(jq -r .lobby.gameType tmp/<tid>/state.json)
TABLE_ID=$(jq -r .tableId tmp/<tid>/state.json)

DOC="$WT/docs/integration-experience/$GAMETYPE/$TABLE_ID.md"
mkdir -p "$(dirname "$DOC")"
# Claude 按 16 节模板填实写入 $DOC（§1-§16 全部必填）

# 2. 更新索引（如 docs/integration-experience/README.md 含目录则补一行）

# 3. commit
cd "$WT"
git add docs/integration-experience/
git commit -m "docs(integration-experience): $GAMETYPE/$TABLE_ID 对接经验

16 节经验文档 + 铁律核对摘要 + unresolved 列表。

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
codex decide:    <N> (铁律核对 + 路径决策等)
codex discuss:   <N> (卡死诊断)
unresolved:      <N> 项（详见经验文档第 15 节）
经验文档:        docs/integration-experience/<gametype>/<tableId>.md
铁律核对报告:    tmp/<tableId>/self-review.md

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
