# roundDetail/ — PP 官方报表页 HTML

`fetch_client.mjs` 对 `gameDetail.txt` 抓到的每个新 `<roundId>` 调 hall B2B 拿一次性 PP 报表 URL，用 headless 浏览器**真实渲染**后保存 SPA 渲染完成的 HTML。`pp-game-develop` 把它定为 `BuildGameReport`（PP 报表）的权威数据源。

## 文件命名

| 文件 | 内容 |
|---|---|
| `{roundId}.html` | 主报表页（playerSummary 表格 + gameHeader + gameResult） |
| `{roundId}-Details-<userId>.html` | 主报表点 `Details` 按钮后弹出的玩家明细页（含逐笔 bet 完整结算） |
| `{roundId}-<其他 label>.html` | 其他可见按钮点击后的快照（如有） |

`fetch_client.mjs` 用 `clickAllButtonsAndSave` 自动扫所有可见按钮逐个点击，label 来自 onclick handler 第一个字符串参数（如 `getPlayerDetails('ppc1735332952136')` 取 `ppc1735332952136`，最终 label = `Details-ppc1735332952136`）。

## 关键结构（roulette 实测）

### 1. 顶部 inline JS — **结构化数据金矿**

页面顶部有：

```html
<script type="text/javascript">
  let config = JSON.parse('{"playerSummary":"...","playerDetails":"...","roundId":"291875302819008"}');
  let data = JSON.parse('{"gameResultMap":[...], "gameName":"Gates of Olympus", "gameInfo":{...}, "gameResult":"R_16"}');
  // ...
</script>
```

`data` 字段（解析后）：

```jsonc
{
  "gameResultMap": [        // 表格行数据（每行 2 列）
    [{"data":"Bonus number","css":"firstCell",...}, {"data":"<base64-SVG>","html":true,...}],
    [{"data":"Multipliers", ...},                    {"data":"<base64-SVG x100 16 / x100 18 / ...>",...}],
    [{"data":"Game Result", ...},                    {"data":"<base64-SVG 24/33/16>",...}]
  ],
  "gameName": "Gates of Olympus",
  "gameInfo": {
    "gameId":     {"asString":"14524480219"},      // raw PP gameId
    "gameType":   "ROULETTE",                       // PP 大类
    "tableVO":    {"operatorTableName":"Gates Of Olympus Roulette","tableId":"gatesofolympus01","tableName":"GOR29.1-PGM"},
    "dealerVO":   {"id":"...","name":"Lizabeth","location":"Bucharest"},
    "gameStartTime": "May 26, 2026 9:01:46 AM",
    "gameEndTime":   "May 26, 2026 9:02:28 AM",
    "numberOfPlayers": 693,
    "isSimulated": false
  },
  "gameResult": "R_16"      // 形如 R_<number>，前缀按 gametype 变
}
```

**AI 应该优先 grep + parse 这块 JS**（结构化、稳定），而不是从渲染后的 HTML 节点反推。

```bash
# 取 inline data JSON（roulette 报表）
grep -oE "let data = JSON.parse\('[^']+'\)" round-detail.html \
  | sed -E "s/^let data = JSON.parse\('//; s/'\)$//"  | jq .

# 取 gameInfo 关键字段
node -e "
  const fs = require('fs');
  const html = fs.readFileSync('round-detail.html', 'utf8');
  const m = html.match(/let data = JSON.parse\('([^']+)'\)/);
  const data = JSON.parse(m[1].replace(/\\\\u003d/g, '='));  // PP 把 = 转义成 =
  console.log(JSON.stringify(data.gameInfo, null, 2));
"
```

### 2. 渲染后 DOM 表格

| `<table id="...">` | 内容 |
|---|---|
| `#gameHeader` | `Game started at <time> / Table name / GameId / RoundId / Dealer name` |
| `#gameResult` | gametype 特定的结果展示（roulette 是 Bonus number / Multipliers / Game Result，**内含 base64 inline SVG 画"雷电格"**） |
| `#playerSummary` | 该 round 所有参与玩家一行（hidden user 隐藏）：Nick / UserId / Login / Casino / Currency / **Total bet amount** / **Total payoff** / EUR 换算 / `Details` 按钮 |
| `#modalTable` | 点 Details 按钮后 ajax 加载的玩家明细（**主页面里是空的**，要去 `{roundId}-Details-<userId>.html` 看） |
| `#dataTable` | 旧字段 / 兼容 |

