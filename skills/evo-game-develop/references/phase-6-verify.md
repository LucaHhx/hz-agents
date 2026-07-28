# Phase 6 — verify 全量验收（AI 自检指南）

> 触发：Phase 5 整体 codex review fix 完成。
> 验收清单（5 确定性 + V6/V7 语义判断 + **V9 per-user 构造闸门（EVO 核心）** + V10-V12 复盘闸门 + V13 DB/live-launch + V14 赢钱反推 + **V14b 公共帧合并我方(winnersList/bettingStats)** + V15 历史隔离/进制 + **V16 资金 /bet→/result wiring**）。
> 阶段：❌ 禁止向用户提问；失败首次 Claude 自修；≥2 次走 codex_decide 根因分类。

## AI 执行步骤

```
1. cd <worktree>
2. 按顺序跑 16 项验收
3. 任一失败：首次 Claude 自修 + 重跑；≥2 次 codex_decide 根因（D5）；不收敛 codex_discuss ≤2 轮（S3）
4. 全 PASS → 进 Phase 7
5. 全程不停问用户
```

> 路径约定：`CORE=<worktree>/server/game/evo/internal/games/<gametype>/<gametype>core`；`CAP=tmp-evo/<dir>`；tableId 用 `b_tables.code`（evo+裸id）。

### V1-V5 确定性闸门

```bash
cd <worktree>/server && go build ./...                                    # V1 退出 0
cd <worktree>/server && go vet ./...                                      # V2 无新增 warning
cd <worktree>/server && go test -race -count=3 ./game/evo/internal/games/<gametype>/...  # V3 3 次全 PASS 无 race
cd <worktree>/server && go test -cover ./game/evo/internal/games/<gametype>/...          # V4 ≥ 25%
cd <worktree> && git diff --name-only --diff-filter=ACMR <base_branch>...HEAD | node scripts/ci/policy-pr.mjs --stdin  # V5 ≤500 行/≤3 层
```

### V6. 双向协议矩阵（语义判断）

**目的**：客户端→server 帧（capture send）vs server struct；server→客户端帧 vs 客户端 bundle reducer。

```bash
# A. 客户端→server type 全集（payload 字符串→fromjson）
jq -rs '.[]|select(.dir=="send")|.payload|fromjson|.type' "$CAP"/message.txt | sort -u
#   实证：placeChips/fetchBalance/metrics.ping/settings.read/settings.update（无 betAction——下注帧名按本族 DICT.downstream_actions）
# B. server 端能解析的 type（downstream_dispatch switch，case 名从 L1 DICT 取本族）
grep -nE "case .*Evt|\"<gt>\.(placeChips|betAction|undo|undoAll)\"|\"fetchBalance\"" "$CORE"/downstream_dispatch.go
# C. server→客户端主动发的帧 → bundle reducer。先反查本族 reducer 全集，别用硬编码 roulette 词表
grep -roE '"<gt>\.[a-zA-Z]+"' "$CAP"/clientResources/frontend/evo/mini/js/ | sort -u
grep -roE '"(subscribe|balanceUpdated|betValidationError)"' "$CAP"/clientResources/frontend/evo/mini/js/ | sort -u
```
**PASS**：每客户端发的 type 在 server 有处理；每 server 主动发的本族帧在 bundle 有 reducer。
**FAIL**：任一行 ❌ → 修（如 server 漏识别某下注帧 → 走 default 默默 ack 不落库）。

### V7a. history JSON 真 fixture 单测 + render 文案 key 化

