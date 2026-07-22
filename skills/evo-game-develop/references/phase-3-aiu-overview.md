# Phase 3 — AIU DAG 实现概览

> 触发：Phase 2 完成（worktree 已建），自此进入完全无人值守模式。
> 目的：按 5 层 20 AIU DAG 建一个新游戏族 `evocore` 包 + 工厂注册 + 报表页。每层完成立即跑层间 codex 审查。
> 阶段：❌ 禁止向用户提问，不确定走 codex-collab。
>
> ⚠️ **先读 `references/evo-platform-primer.md`**：复用边界 + per-user 模式 + roulettecore 18 文件模板，本 phase 的每个 AIU 都照它落地。

## AIU = Analysis-Implementation Unit

每个 AIU 一个 agent owner，单 agent 做"分析 + 实现 1 组职责文件"配对工作。窄上下文（只读自己需要的 capture/bundle 切片 + 上游层产物），不读全部数据。详见 `phase-3-aiu-LN.md`。

## 复用分支（Phase 1 判到 ①②③ 档时走这条，跳过完整 DAG；四档判据见 SKILL.md / known-pitfalls I11）

**① 纯配置复刻**（同族同赔率，又一张既有族桌）→ evocore **一行不写**，收敛为 3 个 AIU + 一次差异核对：

```
REUSE-1 FACTORY     instance_factory case + buildXxxInstance（复用既有 Processor）+ b_tables/currency DB 模板
REUSE-2 REPORT_PAGE client/reports/<裸 tableId>/index.html（对照本桌 roundDetail）
REUSE-3 DIFF_AUDIT  本桌 vs 既有桌差异核对：limits（config 限红字段）/ betCode 全集 / per-user 字段 / 视频参数
        ↓ 层间 codex 审查（一轮）→ Phase 4
```

**② nil-gated 钩子**（同族同协议、仅赔付数学有增量差异）→ 在 ① 基础上加 1 个 AIU：

```
REUSE-0 PAYOUT_HOOK 既有 core 加可空钩子（标准桌恒 nil→原路径逐字节不变）+ 本桌数学 + 双向单测
                    🔴 只改赔付数字，不碰扣款/结算时序/pending/reconcile/Redis 注单
                    验收顺序：先验老桌行为未变，再验新桌赔付（范例 roulettecore/lightning_hook.go）
```

**③ 参数化共享兄弟族 core**（协议逐字段同构、数学层不同）→ 不建 core，收敛为：

```
SHARE-1 MATH        games/<新族>/{odds.go,bet_limits.go}（betCode 白名单/标签/结果解析/赔付/限额，各族独立裸值）
SHARE-2 GAMEDEF     兄弟族 core 的 gamedef.go 加 <新族>Def() 构造函数（字段全必填，禁手工构造）
SHARE-3 FACTORY     + REPORT_PAGE + DIFF_AUDIT（同上）
        ↓ 🔴 回归两族全部测试（改共享层的反向 oracle：还原改动后耐久测试变红=确属共享层职责）
```

**④ 全新协议形态** → 走下面的完整 5 层 DAG。

## 5 层 DAG（新游戏族，本 skill 主攻）

```
Layer 1 (无依赖, 4 并行):
   ENUM                 ─┐ type/状态机(枚举 or 离散事件,从 capture 判)/action/errorCode/Redis key 常量
   DICT                 ─┤ 协议字典：§2A 分类(A / A2 communal 演出 / B per-user / handle / C) + betCode 全集 + 状态机序列(+kind)
   PAYOUT_MODEL         ─┤ betCode 全集 + 赔付参数（roulette 号码集+赔率 bundle 逆向复用 odds.go；game show segment→倍率每局上游下发；从 capture+roundDetail 反推）
   CLIENT_FRAME_EFFECTS ─┘ 客户端帧表现反向分析（哪帧设哪 state / 缺失影响）→ L2 MODELS 强依赖
        ↓ 等齐 → 层间 codex 审查 → fix
Layer 2 (依赖 L1, 5 并行):
   MODELS / PROCESSOR / RULES(bet_limits) / BET_REDIS / BET_WINDOW
        ↓ 等齐 → 层间 codex 审查 → fix
Layer 3 (依赖 L2, 5 并行):
   UPSTREAM(dispatch+handlers,离散事件/枚举) / DOWNSTREAM(dispatch+bet+init+settle,betAction 或 placeChips) / PER_USER(betstate,锚帧从 capture) / SETTLE / CHECK_BET
        ↓ 等齐 → 层间 codex 审查 → fix
Layer 4 (依赖 L3, 5-6 并行):
   PAYOUT / HISTORY_RECENT(recent_results/spinHistory+reconcile) / HISTORY_DETAIL / REPORT_PAGE / CURRENCY_CONFIG / [BETSTATS — 仅 capture 有高频 <gt>.bettingStats 等统计帧的族(如 game show)建：直转或 enrich 我方聚合计数；roulette 无此帧跳过]
        ↓ 等齐 → 层间 codex 审查 → fix
Layer 5 (依赖全部, 1):
   FACTORY(instance_factory case + buildXxxInstance + DB 模板) → 全量 build → 层间 codex 审查 → fix
```

