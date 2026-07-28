# Phase 7 — 经验文档归档

> 触发：Phase 6 verify 全 PASS（或 partial 含 unresolved）。
> 产物：`<repo>/docs/integration-experience/evo/<evo_table_id>.md`（worktree 内）。
> 阶段：❌ 禁止向用户提问；commit 到 worktree 子分支，不 PR。

## 🔴 写之前：先确认这份文档该存在什么

**它的唯一不可替代价值**：`tmp-evo` 被 gitignore（`/tmp*`），capture 与对接期的 BRIEF.md **都不入库**。
临时目录一清，这份文档就是该机台协议事实的**唯一持久记录**。

所以判据很清楚 ——

| 内容 | 去处 |
|---|---|
| 换一台机台**不成立**的事实（协议 shape / 逆向硬细节 / 本族特有陷阱） | **本文档** |
| 下一个机台**还会用到**的结论 | `docs/PROJECT-MEMORY.md` |
| 每次对接都要守的铁律 | `known-pitfalls.md` |
| 这次改了什么、为什么 | commit message |

⚠️ **模板节按需删，不要留占位**。「本族无此项」的节直接删掉 —— 16 节全填会把独有内容淹掉
（实测：读者只会打开一次，看到半屏「无此项」就再也不来了）。
**独有内容不足 5 节就写 5 节**，那也比 16 节注水强。

🔴 **写完必须更新 `docs/integration-experience/README.md` 索引**：加一行
「机台 | gametype | **这份文档独有的**」。31 份文档 8000+ 行散在 24 个目录里，
不进索引 = 不会被任何人找到（实测：本次只把既有文档当格式模板看，没用里面一个事实）。

## 经验文档模板（16 节，**按需删，非全部必填**）

> **完整性铁律**：§1-§16 全部必填。某节无内容写 `无 / N/A` 并一句话说明原因，**禁止整节省略**。节号固定，新族 fork 本模板不自行增删。
> EVO 重点节：§5.2 per-user 改写决策表、§16 客户端帧表现手册——这两节是后续同族对接复用价值最大处。

```markdown
# <evo_table_id> 对接经验（<gametype> / EVO <桌名>）

> 对接日期：<ISO> · base 分支：<...> · worktree 分支：worktree/<base>/evo-<gametype>-<tail>
> reuse_core：<none/roulette> · 是否新游戏族：<是/否>

## 1. 机台基本信息

| 字段 | 值 |
|---|---|
| evo_table_id（裸，协议帧用） | <id> |
| table_code（b_tables.code，索引用） | evo<id> |
| gameType | <gameType> |
| casinoHost | <PROVIDER_HOST 占位> |
| currencyMult | <进制，如 20000> |
| 协议形态 | JSON typed 信封 `{type,args}`（双向 JSON，无 XML） |
| 状态机 | <roulette 5 态 / 新族实测序列> |
| capture 帧数 | message N / message-nobet N |
| 抓 capture 日期 | <YYYY-MM-DD> |

## 2. 协议事实速查（capture 实证，按本族填——下面 roulette/game show 两套范例）

上游事件（message-nobet recv，**帧名/计数按本族实测**）：
- roulette 范例：`tableState`(N 次，5 态枚举,字段 `{state,gameId,result,betState,closeInMillis}`)/`winSpots`/`winnersList`/`recentResults`
- game show 范例(IceFishing)：`<gt>.betsOpen/betsClosed/wheelSpinning/wheelStopping/wheelResult/gameResolved/gameCleared`(离散 7 帧)/`<gt>.bets`(per-user 注态)/`<gt>.bettingStats`(N 次,最高频)/`<gt>.spinHistory`/`<gt>.winnersList`/`<gt>.bonus`/`<gt>.restore.begin/end`
- 公共：`dealer`/`appInfo`/`balanceUpdated`(渠道 USD,drop,无 playerId): 各 N 次

下游事件（message.txt send）：
- roulette：`betAction{action:{type:PLACE/REMOVE/MOVE/UNDO, value:{betCode:amount}}}`
- game show：`<gt>.placeChips{chips:{段名:额}, betAction:"Place"/"Repeat", betTags}` + `<gt>.undo/undoAll`
- 公共：`fetchBalance` / `metrics.ping` / `settings.read/update` × N

## 3. 一轮生命周期（capture 真帧时序，按本族状态机 kind 填）

```
roulette(state 枚举): BETS_OPEN → 玩家 betAction → CLOSING_SOON → BETS_CLOSED(→/bet+betsAccepted)
                      → ANNOUNCED → GAME_RESOLVED(result)+winSpots(→snapshot→结算→/result→per-user win+balance) → winnersList