```bash
head -1 "$CAP"/gameDetail.txt > /tmp/sample.json
grep -rE 'gameDetail.txt|TestBuildGameDetail|os.Open.*gameDetail' "$CORE"/*_test.go
cd <worktree>/server && go test -v -run "TestBuildGameDetail|TestHistory" ./game/evo/internal/games/<gametype>/...

# render 文案 key 化（H7）：漏网的英文会直接拼进 HTML
R=<worktree>/server/game/evo/internal/gateway/renders
grep -nE '"[A-Z][a-z]+( [A-Za-z0-9]+)*"' "$R"/<gametype>.go | grep -vE 'tr\(|trf\(|\.svg|\.webp|\.png|ssr_|data-|class='   # 命中即人工核对是否文案漏 key 化
cd <worktree>/server && go test -v -run "TestLoc|Localized|Keys" ./game/evo/internal/gateway/renders/
```
**PASS**：≥1 个用真 `gameDetail.txt` JSON 的测试；断言关键字段非空；缺数据填 "0" 不空串（I8）；投注类型/开奖结果分离（H3）；🔴 **render 文案全走 `tr(key,英文)`，key 属本族串包命名空间（表驱动测试核对官方 en-US 值 == 我方英文回退），且 `zh-Hans` 渲染出中文 + 无英文残留 + 开奖号/金额不变**。
**FAIL**：英文字面量直接拼进 HTML → 该族历史详情成为客户端里唯一的英文孤岛；只跑 en-US → key 错/取包失败/缺 X-Origin-Secret 三种故障全部不可见（同 G6「USD 一路绿灯」）。

### V7b. 报表前端页视觉还原（≥ 90%）

```bash
R=<worktree>/server/game/evo/client/reports
ls "$CAP"/roundDetail/*.html "$CAP"/roundDetail/*.json     # 还原基线（EVO 多 json，字段直接对照）
# ⚠️ EVO 是「stub + 共享 renderer」架构（不是 PP 的一桌一份自包含）
wc -l "$R"/<裸 evo_table_id>/index.html                     # 应 ≈14 行引导 stub
grep -n "<裸 evo_table_id>" "$R"/_assets/report.js          # RENDERER_BY_TABLE 必须有本桌映射，否则报表空白
ls "$R"/_assets/renderers/                                  # 本族 renderer（同协议桌应复用已有，别新建）
node --check "$R"/_assets/renderers/<gametype>.js
```
**PASS**：stub 已建（≈14 行、引 `/reports/_assets/report.js`）+ `RENDERER_BY_TABLE` 有本桌映射 + renderer 复用或新建合理；渲染关键骨架节点；**roulette 族** Game Result `<svg>`（game show 按 roundDetail 的 segment/倍率盘/bonus 元素）；字段对齐（金额/Description/Payoff/Status/EUR 缺兑率空不 "0"）；**字段值对照 `roundDetail/<rid>.json .data.data`**；视觉 ≥ 90%。
🔴 **倍率口径单独核**：净倍率用 `(payout-stake)/stake`（别用 `payout/betAmount`，那含本金 → 15x 显成 16x）；per-player bonus 取**本人 choice** 对应盘面值（别读 round 级 `multiplier`/`roundMult`，那是整盘候选最大值）。

### V8. 消息时序对照（capture vs server）

```bash
# payload 是字符串→fromjson；ws 帧无 payload 用 .event 兜底
jq -rs '.[] | "\(.ts) \(.dir) \(if .payload then (.payload|fromjson|.type) else .event end)"' "$CAP"/message.txt > /tmp/evo_seq.txt
# 锚帧从 L1 DICT.state_machine 取本族开窗/关窗/结算事件（roulette: BETS_OPEN/CLOSED/GAME_RESOLVED；game show: <gt>.betsOpen/betsClosed/gameResolved）
grep -E '<开窗锚>|<关窗锚>|<结算锚>|<下注帧>|balanceUpdated' /tmp/evo_seq.txt | head -50
```
**PASS（dt 容忍 ±200ms）**：
- 🔴 受理回执（roulette `betsAccepted` / game show `<gt>.bets` status→Accepted）在 **关窗锚之后**（不在下注期定格；客户端只能下一个位置=时序错）
- `balanceUpdated`（商户余额）init 必发、~6s 内到
- 个人派彩在结算锚之后
- per-user 注态帧在每态/每帧推送（含结算锚带本人注）

**FAIL**：受理在下注期逐发 → 改关窗后；balanceUpdated 漏 → init 加；派彩早于结算 → 修 flush 时序。

### V9. ⭐ per-user 数据构造闸门（EVO 核心，PP 无此项）

**目的**：EVO 一上游广播多下游，per-user 改写错=资金/UX 事故（串账/丢注/余额错）。静态 + 单测双查。

