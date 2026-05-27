# message.txt — /game WS 帧

`fetch_client.mjs` 把 PP `/game`（或 `/ws/game`）WebSocket 的所有帧记下来，每行一条 JSON：

```json
{"ts": 1779682853664, "dir": "recv", "payload": "<frame as string>"}
```

| 字段 | 含义 |
|---|---|
| `ts` | 帧到达时刻（Unix ms） |
| `dir` | `"recv"` = 服务端下发；`"send"` = 客户端上行 |
| `payload` | **字符串**形态的帧内容（可能是 JSON 也可能是 XML） |

## ⚠️ 协议是混合的：JSON + XML 同文件

- **recv 帧绝大多数 = JSON**，形如 `{"<eventKey>": {...}}`
- **send 帧绝大多数 = XML**，形如 `<command channel="..."><lpbet ...><bet .../></lpbet></command>` 或 `<ping channel="..." time="..."/>`
- 偶有例外：少量 recv 帧也可能是 XML（PP 老协议遗留），少量 send 也可能是 JSON

**铁律：处理前必判别**

```bash
# 安全模板：先用 startswith("<") 滤掉 XML 行，避免 jq fromjson 报错
jq -r 'select(.dir=="recv") | .payload
       | select(startswith("<") | not)' message.txt \
  | jq -c '.'
```

XML 帧想结构化建议另开管道（`xmllint --xpath`、或在 Go 里 `xml.Unmarshal`），不要硬塞 jq。

## recv 帧（PP → 客户端）— 单 key 事件信封

每条 recv JSON 都是 `{"<key>": {...payload...}}`，**key 名 = 事件类型**。`<payload>` 里几乎总有 `seq`（PP 全局序号，单调递增）。

### gatesofolympus01 实测到的事件 key 全集（roulette 类，可作其它机台参考）

| key | 触发时机 | 关键字段 |
|---|---|---|
| `table` | 进桌握手 | `newTable` / `value`（游戏版本号） |
| `dealer` | 荷官播报 | `id` / `value`（荷官名） |
| `game` | 新局开始 | `id`（raw gameId，15 位）/ `starttime`（ms）/ `table` / `value`（开始时刻字符串） |
| `betsopen` | 下注窗口打开 | `game` / `table` |
| `betsclosingsoon` | 即将关闭下注 | `game` / `table` |
| `betsclosed` | 下注关闭 | `game` / `table` |
| `bets` | 玩家下注被服务端 ack（含历史回放） | `bet: [{amount, betcode, description, currency}]` |
| `timer` | 倒计时刷新 | `value`（剩余秒） |
| `startDealing` | 开始转盘 | — |
| `gameresult` | **开奖结算**（最关键） | `result` / `color` / `mul`（实际倍率，含雷电翻倍） / `luckyWin` / `winType` / `resultBetCodeId` / `id` |
| `gorBonusReady` | 雷电倍率即将公布（gor 协议） | `bonusNo` / `bonusSlotId` / `mCap` |
| `gorRng` | 雷电倍率落地 | 雷电具体倍数信息 |
| `winningBetCodes` | 本局命中的 betCode 列表 | 数组 |
| `winners` | 本局赢家列表 | 玩家头像 / 金额 |
| `lastgame` | 进桌即下发的最近一局回放 | 综合体（含结果） |
| `gameEnded` | 一局完整结束 | `game` |
| `win` | 本玩家中奖具体金额 | `amount` |
| `pong` | 心跳响应 | — |
| `subscribe` | 订阅通道 ack | — |
| `betSpot` / `betSpotWin` | 下注热区/赢区高亮（UI 用） | — |
| `cameraEvent` / `zoomIn` / `zoomOut` | 视频镜头切换 | — |
| `playersCount` | 当前桌玩家数 | — |
| `raw` / `command` | 兜底，能看到原始命令 | — |

> 不同 gametype 事件集会差异：sweetbonanza（slot）没有 `betsopen/betsclosed`，开局即结算；baccarat 多 `freebet`/`squeeze`；dragontiger 有 `roadmap`。**抓 capture 的 recv key 频次表是判定该机台属哪个协议族的最快方式**（见 SKILL.md 上手三连第 3 步）。

### 关键事件 payload 实例

```jsonc
// 新局开始
{"game":{"id":"13273574302","starttime":"1779682847937","table":"gatesofolympus01","seq":3,"value":"04:20:47"}}

// 下注关闭
{"betsclosed":{"game":"13273574302","table":"gatesofolympus01","seq":21}}

// 玩家下注 ack
{"bets":{"seq":23,"bet":[
  {"amount":0.1,"betcode":4,"description":"1 Red","currency":"USD"},
  {"amount":0.1,"betcode":48,"description":"Red","currency":"USD"},
  {"amount":0.1,"betcode":121,"description":"Corner bet: 19, 20, 22, and 23","currency":"USD"}
]}}

// 开奖（含雷电倍率）
{"gameresult":{"result":15,"color":"black","mul":21.0,"luckyWin":false,
                "id":"13273574302","time":"04:20:47","winType":0,
                "resultBetCodeId":18,"seq":33,"value":"15 Black"}}
```