game show(离散事件):  <gt>.betsOpen → 玩家 placeChips → betsClosed(→/bet) → wheelSpinning→wheelStopping→wheelResult(A2 演出)
                      → gameResolved(result+倍率盘,→snapshot→结算→/result→per-user bets:Settled+balance) → gameCleared → winnersList
```

## 4. 字典（来自 dict.json）

- betCode 全集：<N> 个（roulette `betAction.value` 数字键 / game show `placeChips.chips` 字符串段名；roundDetail 前缀映射如 `IF_`）
- errorCode 全集：<N> 项
- 状态机：kind=<state_enum / discrete_events> · 序列 <…>
- 下注模型：<增量+UNDO 栈 / 全量 chips 快照> · 赔付模型：<号码 odds / segment 倍率 / 牌型>
- currencyMult：<进制> · 限红字段：<config.txt 字段集> · betstats：<有 `<gt>.bettingStats` / 无>

## 5. 协议处理决策表

> 按本族实测填；下表 roulette 范例 + game show(IceFishing) 范例对照。

| 事件（roulette / game show） | 处置 | 业务 | 理由 |
|---|---|---|---|
| tableState(5 态) / `<gt>.betsOpen/betsClosed/gameResolved` | handle | 窗口/结算锚 | 状态机（kind 不同） |
| winSpots / `<gt>.gameResolved` | handle | 触发派彩 | 结算锚 |
| （无）/ `<gt>.wheelSpinning/wheelStopping/wheelResult/bonus` | **A2 communal 演出** | 开奖动画 | 全桌一份直转不缓存 |
| winnersList / `<gt>.winnersList` | **合并我方中奖者后广播**（非纯直转，B8） | 全场赢家 | 上游榜结构上不含我方，须注入本局我方 win |
| recentResults / `<gt>.spinHistory` | A 直转 + 缓存回放 | 走势 | 全量快照帧 |
| （无）/ `<gt>.bettingStats` | A 直转/enrich | 投注热度 | 聚合计数，可加我方 |
| dealer/appInfo | A 直转 + init 缓存 | — | root-key/init |
| balanceUpdated（上游） | **B drop + 商户余额重发** | 余额本地 | 渠道 USD 不透传，无 playerId |
| tableState.betState / `<gt>.bets` | **B per-user 改写** | 本人注剥离+回填 | per-user 节 §5.2 |
| betAction / `<gt>.placeChips` | **C 自合成 echo** | 本地拦截下注 | 仅 message.txt |
| betsAccepted/betActionResponse / （合并在 `<gt>.bets.acceptedBets`） | C 自合成 | 受理回执 | 关窗后下发 |
| win / `<gt>.bets`(Settled+payout) | C 自合成（per-user SendToUser） | 个人派彩 | 裸 tableId |
| betValidationError | C 自合成 | 拒单 | 客户端可识别 code |

### 5.1 客户端-后端一致性矩阵（强制节）
| 客户端展示项 | 来源字段 | 客户端 fallback | 后端 enforce 位置 | 一致? |
|---|---|---|---|---|
| 单注上下限 | config.<betType>_bet_max | ?? | check_bet | ✅ |
| 派彩封顶 | euro_table_payout_max 等 | ?? | payout per-bet cap（#64 反转，非 round-level） | ✅ |
| currencyMult 进制 | config.currencyMult | — | 全路径金额换算 | ✅ |

### 5.2 per-user 改写决策表（⭐ EVO 强制节，复用价值最大）
> 锚帧名按本族（roulette `tableState.betState` / game show `<gt>.bets.state`）。

| 帧（本族个人注态帧） | 会话私有字段 | 广播处理 | per-user 回填 | 下发 tableId |
|---|---|---|---|---|
| roulette `tableState.betState` | bets/lastGameChips/history | strip 剥离 | personalize 回填本人注 + 开窗注入 lastGameChips | 裸 id |
| game show `<gt>.bets.state` | chips/repeat/acceptedBets/history | strip 剥离 | 回填本人 chips + 开窗注入 repeat(rebet) | 裸 id |
| balanceUpdated | balance(渠道USD)/balances[] | drop 上游 | 商户余额(PlayerBalance) **按连接寻址（无 playerId）** | 裸 id |
| 个人派彩(roulette win / game show bets:Settled) | — | 不广播 | SendToUser 仅本局有注用户 | 裸 id |
| 快照时序 | — | — | userBetsSnapshot 在**结算锚帧**清 Redis **之前** | — |

## 6. 服务端→客户端帧合成清单

必合成（C）：subscribe(channel=table-<裸id>) / balanceUpdated(商户余额，init 必发，无 playerId) / 受理回执(关窗后) / 个人派彩(裸 tableId) / betValidationError。
per-user 改写（B）：个人注态帧（roulette `tableState.betState` / game show `<gt>.bets.state`）/ balanceUpdated。
A2 communal 演出（game show，直转不缓存）：`<gt>.wheelSpinning/wheelStopping/wheelResult/bonus`。
结算消息顺序（按本族结算锚）：`结算锚 → snapshot → /result → SendToUser(派彩 + balanceUpdated)`。

## 7. 遇到的问题 + 解决方案（Phase 3 层间 + Phase 5 整体修复记录）
每 finding 一条：症状 / 根因 / 修复 `commit <sha>` / 依据（known-pitfalls 条 / capture 样本）。

## 8. 资金安全清单（known-pitfalls C 节逐项）
- [x] C1 CanBet Redis 异常 false  - [x] C7 GetRedisUserBets fail-closed  - [x] C9 context 超时
- [x] /result 必先 /bet（SubmitBets OnMerchantBetResult + hasSuccessfulBetDebit）
- [x] MarkBetAccepted 仅 accepted 分支  - [x] OnRoundSettled 必调  - [x] payout per-bet cap（#64 已下线 round-level）
- [x] per-user 余额=商户钱包（上游 drop）  - [x] snapshot-before-settle 时序

## 9. 测试策略
测试文件（evocore 包内）：
- `odds_test.go` / `payout_test.go`（≥4 roundDetail 真样本）
- `per_user_betstate_test.go`（strip/personalize/snapshot 时序）⭐
- `reconcile_test.go`（孤儿局 fail-closed）
- `settle_*_test.go`（requireAccepted + OnRoundSettled）
- `check_bet_test.go`（窗口/限额/进制）
- `history_test.go`（真 gameDetail.txt JSON；结构化对账以 `roundDetail .data.data` 为准，gameDetail `.data.render` 是 HTML）
- `betstats_test.go`（条件，game show enrich 我方聚合计数）
- `v14_payout_reverse_test.go`（roundDetail `.data.data` 反推；betCode 前缀 `IF_` 映射）
- `client/reports/<裸id>/index.html`（报表前端页，无 Go test，对照 roundDetail html+json ≥90%）

capture fixture 路径：`tmp-evo/<evo_table_id>/{message.txt,message-nobet.txt,config.txt,gameDetail.txt,roundDetail/<rid>.{json,html},clientResources/...}`
coverage：<X>%

## 10. 项目级跳过状态
本族跳过项（第 1 次提及一次性记入）：<如有>

## 11. 与其他机台对比
| 维度 | 本族 | roulette（vctlz20yfnmp1ylr） |
|---|---|---|
| 协议形态 | JSON typed | JSON typed |
| 状态机 | <...> | 5 态 |
| 下注协议 | action 增量+UNDO 栈 | action 增量+UNDO 栈 |
| per-user 帧 | <...> | tableState.betState/balanceUpdated |

## 12. 部署前 checklist
- [ ] `b_tables` 行（vendor_type='evo'、code='evo'+裸id、original_id=裸id、game_type、enabled、failover_group_id）
- [ ] `b_table_currency_configs` 各币种限红 + currencyMult（per-currency）
- [ ] `b_currency_rates` 有启用 EUR 行 + symbol
- [ ] factory 注册（L5 完成）
- [ ] 大厅 allowlist 自动订阅（DB enabled=true 即生效，无需改代码）
- [ ] 报表页 `client/reports/<裸id>/index.html`
- [ ] post-merge live-launch：/config wsHost 指我方 + 限红非空 / game ws 进桌 / 视频（可后置）/ session mint(Akamai)
- [ ] worktree 子分支 merge 到 base（用户决定时机）

## 13. 必看注意事项（本族新坑）
总结 Phase 3-6 学到的本族特殊知识，给后续同 gameType 对接参考：
- <如 状态机与 roulette 不同 / 特殊 betCode / per-user 帧额外字段 / 进制特殊>

## 14. 铁律核对补充（来自 self-review.md）
引用 `tmp-evo/<evo_table_id>/self-review.md`：总问题 N / ✅ 已修 M / ⏭️ unresolved K / ⚠️ 待人工 L。

## 15. unresolved 摘要（用户后续审视）
| id | phase | category | 描述 | 建议动作 |
|---|---|---|---|---|
| unresolved-<uuid> | <N> | <category> | <...> | <...> |

## 16. 客户端帧表现手册（⭐ 强制节，从 L1.4 client_frame_effects.md 复制 + 实测补全）
> 整段复制 `tmp-evo/<evo_table_id>/client_frame_effects.md`，后续同 gameType 对接 L1.4 直接 fork 本节，省 80% 客户端反向分析。
每帧 6 字段（分类 / bundle reducer / state 切换 / UI 表现 / 缺失影响 / 字段说明表），分组：init / 运行时(5 态) / 结算 / 错误 / 心跳 / 状态机映射总览。
EVO 重点：subscribe channel=裸id、balanceUpdated 商户余额 6s 闸门、tableState.betState per-user、win 裸 tableId。
```

