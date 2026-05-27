# gameDetail.txt — `cgibin/usermanagement/audit/game.jsp` 玩家历史 XML

PP 玩家端在"游戏历史"页拉的 XML，**capture 当前账号在该机台的全部历史下注 + 结算**。`pp-game-develop` 把它定为 `BuildGameDetail`（玩家明细列表）的权威数据源。

## 文件形态

- **每行一条裸 XML**（不是 JSONL of objects；脚本会去掉节点间空白以保证一行一段）
- jq **不能直接吃**；用 `xmllint --xpath` / Go `encoding/xml` / Python `xml.etree`

第一步建议格式化看一行：

```bash
head -1 gameDetail.txt | xmllint --format -
```

## XML Schema（roulette 实测）

```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<games>
  <account>
    <currencyBefore>true</currencyBefore>
    <currencyCode>$                                             </currencyCode>  <!-- trailing spaces -->
    <currencySymbol>$                                             </currencySymbol>
    <firstName>...</firstName>
    <fullName>...</fullName>
    <lastName>...</lastName>
    <rowCount>0</rowCount>
    <screenName>hhxluca</screenName>       <!-- 玩家昵称 -->
    <userId>ppc1735296309927</userId>      <!-- PP 用户 ID -->
  </account>
  <game>
    <bet>
      <amount>0.1</amount>                 <!-- 单注金额 -->
      <code>4</code>                       <!-- 🔑 betCode（与 lpbet bc 同） -->
      <description>1 RED</description>     <!-- 英文 description（不局部化） -->
      <localisedDescription>1 {RED}</localisedDescription>  <!-- 模板占位，客户端填色 -->
      <maxcap>false</maxcap>               <!-- 是否触顶 -->
      <megawin>false</megawin>             <!-- 是否大奖 -->
      <netCash>-0.1</netCash>              <!-- 净结算（负=输；正=赢） -->
      <partiallyRefunded>false</partiallyRefunded>
      <player>hhxluca</player>
      <result>15 Black</result>            <!-- 本局开奖结果（字符串） -->
    </bet>
    <bet>...</bet>                          <!-- 同局可多注 -->
    <currency>USD       </currency>         <!-- 货币（带 trailing spaces） -->
    <dataTimeStart>2026/05/25 04:20:47 GMT</dataTimeStart>
    <entireGameCancelled>false</entireGameCancelled>
    <freeBet>false</freeBet>
    <fullyRefunded>false</fullyRefunded>
    <gameCancelled>false</gameCancelled>
    <gameId>13273574302</gameId>            <!-- raw PP gameId（同 message.txt 中 game.id） -->
    <gameStartTimestamp>0</gameStartTimestamp>
    <roundId>291875302819008</roundId>      <!-- 🔑 hall round_id（15 位数字），驱动 roundDetail/ -->
    <!-- ... 更多字段 -->
  </game>
  <game>...</game>                          <!-- 多局历史 -->
</games>
```

> **关键互查表**：单局有 N 个 `<bet>`，每个 `<bet>` 都含 `<code>` (betCode) + `<description>` (人类可读) — 这是 **betCode 编码 → 含义 的唯一权威数据源**，比客户端 main.js 反编 webpack chunk 稳得多。

## 高频提取

```bash
# betCode → description 全集（去重）
xmllint --xpath '//bet' <(cat gameDetail.txt | tr '\n' ' ') 2>/dev/null \
  | grep -oE '<code>[0-9]+</code><description>[^<]+</description>' \
  | sort -u

# 当前账号下注过的所有 gameId
grep -oE '<gameId>[0-9]+</gameId>' gameDetail.txt | sort -u

# 全部 roundId（驱动 roundDetail 抓取）
grep -oE '<roundId>[0-9]+</roundId>' gameDetail.txt | sort -u

# 单局所有 bet 一览（取一行 + 用 xmllint）
head -1 gameDetail.txt | xmllint --xpath '//game[1]/bet' - 2>/dev/null
```

更稳的做法是**写脚本**（10 行 Go / Python），用 XML 解析器逐 `<game>` 提取，结果按 gameId 聚合。

## 字段处理细节

| 字段 | 坑 |
|---|---|
| `currencyCode` / `currencySymbol` / `currency` | **带大量 trailing spaces**（PP 服务端 padding）。处理前先 trim |
| `description` 大小写不一 | `1 RED` vs `Corner bet: 19, 20, 22, and 23` vs `RED` — 不要做大小写敏感匹配；以 `code` 整数为权威 |
| `localisedDescription` | 含 `{RED}` 这种占位符，客户端模板替换 — AI 解读时**不要**用它当人类可读字段 |
| `netCash` | 玩家**净**结算（赢 - 投注），不是派彩 = 派彩 + 注 |
| `result` | 字符串"15 Black" / "0 Green" — 提取数字用 regex |
| `entireGameCancelled` / `fullyRefunded` | 整局取消（账目退回） — 派彩验证时要排除 |
| `gameCancelled` / `partiallyRefunded` | 部分取消 / 单注退还 — 派彩验证时 netCash 仍可能非零 |
| `freeBet` / `freeBetExpired` | 免费投注（不扣余额） — 钱包验证逻辑要分开 |
| `<game>` 顺序 | XML 文档里**最新局在前还是在后取决于 PP**；用 `dataTimeStart` 或 `gameStartTimestamp` 自己排序 |

## roundId 抽取（驱动 roundDetail/）

`fetch_client.mjs` 监听到 `game.jsp` 响应时，扫每条 `<roundId>\d+</roundId>`，对每个新 roundId 异步调 hall B2B 接口拿 PP 报表 URL → 浏览器渲染 → 落 `roundDetail/{roundId}.html`。

**rule of thumb**：
- `gameId` 是 PP 内部 raw 局号（15 位，**跨 tableId 可重号**）
- `roundId` 是 hall 持久化的 round 主键（15 位数字，全局唯一）
- 两个 ID 不可互替；钱包接入用 `roundId`，与 PP 协议交互用 `gameId`

## 常见坑

| 坑 | 现象 | 处理 |
|---|---|---|
| 用 jq 处理 gameDetail.txt | parse error | 它是 XML 不是 JSON；用 xmllint / awk / xml parser |
| `<account>` 多次出现 | 多个 `<games>` 文档（多条响应） | 每行独立处理 |
| `<roundId>` 在 capture 录前的历史也出现 | 历史回放 | 这是 feature 不是 bug；`pp-game-develop` BuildGameDetail 需要历史明细 |
| betCode → description 翻译不全 | 该 capture 玩家**没下过**那些注 | 补抓 capture（让玩家覆盖所有 betCode）或查 `clientResources/.../main.js` 找客户端编码逻辑 |