**`gameresult` 字段速记**：
- `result` — 开奖号（roulette 是数字 0-36）
- `color` — `red` / `black` / `green`（0）
- `mul` — **派彩用的实际倍率**（直注命中 = 36 ± 雷电额外倍数；雷电翻倍后通常 ≥ 50）
- `luckyWin` / `isBoosted` / `luckyMul` — 是否触发雷电类玩法
- `winType` — `0` = 普通中奖；`1` = 雷电中奖；具体语义见 `clientResources/desktop/.../main.js` 里的枚举
- `resultBetCodeId` — 命中的"号码"对应的 betCode（不是 result 数字本身），与 `<bet>` description 对照查

## send 帧（客户端 → PP）— XML lpbet 协议

最常见：

```xml
<command channel="table-gatesofolympus01">
  <lpbet gm="gor_desktop" gId="13273574302" uId="ppc1735296309927" ck="1779682857409">
    <bet amt="0.1" bc="4" ck="1779682857409"/>
    <bet amt="0.1" bc="13" ck="1779682857409"/>
  </lpbet>
</command>
```

| 属性 | 含义 |
|---|---|
| `channel` | 始终是 `table-<tableId>`（PP 真实 tableId，**不是** capture 目录名） |
| `lpbet.gm` | game module 标识，roulette 系是 `gor_desktop`（GameOver / Roulette），slot 系是 `gameplay_desktop` 等 |
| `lpbet.gId` | raw gameId（同 recv `game.id`） |
| `lpbet.uId` | PP 用户 ID（`ppc...` 前缀） |
| `lpbet.ck` | client tick（毫秒），用作幂等 |
| `bet.amt` | 单注金额（货币最小单位为 1 不是分） |
| `bet.bc` | **betCode** — 整型，roulette 1-36=直注号码，48-51=红黑奇偶，100+ 为线/角/dozen/column |
| `bet.ck` | 单注 client tick（撤注 / 重发参考） |

另常见心跳：`<ping channel="table-<tableId>" time="<ms>"/>`

> betCode 完整映射看 `gameDetail.txt` 的 `<bet><code>N</code><description>...</description></bet>` 对照表（见 `references/game-detail.md`）；脚本读不到 description 时去 `clientResources/desktop/.../main.js` grep `betcode|bc:` 找客户端编码逻辑。

## 常用 jq 速查

```bash
# 1. 只看协议事件类型清单
jq -r 'select(.dir=="recv") | .payload | select(startswith("<")|not)
       | fromjson | keys[]' message.txt | sort -u

# 2. 所有 gameresult（按时间序）
jq -c 'select(.dir=="recv") | .payload | select(startswith("<")|not)
       | fromjson | select(.gameresult) | .gameresult' message.txt

# 3. 单局完整时间线（按 gameId 过滤，含 send/recv）
GID=13273574302
jq -c --arg g "$GID" '
  select(.payload | test($g)) | {ts, dir, p: .payload[0:120]}
' message.txt

# 4. 抽该玩家所有下注（XML send，从 lpbet 解析）
jq -r 'select(.dir=="send") | .payload' message.txt \
  | grep -oE 'bc="[0-9]+"' | sort | uniq -c | sort -rn

# 5. 找进桌握手到首个 betsopen 之间的序列（机台初始化协议）
jq -r 'select(.dir=="recv") | .payload | select(startswith("<")|not)
       | fromjson | keys[0]' message.txt \
  | awk '/betsopen/{exit} {print}'
```

## 常见坑

| 坑 | 现象 | 处理 |
|---|---|---|
| `fromjson` 大面积 parse 报错 | 同文件混 XML payload | 先 `select(startswith("<") | not)` 过滤 |
| `gameresult.mul` 数字偏小 | roulette 直注未触发雷电 | 看下条 `gorRng` / `winningBetCodes`；雷电翻倍后 mul 应该 ≥ 50 |
| `bets` 里出现"陌生" description | 服务端语言不一定是 en（受 `params.dealer.lang` 影响） | 以 `betcode` 整数为权威字段，description 仅供阅读 |
| 同一 gameId 出现多次 `gameresult` | 重连回放（PP 服务端会重发完整局） | 按 `seq` 单调递增筛最新；或按 `(table_id, game_id)` 复合 key 去重 |
| 找不到 `betsopen`（slot 类） | sweetbonanza 类不分窗口 | slot 协议无下注窗口，直接 send 一帧下注 → recv `gameresult` |
| `dir: "recv"` 出现 XML（少见但有） | 老协议或 ack | 跳过 / 单独 xmllint |
