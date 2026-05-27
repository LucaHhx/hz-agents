---
name: pp-capture-reader
description: PP（Pragmatic Play）机台 capture 数据导航与解读指南。当 AI 需要读取/分析 `scripts/game_dev/fetch_client.mjs` 产出的 `tmp/CAPTURE_DIR/` 数据包（含 message.txt / tableConfig.txt / statisticHistory.txt / gameDetail.txt / roundDetail/ / clientResources/）时使用：定位 PP tableId、抽下注协议、读结算字段、解析 betCode、查 paytable、查 ws_address、判断 capture 是否完整。触发关键词：「分析 capture」「这个机台的协议」「读 message.txt / tableConfig / gameDetail」「找 betCode / paytable / ws_address / mul」「PP 机台数据」「capture 缺什么」。**只负责"怎么读"，不负责对接落地**（落地走 pp-game-develop）。
---

# pp-capture-reader

`scripts/game_dev/fetch_client.mjs` 一次跑齐 PP 机台对接所需的全部数据，落在 `tmp/<captureDir>/` 下。AI 读 capture 时常踩的坑这里都有。

## ⚠️ 三条最常踩的坑（开工前必看）

1. **`<captureDir>` ≠ PP `tableId`**
   - `<captureDir>` = hall external_code（数字，如 `2244`），是脚本调用 hall-for-live 接口用的 ID
   - 真实 PP `tableId` 在 `tableConfig.txt` 第一条记录的 `tableId` 字段（字符串，如 `gatesofolympus01`）
   - 对接代码（`enum.TableID` / instance 注册）只能用 PP `tableId`，不能用目录名
   - 反查命令：`jq -s -r '.[0].tableId' tmp/<captureDir>/tableConfig.txt`

2. **`message.txt` 是混合协议（JSON + XML 同文件）**
   - `dir: "recv"` 几乎全是 JSON payload：`{"betsopen":{...}}` / `{"bets":{...}}` / `{"gameresult":{...}}`
   - `dir: "send"` 几乎全是 XML payload：`<command channel="..."><lpbet ...><bet bc="4"/></lpbet></command>`、`<ping .../>`
   - **直接对 payload 做 `fromjson` 会大面积报错**。判别：`.payload | if startswith("<") then "xml" else "json" end`
   - 见 `references/message-txt.md`

3. **`gameDetail.txt` 是 XML JSONL（每行一整段 XML）**
   - 不是 JSONL of objects，而是「每行一条裸 XML」，jq 不能直接吃
   - 想要结构化先 `xmllint --format -` 或者 awk 一行一行处理
   - currency 字段有大量 trailing spaces（PP 服务端 padding），用 `.trim()` 处理
   - 见 `references/game-detail.md`

## 📂 产物目录速查表（按"想知道什么"反查）

| 想知道 | 看哪个文件 | reference |
|---|---|---|
| PP 真实 tableId / operatorGameId / tableVariant | `tableConfig.txt` 第一条 | `references/table-config.md` |
| WS 地址 / 钱包币种限额 / 桌台数值上限 | `tableConfig.txt` → `.params` | `references/table-config.md` |
| 该机台所有协议事件类型（betsopen / bets / gameresult / timer …） | `message.txt` recv 帧 | `references/message-txt.md` |
| 客户端下注协议（lpbet XML 字段 / betCode） | `message.txt` send 帧 | `references/message-txt.md` |
| 单局结算（开奖号、mul、雷电翻倍、winType） | `message.txt` 中 `gameresult` recv 帧 | `references/message-txt.md` |
| 最近 N 局历史（gameResult + mul 时间序列，**不含玩家明细**） | `statisticHistory.txt` | `references/statistic-history.md` |
| **本玩家**实际下注 + 结算（含 betCode → description 映射，权威赔率源） | `gameDetail.txt` | `references/game-detail.md` |
| PP 官方报表页面（含 SVG 转盘动画 / 雷电倍率 / playerSummary） | `roundDetail/*.html` | `references/round-detail.md` |
| paytable / 规则文案 / UI 翻译 | `clientResources/apps/translations-help/...` 或 `translations-ui/...` | `references/client-resources.md` |
| betCode 编码逻辑 / lpbet 构造 / 错误码 | `clientResources/desktop/<gametype>/.../main.js` | `references/client-resources.md` |

## 🚀 上手三连

```bash
# 1) 锁 capture 目录 + 反查真实 PP tableId
CAPTURE_DIR=tmp/2244
PP_TABLE_ID=$(jq -s -r '.[0].tableId' "$CAPTURE_DIR/tableConfig.txt")
echo "PP tableId = $PP_TABLE_ID"

# 2) capture 完整度自检
for f in message.txt tableConfig.txt statisticHistory.txt gameDetail.txt; do
  printf "%-22s %5d 行\n" "$f" "$(wc -l < "$CAPTURE_DIR/$f" 2>/dev/null || echo 0)"
done
printf "%-22s %5d 个 HTML\n" "roundDetail/" "$(ls "$CAPTURE_DIR/roundDetail/" 2>/dev/null | wc -l)"

# 3) 看协议事件分布（recv 帧，自动跳过 XML payload 防止 jq 炸）
jq -r 'select(.dir=="recv") | .payload
       | select(startswith("<") | not)
       | fromjson | keys[]' "$CAPTURE_DIR/message.txt" \
  | sort | uniq -c | sort -rn
```

第 3 步出来的 key 集合 = 该机台的协议事件清单，是后续对接 GameLifecycle / ResultProcessor 的最权威依据。

## 📖 reference 总览（按需读取）

- `references/message-txt.md` — WS 帧 JSON/XML 混合协议解读、recv 各 key 字段、lpbet 下注 XML 结构、按 gametype 的协议差异
- `references/table-config.md` — `params` 字段大全（chip / 限额 / WS 地址 / 多倍率 / autoplay），JSON vs XML 两路上游
- `references/statistic-history.md` — 最近局历史 schema，与 gameresult 字段映射
- `references/game-detail.md` — game.jsp XML schema、`<bet>` 节点 betCode↔description 互查、currency 处理、roundId 抽取
- `references/round-detail.md` — PP 官方报表页 DOM 结构、SVG 雷电倍率提取、playerSummary 关键字段
- `references/client-resources.md` — `desktop/` `apps/` 目录树、grep main.js 找 betCode/错误码、translations-help 注意事项

## 🔗 关联资源

- **对接落地（写代码）**：[`pp-game-develop`](../pp-game-develop/SKILL.md) — v2 8-phase 流程，依赖本 skill 教 AI 读 capture
- **录 capture（用户操作，不在本 skill 范围）**：[`scripts/game_dev/fetch_client.md`](../../scripts/game_dev/fetch_client.md) — 主流程脚本文档
- **已对接机台验证笔记**：仓库 `experience/<gametype>/` —— 协议铁律已固化到代码的可看实例
