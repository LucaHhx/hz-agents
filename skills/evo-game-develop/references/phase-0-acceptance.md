# Phase 0 — 用户输入验收（AI 自检指南）

> AI 自检模式：按 gametype 动态选关键事件清单 + config 字段清单，跑通用指标 + 协议分类 diff + 机台特化检查，综合判断后写 state.json。**不用脚本**，AI 直接 bash/jq/grep。
> 阶段允许问用户：✅ 验收失败时可向用户列具体补救建议。
>
> 与 PP phase-0 的关键不同：EVO capture 目录名 = 真实 tableId（无 hall external_code 反查）；文件是 6 类（`config.txt` 替代 `tableConfig.txt`，**无 `statisticHistory.txt`**，`roundDetail/` 多一份结构化 JSON）；帧是 JSON 信封一帧一 type（无 XML、无合包排序）。

## 1. AI 执行步骤

```
1. 进入仓库根：cd $(git rev-parse --show-toplevel)
2. 定位 capture 目录（EVO 简单：目录名 = tableId）：
   - 用户给的 ID 可能是裸 EVO tableId（"vctlz20yfnmp1ylr"）或 b_tables.code（"evovctlz20yfnmp1ylr"）
   - 试 tmp-evo/<INPUT>/、tmp-evo/<去 evo 前缀>/ 是否存在且含 config.txt
   - 都不在则扫 tmp-evo/*/config.txt 反查 .table_id == INPUT
   - capture_dir = evo_table_id = 目录名；table_code = "evo"+evo_table_id
3. 确认文件齐全：tmp-evo/<dir>/{message.txt, message-nobet.txt, config.txt, gameDetail.txt, roundDetail/, clientResources/} 都存在
   - message.txt = 有头下注会话（我方↔下游完整协议）；message-nobet.txt = 无头影子账号（上游广播完整协议）。**两份同批局时间对齐 → diff 即得协议分类**（§2A）。
   - message-nobet.txt 缺失 → 退化为「单看 message.txt + uId/playerId 启发式」分类 + 记 P1 警告，建议补双会话录制。
4. 跑通用指标（§2）+ 协议分类 diff（§2A）
5. 推断 gametype：config.txt 的 `game_type` 字段优先；fallback clientResources/frontend/evo/mini/js/ 业务 chunk 文件名（如 roulette.*.js）
6. 按 gametype 跑特化检查（§3）；新游戏族（无既有 core）走 §3「新族」分支
7. 综合 P0/P1/P2 判断（§4）
8. 抽元信息（§5）
9. 写 state.json（§6 模板）
10. 输出报告
11. 失败时给用户具体补救建议（§7）
```

## 2. 通用指标速查表

> 命令里 `CD=<capture_dir>`。帧每行 JSON `{ts,dir,payload}`，🔴 **`payload` 是 JSON 编码的字符串**——一律 `.payload|fromjson` 再取 `.type`/`.args`（直接 `.payload.type` 抛 `Cannot index string with string` **终止脚本**）；`dir` ∈ `recv`/`send`/`ws`（`ws` = 连接 open/close 事件、**无 payload**，统计帧必 `select(.dir=="recv" or .dir=="send")` 排除，否则 fromjson 报错）。
> 🔴 **下面指标里的事件名/字段是 roulette 范例**。新族先抽 type 全集（§3）确定本族开窗/关窗/结算锚帧、下注帧名、限红字段，**禁止假设 roulette 的 5 态 `tableState.state`/`winSpots`/`betAction`/`table_bet_*`**——否则下面 P0 会把合格的 game show capture 误判拒收。

### 🔴 P0 必须通过（任一未过 = 拒收）

