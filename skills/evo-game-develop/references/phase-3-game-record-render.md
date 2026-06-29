# L4.3 配套 — 游戏记录详情 render 1:1 复刻方法

> 目的：让玩家「我的历史 → 游戏详情」的局面区与真实 EVO **逐字节一致**（结果区 UI + bet 表），而不是早期的纯文字降级版。
> 适用：任何新 EVO 游戏族。已落地范例：`roulette`（号码盘）/ `crazytime`（轮盘 sector + bet 表逐段图标）/ `icefishing`（leaf/bonus 框图）。
> 数据源：`tmp-evo/<dir>/gameDetail.txt` 的 `.data.render`（EVO 服务端 SSR 的 HTML 串，客户端 `dangerouslySetInnerHTML` 直插）。

## 0. 架构落点（renders 子包，新族照此摆放）

```
server/game/evo/internal/gateway/
├── history_api.go          # 通用：EvoHistoryGame 调 renders.BuildRoundRender(gameType, gameID, tableDBID, txns, symbol)
└── renders/                # 每族一份 render，集中管理
    ├── render.go           # 唯一导出入口 BuildRoundRender 按 gameType 分发 + 共享 renderBetRow / evoTablesFilter / gameType 常量
    ├── <gametype>.go       # 该族查询(b_game_rounds/transactions) + 模板装配 + <gametype>_test.go
    └── assets/<gametype>/  # 从 capture 字节级抽出的 SSR 片段，//go:embed assets/<gametype>/<name>.html 注入
        ├── style.html      # 自包含 <style>（含 ssr_* 布局；可能内嵌 base64 字体）
        └── <部件>.html     # sector / icon / multiplier / bet 行 等模板，命名去族前缀
```

- gateway 只认 `renders.BuildRoundRender`，不关心各族细节。新族 = 在 `render.go` 的 switch 加一个 `case gameType<Family>: return build<Family>Render(...)` + 新建 `<gametype>.go` + `assets/<gametype>/`。
- 简化文字 render 族可仅 `style.html`；1:1 族模板较多属正常（crazytime ~20 个，icefishing ~8 个）。
- **禁 raw 字符串硬拼**整段 HTML：动态片段走模板占位替换（`{{KEY}}`），静态美术片段 verbatim 落 `assets/`。

## 1. 四步法（每族重复）

### Step A — 分析结果区结构（先读 gameDetail.txt）
- 抽 `.data.render`，剥 `<style>` 后看 body 骨架；枚举**所有结果形态**（数字/各 bonus/miss/leaf-带倍率…）。逐形态找 capture 样本。
- 判定动态 vs 静态：哪些是随局变化的值（中奖段、倍率、坐标、图标名），哪些是固定美术（金框 SVG、渐变 defs、字体）。
- 映射我方落库字段：`b_game_rounds.{ResultCode, Multiplier, Extra}` + `b_game_transactions.{BetCode, BetAmount, Payout}`。**render 的 data-sector 展示名可能 ≠ 我方裸码**（如 crazytime DB 存 `b4`，render 用 `CrazyBonus` + 图标 `CrazyTime.svg`）——建段码→展示名/资产名映射表。

### Step B — 验证资源可达（务必先验，再写代码）
- `render` 常引外链美术（`<img src>` / SVG `<image href>`）。两种形态：
  - 相对 `/frontend/game-render-assets/<gt>/...`（crazytime）→ 我方 `/frontend/*` 路由本就代理（本地优先 + EVO CDN 回源 cache-through，见 `gateway/routes.go` + `client_proxy.go` 的 `evoCDNBase`）。
  - 绝对 `https://livecasino.evo-games.com/frontend/...`（icefishing）→ **改写为相对 `/frontend/...`** 走我方代理（统一、cache-through；别留绝对域，绕过代理且有 CORS/geo 风险）。
- 实测三路 200 再动手：`curl https://tmbge.evo-games.com/frontend/...`（CDN 基）、`curl http://127.0.0.1:9691/frontend/...`（我方代理，需 game-evo 在跑）。回源会自动落盘 `server/game/evo/client/frontend/game-render-assets/`。

### Step C — 字节级抽模板（用脚本，别手抄）
- 从 capture 取目标片段，**只把动态位替换成 `{{KEY}}`**，其余 verbatim。Python 脚本批量产出 `assets/<gametype>/*.html`，避免手抄出错。
- 静态美术（金框 wheel SVG ~10KB defs、base64 字体）原样保留在模板里；体积大属正常（不进 .go，不触 policy-pr 行数）。
- 占位粒度尽量粗：能把整块 `<g id="multiplier">…</g>` 作一个 `{{MULT}}` 占位、由 Go 构造，就别拆成十个小占位。