```bash
# 1. tableState 广播前必经 strip；per-user 下发必经 personalize
grep -nE 'stripTableStateBetState|broadcastTableStatePerUser' "$CORE"/upstream_handlers.go
grep -nE 'personalizeTableState' "$CORE"/per_user_betstate.go "$CORE"/downstream_init.go
# 1. per-user 注态帧广播前必经 strip、下发必经 personalize（函数名按本族：roulette stripTableStateBetState / game show stripBetsState 等）
grep -nE 'strip.*State|broadcast.*PerUser' "$CORE"/upstream_handlers.go "$CORE"/per_user_betstate.go
grep -nE 'personalize' "$CORE"/per_user_betstate.go "$CORE"/downstream_init.go
# 2. 🔴 快照在清 Redis 之前：userBetsSnapshot 调用早于 settle 清注
grep -nE 'userBetsSnapshot|OnGameResult|clearBets|DeleteBets' "$CORE"/upstream_handlers.go   # 人工确认 snapshot 在 settle 之前
# 3. 🔴 tableId 双口径：桌态/派彩帧用 PPTableID（裸 id）；balanceUpdated 反过来用我方 code（须与 /config.table_id 同源）
grep -rnE 'TableId:|"tableId"' "$CORE"/*.go | grep -vE 'PPTableID|test'   # 命中处人工核对是否应为 PPTableID
# 4. 🔴 余额来源：balanceUpdated 用商户余额，上游渠道 drop（无 playerId，按连接寻址）
grep -nE 'balanceUpdated|PlayerBalance|merchantBalance' "$CORE"/*.go
grep -nE 'BalanceUpdated.*DispDrop|balanceUpdated.*Drop' "$CORE"/upstream_dispatch.go
# 5. 单测：strip 后无私有字段 + personalize 回填 + snapshot-before-clear
cd <worktree>/server && go test -v -run "TestPerUser|TestStrip|TestPersonalize|TestSnapshot" ./game/evo/internal/games/<gametype>/...
```
**PASS**：① strip 剥净本族个人注态私有字段（roulette bets/lastGameChips/history；game show chips/acceptedBets/history）；② 按 userId 回填；③ snapshot 在 settle 清注前；④ 桌态/派彩 per-user 下发帧 tableId=PPTableID（裸 id），**但 balanceUpdated=我方 code**（与 /config.table_id 同源）；⑤ balanceUpdated=商户余额、上游渠道 drop、**无 playerId 按连接寻址**；⑥ 单测覆盖 ①②③。
**FAIL**：漏 strip → 全桌串注；snapshot 时序颠倒 → 丢本局注；桌态帧填 code → 客户端判「不属本桌」；**balanceUpdated 填裸 id → 客户端判余额未收到**（余额帧要 code，与 /config.table_id 同源）；透传上游余额 → 串账。

### V10. balanceUpdated 商户余额 + 6s init 闸门

```bash
grep -nE 'sendInitSequence|init.*balanceUpdated|merchantBalance' "$CORE"/downstream_init.go
```
**PASS**：init 序列含 balanceUpdated（商户余额）；缺余额源 → LOW BALANCE / 6s 重连。
**FAIL**：init 漏 balanceUpdated → 加；用上游余额 → 改 PlayerBalance。

### V11. betValidationError code 客户端可识别

```bash
JS="$CAP"/clientResources/frontend/evo/mini/js
grep -roE 'case ?"?[0-9A-Z_]{3,}"?' "$JS" | grep -oE '[0-9A-Z_]{3,}' | sort -u | head -40   # 客户端识别集
grep -rnoE 'ErrCode[A-Za-z]+|"[0-9A-Z_]{3,}"' "$CORE"/enum.go                                 # server 拒单 code
```
**PASS**：server 每拒单 code ∈ 客户端识别集；普通拒单 extendedErrorCode 留空（仅会话失效填）；拒单后无追发错误命令。

### V12. reconcile 孤儿局 + recentResults 缓存 + root-key dealer（EVO 自愈，替代 PP switch/seat）