### 3. 雷电倍率（roulette 类）

`#gameResult` 中 "Multipliers" 行包含若干 inline `<svg>`，每个 SVG 渲染一个 `x<n>` 标签 + 一个开奖号。**`gameResultMap` 里的对应单元格是 base64-encoded HTML**（含整段 SVG），形态：

```text
data = "PGRpdiBjbGFzcz0nZ29vLWdhbWUtYm9udXMtbnVtYmVycyc+..."  // base64 of <div class="goo-game-bonus-numbers"><svg>...x100 16</svg><svg>...x50 26</svg>...</div>
```

解码后是 inline SVG 序列，每个 SVG 的 `<text>` 包含倍率（`x100`/`x50` 等）和号码。**AI 抽取雷电倍率**：

```python
import base64, re
encoded = "PGRpdi..."   # 从 inline JSON 拿
html = base64.b64decode(encoded.replace("\\u003d", "=")).decode()
# 配对 (multiplier, number) — 每个 <svg> 两个 <text>
pairs = re.findall(r'>x(\d+)</text>.*?font-size=\'20\'.*?>(\d+)</text>', html)
# pairs = [('100', '16'), ('100', '18'), ('100', '20'), ('100', '21'), ('50', '26'), ('50', '30')]
```

也可以直接在渲染后 DOM 抓 `#gameResult` 的 SVG，效果一样。

### 4. `Details` 子页（`{roundId}-Details-<userId>.html`）

主页面 `<input value="Details" onclick="game.getPlayerDetails('ppc...')">` 被脚本点击后页面通过 AJAX 渲染玩家逐笔下注详情。脚本等 networkidle + loader 消失后 `page.content()` 落盘。

关键 DOM：`#modalTable` 里出现具体表格 — 每个 bet 一行（amount / betcode / description / netCash / refund 状态）。其它字段视 gametype 而定。

## 高频提取速记

```bash
# 1. 主报表 gameInfo（tableId / gameId / 时间）
grep -oE 'let data = JSON.parse\([^)]+\)' {roundId}.html | head -1

# 2. 雷电倍率（base64 inline SVG → 配对）
# 见上面 python 片段

# 3. playerSummary 关键金额（DOM 解析）
xmllint --html --xpath '//*[@id="playerSummary"]' {roundId}.html 2>/dev/null

# 4. 玩家逐笔明细
xmllint --html --xpath '//*[@id="modalTable"]' {roundId}-Details-<userId>.html 2>/dev/null
```

## 常见坑

| 坑 | 现象 | 处理 |
|---|---|---|
| `=` 被 `=` 转义 | inline JSON 解析失败 | 解析前替换：`s.replace(/\\u003d/g, "=")` |
| 主页面 `#modalTable` 是空表 | Details 按钮还没点 | 看 `{roundId}-Details-<userId>.html` |
| 报表 token 过期 | 离 capture 录制时间过远，URL 拉到 401 | 这是一次性 token，**重抓 capture**；不要尝试重新拉 PP URL |
| `gameResultMap` 的展示与 gametype 强相关 | roulette 是 Bonus/Multipliers/Result；baccarat 是 Player/Banker 牌点；slot 是滚轴；dragontiger 是 Dragon/Tiger 牌 | 按 `data.gameInfo.gameType` 分支处理 |
| 报表里 `tableId` 是 PP 真实 ID | 同 tableConfig 的 `.tableId` | 可作交叉验证 |
| EUR 列是估算值 | `Total bet amount EUR` 用 PP 内部汇率 | 钱包派彩**只信 native currency 列**，EUR 列只是显示 |
| 部分机台**没有** Multipliers 行 | 普通 roulette 无雷电 | `gameResultMap` 行数变，遍历时按 `data` 第一列 label 判断 |