## commit + 索引更新

```bash
WT=$(jq -r .worktree_path tmp-evo/<dir>/state.json)
TABLE_ID=$(jq -r .evo_table_id tmp-evo/<dir>/state.json)
DOC="$WT/docs/integration-experience/evo/$TABLE_ID.md"
mkdir -p "$(dirname "$DOC")"
# Claude 按 16 节模板填实写入 $DOC（§1-§16 全部必填）
cd "$WT" && git add docs/integration-experience/evo/
git commit -m "docs(integration-experience): evo/$TABLE_ID 对接经验

16 节经验文档 + per-user 改写决策表 + 客户端帧表现手册 + 铁律核对 + unresolved。
capture 6 文件作 fixture。"
```

## 最终输出（流程结束摘要）

```
✅ evo/<gametype>/<evo_table_id> 对接完成

worktree:        worktree/<base>/evo-<gametype>-<tail>
reuse_core:      <none/roulette>
commits:         <N>      新增文件: <N>      测试覆盖率: <X.X>%
codex review 轮: <N>（L1-L5 层间 + 整体循环）
codex decide:    <N>      codex discuss: <N>
unresolved:      <N> 项（详见经验文档 §15）
经验文档:        docs/integration-experience/evo/<evo_table_id>.md
铁律核对报告:    tmp-evo/<evo_table_id>/self-review.md

未做：PR / 部署（用户决定时机；铁律：不 PR）
```

## state.json 写入

```jsonc
{ "phase":7, "status":"done",
  "experience_doc_path":"<repo>/docs/integration-experience/evo/<evo_table_id>.md",
  "final_summary":{"commits":N,"coverage":"X.X%","codex_reviews":M1,"codex_decisions":M2,"codex_discussions":M3,"unresolved_count":K} }
```

流程结束。