```bash
# EVO 无 PP 的 switch/seat 帧（容灾在 runtime/runner+lobby_failover 基础设施层）。evocore 查自愈：
grep -nE 'reconcileFrom|reconcileOnNewRound' "$CORE"/reconcile.go      # 漏结算锚用走势帧(recentResults/spinHistory)补结算
grep -nE 'requireAccepted|hasSuccessfulBetDebit' "$CORE"/reconcile.go               # 补结算 fail-closed
grep -nE 'cache|Cache' "$CORE"/recent_results.go     # 走势全量快照帧(recentResults/spinHistory)缓存回放
grep -nE 'Dealer.*cache|EvtDealer.*Broadcast|decodeRootKeyFrame' "$CORE"/upstream_dispatch.go  # root-key dealer 缓存广播不丢弃
```
**PASS**：reconcile 漏局补结算且 fail-closed（不给没扣款的注派彩）；recentResults 缓存回放；root-key dealer 帧缓存广播（不当坏帧丢弃）。

### V13. DB-config 前置 + per-currency + live-launch checklist（清单交付）

AI 填实进经验文档部署节：
- **DB 前置**：`b_tables`（vendor_type='evo'、code='evo'+裸id、original_id=裸id、game_type、enabled=1、failover_group_id）；`b_table_currency_configs` 各币种限红 + **currencyMult**；`b_currency_rates` 有启用 EUR 行 + symbol
- **ID 双字段对齐**：`b_tables.code`(索引) vs `original_id`(协议帧)；factory implementedTables 键=**original_id**、switch=**original_id**（两者同口径裸 id，键误用 code → 后台弹窗全显「未实现」）
- **per-currency 进制**：每币种 currencyMult 正确（IDR 20000 / BRL 5 / INR 100…）
- 🔴 **非 USD 账号实测下注+派彩**（G5/G6，`go test` 与 codex 都抓不到）：拿一个 IDR 或 INR 账号进桌，下一笔**接近该币种上限**的注（如 IDR 直注 20000）确认受理、中奖确认派彩未被截顶。USD 账号必然通过（mult=1），**只跑 USD 等于没测**。历史：roulette 的 `CheckBet` 直读 USD 机台默认限额，IDR 玩家 13 笔 betAction 全回 `1048` 静默 wipe chip，USD 测试一路绿灯，直到用户抓 HAR 才暴露
- **post-merge live-launch 必查**（test/codex 抓不到）：`/config` wsHost 指我方 + 视频参数 + 限红非空；大厅 allowlist 自动订阅新桌；game ws 连我方进桌；descrambler/视频可放后置；session mint（Akamai tls-client）

**PASS**：经验文档填实四组清单 + 非 USD 账号实测通过。

### V14. 赢钱反推验证（capture 局对照算钱）

**目的**：同样下注 + 同样开奖，我方 payout 算出的赢钱必须与上游一致。**EVO 优势**：`roundDetail/<rid>.json` 是结构化 outcomes（participants/bets/result），比 PP html 更好对。

```bash
ls "$CAP"/roundDetail/*.json | head -3
# 对每个有 .json 的 round：a. 解析 .data.data.participants[].bets[]{code,stake,payout} + result;
#   b. message.txt 取该局结算锚（roulette winNumber / game show gameResolved.{result,<seg>Multipliers,totalMultiplier}）;
#   c. 用 payout 函数算 expected（号码 odds / segment 倍率，按本族）; d. 对比 roundDetail payout，差异 > 0.01（进制单位）= FAIL
#   ⚠️ betCode 双命名空间：roundDetail 用 IF_ 前缀、下注帧裸名，反推前先映射
cd <worktree>/server && go test -v -run "TestV14PayoutReverse" ./game/evo/internal/games/<gametype>/...
```
**PASS**：≥ 3 个真实 round 反推一致（≤ 0.01）；覆盖 直注命中 / 多注 / 全输；fixture 用 roundDetail json + message.txt 真数据（不构造）；**currencyMult 进制正确**。
**FAIL**：单注差异→赔率/号码集错；全局同系数→per-bet cap 顺序错；进制错→currencyMult 漏乘。

### V14b. 公共帧合并我方数据（winnersList / bettingStats，名为公共实须 enrich）

