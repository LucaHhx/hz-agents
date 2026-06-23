# Phase 3 — 层间 codex 审查

> 触发：每层（L1-L5）全部 AIU commit 完成后立即跑。软上限：每层 ≤ 2 轮。
> 模式：codex-collab review（`$CODEX_COLLAB/scripts/codex_review.sh`）。

## 调用模板

```bash
LAYER=L1; ROUND=1
WT=$(jq -r .worktree_path tmp-evo/<dir>/state.json)
HEAD_N=$(jq ".aiu_progress.$LAYER.commits | length" tmp-evo/<dir>/state.json)
bash $CODEX_COLLAB/scripts/codex_review.sh -d "$WT" -l "layer-${LAYER}-round-${ROUND}" \
    -- "$(render_layer_review_prompt $LAYER $HEAD_N)"
```

## 每层审查重点（注入 prompt）

### L1 — ENUM / DICT / PAYOUT_MODEL / CLIENT_FRAME_EFFECTS（协议事实正确性）
- **ID 双字段**：`Variant.TableID`=code（带 evo 前缀）/ `PPTableID`=裸 tableId；下发帧 tableId 用裸 id
- 上游事件 type 全集（capture 实证 + bundle 补 canceled/gameCancelled/betValidationError/restore 等罕见）
- **状态机 kind + 序列实证**：roulette 5 态枚举；**离散事件型（game show）必判 kind=discrete_events** 并列全生命周期事件链；**禁假设 5 态 tableState.state**
- **betCode 全集 + 赔付参数**：`odds.go` 与 `roundDetail/<rid>.json .data.data` 三方交叉；roulette 号码 odds（含 0 周边特殊码）/ game show segment 倍率（每局上游下发，无固定表）；**betCode 双命名空间映射**（下注帧 `Leaf1` vs roundDetail `IF_Leaf1`）
- **init_frame_sequence**：含 subscribe(channel=`table-<裸 id>`) + balanceUpdated(商户余额，无 playerId) + 个人注态帧（roulette tableState / game show `<gt>.bets`+restore）；最少+最必要
- **message_classification**：A 广播 / **A2 communal 演出** / B per-user 改写 / handle / C 自合成；**找 per-user 用计数悬殊+per-session 字段（集合差对 game show 失效）**
- Redis key 走 `server/enum/cache_key.go`

**主信息源**：`message-nobet.txt`（上游广播契约）+ `message.txt`（下游+per-user）+ `config.txt` + `roundDetail/*.json` + `clientResources/frontend/`

### L2 — MODELS / RULES / PROCESSOR / BET_REDIS / BET_WINDOW（struct 与真帧匹配）
- models.go struct vs `message.txt`/`message-nobet.txt` 真帧逐字段（**禁 map[string]interface{}**）
- **个人注态帧嵌套 map**（per-user 依赖，不可扁平）：roulette `ArgsTableState.BetState{Bets,LastGameChips,History}` / game show `ArgsBets.State{chips,repeat,acceptedBets,history}`
- **currencyMult 进制**：金额/限额字段类型 + 进制处理
- **下注模型按 bet_protocol 结论**：roulette 增量 + per-user UNDO 栈；game show placeChips 全量 chips 快照覆盖、无 UNDO 栈
- PROCESSOR 单例锁字段齐（mu/betsMu/cacheMu/stacksMu）+ betStacks(仅增量协议) + initFrames + SetBalanceSource 字段
- BET_REDIS fail-closed（SCAN 失败返 error 不返 nil，C7/C9）+ requireAccepted 过滤
- BET_WINDOW `CanBet` Redis 异常 return false（C1）

**主信息源**：全 capture + bundle + 上游 L1 产物

### L3 — UPSTREAM / DOWNSTREAM / PER_USER / SETTLE / CHECK_BET（业务符合状态机）
- DecodeUpstream 四类分流正确（Broadcast/**A2 演出**/Handle/Drop）+ **root-key 帧 dealer 缓存广播**（不丢弃）+ A2 演出帧（wheel/bonus）直转不缓存
- **🔴 snapshot-before-settle 时序**：**结算锚帧**（roulette GAME_RESOLVED / game show `<gt>.gameResolved`）在清 Redis 前 `userBetsSnapshot`
- **🔴 PER_USER**：剥净私有字段（roulette `tableState.betState` / game show `<gt>.bets.state`）/ 回填本人注 / 下发帧 tableId 用**裸 id** / 1007 LateBet 回填
- balanceUpdated 上游 drop + 商户余额 per-user 重发（余额源 PlayerBalance；**无 playerId 按连接寻址**）
- **🔴 资金**：**关窗锚帧**（roulette BETS_CLOSED / game show `<gt>.betsClosed`）必调 `SubmitBets(...,OnMerchantBetResult)`；MarkBetAccepted 只在 accepted 分支；受理回执在关窗**之后**下发（不在下注期定格）
- SETTLE：requireAccepted fail-closed / `OnRoundSettled` 必调 / `/result` 必先 /bet（hasSuccessfulBetDebit）/ Extra 前瞻落盘 / 列宽 ≥ 最长串（J12）
- betValidationError 字段全填 + error code 命中客户端真识别分支 + 普通拒单 extendedErrorCode 留空
- CheckBet 双重 fail-closed + currencyMult 进制 + 撤单窗口校验（C3/C4）

