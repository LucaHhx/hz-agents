# Phase 4 — 自问审查

> 触发：Phase 3 全 5 层 + 层间 fix 完成。
> 目的：主 Claude 内省，发现层间 codex 未捕捉的设计缺陷（尤其 EVO 的 per-user 构造）。
> 阶段：❌ 禁止向用户提问；每个发现的问题调 `codex_decide.sh` 决策。

## 工作流程

```
1. 在 worktree 内回答 6 题（用户可扩展）
2. 每个发现的问题 → 调 codex_decide.sh 决策（修 / 不修 / 待人工）
3. 分流：修 → fix agent + commit + 标 ✅ / 不修 → state.unresolved[] + 标 ⏭️ / codex 失败 → unresolved(category="codex-script-failed") + 标 ⚠️
4. 写 tmp-evo/<dir>/self-review.md（**必须落盘**）
5. 无论 unresolved 数量，进 Phase 5（绝不停问用户）
```

## 固定 6 题

### Q1. per-user 数据构造正确性（⭐ EVO 核心，PP 无此题）

逐项核对 `per_user_betstate.go` + 调用点（**锚帧名按本族**：roulette `tableState.betState` / game show `<gt>.bets.state`）：
- strip 广播前是否剥净个人注态私有字段（roulette `betState.{bets,lastGameChips,history}` / game show `<gt>.bets.state.{chips,acceptedBets,history}`）？（漏 → 全桌看别人的注）
- personalize 是否按连接 userId 回填本人注？开窗帧是否注入 rebet 注（roulette lastGameChips / game show `bets.repeat`）？
- 🔴 **快照时序**：`userBetsSnapshot` 是否在 **结算锚帧（roulette GAME_RESOLVED / game show `<gt>.gameResolved`）触发清 Redis 之前**抓？（颠倒 → 读空丢本局注）
- 🔴 **裸 tableId**：所有 per-user 下发帧的 `tableId` 是否填 PPTableID（裸 id）？
- 🔴 **余额来源**：balanceUpdated 是否用商户余额（PlayerBalance）、上游渠道 drop？**balanceUpdated 无 playerId，按连接寻址**？

**自答模板**：逐条 ✅/❌ + file:line + capture 实证（message.txt per-user 帧 shape）

### Q2. 初始化消息清单 + 必要性

server 在 init 路径合成哪些帧？每帧必要性（bundle 哪个 reducer 读它）？缺失影响？
- subscribe（channel=`table-<裸 id>`，缺/错 → 客户端丢全部桌态帧）
- balanceUpdated（商户余额，缺 → ~6s 超时重连 / LOW BALANCE）
- tableState（personalize 回填本人注）
- dealer / appInfo（缓存回放）

**自答模板**：列合成帧 + 每帧 bundle grep 验证 + 缺失影响

### Q3. 用户非下注操作窗口期

有哪些用户操作（roulette 无决策；新族可能有 decision/squeeze/insurance/选择等）？窗口何时开/关？兜底？如无决策必须明确写"无"+ 给 grep 证据（`clientResources/frontend/` send 入口）。

**自答模板**：列操作 + 每操作窗口（开/关/兜底）或 "无用户决策"

### Q4. 下注窗口期 + 资金链路闭环（/bet→/result）

- 开窗锚（roulette BETS_OPEN / game show `<gt>.betsOpen`）MarkBetsOpen + Redis TTL / 关窗锚（roulette BETS_CLOSED / game show `<gt>.betsClosed`）DEL / 双重 fail-closed（C1）/ 撤单窗口校验（C3）
- 🔴 **资金铁律（必答）**：**关窗锚 handler** 是否 `go handlers.SubmitBets(...,p.OnMerchantBetResult)` 向下游商户 /bet 扣本金？`MarkBetAccepted` 是否**只**在 `OnMerchantBetResult` accepted 分支（**绝不**在下注帧/applyBet）？`OnRoundSettled` settle 成功是否必调？
- 🔴 **受理时序**：受理回执（roulette betsAccepted / game show `<gt>.bets` status→Accepted）是否在关窗**之后**下发（不在下注期定格）？

**自答模板**：开/关 handler file:line + 双重 fail-closed ✅/❌ + SubmitBets(OnMerchantBetResult) ✅/❌ + MarkBetAccepted 仅 accepted ✅/❌ + OnRoundSettled ✅/❌ + betsAccepted 时序

### Q5. 消息分类决策（每事件分类必须 capture 实证）

逐个 upstream/downstream 事件分类（A 广播 / A2 communal 演出 / B per-user 改写 / handle / C 自合成），按本族 DICT.message_classification：