**目的**：上游 winnersList/bettingStats 只反映上游侧，裸直转会漏我方 seamless 玩家（中奖者不上榜 / 在桌人数偏少）。IceFishing000001 实测漏合并被用户指证（本人净中 10000 该排第二却不见自己）。

```bash
# 1. winnersList 不得仅落 DispBroadcast 默认分支（=漏合并）；须有拦截合并入口
grep -nE 'winnersList|CollectOurWinners|mergeWinners' "$CORE"/upstream_*.go "$CORE"/winners_broadcast.go 2>/dev/null
# 2. bettingStats 同理（若本族有该帧且需计入我方聚合计数）
grep -nE 'bettingStats' "$CORE"/*.go
```
**PASS**：① winnersList 走拦截合并（`CollectOurWinners` → 追加本局我方中奖者 → 按 payout 降序 → 截断回上游原 len → **替换**原帧 1 进 1 出只广播一次）；② 合并失败（DB/查询/解码错）整局不广播、零中奖原样透传；③ 聚合字段 winnersCount/bettorsCount/totalAmount 透传上游原值不动；④ 单测用真实帧断言「本人中奖额插入正确排名」。
**FAIL**：winnersList 仅落 DispBroadcast 默认分支=漏合并（我方中奖者永不上榜）；改了 winnersCount/totalAmount=露馅；除替换原帧外再 Broadcast 一帧=重复广播。

### V15. history API per-player 隔离 + currencyMult 进制端到端

```bash
# 1. history 按 vendor_type='evo' filter + token→玩家隔离（通用 gateway/history_api.go，确认覆盖新桌）
grep -nE "vendor_type.*evo|evo.*filter" <worktree>/server/game/evo/internal/gateway/history_api.go
# 2. /config 限红按 currencyMult 换算（起 worktree game-evo，curl /config）
curl -s 'http://127.0.0.1:9691/config?table_id=<b_tables.code>' -H 'Cookie: EVOSESSIONID=<sid>' -o /tmp/cfg.json
grep -oE '"(currencyMult|table_bet_min_limit|table_bet_max_limit)"[: ]*[0-9]+' /tmp/cfg.json
```
**PASS**：history 仅返本玩家、仅 evo 局（不窜 PP）；`/config` 限红 + currencyMult 正确（本地无会话则 mock，记 unresolved 留线上验）。

### V16. 资金安全：/result 必先有 /bet 扣款（wiring 静态审查）

```bash
grep -nE 'handlers\.SubmitBets\([^)]*OnMerchantBetResult' "$CORE"/upstream_handlers.go || echo "❌ onBetsClosed 未调 SubmitBets(OnMerchantBetResult)"
grep -nE 'MarkBetAccepted' "$CORE"/downstream_bet.go && echo "❌ downstream 不得 MarkBetAccepted" || echo "OK"
grep -nE 'func .*OnMerchantBetResult' "$CORE"/upstream_handlers.go && grep -nE 'MarkBetAccepted|echoBetsAfterMerchantAck' "$CORE"/upstream_handlers.go || echo "❌ 缺 accepted 标记/echo"
grep -nE 'OnRoundSettled' "$CORE"/settle.go || echo "❌ settle 成功未调 OnRoundSettled"
```
**PASS**：onBetsClosed `go handlers.SubmitBets(...,OnMerchantBetResult)`；downstream 无 MarkBetAccepted；OnMerchantBetResult accepted 分支 MarkBetAccepted+echo；settle 成功 `OnRoundSettled` 必调；`/result` 前 `hasSuccessfulBetDebit` 闸门生效（运行时兜底，但 wiring 必须对）。
**FAIL**：缺 SubmitBets → 无扣款派彩（凭空给钱）；缺 OnRoundSettled → 下局误标 cancelled+重复退款。

### V17. 撤注快照栈 + 交互式 bonus（仅 game show；有选择帧才查；known-pitfalls K）

> 触发条件：capture/bundle 有 `<gt>.undo`/`undoAll`（或 `<gt>.bet` Undo action）→ 查撤注栈；有 `chooseColor`/`setChoice`/`playerChoiceMade`/`colorChoice` 选择帧 → 查交互 bonus 全套。无则跳过。

