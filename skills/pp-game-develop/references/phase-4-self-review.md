# Phase 4 — 自问审查

> 触发：Phase 3 全 5 层 + 层间 fix 完成。
> 目的：主 Claude 内省，发现层间 codex 未捕捉的设计缺陷。
> 阶段：❌ 禁止向用户提问；每个发现的问题调 `codex_decide.sh` 决策。

## 工作流程

```
1. 读 docs/integration-experience/common/self-review-checklist.md（pp-game 仓库内方法论）
2. 在 worktree 内回答 4 题（用户可扩展）
3. 每个发现的问题 → 调 codex_decide.sh 决策（修 / 不修 / 待人工）
4. codex 决策结果分流：
   - 修 → fix agent 修 + commit + self-review.md 标 ✅
   - 不修 → 写 state.unresolved[] + 标 ⏭️
   - codex 失败 / INSUFFICIENT_CONTEXT → fallback 写 unresolved（category="codex-script-failed"）+ 标 ⚠️
5. 写 tmp/<tableId>/self-review.md（**必须落盘**）
6. 无论 unresolved 数量，进 Phase 5（绝不停问用户）
```

## 固定 5 题（用户可在 pp-game `docs/integration-experience/common/self-review-checklist.md` §6+ 扩展）

### Q1. winners 处理逻辑跨机台一致性

是 pass / rewrite / 其他？与既有机台一致吗？不一致的理由必须有 capture 实证或 main.js 字面量支撑，不能"按 dragontiger 类比"。引 known-pitfalls B2 修正版。

**自答模板**：
- 本机台 winners verdict：<file:line> 实现的处理方式
- 既有机台对照（grep `docs/integration-experience/<gametype>/*.md` 第 5 节）
- 差异理由（必须有 capture 实证或 main.js 字面量；不能"按 dragontiger 类比"）

### Q2. 初始化消息清单 + 必要性

server 在 sendInit 路径合成哪些帧？每帧必要性（main.js 哪个分支读它）？缺失影响（如 subscribe.channel 缺失 → isTableSubscribed 永远 false → 10s 断连）？

**自答模板**：
- 列出 server 合成帧
- 每帧 main.js grep 验证（哪段读它）
- 缺失各帧的具体影响

### Q3. 用户非下注操作窗口期

有哪些用户操作（decision / 选球 / squeeze peel / chosenBalance 等）？窗口何时开/关？兜底逻辑？不限制后果？跨机台对照？如无决策必须明确写"无"+ 给出 grep 证据。

**自答模板**：
- 列出本机台所有用户操作（grep main.js `send(` / `dispatch`）
- 每个操作窗口期：开启帧 / 关闭帧 / 兜底
- 限制必要性 / 不限制后果

### Q4. 下注窗口期管理

betsopen 开启机制（MarkBetsOpen + Redis TTL 30s）/ betsclosed 关闭（DEL Redis）/ 双重 fail-closed（内存 + Redis C1）/ 空 lpbet 撤单防御（C3）/ 跨机台时序差异？

**自答模板**：
- 开启 handler 文件:行
- 关闭 handler 文件:行
- 双重 fail-closed ✅/❌
- C3 撤单防御 ✅/❌
- 跨机台对比

### Q5. 消息格式三分类决策（每个事件分类必须有 capture 实证）

PP 机台运行时所有消息（client ↔ server）分为三类，必须**逐个 upstream / downstream 事件分类**，
并与 capture 实证对齐。漏分类或分类错都会导致：客户端卡死 / 时序错乱 / 字段被误透传。

**三类定义**：

| 分类 | 含义 | 典型例子 |
|---|---|---|
| **A: 上游 → 直接转发** (pass) | PP 上游帧 server 不动字节直传给客户端 | dealer / game / timer / winners / playersCount / pong（透传） |
| **B: 上游 → server 修改后转发** (rewrite) | PP 上游帧 server 拦截 + 改字段 / enrich 再发 | betstats（EnrichBetstats 加我方平台金额） / table（B1 tableId 字节替换） |
| **C: 上游不发 → server 自合成** (synthesize) | PP 上游不发，server 主动构造发给客户端 | **subscribe ack**（I5 协议铁律，1 上游 fan-out N client 必须自合成） / bet echo（accepted 落账后回） / win 帧（我方私聊） / betValidationError |

**自答模板**：

```markdown
| 事件 / 帧 | 分类 | 实现位置 file:line | 证据 |
|---|---|---|---|
| `betsopen` | A pass | upstream_handlers.go:N | capture seq=N |
| `subscribe` ack | C 自合成 | downstream_dispatch.go:sendSubscribeAck | capture PP 上游连接时发 1 次，多 client 必须各自合成 |
| `bet` | C 自合成（OnMerchantBetResult accepted） | downstream_bet.go:echoBetsAfterMerchantAck | capture betsclosed 后 1.4s |
| `win` | C 自合成（FlushPendingWins） | settle_persistence.buildWinFrame | capture winners 后 ~500ms |
| `betstats` / `betResultStats` | B rewrite | betstats_enrich.go | capture 真帧 + Redis 用户下注合并 |
| `betValidationError` | C 自合成（lpbet 校验失败） | downstream_bet.go:buildBetValidationError | capture 未观察到（main.js 7 字段） |
| `dealer` | A pass + side-effect 解析 dealer.value 存 cache | upstream_cache.go:cacheDealer | capture seq=2 |
| `<gametype>gameresult` | A pass + 业务触发结算 | upstream_handlers.go:on<G>GameResult | capture seq=N |
| `winners` | A pass + 触发 FlushPendingWins 延迟 | upstream_dispatch.go:onWinners + time.AfterFunc | B2 修正版 |
| `command` reply | C 自合成（lpbet ack） | downstream_bet.go:sendCommandReply | capture lpbet 后立即回 |
| `switch` | drop + 业务（B10 reconnect） | upstream_handlers.go:onSwitch | capture 罕见 |
| ... 全部事件 ... | | | |
```