| # | 指标 | AI 检测命令 |
|---|---|---|
| 1 | 4 个数据文件齐全 + 非空 | `[[ -s tmp-evo/$CD/message.txt && -s tmp-evo/$CD/message-nobet.txt && -s tmp-evo/$CD/config.txt && -s tmp-evo/$CD/gameDetail.txt ]]` |
| 2 | clientResources 业务 chunk 存在 | `find tmp-evo/$CD/clientResources/frontend -name '*.js' \| head -1` |
| 3 | 上行 send 帧 ≥ 5 | `jq -s '[.[]\|select(.dir=="send")]\|length' tmp-evo/$CD/message.txt` |
| 4 | 上行下注帧 ≥ 2 | 先 `jq -rs '.[]\|select(.dir=="send")\|.payload\|fromjson\|.type' tmp-evo/$CD/message.txt \| sort \| uniq -c` 看下注帧真名（roulette=`betAction`；game show=`<gt>.placeChips`），再计该帧 ≥ 2 |
| 5 | 关键上游事件齐全 | 按 gametype 查（§3）；roulette: `tableState`/`winSpots`/`winnersList`/`recentResults`；game show: 开窗+关窗+结算锚+赢家帧各 ≥1 |
| 6 | ≥ 2 局完整循环 | 结算锚帧 ≥ 2：`jq -rs '.[]\|select(.dir=="recv")\|.payload\|fromjson\|.type' tmp-evo/$CD/message-nobet.txt \| grep -c '<结算锚 type>'`（roulette 用 `select(...).args.state` grep `GAME_RESOLVED`；game show grep `<gt>.gameResolved`） |
| 7 | 状态机序列实证 | §3 抽到的状态机序列完整（roulette=5 态枚举 BETS_OPEN…GAME_RESOLVED；game show=离散事件链 开窗→关窗→演出→结算→清局）。**不假设具体形态**，从 capture 实证 |
| 8 | config 含 table_id + currencyMult + 限红 | `grep -oE '"(table_id\|currencyMult)"' tmp-evo/$CD/config.txt`（必在）+ `grep -oE '"[a-z_]+_bet_(min\|max)_limit"' tmp-evo/$CD/config.txt \| head`（≥1 组限红，`table_bet_*` 或 per-betcode `<segment>_bet_*` 皆可） |

### 🟡 P1 应该通过（> 2 项警告 → degraded 询问用户）

| # | 指标 | AI 检测 |
|---|---|---|
| 9 | message-nobet 总帧 ≥ 200 | `wc -l tmp-evo/$CD/message-nobet.txt` |
| 10 | 时间跨度 ≥ 120s | `jq -s '(map(.ts)\|max-min)/1000' tmp-evo/$CD/message-nobet.txt` |
| 11 | 每局开奖/结果帧 ≥ 2 | roulette=`winSpots`；game show=`<gt>.wheelResult`/`gameResolved`。`jq -rs '.[]\|select(.dir=="recv")\|.payload\|fromjson\|.type' tmp-evo/$CD/message-nobet.txt \| grep -c '<开奖锚>'` |
| 12 | send metrics.ping ≥ 3（保活） | `jq -rs '.[]\|select(.dir=="send")\|.payload\|fromjson\|.type' tmp-evo/$CD/message.txt \| grep -c metrics.ping` |
| 13 | per-user 帧样本齐（自合成依据） | message.txt 含 per-user 帧（roulette `betsAccepted`+`tableState.betState`；game show `<gt>.bets`(私有 state)+`balanceUpdated`），靠**计数悬殊**判（见 §2A） |
| 14 | config 含视频 + 筹码字段 | `grep -oE '"(video.stream.name\|chipAmounts\|wrapper_token\|currencyCode)"' tmp-evo/$CD/config.txt \| sort -u` |

### 🟢 P2 可选

| # | 指标 | AI 检测 |
|---|---|---|
| 15 | gameDetail.txt ≥ 1（**BuildGameDetail/history 数据源**） | `[[ -s tmp-evo/$CD/gameDetail.txt ]]` + 抽样看是 JSON |
| 16 | roundDetail/ ≥ 1 完整对（**报表前端页基线**） | `ls tmp-evo/$CD/roundDetail/*.json 2>/dev/null \| wc -l` ≥ 1（含同名 .html） |
| 17 | 罕见事件样本 | grep `canceled\|session\|betValidationError\|dealer` |
| 18 | 跨段位下注 | `jq -rs '.[]\|select(.dir=="send")\|.payload\|fromjson\|(.args.chips // .args.action.value) // empty' tmp-evo/$CD/message.txt`（抽不同 betCode ≥ 2；roulette=`action.value`，game show=`chips`） |

## 2A. 协议分类 diff（message.txt vs message-nobet.txt）