| 分类 | 含义 | roulette 范例 / game show 范例 |
|---|---|---|
| **A 广播** | 上游帧直转 | winnersList/recentResults/appInfo/dealer · gs: `<gt>.spinHistory`/`<gt>.bettingStats`(可 enrich 我方聚合) |
| **A2 communal 演出** | 全桌开奖动画直转不缓存 | （roulette 无）· gs: `<gt>.wheelSpinning/wheelStopping/wheelResult/bonus` |
| **B per-user 改写** | 拦截改写 per-user | tableState.betState · gs: `<gt>.bets.state` / balanceUpdated（drop+商户余额，无 playerId） |
| **handle 业务** | 触发状态机/结算 | tableState 5 态/winSpots · gs: `<gt>.betsOpen/betsClosed/gameResolved` |
| **C 自合成** | 上游不发、server 构造 | subscribe/betsAccepted/betActionResponse/win · gs: subscribe/`<gt>.placeChips` echo/`<gt>.bets` |

🔴 **Q5 关键**：① **comm 集合差对 game show 失效**（所有 type 两份都有）→ per-user 主判据=计数悬殊+per-session 字段；② 漏 A2 演出帧类；③ C 类易漏。
**自答模板**：表格逐事件 — 事件 / 分类 / 实现位置 file:line / capture 证据（含计数）。

### Q6. currencyMult 进制 + per-currency 配置（EVO 特有）

- 金额是否全路径按 currencyMult 进制处理（下注校验 / 结算 / payout / 显示）？
- `b_table_currency_configs` 是否含本桌各币种限红？`/config` 返回限红是否非空？
- 限额比较是否与下注金额同进制？

**自答模板**：逐路径 ✅/❌ + config.txt currencyMult 值 + DB 行确认

## codex_decide.sh 调用模板（每问题一次）

```bash
bash $CODEX_COLLAB/scripts/codex_decide.sh -d "$REPO_ROOT" -l "self-review-q<N>-<uuid>" \
    -- "## 背景
gameType: <gametype> / evo_table_id: <id> / worktree: <path> / self-review 第 <N> 题
问题描述：<具体问题，含 file:line + capture 对比>

## 关联文件（codex 自己 rg/cat 探索，不喂答案）
- 本实现: <file:line>  · 模板对照: roulettecore 同名文件
- capture 证据: tmp-evo/<dir>/<file> + grep
- known-pitfalls: <相关条款>

## 决策点：是否需改本实现？
候选 A: 修 — 改成与 roulettecore 一致 / capture 实证形态
候选 B: 不修 — 本族特殊（理由必须 capture/bundle 实证）
候选 C: 不修 — 差异可接受（不影响资金/per-user/UX）
候选 D: 待人工 — 信息不足
判断标准：资金/per-user 安全 → 必修；capture 实证支撑差异 → 可不修；命名风格 → 可不修；缺实证 → D"
```

## codex 决策 → 行动

| codex 输出 | 行动 | self-review.md 标记 |
|---|---|---|
| A 修 | Agent fix worker → commit | ✅ 已修 commit:<sha> |
| B 不修-本族特殊 | unresolved（category="self-review-deferred"） | ⏭️ unresolved id:<uuid> |
| C 不修-可接受 | 同上 | ⏭️ unresolved id:<uuid> |
| D 待人工 | unresolved（category="self-review-no-evidence"） | ⚠️ 待人工 |
| codex 超时/不可解析 | unresolved（category="codex-script-failed"） | ⚠️ 待人工 |

## self-review.md 落盘格式（必须写）

```markdown
# <evo_table_id> 自问审查报告
> 日期：<ISO> · 触发：L5 + 层间 fix 完成、进 Phase 5 前 · 处理原则：每问题调 codex；不停问用户

## 1. per-user 数据构造
**结论**：strip/personalize/snapshot/裸 tableId/余额来源 各 ✅/❌ — file:line
**自检发现问题**：问题 / codex 决策 id / 结论 / 行动（✅ 已修 commit / ⏭️ unresolved / ⚠️ 待人工）
## 2. 初始化消息清单  ## 3. 用户非下注操作  ## 4. 下注窗口+资金闭环  ## 5. 消息分类  ## 6. currencyMult+per-currency
（每节同上格式）
## 综合汇总
- 总问题数 N / ✅ 已修 M / ⏭️ unresolved K / ⚠️ 待人工 L / 进 Phase 5 ✅
## state.unresolved[] 引用
- [unresolved id:<uuid> from §N] — <摘要>
```

## state.json 写入

```jsonc
{ "phase":4, "status":"done", "self_review_path":"tmp-evo/<dir>/self-review.md",
  "codex_decisions":[{"id":"<uuid>","phase":4,"label":"self-review-q1","question":"per-user 快照时序","selected":"A","rationale":"...","written_to":"self-review.md §1"}],
  "unresolved":[...] }
```

进 Phase 5。
