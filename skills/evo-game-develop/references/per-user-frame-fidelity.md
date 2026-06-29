# per-user 帧保真度（EVO 合成帧的通用方法论，所有族适用）

> **为什么单列**：EVO 一上游会话广播多下游，我方**合成** per-user 帧（不是裸转）。反复踩坑的一整类 bug
> ——客户端 mobx `Reaction` 崩 `undefined.map`、UI 卡死/不渲染、卡面/计时器/红点不更新——**根因全是同一个**：
> 我方合成帧与真客户端实际收到的帧（`message.txt`）**字段集不全 / 形态不符 / 广播频率不够**。
> 这些 bug **不会被编译/单测/codex 审查发现**（它们只看我方代码自洽，不看「客户端要什么」），只能靠
> **逐字段 + 逐相位 + 按频率对齐真实流** 提前发现。本文件就是那个强制方法论。
>
> 🔴 **铁律一句话**：凡是我方**合成/改写**下发的帧（非 raw 直转），必须先建立「真客户端收到的帧契约」
> （字段集 × 相位/状态 × 广播频率），再让我方输出逐项对齐。**漏一个字段 = 客户端崩或不渲染。**

## 0. 三份数据的角色（务必分清，别只看两份）

| 数据 | 是什么 | 用途 |
|---|---|---|
| `message-nobet.txt` | **我方上游会话收到的**（影子/Observer 视角） | 我方**能拿到什么**原料（缓存进 roundState） |
| `message.txt` | **真客户端收到的完整 per-user 流** | 我方下发帧的**权威 target**（字段集+频率+逐相位） |
| 我方运行时下发（HAR / 探针 dump） | 我方**实际发出什么** | 与 target 逐项 diff |

> ⚠️ 只对 nobet↔我方代码看，会漏「客户端要、但 nobet 里我方会话碰巧没有/形态不同」的字段。**target 永远是 message.txt（bet），不是 nobet。**

## 1. 强制步骤 A：建「per-user 帧字段契约」（按 相位 × status 笛卡尔积）

对**每个我方合成的帧 type**，从 `message.txt` 抽**逐相位 × 逐 player.status 的完整字段并集**。EVO 帧字段**随相位/状态出现或消失**，必须按维度拆，不能只看「某一帧」。

```bash
python3 - << 'PY'
import json,collections
CD="tmp-evo/<dir>"
def rows(f):
    for l in open(f"{CD}/{f}"):
        l=l.strip()
        if not l: continue
        r=json.loads(l)
        if r.get("dir")!="recv" or not r.get("payload"): continue
        try: yield json.loads(r["payload"])
        except: pass
TYPE="<gt>.playerState"           # 换成本族的 per-user 锚帧
gk=collections.defaultdict(set); pk=collections.defaultdict(set); n=collections.Counter()
for p in rows("message.txt"):
    if p.get("type")!=TYPE: continue
    g=(p.get("args") or {}).get("game") or p.get("args") or {}   # 按本族信封路径调整
    ph=g.get("phase") or g.get("state") or "(none)"
    n[ph]+=1
    for k in g: gk[ph].add(k)
    pl=g.get("player") or g.get("state") or {}
    if isinstance(pl,dict):
        st=pl.get("status") or "-"
        for k in pl: pk[(ph,st)].add(k)
for ph in sorted(gk): print(f"[{ph}] n={n[ph]} game={sorted(gk[ph])}")
for key in sorted(pk): print(f"  {key} player={sorted(pk[key])}")
PY
```

把输出**逐格**记进 `tmp-evo/<dir>/frame_contract.md`：每 (相位,status) → 必含字段 + 哪些是数组 + 哪些条件出现。这是 L3 PER_USER 的**实现规格**，也是 V-fidelity 的断言来源。

**契约里必须标注三件事**（漏任一就是下一个崩点）：
1. **数组字段**（客户端可能 `.map`）：grid / winCombinations / 各种 `*Balls` / luckySymbols[key] / winners…。我方下发**永不能 null/缺**（→ `undefined.map` 崩 mobx Reaction）。缺则补 `[]`。
2. **逐相位出现/消失**：如 `timeRemaining` 只在开窗类相位、`luckySymbols` 只在某些相位、`drawnBalls` 只在摇球后、`monopolyData` 只在 bonus 相位。我方用 `omitempty` + **按相位填充**精确复刻（多发/少发都可能改变客户端分支）。
3. **status 互斥形态**：未下注 Observer 与已下注 Participant 的 player 字段集**不同**（如 Observer 无 cards、Betting 用 chipsHistory 不用 chips）。按 status 分支构造，别一套字段套所有人。

## 2. 强制步骤 B：建「广播频率契约」（cadence）

EVO 真客户端的渲染**靠服务端持续推帧**，不是只在相位边界推一次。漏推 = 卡面/计时器/计数器**停在旧值**（最典型：摇球时卡面红点不更新）。

```bash
# 每 type 帧数（一会话），再除以局数 → 每局频率
jq -rs '[.[]|select(.dir=="recv")|.payload|fromjson|.type]|group_by(.)|map({t:.[0],n:length})|sort_by(-.n)' tmp-evo/<dir>/message.txt
```