> 两份同批局时间对齐，产出每 type 的处置分类（A/A2/B/handle/C），喂 L1 DICT `message_classification` + L3 UPSTREAM 处置契约。
> 🔴 **两种判 per-user 的方法，按机台选**：

```bash
CD=<capture_dir>
# 上游广播 type 计数（A/A2/B/handle 候选）。payload 是字符串 → fromjson；排除 ws 帧
jq -rs '.[]|select(.dir=="recv")|.payload|fromjson|.type' tmp-evo/$CD/message-nobet.txt | sort | uniq -c | sort -rn > /tmp/evo_nobet_types
# 下游完整协议 type 计数
jq -rs '.[]|select(.dir=="recv")|.payload|fromjson|.type' tmp-evo/$CD/message.txt | sort | uniq -c | sort -rn > /tmp/evo_bet_types
echo "=== 上游广播计数 ==="; cat /tmp/evo_nobet_types
echo "=== 下游计数 ==="; cat /tmp/evo_bet_types
# 方法①（roulette 类：per-user 帧从不广播）：集合差出 per-user
echo "=== 只在 message.txt 的 type（roulette 类 per-user）==="; comm -23 <(awk '{print $2}' /tmp/evo_bet_types|sort) <(awk '{print $2}' /tmp/evo_nobet_types|sort)
# 方法②（game show 类：同名帧也广播空壳）：集合差为空 → 看计数悬殊（bet/nobet ≥2x）+ per-session 字段
echo "=== 计数悬殊帧（per-user 候选）：手动比上两份计数，如 bets 146 vs 50、balanceUpdated 98 vs 1 ==="
```

🔴 **方法选择**：先跑方法①，若 `comm -23` 输出**为空**（game show 典型，所有 type 两份都有）→ 改方法②：**计数悬殊 + per-session 字段实证**（影子会话该帧的个人字段恒空/默认）。**别因集合差为空就判「无 per-user 帧」。**

🔴 **必须补跑 shape diff（防漏“公共帧夹带个人字段”）**：type 集合与计数只能找候选，最终分类要比较每个同名 type 的 `args` key-set、嵌套 key-set、字段值域。尤其结果/终局类帧：若有下注会话的同名帧出现下注快照、受理/拒单、派彩、余额、rebet 等个人子对象，而 nobet 同名帧没有或为空，则该帧不是纯公共广播，而是 **handle + B per-user 改写**。

```bash
# 每个 type 的 args 顶层 shape：找同名帧字段差异
node - "$CD" <<'NODE'
const fs=require('fs'); const CD=process.argv[2];
function rows(f){return fs.readFileSync(`tmp-evo/${CD}/${f}`,'utf8').trim().split(/\n+/).filter(Boolean)
  .map((l,i)=>{const r=JSON.parse(l); if(r.dir!=='recv'||!r.payload) return null;
    const p=JSON.parse(r.payload); return {line:i+1,type:p.type||'(root)',args:p.args||{}};}).filter(Boolean)}
function shapes(rs){const m=new Map(); for(const r of rs){const s=Object.keys(r.args).sort().join(',');
  if(!m.has(r.type)) m.set(r.type,new Map()); m.get(r.type).set(s,(m.get(r.type).get(s)||0)+1)} return m}
const a=shapes(rows('message.txt')), b=shapes(rows('message-nobet.txt'));
for (const t of [...new Set([...a.keys(),...b.keys()])].sort()) {
  const sa=[...(a.get(t)||new Map()).keys()].sort(), sb=[...(b.get(t)||new Map()).keys()].sort();
  if (JSON.stringify(sa)!==JSON.stringify(sb)) console.log(`${t}\n  message: ${sa.join(' | ')}\n  nobet:   ${sb.join(' | ')}`);
}
NODE
```

shape diff 后逐个 type 填判定依据：

| 证据 | 说明 | 归类倾向 |
|---|---|---|
| 字段会改变下注窗口/局状态/开奖/取消/倍率 | 业务状态机或资金结算依赖 | handle |
| 字段只在下注会话出现，或 nobet 恒空/默认 | 个人注单、个人余额、受理、拒单、派彩、rebet | B per-user 或 C 自合成 |
| 两份 feed shape/值域一致，且只影响动画/走势/公共展示 | 全桌公共信息 | A/A2 直转 |
| message.txt 有客户端必须收到的回执，上游 mirror-feed 不会提供 | server 要模拟 EVO 服务端 | C 自合成 |
| 上游代理会话私有、不能代表下游用户 | 渠道余额、订阅 ack、心跳、恢复标记等 | drop 或本地重发 |