```bash
# 撤注快照栈（全量快照族也须有：撤注是独立帧、不重发 placeChips）
grep -lE 'pushBetSnapshot|popBetSnapshot|bet_undo' "$CORE"/*.go || echo "⚠️ 有 undo 帧但无快照栈 → 撤注无效+残留注超扣(K6)"
# 交互 bonus：参与时序(betsClosed 发 Accepted) / 选择窗口锁 / auto 随机 / 盘缺失 fail-closed
grep -lE 'broadcastBetsClosedPerUser|betsClosed.*Accepted' "$CORE"/*.go || echo "⚠️ 交互 bonus 须 betsClosed 即发 Accepted，否则参与 UI 不显示(K1)"
grep -lE 'closeBonusChoice|bonusChoiceClosed' "$CORE"/*.go || echo "⚠️ 缺选择窗口锁 → 玩家看盘后改选超付(K2)"
grep -nE 'minByValue.*未选|取最小' "$CORE"/*.go && echo "⚠️ 未选取最小不公，应 auto 随机匹配 EVO(K3)"
grep -lE 'bonusBoardReady|abortOnBonusBoardMissing' "$CORE"/*.go || echo "⚠️ 缺倍率盘缺失 fail-closed → 中奖误判 0(K5)"
```
**PASS**：撤注有 `bet_undo.go` 快照栈（push 受理/pop undo/清栈 MarkBetsClosed/窗口关拒）；交互 bonus 四件套齐（betsClosed 发 Accepted / 选择窗口锁 / 未选 auto 随机+回执 / 盘缺失 fail-closed）。
**FAIL**：撤注无栈 → "无效果"+超扣；缺参与时序 → bonus UI 整块不显示；缺选择锁 → 超付；缺盘校验 → 中奖派 0。

## 失败决策树

```
单项 V_N FAIL
 ├─ 首次：Claude 自诊断修小问题 → 重跑（PASS 进下项 / FAIL 进 ≥2 次分支）
 └─ ≥2 次 / 跨边界：codex_decide.sh 根因分类（D5）
      A 实现 bug → 回 Phase 3 / B 测试断言错 → 改测试 / C policy-pr 拆 / D 设计遗漏 → 回 Phase 4
      不收敛：codex_discuss.sh ≤2 轮（S3）→ 收敛按建议修 / 不收敛 unresolved(category="verify-no-converge") + 强制进 Phase 7
```

## state.json 写入

```jsonc
{ "phase":6, "status":"done | partial",
  "verify_results": {
    "V1_build":"PASS","V2_vet":"PASS","V3_test_race":"PASS","V4_cover":"27.3%","V5_policy_pr":"PASS",
    "V6_protocol_matrix":"PASS","V7a_history_json_render_i18n":"PASS — 真 fixture + 文案全 key 化 + zh-Hans 无英文残留",
    "V7b_report_real_html":"PASS ≥90% 含 SVG 自包含",
    "V8_message_timing":"PASS — betsAccepted@BETS_CLOSED后 / balanceUpdated init / win@resolve后",
    "V9_per_user_construction":"PASS — strip/personalize/snapshot前置/裸 tableId/商户余额 + 单测",
    "V10_balance_merchant_init":"PASS","V11_errcode_client_recognized":"PASS",
    "V12_reconcile_recent_dealer":"PASS — 孤儿局 fail-closed 补结算 / recentResults 缓存 / dealer root-key 缓存",
    "V13_db_currency_live_launch":"DELIVERED — 经验文档填 DB+per-currency+post-merge 必查",
    "V14_payout_reverse":"PASS — N round 反推一致含全输 / currencyMult 进制正确",
    "V14b_public_frame_merge":"PASS — winnersList 拦截合并本局我方中奖者 / 聚合透传 / 1 进 1 出只播一次",
    "V15_history_isolation_mult":"PASS — evo filter 隔离 / config 限红进制",
    "V16_bet_debit_before_result":"PASS — SubmitBets(OnMerchantBetResult) / 无误标 accepted / OnRoundSettled 必调"
  },
  "verify_failures": [] }
```

进 Phase 7 归档。