## 各层详情索引（执行该层时再读）

| Layer | 读 reference | AIU 数 | 核心产物 |
|---|---|---|---|
| L1 | `phase-3-aiu-L1.md` | 4 | enum.go / 字典 md / odds.go(赔付参数) / client_frame_effects.md |
| L2 | `phase-3-aiu-L2.md` | 5 | models.go / processor.go / bet_limits.go / bet_redis.go / bet_window.go |
| L3 | `phase-3-aiu-L3.md` | 5 | upstream_*.go / downstream_*.go / **per_user_betstate.go** / settle.go / check_bet.go |
| L4 | `phase-3-aiu-L4.md` | 5-6 | payout.go / recent_results+reconcile.go / **history detail render（renders/<gt>.go 局面区 1:1）** / 报表页 / currency config / [BETSTATS 条件] |
| L5 | `phase-3-aiu-L5.md` | 1 | factory 注册 + DB 模板 + 全量 build |

层间 codex 审查执行：`phase-3-layer-review.md`

## 新族包文件布局参照（roulettecore 18 文件提炼）

> 新族 = `server/game/evo/internal/games/<gametype>/<gametype>core/` 一个独立 Go 包；赔率/限额在父目录 `games/<gametype>/{odds.go,bet_limits.go}`。
> 逐文件职责见 `evo-platform-primer.md §4`。下表标注产出该文件的 AIU。

| 文件 | 产出 AIU | 必改点（vs roulette 模板） |
|---|---|---|
| `enum.go` | L1 ENUM | 新族 type 前缀 / 状态机状态 / errorCode |
| `models.go` | L2 MODELS | 按 capture 帧建 ArgsXxx struct（禁 map） |
| `processor.go` | L2 PROCESSOR | 嵌同骨架，换业务状态字段 |
| `bet_limits.go`（父目录） | L2 RULES | betType/币种限额 |
| `bet_redis.go` | L2 BET_REDIS | 照抄机制，换 Redis key 族 |
| `bet_window.go` | L2 BET_WINDOW | 照抄机制，换触发态 |
| `upstream_dispatch.go`+`upstream_handlers.go` | L3 UPSTREAM | 换状态机锚（枚举/离散事件）+ §2A 四类分类 switch（含 A2 演出帧） |
| `downstream_dispatch.go`+`downstream_bet.go`+`downstream_init.go`+`downstream_settle.go`+`bet_actions.go` | L3 DOWNSTREAM | 换下注协议（betAction 增量 / placeChips 快照）+ init 帧集（含 restore） |
| `per_user_betstate.go` | L3 PER_USER | 照抄 strip/personalize/snapshot 机制，换**锚帧名**（roulette `tableState.betState` / game show `<gt>.bets.state`）+ 字段名（EVO 核心资产） |
| `settle.go` | L3 SETTLE | 换结算锚解析（winNumber / gameResolved 倍率）+ 派彩；OnRoundSettled 必调；留 gameCancelled |
| `check_bet.go` | L3 CHECK_BET | 换限额规则 fail-closed |
| `payout.go` | L4 PAYOUT | 换赔付算法（号码 odds / segment 倍率 / 牌型，从 roundDetail 反推；纯函数易单测） |
| `recent_results.go`+`reconcile.go` | L4 HISTORY_RECENT | 换历史帧名（recentResults/spinHistory）+ 格式 + 孤儿局恢复 |
| `odds.go`（父目录） | L1 PAYOUT_MODEL | 赔付参数（roulette 号码赔率复用；game show 倍率制无固定表；betCode 双命名空间映射） |
| `[betstats_enrich.go]`（条件） | L4 BETSTATS | 仅 capture 有 `<gt>.bettingStats` 等统计帧的族建；直转或合并我方聚合计数 |
| `client/reports/<裸 tableId>/index.html` | L4 REPORT_PAGE | 一桌一份自包含，对照 roundDetail json+html |
| `factory/instance_factory.go`（包外，唯一改动点） | L5 FACTORY | switch case + implementedTables + buildXxxInstance |