EVO 实测分类——**roulette 范例（方法论照搬、type 名/shape 必从本族 capture 重取，禁照抄帧名）**：

| type（roulette 范例） | 出处 | 处置 | game show 对应（IceFishing 实证） |
|---|---|---|---|
| `tableState`(5 态) | 两份 | **handle + B per-user**（betState 剥离回填） | 离散事件 `<gt>.betsOpen/betsClosed/.../gameResolved`(handle) + `<gt>.bets`(B per-user，state.{chips,acceptedBets,repeat,history}) |
| `winSpots` | 两份 | handle 触发派彩 | `<gt>.gameResolved`(结算锚 handle，result+倍率盘) |
| `winnersList` | 两份 | **合并我方中奖者后广播**（非纯直转，B8） | `<gt>.winnersList`(同) |
| `recentResults` | 两份 | A 直转（走势） | `<gt>.spinHistory`(同) |
| （无演出帧） | — | — | **A2 communal 演出**：`<gt>.wheelSpinning/wheelStopping/wheelResult/bonus`(全桌动画直转不缓存) |
| （无 betstats） | — | — | **A 直转/enrich**：`<gt>.bettingStats{bettors,watchers}`(最高频聚合计数，可加我方聚合) |
| `appInfo`/`dealer`/`settings.*` | 两份 | A 直转（init 缓存回放） | 同 + `<gt>.table`/`<gt>.restore.begin/end`(重连恢复包) |
| `balanceUpdated` | 两份 | **B drop + per-user 重发** | 同（drop 渠道 USD → 商户余额重发；🔴 **无 playerId 字段**，含 `balance/balances[]/currencyCode/tableId`，按下游连接寻址） |
| `betAction` | 仅 message.txt | **C 自合成 echo** | `<gt>.placeChips`(C echo，`{chips:{段名:额},betAction:"Place"/"Repeat",betTags}`) |
| `betsAccepted`/`betActionResponse` | 仅 message.txt | **C 自合成** | **无独立受理帧**——受理结果就在 `<gt>.bets.state.{acceptedBets,rejectedBets}` |
| `fetchBalance`/`metrics.ping` | 仅 message.txt | C 自合成应答 | 同 + `settings.update`(筹码偏好) |

- ⚠️ **影子账号"只看不动" → message-nobet 的 per-user 字段只剩公共空壳或完全缺失**，但**同名帧仍可能广播**——这是 mirror-feed 实锤，也是方法①对 game show 失效的原因。
- ⚠️ **diff 是候选不是真相**：① 帧频悬殊是判 per-user 的判据（方法②），但**不能拿 message.txt 帧频推断广播频率**（广播频率只看 nobet）；② capture 天然不完整，稀有帧（`canceled`/`gameCancelled`/`betValidationError`/`restore`/特殊货币/大奖）可能从不出现 → 结合 `clientResources/frontend/evo/mini/js/` 反推 + roulette 既有实现，**不可"没录到=不存在"**。

## 3. 机台特化检查清单（**AI 按 gametype 选**）

### gametype = `roulette`（既有 core，可复用）

**P0 #5 关键事件**：`roulette.tableState`(5 态) / `roulette.winSpots` / `roulette.winnersList` / `roulette.recentResults` 各 ≥ 1。
**P1 #14 config 核心字段**：`table_bet_min_limit`/`table_bet_max_limit`/`currencyMult`/`chipAmounts`/`scenario.*.result`（赔率布景）/`even_bet_max`/`split_bet_min` 等分注限额。
**betCode**：`betAction.value` 的 key（如 `"43"`=dozen1）；与 PP `roulette/odds.go` 体系一致（标准单零欧轮直接复用 EVO `roulettecore/odds.go`）。

### gametype = 新游戏族（无既有 core，本 skill 主攻）

EVO 现仅 roulette。其它族（baccarat / blackjack / sicbo / dragontiger / game show 等）首次对接：

