# Phase 3 — AIU DAG 实现概览

> 触发：Phase 2 完成（worktree 已建），自此进入完全无人值守模式。
> 目的：按 5 层 17 AIU DAG 实现机台对接代码。每层完成立即跑层间 codex 审查。
> 阶段：❌ 禁止向用户提问，不确定走 codex-collab。

## AIU = Analysis-Implementation Unit

每个 AIU 一个 agent owner，单 agent 做"分析 + 实现 1 个文件"配对工作。窄上下文（只读自己需要的数据），不读全部 capture/main.js。详见 `phase-3-aiu-LN.md` 各层定义。

## 5 层 DAG

```
Layer 1 (无依赖, 4 并行):
   ENUM            ─┐
   DICT            ─┤
   ERRCODE         ─┤
   CLIENT_FRAME_EFFECTS  ─┘  ← L1.4 客户端帧表现反向分析（L2.1 MODELS 强依赖）
        ↓ 等齐 → 层间 codex 审查 → fix
Layer 2 (依赖 L1, 5 并行):
   MODELS / BETPROTO / RULES / PROCESSOR / INSTANCE
        ↓ 等齐 → 层间 codex 审查 → fix
Layer 3 (依赖 L2, 6 并行):
   UPSTREAM / DOWNSTREAM_BET / SETTLE / HISTORY_DETAIL / HISTORY_REPORT / CHECK_BET
        ↓ 等齐 → 层间 codex 审查 → fix
Layer 4 (依赖 L3, 6 并行):
   PAYOUT / BETSTATS / WINNERS / STATS_API / TABLECONFIG_API / RTP_API
        ↓ 等齐 → 层间 codex 审查 → fix
Layer 5 (依赖全部, 1):
   FACTORY → 跑全量 build → 层间 codex 审查 → fix
```

## 各层详情索引（执行该层时再读）

| Layer | 读 reference | AIU 数 |
|---|---|---|
| L1 | `phase-3-aiu-L1.md` | **4** |
| L2 | `phase-3-aiu-L2.md` | 5 |
| L3 | `phase-3-aiu-L3.md` | **6**（HISTORY_PARSER 拆 DETAIL + REPORT） |
| L4 | `phase-3-aiu-L4.md` | 6 |
| L5 | `phase-3-aiu-L5.md` | 1 |

层间 codex 审查执行：`phase-3-layer-review.md`

## 机台文件布局参照（6 已对接机台共性提炼）

> 每张机台是 `server/game/pp/internal/games/<gametype>/<tableId>/` 下一个独立 Go 包。
> 无固定文件数（职责不绑定文件），但 6 机台收敛出稳定的**核心文件集**，下表标注产出该文件的 AIU。
> 用途：L5 FACTORY 前自检文件是否齐全；新机台对接时按此预估 policy-pr 拆分。

### 核心文件集（6 机台全部或近全部都有）