**关键陷阱（必检）**：
- **C 类自合成易漏**：subscribe ack（PP 单上游连接发一次 → 多 client fan-out 必须各自合成；
  jackpotwheel 历史教训：漏掉导致客户端 isTableSubscribed 永远 false → 不发 ping）
- **B 类 rewrite 易引入双信封**（B7）：rewrite 后必须 unwrapEnvelope 再放回 action.data
- **A 类 pass 不能丢字段**：单帧多 key 时按 B3 priority rebuild envelope（drop 一个 key 不
  应丢同帧其他 pass key）

**自检发现问题**：同前 4 题格式 — 调 codex_decide / fix agent / 写 unresolved。

## codex_decide.sh 调用模板（每问题一次）

```bash
bash $CODEX_COLLAB/scripts/codex_decide.sh \
    -d "$REPO_ROOT" \
    -l "self-review-q<N>-<uuid>" \
    -- "## 背景
gameType: <gametype> / tableId: <tableId>
worktree: <worktree_path>
self-review 第 <N> 题
问题描述：<具体问题，含 file:line + 跨机台对比结果>

## 关联文件（codex 自己 rg/cat 主动探索，不要直接喂答案）
- 本机台实现: <file:line>
- 既有机台对照: <repo>/docs/integration-experience/<gametype>/*.md
- capture 证据: <tmp/<tid>/<file> + grep 命令>
- known-pitfalls: <相关条款 B2/C1/I3 等>

## 决策点
是否需要修改本机台实现？
候选 A: 修 — 改成与既有机台一致 / 改成 capture 实证形态
候选 B: 不修 — 本机台特殊（理由必须有 capture/main.js 实证）
候选 C: 不修 — 当前差异可接受（不影响资金安全 / UX）
候选 D: 待人工评估 — 信息不足

判断标准：
- 资金安全相关 → 必修
- capture 实证支撑差异 → 可不修
- 仅命名/风格差异 → 可不修
- 缺少实证 → 候选 D"
```

## codex 决策 → 行动

| codex 输出 | 行动 | self-review.md 标记 |
|---|---|---|
| 候选 A（修） | `Agent` 启动 fix worker（按 codex 给的修复路径）→ commit | ✅ 已修 commit:<sha> |
| 候选 B（不修-本机台特殊） | 写 state.unresolved[]（category="self-review-deferred"） | ⏭️ unresolved id:<uuid> |
| 候选 C（不修-可接受） | 同上 | ⏭️ unresolved id:<uuid> |
| 候选 D（待人工） | 写 state.unresolved[]（category="self-review-no-evidence"） | ⚠️ 待人工 |
| codex 超时 / 不可解析 | fallback 写 state.unresolved[]（category="codex-script-failed"） | ⚠️ 待人工（codex 失败） |

## self-review.md 落盘格式（必须写）

```markdown
# <tableId> 自问审查报告

> 自问审查日期：<ISO>
> 触发：L5 完成 + 所有层间 fix 完成 + 进 Phase 5 之前
> 处理原则：每问题调 codex 决策；不停问用户；用户后续审视本文件

## 1. winners 处理逻辑
**结论**：<pass / rewrite / 其他> — `<file:line>`
**跨机台对比**：与 <既有机台> <一致 / 不一致>
**差异理由**：<capture seq=N / main.js line=M>

**自检发现问题**：
- 问题：<...>
- codex 决策 id：<uuid>
- codex 结论：<修 / 不修 / 待人工>
- codex 理由摘要：<...>
- 行动：✅ 已修 commit:<sha> / ⏭️ 写 unresolved id:<uuid> / ⚠️ codex 失败 待人工

## 2. 初始化消息清单
**当前 server 合成**：<list>
**每帧必要性**：<逐项 + main.js grep 证据>
**缺失影响**：<逐项>

**自检发现问题**：同上格式

## 3. 用户非下注操作
**用户操作**：<list> 或 "无用户决策"
**窗口期限制**：<表格>

**自检发现问题**：同上

## 4. 下注窗口期
**开启**：<file:line>
**关闭**：<file:line>
**双重 fail-closed**：✅ / ❌
**跨机台对比**：<差异说明>

**自检发现问题**：同上

## 5+. 用户扩展自问（来自 self-review-checklist.md §5+）
<如有>

## 综合汇总
- 总问题数：N
- ✅ 已修（含 commit sha）：M
- ⏭️ 写 unresolved（codex 判定可延后）：K
- ⚠️ codex 失败待人工：L
- 进 Phase 5 整体循环：✅ 自问处理完成（无论 K/L 数量）

## state.unresolved[] 引用
- [unresolved id:<uuid> from self-review.md §1] — <问题摘要>
- ...
```

## state.json 写入

```jsonc
{
  "phase": 4,
  "status": "done",
  "self_review_path": "tmp/<tableId>/self-review.md",
  "codex_decisions": [
    {"id": "<uuid>", "phase": 4, "label": "self-review-q1",
     "question": "winners 跨机台一致性",
     "options": ["A 改回 pass","B 保留 rewrite","C 待人工"],
     "selected": "A", "rationale": "...", "written_to": "self-review.md §1"}
  ],
  "unresolved": [...] // 已含本 phase 写入项
}
```

进 Phase 5。