### Step D — Go 装配 + 字节对比（验收闸门）
- `build<Family>Render`：查 round + 聚合每注 → 选模板 → `fillTemplate(tpl, map{...})` 填值 → 拼结果区 + bet 表。
- **验收必做字节对比**：把同一局输入喂进装配器，与 capture 的 `sectorGroup`（结果区）/ bet 行做归一化（压空白）后逐字节 diff，覆盖**每种结果形态**。这是 1:1 的唯一硬证据，写成临时 dump test 跑完即删，关键断言留进 `<gametype>_test.go`。

## 2. 逆向硬细节（踩过的坑，新族大概率重演）

| 现象 | 处理 |
|---|---|
| `<style>` 内嵌 `@font-face` base64 字体 | 整段照抄即自包含，倍率/特殊字体不依赖外部。 |
| 某属性随**值/位数**变（如倍率 `viewBox` 宽 138/206/275、sign `translate-X`、digit `em` 宽） | 先抽多个样本看是否变；变则**逐位/逐值建表**或推公式（照搬真实 JS 浮点原文，如 `59.040000000000006`）；不变就当常量。 |
| 每段图标自带**逐段渐变/配色**（不止 text fill） | 别参数化颜色——**每段一个图标文件** verbatim（如 crazytime topnum_1/2/5/10、hist_*；icefishing 段 webp）。 |
| 文字两侧有空格（`> 1 <`、`> 37 <`） | 模板保留空格、只替换数字；1:1 必须保留。 |
| 属性间有换行（`data-sector="X"\n  data-bonus="X"`） | 抽取/断言按真实换行处理，别假设单空格。 |
| 每次 render 随机 UUID（如 `bonusGameTicket-<uuid>`，自引用 def+use 内部一致） | 功能无关，对比时**正则 mask 掉再比**；模板用固定 UUID 即可（自洽即合法）。 |
| 资产名大小写约定 | 建映射（crazytime `b4→CrazyBonus`+图标 `CrazyTime.svg`；icefishing 段首字母小写 `HugeReds→hugeReds`）。 |
| 同一形态因**别的状态**换资产（icefishing leaf logo：base 用 `leaf{N}`、带倍率用共享 `leafGlobal`） | 别只按段判，按真实条件（是否带倍率）切换。 |
| 倍率/角标**仅特定条件显示** | 从样本反推条件（crazytime 数字 result 仅 `slotResult==result` 时叠角标；icefishing leaf 仅 `totalMultiplier>1` 才显示，且数字 svg vs bonus webp 两套资产）。 |

## 3. bonus 内部局面 → 需先落库（数据前置）

bonus 局 `render` 除结果主面板外，常含**内部演出网格**（crazytime flapper 转盘 / cash hunt 网格 / pachinko / coin flip）。要 1:1 这段，bonus 结果帧的完整数据必须**落库**——而 handler 往往只抽了最终倍率、丢了全网格。

落库模式（**纯展示、不碰结算数学**，crazytime 已落地范例）：
- Processor 加 `bonusFrames map[string]json.RawMessage`；bonus 结果事件在记倍率时 `rememberBonusFrame(gameID, a)`（marshal 失败仅 log、不阻断结算）。
- `persistRound` 对 bonus 局把帧原文写 `b_game_rounds.Extra["bonusResult"]`；`forgetResultContext` 一并清。
- 内部 UI 所需字段不在 Args struct 的，**扩 struct**（如 `ArgsPachinkoResult.LandingZone`、`ArgsCoinFlipResult.Coin`），别用 map。
- ⚠️ **数据齐全度先核**：result 帧可能不含全部内部数据（pachinko 只给 `landingZone+totalResult`、缺 per-zone 倍率；coinflip 缺另一枚币）。缺的需另抓 setup 帧落库，或内部简化展示——落库前先确认 render 要什么 vs 帧给什么。

## 4. 验收清单（B5）

- [ ] `renders/<gametype>.go` + `assets/<gametype>/` 就位，`render.go` 分发加 case。
- [ ] 资源三路 200（CDN / 我方代理），绝对 URL 已改相对。
- [ ] **每种结果形态**与 capture 字节级 diff 通过（归一空白 + mask 随机 UUID）。
- [ ] bet 表结构对齐真实（族专属 class + 逐段图标），金额精度无浮点尾巴（`math.Round(x*100)/100` 再去尾零）。
- [ ] `<gametype>_test.go` 留结构断言（关键 class / 资产路径 / 倍率规则 / 精度）。
- [ ] bonus 局若做内部网格：bonus 帧已落 `Extra["bonusResult"]`，资金路径未动（cache-before-settle、marshal-fail 不阻断、OnRoundSettled 时序不变）。
- [ ] build/vet/test + policy-pr（单 .go ≤500 行；模板 .html 不计）+ 5 binary 编译。