| 文件 | 产出 AIU | 职责 |
|---|---|---|
| `enum.go` | L1.1 ENUM | TableID / GameType / UpstreamFmt / ResultKey / 事件名常量 / errorCode / betCode 范围 / Redis key |
| `models.go` | L2.1 MODELS | 上游消息 + 下游合成帧的具名 struct（禁匿名 struct / 禁 Sprintf 拼 JSON） |
| `instance.go` | L2.5 INSTANCE | `New()` 装配，嵌 `common.GameInstanceBase`，持 `*Processor` |
| `bet_window.go` | L2.5 INSTANCE | 下注窗口状态机 `MarkBetsOpen/Closed` + `CanBet`（C1 Redis 异常 false） |
| `bet_redis.go` | L2.5 INSTANCE | Redis bet key 读写，fail-closed（C7 / C9） |
| `processor.go` | L2.4 PROCESSOR | `Processor` 类型，嵌 `handlers.EventHandler`，锁 / 窗口 / idle 状态 |
| `bet_limits.go` | L2.3 RULES | 按 bc / 币种取限额（处理 typo 字段）；轮盘族在 gametype 层共享 |
| `upstream_dispatch.go` | L3.1 UPSTREAM | PP→server 单入口：B1 tableId 字节替换 + 事件 switch + verdict |
| `upstream_handlers.go` | L3.1 UPSTREAM | 上游业务 handler（gameresult / HTTP stat 回调 / bet 确认） |
| `upstream_cache.go` | L3.1 UPSTREAM | init 类帧缓存回放（J2：仅 table/dealer + 每局重发的全量快照帧，最小化） |
| `downstream_dispatch.go` | L3.2 DOWNSTREAM_BET | 客户端→server 单入口：`raw==nil` 新连接发 init 序列 / `raw!=nil` 按 root 元素分发 |
| `downstream_bet.go` | L3.2 DOWNSTREAM_BET | 下注业务：解析 lpbet/placeBet、校验、`BetSvc.PlaceBet`、合成确认帧 |
| `xml_util.go` | L3.2 DOWNSTREAM_BET | 仅 XML 机台；ping/pong 等 trivial 帧 attr helper（业务 XML 走 struct，见下方注意） |
| `check_bet.go` | L3.6 CHECK_BET | `CheckBet` override：窗口 + 币种 + 限额 fail-closed |
| `settle.go` | L3.3 SETTLE | 结算核心：`OnGameResult` 写 b_game_rounds / 读 Redis bets / 算派彩 / 写 txn / 调商户 |
| `payout.go` | L4.1 PAYOUT | 纯赔率 / 派彩计算函数（保持纯函数易单测） |
| `history.go` | L3.4 HISTORY_DETAIL | `BuildGameDetail`：PP `cgibin/.../audit/game.jsp` XML 历史详情，registry 注册 |
| `client/reports/<tableId>/index.html` | L3.5 HISTORY_REPORT | **前端自包含报表页**（非 Go）：fetch 通用 `/gameHistory/report` JSON 后渲染，90%+ 还原 PP 真服；一机台一份不共用，无共享 `_assets`。后端报表零 per-machine 代码 |
| `archive_detect.go` | L3.1 UPSTREAM | upstream-log 归档小 helper |

### 按 gametype 的附加文件

| 文件 | 出现于 | 职责 |
|---|---|---|
| `card_history.go` / `description_en.go` | baccarat / dragontiger | 牌面累计 + betCode→人类可读 Description |
| `side_bet_rule.go` / `side_bets_gate.go` | baccarat / dragontiger | 边注启停闸门（按 `ShoeSummary.totalGames` 自算，**不靠上游 disablesidebets** — J2） |
| `betstats_enrich.go` | dragontiger / jackpotwheel | betstats 帧 rewrite 注入我方玩家（L4.2 BETSTATS） |
| `winners_broadcast.go` | 全机台（Model A 统一） | drop 上游 + `CollectOurWinners` 合并我方 + EUR 归一排序 + per-观众币种 `BroadcastToTableByCurrency`（L4.3 WINNERS；一局只播一次、合并失败不广播） |
| `settle_block.go` / `settle_persistence.go` | dragontiger / jackpotwheel / megaroulette | 结算 fail-closed 阻断 + `b_settlement_failed` 持久化 |
| `candy_drop*.go` | sweetbonanza | 玩家决策状态机（选球，须落 `b_game_user_actions` — H7） |
| `models_client.go` / `*_helpers.go` | megaroulette 等 | 纯为满足 policy-pr 500 行拆分（按职责拆，仍属同一 AIU） |

### 注意

