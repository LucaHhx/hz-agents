# tableConfig.txt — 桌台配置

`fetch_client.mjs` 抓 PP 两种上游配置接口，写到同一文件（JSONL）：

| 上游路径 | 实际响应 | 落盘形态 |
|---|---|---|
| `/ui/tableConfig` | JSON | 直接 JSON 写一行 |
| `/cgibin/tableconfig.jsp` | XML | 包装成 `{"raw_xml": "..."}` 写一行 |

判别：每行先 `jq -r '. | type'`，或者读 key 是否含 `raw_xml`。

## JSON 形态（最常见，roulette/baccarat 系新桌都走这条）

顶层字段：
```jsonc
{
  "status": "TC100",                       // PP 状态码
  "tableId": "gatesofolympus01",           // 🔑 PP 真实 tableId（字符串）
  "tableName": "GATES_OF_OLYMPUS_ROULETTE",
  "operatorGameId": "2244",                // 🔑 hall external_code（capture 目录名）
  "params": { /* 见下 */ }
}
```

> **AI 反查真实 PP tableId 的唯一权威字段**：`jq -s -r '.[0].tableId' tableConfig.txt`。**不要**用 `operatorGameId`（那是 hall external_code）。

### `.params` 关键字段（按用途分组）

#### 桌台元信息
| 字段 | 含义 |
|---|---|
| `tableVariant` | PP 内部变种名（如 `olympusroulette`），instance factory 用 |
| `frontend_roulette` / `frontend_*` | 客户端目录名（用来定位 `clientResources/desktop/<frontend>`） |
| `table_closed` / `isTableDecommissioned` | 桌台是否停服 |
| `subtitles_available` / `subtitle` | 字幕语言 |
| `automated_messages_enabled` | 自动播报开关 |

#### WS / 服务地址（**对接代码用**）
| 字段 | 含义 |
|---|---|
| `ws_address` | **PP /game WS 真实地址**（如 `wss://gs2.dkitrxmdwoqruvsi.net/game`，根域是渠道代理域） |
| `broadcaster_ws` | 公告/直播 WS（次要） |
| `gamestats_address` | 历史统计接口 host（capture 里可能被星号掩码） |

#### 限额（**钱包接入用**）
| 字段 | 含义 |
|---|---|
| `table_bet_min_limit` | 桌台单局最小总注 |
| `table_payout_max` / `euro_table_payout_max` | 桌台单局最大派彩 |
| `*_bet_min` / `*_bet_max` | 各 betCode 族最小/最大（如 `straight_bet_max=500` 直注上限） |
| `maxMultiplier` | 实际最大倍率（雷电叠加后封顶） |
| `max_table_multipliers` | **按币种**最大倍率覆盖（如 `{"BDT":100,"PKR":300,"NPR":150}`），覆盖默认 |

#### Chip / UI
| 字段 | 含义 |
|---|---|
| `chip_color_codes` | 筹码色板（逗号分隔 hex） |
| `default_chip_order` | 默认选中筹码索引 |
| `autoplay` / `autoBet` | 自动局数选项（不是对接核心） |

#### 营销 / 其它
| 字段 | 含义 |
|---|---|
| `isPromoBetDataSendEnabled` | 是否上报 promo 下注 |
| `isPrizeDropBetDataSendEnabled` | 是否上报 prize drop 下注 |
| `show_pp_branding` | UI 是否露 PP logo |

> chip_amounts / dealer / video 等是**运行时数据**，不在 tableConfig，不要硬抓。

## XML 形态（`raw_xml` 包装）

老协议 `/cgibin/tableconfig.jsp` 返回 XML（多见于 dragontiger / 早期 baccarat）。AI 处理：

```bash
# 抽出原始 XML 文本
jq -r 'select(has("raw_xml")) | .raw_xml' tableConfig.txt
```

XML 顶层 `<tableConfig>`，字段名与 JSON 形态语义对应（驼峰 → 中划线 / 下划线小写）。具体字段以实际响应为准。

## 常用 jq 速查

```bash
# 真实 PP tableId（必查）
jq -s -r '.[0].tableId' tableConfig.txt

# WS 地址（仅 JSON 形态）
jq -s -r '.[0].params.ws_address' tableConfig.txt

# 所有限额一览
jq -s -r '.[0].params | to_entries[] | select(.key | test("bet|limit|max|min")) | "\(.key) = \(.value)"' tableConfig.txt

# tableVariant（factory 注册用）
jq -s -r '.[0].params.tableVariant // .[0].params.gameVariant' tableConfig.txt

# 多币种 maxMultiplier（注意：值是字符串化的 JSON，需要二次解析）
jq -s -r '.[0].params.max_table_multipliers' tableConfig.txt | jq .
```

## 常见坑

| 坑 | 现象 | 处理 |
|---|---|---|
| 把 `operatorGameId` 当 PP tableId | 注册到 instance factory 用了数字，运行时配错 | 永远以 `.tableId` 为准 |
| `ws_address` 是渠道随机子域 | 每次部署可能换 | 对接代码不要硬编码 host，**运行时**从 tableConfig 读 |
| 多币种限额 `max_table_multipliers` 是字符串嵌套 JSON | jq 直接读会拿到字符串 | `| jq .` 二次解析；或在 Go 里 `json.Unmarshal` 两次 |
| 字段被星号掩码（`***`） | 抓 capture 时该信息被 PP 上游脱敏 | gamestats / 部分 URL 字段会这样；不影响主对接 |
| `params.broadcaster_ws` 域 ≠ `params.ws_address` 域 | 两个独立 WS | 对接只用 `ws_address` |
| 同一 `tableConfig.txt` 出现 ≥ 2 行 | 抓期间客户端重新请求过 config | 以最后一条为准（PP 服务端配置可热更新） |