```bash
# 1. 上游事件计数（payload 字符串→fromjson；新族前缀 = gametype.*）
jq -rs '.[]|select(.dir=="recv")|.payload|fromjson|.type' tmp-evo/$CD/message-nobet.txt | sort | uniq -c | sort -rn
# 2. 下游事件计数（看下注帧真名 + betAction 字符串模式）
jq -rs '.[]|select(.dir=="send")|.payload|fromjson|.type' tmp-evo/$CD/message.txt | sort | uniq -c
# 3. 抽一帧下注帧看下注模型（roulette betAction{action.type,value} / game show placeChips{chips,betAction,betTags}）
jq -rs '.[]|select(.dir=="send")|.payload|fromjson|select(.type|test("placeChips|betAction"))|.args' tmp-evo/$CD/message.txt | head -c 500
# 4. 抽结算锚帧看赔付模型（roulette winNumber→号码集 / game show result+<seg>Multipliers+totalMultiplier）
jq -rs '.[]|select(.dir=="recv")|.payload|fromjson|select(.type|test("gameResolved|winSpots|gameResult"))|.args' tmp-evo/$CD/message-nobet.txt | head -c 600
# 5. config 限额字段（config 可能 {_source,_endpoint,data} 包裹）：grep -oE '"[a-z_]+_bet_(min|max)_limit"' config.txt | sort -u
# 6. betCode 双命名空间核对：下注帧裸名 vs roundDetail .data.data.participants[].bets[].code（可能带前缀如 IF_）
jq -r '.data.data.participants[]?.bets[]?.code' tmp-evo/$CD/roundDetail/*.json 2>/dev/null | sort -u | head
# 7. 客户端协议常量 + reducer 全集
grep -roE '"<gametype>\.[a-zA-Z]+"' tmp-evo/$CD/clientResources/frontend/evo/mini/js/ | sort -u | head -50
```

**实证这 6 个变量轴写入 state.json**（SKILL.md「新游戏族协议 shape 必须从 capture 自推导」铁律）：① 状态机（state 枚举 or 离散事件帧序列 → `lobby.state_machine` + `state_machine_kind`）② 下注模型（增量 betAction or 全量 placeChips 快照）③ betCode 形态（数字/字符串段名 + roundDetail 前缀映射）④ 赔付模型（号码 odds / segment 倍率 / 牌型）⑤ betstats 是否存在（`<gt>.bettingStats`）⑥ A2 演出帧 / restore 是否存在。**per-user 私有帧靠计数悬殊 + per-session 字段判（§2A 方法②），不靠 playerId 字段**（balanceUpdated 等可能无 playerId）。新族状态机不假设 roulette 5 态（IceFishing 是 7 离散事件帧；blackjack 有发牌/决策轮；baccarat 有 card 序列）——以 capture 实证为准。

## 4. P0/P1/P2 综合判断

```
P0 全过 + P1 警告 ≤ 2 → status="done"，进 Phase 1
P0 任一未过 → status="failed"，拒收 + 给用户补救（§7）→ 停
P0 全过 + P1 警告 > 2 → status="degraded"，向用户报告问题 → 询问是否继续（Phase 0 可问）
```

## 5. 元信息抽取（AI 用 jq/grep）

> ⚠️ **目录名 = 裸 EVO tableId**（与 PP 不同，无需反查）。`evo_table_id` 用于协议帧；`table_code`=`evo`+id 用于索引。

| 字段 | 来源 + 命令 |
|---|---|
| `evo_table_id` | = capture_dir（目录名）；交叉验 `grep table_id config.txt` |
| `table_code` | `"evo"+evo_table_id` |
| `gameType` | `grep -oE '"game_type"[: ]*"[^"]+"' tmp-evo/$CD/config.txt`（如 roulette） |
| `currencyMult` | `grep -oE '"currencyMult"[: ]*[0-9]+' tmp-evo/$CD/config.txt`（进制，结算/显示必用） |
| `currencyCode` | `grep -oE '"currencyCode"[: ]*"[^"]+"' tmp-evo/$CD/config.txt`（capture 会话币种） |
| `casinoHost` | `grep -oE '"wsUrl"[: ]*"[^"]+"' tmp-evo/$CD/config.txt`（取 host 段；占位文档用 `<PROVIDER_HOST>`） |
| `limits.min/max` | `grep -oE '"[a-z_]+_bet_(min\|max)_limit"[: ]*[0-9]+' tmp-evo/$CD/config.txt`（roulette `table_bet_*`；game show per-betcode `<segment>_bet_*`+`payout_limit`） |
| `chipAmounts` | `grep -oE '"chipAmounts"[: ]*\[[^]]+\]' tmp-evo/$CD/config.txt` |
| `dealer.name` | `jq -rs '.[]\|select(.dir=="recv")\|.payload\|fromjson\|.args.dealer.name // .args.name // empty' tmp-evo/$CD/message-nobet.txt \| head -1` |
| `state_machine` + `state_machine_kind` | §3 抽到的序列（roulette=5 态枚举 kind=`state_enum`；game show=离散事件链 kind=`discrete_events`） |
| `bet_model` | §3 实证（roulette=`betAction` 增量+UNDO 栈；game show=`placeChips` chips 全量快照） |
| `payout_model` | §3 实证（roulette=号码集→odds；game show=segment→倍率；从 roundDetail json 反推） |