### 注意（EVO 特有）
- 🔴 **roulette 模板是范例非通用，L1 先定 6 轴**：本 phase 的"vs roulette 模板"列默认 roulette shape；新族 L1（ENUM/DICT/PAYOUT_MODEL）必须先从 capture 实证 ① 状态机 kind（`tableState.state` 枚举 vs 离散事件帧，IceFishing 7 帧）② 下注模型（betAction 增量+UNDO 栈 vs placeChips 全量快照）③ betCode 形态 + roundDetail 前缀映射 ④ 赔付模型（号码 odds / segment 倍率）⑤ betstats 是否存在 ⑥ A2 演出帧 / restore 是否存在，写入 state.json，后续层据此落地。**禁止假设 roulette 形态**（详见 SKILL.md「新游戏族协议 shape 必须从 capture 自推导」）。
- **包结构 ≠ PP**：PP 一机台一包（`games/<gt>/<tableId>/`）；EVO 一族一 core（`games/<gt>/<gt>core/`），多桌共用 core，桌差异靠 `Variant` + DB limits 注入。**新桌不新建包，只加 factory case**。
- **per_user_betstate.go 是必产文件**（PP 无对应）——新族最易漏、最易错（快照时序、裸 tableId、余额来源），单列一个 L3 AIU 重点保障。
- **强类型铁律**：所有协议帧 struct + `json.Marshal`/`Unmarshal`，**禁 `map[string]interface{}` 跨边界**（models.go）。
- **包外唯一改动**：`factory/instance_factory.go`（L5）+ DB 行 + 报表页。runtime/gateway/video/lobby/容灾/资金全复用，**不碰**。
- **history detail 是 render HTML，不是 PP 的逐字段结构化**：EVO 玩家"我的历史"端点走 `gateway/history_api.go`（通用：token→玩家→`vendor_type='evo'`→时区分组），但**详情局面区是 EVO 服务端 SSR 的一段 HTML**（`gameDetail.txt .data.render`）。新族**必产一份 1:1 render**（`gateway/renders/<gt>.go` + `assets/<gt>/`，逐字节对齐真实），不是"通用接口拼字段、不够再补"（那是 PP cgibin XML 思路）。结构化结算体 `roundDetail/<rid>.json` 仅报表页（L4.4）逐字段对账用。详见 L4.3 + `references/phase-3-game-record-render.md`。

## 调度伪代码

```
read state.json → 取 base_branch / worktree_path / gametype / evo_table_id / table_code / reuse_core

if reuse_core != "none":
    run [REUSE-1 FACTORY, REUSE-2 REPORT_PAGE, REUSE-3 DIFF_AUDIT] → 一轮层间审查 → Phase 4
    exit

for layer in [L1, L2, L3, L4, L5]:
    aius = read_layer_definition(layer)                       # 读 phase-3-aiu-LN.md
    aiu_results = parallel(Agent(render_aiu_prompt(aiu, state, prev_layer_commits)) for aiu in aius)
    for r in aiu_results:                                      # 验收 B5 契约 6 项
        assert b5_passed(r); state.aiu_progress[layer].done.append(r.aiu_name)
        state.aiu_progress[layer].commits.append(r.commit_sha)
    layer_head = git_head()
    for round in [1, 2]:                                       # 层间 codex 审查 ≤2 轮
        review = bash(codex_review.sh -d worktree -l layer-N-round-K -- render_layer_review_prompt(layer))
        if review.no_issues(): break
        for f in review.findings:
            if f.severity in ("small","medium-必要"): Agent(render_fix_prompt(f)); assert b5_passed(fix)
            else: state.unresolved.append(f)
    else: state.unresolved += review.findings
    update_state(phase=3, current_layer=layer, layer_head=layer_head)
# 全 5 层完成 → Phase 4
```

## 失败回滚策略

| 情况 | 处理 |
|---|---|
| 单 AIU 失败首次 | `git reset --hard` 该 AIU 改动 + 重启该 AIU（不影响同层其他已 commit） |
| 同 AIU 失败 ≥ 2 次 | `codex_discuss.sh` ≤ 3 轮诊断根因（codex-collab.md S1） |
| 同层多 AIU 失败 | `codex_decide.sh` 一次性根因（可能上游 AIU 字段不全需补） |
| L1 ENUM / L3 PER_USER 失败 = block 下游 | 必须先修；写 unresolved[] 后绝不停问用户 |

## codex-collab 三模式触发点（详见 `codex-collab.md`）

| 触发 | 模式 | reference 节 |
|---|---|---|
| 每层完成审查（≤2 轮） | review | layer-review.md |
| AIU 启动前路径选择（复用 roulettecore 机制 / 抽 helper / 独立写） | decide | codex-collab.md D1 |
| L2 MODELS 字段类型歧义（capture vs bundle 不一致） | decide | codex-collab.md D2 |
| L3 PER_USER 改写时序/字段不确定 | decide | codex-collab.md D2' |
| AIU 卡 ≥10min / 失败 ≥2 次 | discuss | codex-collab.md S1 |

## state.json 写入

```jsonc
{
  "phase": 3, "current_layer": "L3",
  "aiu_progress": {
    "L1": {"done":["ENUM","DICT","ODDS_BETCODE","CLIENT_FRAME_EFFECTS"], "commits":[...], "review_rounds":1},
    "L2": {"done":[], "commits":[], "review_rounds":0}
  },
  "last_updated": "ISO"
}
```

全 5 层完成后 `phase=3, status="done"`，进 Phase 4。