**主信息源**：`message.txt`/`message-nobet.txt`（时序）+ `roundDetail/*.json`（结算体）+ `config.txt`（限额）+ `clientResources/frontend/`

### L4 — PAYOUT / HISTORY_RECENT / HISTORY_DETAIL / REPORT_PAGE / CURRENCY_CONFIG / [BETSTATS 条件]（派生产物一致性）
- payout 公式**含本金、按族**（roulette `amount×(odds+1)` / game show `stake×倍率`）+ G3 三路 cap min（用户级非单注）+ CapUserPayout（C8）+ currencyMult 进制
- **BETSTATS check**：capture 有 `<gt>.bettingStats` 则建（直转或合并我方聚合计数，**非 per-player 不可注单玩家注**）；roulette 无则跳过——**不可默认「EVO 无 betstats」**
- **reconcile fail-closed**：走势帧（recentResults/spinHistory）补结算同样走 requireAccepted + hasSuccessfulBetDebit
- 走势全量快照帧（recentResults/spinHistory）缓存 + 新连接回放
- HISTORY_DETAIL：结构化对账以 `roundDetail/<rid>.json .data.data` 为准（`gameDetail.txt .data` 含 `render` HTML 非逐字段）；投注类型/开奖结果分离（J7）；缺数据填 "0" 不空串（I8）
- **REPORT_PAGE**：渲染 vs `roundDetail/<rid>.html` ≥ 90% + 对照 `roundDetail/<rid>.json` 字段；**一桌一份不共用、不引共享 _assets**；前置 messages 非空 + round/extra 齐
- CURRENCY_CONFIG：`b_table_currency_configs` 各币种限红 + currencyMult；`/config` 返回限红非空

**主信息源**：全 capture + `roundDetail/*.{json,html}` + bundle + 上游 L1-L3 产物

### L5 — FACTORY（注册完整性）
- import 路径正确 + 别名唯一
- `implementedTables` 键 = **b_tables.code（evo+裸id）**；switch on **table.OriginalId（裸 id）**
- buildXxxInstance：Variant 双 ID 正确 + LoadLimits + NewProcessor + **`SetBalanceSource(runtime.PlayerBalance)`**（缺 → LOW BALANCE）+ SeamlessBetService + NewEvoInstance
- **全仓库 build pass**（既有 roulette + 新族）+ 无重复 case
- DB 模板写进经验文档（不执行）

**主信息源**：上游 L1 enum.go + 既有 instance_factory.go（buildRouletteInstance 范例）

## 通用 codex review prompt 结构

```
你是 EVO <gametype> 桌 <evo_table_id> Phase 3 Layer N 完成后的代码审查者。
只审查、不修改任何文件。按 🔴/🟡/🟢 分类输出，每条 file:line + 描述 + 修复建议。

【本层范围】Layer N 完成的 AIU：<list>；本层 diff：git diff HEAD~<M>..HEAD
【审查重点】<按层注入上方 checklist>
【主信息源（必读，验证产物正确性）】
1. capture（事实最高权威）：message.txt / message-nobet.txt / config.txt / gameDetail.txt / roundDetail/*.{json,html} / clientResources/frontend/
2. 上游 AIU 产物（参考不审）：按 N 注入
3. 既有：roulettecore 模板 / $SKILL_DIR/references/{evo-platform-primer,known-pitfalls}.md
【输出格式】🔴/🟡/🟢 + file:line + 描述 + 修复建议 + 引用 known-pitfalls 条目
【硬规则】
- capture 真帧与 bundle 字面量冲突时以 capture 为准
- struct 字段名/下发帧 tableId 与 capture 不一致 → 🔴 must-fix
- per-user 改写缺失/快照时序错/余额来源错 → 🔴 must-fix（资金/UX 安全）
- "功能对了但 capture 没验证过" → 🟡 should-fix
- 与 roulettecore 模板不一致但符合本族 capture → ✅ OK 不报
```

## fix 决策（自主分流）

| finding 类型 | 处理 |
|---|---|
| 🔴 must-fix small（≤50 行/单文件） | 立即修 + commit |
| 🔴 must-fix medium 资金/per-user 安全必要 | 立即修 |
| 🟡 medium 非必要 | `state.unresolved[]`（category="medium-non-essential"） |
| 🟡 large（跨 AIU/新表/新 API） | `state.unresolved[]`（category="large-impact"） |
| 🟢 nice-to-have | 跳过 |
| 同 hash ≥ 3 次重提 | `state.unresolved[]`（category="repeated-N-times"）+ 后续跳过 |

## 退出条件
- codex 报"无重大问题" → 进下层
- 2 轮跑完仍有 finding → 写 `state.unresolved[]` + 进下层（**绝不停问用户**）
- codex CLI 卡死 → 写 unresolved（category="codex-script-failed"）+ 进下层

## state.json 写入
```jsonc
{ "codex_reviews": [{"layer":"L1","round":1,"findings":5,"fixed":4,"unresolved_count":1}],
  "aiu_progress": {"L1":{"done":["ENUM","DICT","ODDS_BETCODE","CLIENT_FRAME_EFFECTS"],"commits":[...],"review_rounds":2,"review_fixed":4,"review_unresolved":1}} }
```