- **XML 解析模板看 dragontiger / megaroulette**（`encoding/xml` struct 解析），**不要参考 baccarat / sweetbonanza** 的 `xml_util.go` regex extractAttr —— 后者是已记录的违规（`feedback_struct_only`），新机台勿传播。
- **目录名 ≠ tableId**：megaroulette 目录是 `megaroulettelxuq` 但 `enum.TableID` 是 `1hl65ce1lxuqdrkr`。一律从 `enum.go` 读 TableID，不从目录名推断。
- 注册：机台目录外只改 `factory/instance_factory.go`（switch case + `ImplementedTableIDs`）+ `factory/history_factory.go`（L3.4 `BuildGameDetail` registry 注册）。**L3.5 报表无 Go 注册**（通用 JSON handler + 前端页）；商户报表 URL 由 merchant `/roundreport` 指向 `/reports/<tableId>/index.html`。
- **runtime/history_<gametype>.go 已废弃**：旧 runtime 公共 GameEntryXML + switch by gameType fallback 不再用。新机台 100% 走 registry，`BuildGameDetail` 落机台 internal 包；报表走前端页（`client/reports/<tableId>/`，一机台一份不共用）+ 通用 `reportjson` JSON，**后端无 `BuildGameReport` / `report.go`**（旧 server-render HTML + `reporthtml` 已删除）。
- `lifecycles/` 目录当前为空：`ARCHITECTURE.md` 描述的 `GameLifecycle` 层尚未拆出，6 机台全部把逻辑放机台包内。**按现有机台做**，不要照 ARCHITECTURE.md 新建 `lifecycles/<gametype>.go`。

## 调度伪代码

```
read state.json → 取 base_branch / worktree_path / gametype / tableId

for layer in [L1, L2, L3, L4, L5]:
    # 1. 读对应 phase-3-aiu-LN.md 拿本层 AIU 定义
    aius = read_layer_definition(layer)

    # 2. 同层全部 AIU 并行启动（同一条 Agent tool message 多次 Agent 调用）
    aiu_results = parallel(Agent(prompt=render_aiu_prompt(aiu, state, prev_layer_commits))
                           for aiu in aius)

    # 3. 验收 B5 契约（commit/build/vet/test/policy-pr/关键决策 6 项）
    for r in aiu_results:
        assert b5_passed(r)
        state.aiu_progress[layer].done.append(r.aiu_name)
        state.aiu_progress[layer].commits.append(r.commit_sha)

    layer_head = git_head()

    # 4. 层间 codex 审查（≤2 轮，按 phase-3-layer-review.md）
    for round in [1, 2]:
        review = bash(codex_review.sh -d worktree -l layer-N-round-K -- render_layer_review_prompt(layer))
        if review.no_issues(): break
        # small / medium-必要 finding → fix agent 立即修；其他 → state.unresolved[]
        for f in review.findings:
            if f.severity in ("small", "medium-必要"):
                fix = Agent(prompt=render_fix_prompt(f))
                assert b5_passed(fix)
            else:
                state.unresolved.append(f)
    else:
        # 2 轮仍有 finding → unresolved + 进下层
        state.unresolved += review.findings

    update_state(phase=3, current_layer=layer, layer_head=layer_head)

# 全 5 层完成 → 进 Phase 4 铁律核对
```

## 失败回滚策略

| 情况 | 处理 |
|---|---|
| 单 AIU 失败首次 | `git reset --hard` 该 AIU 改动 + 重启该 AIU（不影响同层其他 AIU 已 commit） |
| 同 AIU 失败 ≥ 2 次 | 调 `codex_discuss.sh` ≤ 3 轮诊断根因（见 codex-collab.md S1） |
| 同层多 AIU 失败 | 调 `codex_decide.sh` 一次性根因（可能上游 AIU 字段不全，需补） |
| L1 ENUM 失败 = block 整层 | 必须先修，否则下游全部受阻；写 unresolved[] 后绝不停问用户 |

## codex-collab 三模式触发点（详见 `codex-collab.md`）

| 触发 | 模式 | reference 节 |
|---|---|---|
| 每层完成审查（≤ 2 轮） | review | layer-review.md |
| AIU 启动前路径选择（复用/抽 helper） | decide | codex-collab.md D1 |
| L2 MODELS 字段类型歧义 | decide | codex-collab.md D2 |
| AIU 卡 ≥ 10 min / 失败 ≥ 2 次 | discuss | codex-collab.md S1 |

## state.json 写入

每层完成后更新：

```jsonc
{
  "phase": 3,
  "current_layer": "L2",
  "aiu_progress": {
    "L1": {"done": ["ENUM","DICT","ERRCODE"], "commits": ["sha1","sha2","sha3"], "review_rounds": 1},
    "L2": {"done": [], "commits": [], "review_rounds": 0},
    ...
  },
  "last_updated": "ISO"
}
```

全 5 层完成后 `phase=3, status="done"`，进 Phase 4。