## 6. state.json 写入模板

```bash
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
jq -n \
  --arg evo_table_id "<evo_table_id>" --arg table_code "<table_code>" \
  --arg capture_dir "<capture_dir>" --arg repo_root "$(git rev-parse --show-toplevel)" \
  --arg ts "$TS" --arg status "done|failed|degraded" \
  --arg gameType "<...>" --arg casinoHost "<...>" --arg currencyCode "<...>" \
  --argjson currencyMult "<int>" --arg min "<...>" --arg max "<...>" --arg dealer "<...>" \
  --argjson p0_passed "true|false" --argjson p1_warnings '["#10 跨度 110s","..."]' \
  --argjson broadcast '["<gt>.winnersList","<gt>.spinHistory/recentResults","appInfo","dealer"]' \
  --argjson per_user '["<gt>.placeChips/betAction","<gt>.bets/tableState.betState","balanceUpdated"]' \
  --arg smkind "state_enum|discrete_events" --arg betmodel "..." --arg payoutmodel "..." \
  '{
     evo_table_id:$evo_table_id, table_code:$table_code, capture_dir:$capture_dir, repo_root:$repo_root,
     phase:0, status:$status,
     lobby:{ gameType:$gameType, casinoHost:$casinoHost, currencyCode:$currencyCode,
             currencyMult:$currencyMult, limits:{min:$min,max:$max}, dealer:{name:$dealer},
             state_machine_kind:$smkind, bet_model:$betmodel, payout_model:$payoutmodel },
     capture_audit:{ p0_passed:$p0_passed, p1_warnings:$p1_warnings,
                     classification:{ broadcast:$broadcast, per_user:$per_user } },
     codex_reviews:[], codex_decisions:[], codex_discussions:[], unresolved:[],
     last_updated:$ts
   }' > tmp-evo/<capture_dir>/state.json
```

## 7. 失败补救建议（按发现的具体问题动态生成）

AI **不要**硬背模板。按实际触发的 P0/P1 失败项 + capture 状态 + gametype 综合给建议。例如：

- 「#1 message-nobet.txt 缺失/空」→ "无头影子账号会话没建起来（Akamai 反爬 / 会话 mint 失败），EVO 协议分类强依赖双会话对比；建议检查 evo_fetch.mjs 的 nobet 路日志，确认 EVOSESSIONID 取到 + UA=evo-client/1.0"
- 「#4 betAction=0 + 有头会话」→ "有头会话没真下注（或客户端没连上我方/真 EVO），per-user 帧 shape 取不到；建议 headed 模式手动在桌面放 ≥2 个不同 betCode 的筹码"
- 「#6 GAME_RESOLVED<2 + 抓了 3min」→ "真人轮盘约 30-45s/局，3min 不够 2 局完整循环；建议 DURATION_MS 调到 ≥ 6min 重抓"
- 「#8 config.txt 缺 currencyMult」→ "EVO 金额是进制制（IDR÷20000），缺 currencyMult 结算/显示必错；检查 /config 是否带 Cookie EVOSESSIONID、是否抓的是目标桌"
- 「新族 #5 找不到结算锚帧」→ "新游戏族状态机与 roulette 不同，先 grep clientResources 业务 chunk 的 type 字面量列全集，人工标注哪个是开奖/结算锚"
