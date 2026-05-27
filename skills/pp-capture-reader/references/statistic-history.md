# statisticHistory.txt — 最近局历史

`fetch_client.mjs` 抓 PP `statisticHistory` 接口，每行一条 JSON 响应。客户端用这条数据画路单 / 历史小图。

## Schema（roulette 系实测）

```jsonc
{
  "errorCode": "0",
  "description": "Success",
  "history": [
    {
      "gameId": "13273574202",        // raw PP gameId（15 位）
      "gameType": "0000000000000001", // 内部 game 协议族标识（位掩码）
      "betCount": 0,                  // 该局总下注笔数（>0 = 桌台有人下注）
      "playerCount": 0,               // 参与玩家数
      "playerWinCount": 0,            // 中奖玩家数
      "gameResult": "2  Black",       // ⚠️ 字符串，空格 + 大小写不规范
      "tableVariant": "olympusroulette",
      "winType": 0,                   // 0=普通；1=雷电
      "mul": 21                       // 该局开奖倍率
    },
    // ... 最近 N 局，时序倒序（最新在前）
  ]
}
```

字段语义跟 `message.txt` 里 `gameresult` recv 帧一一对应：
- `gameId` ↔ `gameresult.id`
- `gameResult` ↔ `gameresult.value`（PP 在这里给了 `"2  Black"`，注意 result < 10 时数字前**有两个空格**）
- `mul` ↔ `gameresult.mul`
- `winType` ↔ `gameresult.winType`

> 各 gametype 字段集会变（slot 类没有 `gameResult` 字符串），按实际响应看。

## 用途

| 想知道 | 怎么用 |
|---|---|
| 最近 N 局趋势（雷电触发频率 / 倍率分布） | `jq -s '.[0].history | group_by(.winType) | map({winType: .[0].winType, n: length})'` |
| 验证 `gameresult` 在 `message.txt` 中是否漏帧 | 取 history `gameId` 集合 vs message.txt `gameresult.id` 集合做 diff |
| 验证派彩 mul 是否合理 | `mul == 36` 直注命中无雷电；`mul >> 36` 命中雷电 |

```bash
# 该机台最近 100 局 mul 分布
jq -s -r '.[0].history[] | .mul' statisticHistory.txt | sort -n | uniq -c

# 雷电触发率
jq -s '.[0].history | map(.winType) | length as $n
       | { total: $n, lightning: (map(select(. == 1)) | length) }' statisticHistory.txt
```

## 常见坑

| 坑 | 现象 | 处理 |
|---|---|---|
| `gameResult` 不是数字 | `"2  Black"` / `"15 Black"` / `"00 Green"` | 当字符串处理；数字提取用 `(. | capture("(?<n>[0-9]+)").n | tonumber)` |
| `gameType` 是位掩码字符串 | `"0000000000000001"` | 不要当游戏类型枚举；真正的 gametype 看 `tableConfig.params.tableVariant` |
| 同一 gameId 不在 message.txt | capture 启动前的历史回放 | 正常；只跟踪 capture 期间的局用 message.txt 即可 |
| `history` 是数组但常常只回填 N 条 | PP 服务端默认返回最近 ~100 局 | 想抓更长历史得多次刷接口（capture 不主动多刷） |