对每个我方合成帧，确定**触发器**并对齐：

| 真实触发 | 我方必须对应触发 |
|---|---|
| 相位变化（开窗/关窗/结算） | 相位变化广播（已有） |
| **每个子事件**（每摇一球 / 每个 bonus 步 / 走势更新） | **收到对应 upstream delta 帧（如 playerPartialState）时重广播 per-user** —— 不能只在相位变化广播 |
| **每次本人动作**（下注/撤注/切卡） | 动作回执时给本连接重发 |

🔴 **判据**：若真实某 per-user 帧 **每局帧数 ≫ 相位数**（如 playerState 12/局 vs 5 相位），说明它在相位内**逐子事件重发**，我方也必须在子事件（partialState）上重广播，否则显示停滞。

## 3. 强制步骤 C：「客户端渲染源」判定（别假设客户端会自己算）

最隐蔽的坑：**假设客户端从原始数据自行派生显示态**（如「发了 drawnBalls，客户端自己会在卡上标红点」）。**经常不是**——客户端直接读服务端帧里的某字段。

- **判定方法**：在 `clientResources/frontend/evo/mini/js/` 里找该显示元素的渲染/computed，看它读**哪个字段**。
  - 例（Monopoly Big Baller 实证）：卡格红点渲染读 `card.grid[i].drawn`（服务端发的标志），客户端 `computedCards=ge(cards,luckySymbols,phase)` **不接收 drawnBalls** → **必须服务端把命中格标 `drawn:true` 再发**，光发 drawnBalls 没用。
- **数据处理推论**：若显示态来自服务端字段，我方必须**在合成时算出该字段**（如逐球标记 grid），并在正确 cadence 重发。
- ⚠️ 与「内部计算用原始值」分离：payout 引擎需要**原始 grid value**，显示需要**标记后的 grid**——**两份分开**（缓存原始供结算，下发时按 drawnBalls 派生标记版），别为显示污染结算源。

## 4. 强制步骤 D：自动化 diff（落单测 + verify 闸门）

写一个 **Go wire 测试**（`per_user_wire_test.go`）：对每个 (相位,status)，构造对应 roundState，marshal 我方合成帧，断言：
1. **字段集 ⊇ 契约**（每个真实字段我方都有，或有意省略且注明理由）。
2. **所有数组字段非 null**（`json` 里不是 `null`，是 `[]` 或有值）。
3. **逐相位字段出现/消失**与契约一致（如 BetsOpen 有 timeRemaining、无 drawnBalls）。

并在 Phase 6 verify 增加 **V-fidelity 闸门**（见 phase-6-verify.md），人工/HAR 复核 cadence。

## 5. 通用 checklist（每个新族 L3 PER_USER 完成前逐项打勾）

- [ ] 已从 `message.txt` 建 `frame_contract.md`：每个合成帧 × 每相位 × 每 status 的完整字段集。
- [ ] 每个数组字段：我方下发**保证非 null**（默认 `[]`）。
- [ ] 每个逐相位字段：`omitempty` + 按相位精确填充（与契约出现/消失一致）。
- [ ] status 互斥形态：Observer / Betting / Participant / 结算 各自字段集分支正确。
- [ ] 公共 pass-through 字段（计时器 / 各种球 / 走势）：缓存上游 + 在 per-user 帧回显。
- [ ] cadence：真实「逐子事件重发」的帧，我方在对应 upstream delta 上重广播（不止相位变化）。
- [ ] 渲染源判定：每个动态显示元素（红点/计时/计数/中奖高亮）确认读服务端字段还是客户端算；服务端字段的，我方合成 + 正确 cadence 重发。
- [ ] `per_user_wire_test.go`：逐 (相位,status) 断言字段集 + 数组非 null。
- [ ] 有条件：用真机 HAR（客户端↔我方 WS 帧）逐帧 diff，确认无字段缺失/cadence 不足。

## 6. 历史指证（本族实证，新族引以为戒）

Monopoly Big Baller 对接中，因**没先建字段+cadence 契约**，被用户连续指证 5 轮反应式修：
1. `luckySymbols` 缺键/init 省略 → `computedCards` `undefined.map` 崩、永不开窗。
2. `threeRollsBalls`/`fiveRollsBalls` **GameState struct 根本没这字段** → `computedThreeRollsBalls.map` 崩。
3. `timeRemaining` 加了字段却没缓存/下发 → 客户端不启动下注计时器、卡「下一局即将开始」无法下注。
4. 卡格 `drawn` 标记不更新 → 摇球无红点（误以为客户端会自己从 drawnBalls 算，实则读服务端 grid.drawn）。
5. 广播只在相位变化（~5/局）vs 真实 ~12/局逐球重发 → 卡面/计数停滞。

**全部一次性可避免**：若 L3 PER_USER 一开始就跑步骤 A/B/C/D，这 5 个字段/频率缺口在写代码时就暴露了。**新族务必先建契约再写合成代码。**
