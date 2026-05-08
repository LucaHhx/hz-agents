# Phase 8 — 经验文档结构（13 节）

每次对接结束**必须**写 `<repo>/docs/integration-experience/<gametype>/<tableId>.md`，按下列 13 节结构。

## 总体目录

```markdown
# <tableId> — <Title> (<gameType>) 对接经验

**机台**：<tableId> · <Title>
**对接日期**：<YYYY-MM-DD>
**实现分支**：worktree/<base>/<branch>
**状态**：<是否首个该 gameType / 状态总结>

---

## 目录

1. [机台基本信息](#1-机台基本信息)
2. [协议事实速查](#2-协议事实速查)
3. [生命周期 + 事件流](#3-生命周期--事件流)
4. [字典](#4-字典)
5. [协议处理决策表](#5-协议处理决策表)
6. [服务端→客户端帧合成](#6-服务端客户端帧合成)
7. [遇到的问题 + 解决方案](#7-遇到的问题--解决方案)
8. [资金安全清单](#8-资金安全清单)
9. [客户端-后端一致性矩阵](#9-客户端-后端一致性矩阵)
10. [游戏记录展示链路审查](#10-游戏记录展示链路审查)
11. [测试策略](#11-测试策略)
12. [项目级跳过项](#12-项目级跳过项)
13. [与其他机台对比](#13-与其他机台对比)
14. [部署前 checklist](#14-部署前-checklist)
15. [⚠️ 必看注意事项](#15-必看注意事项)
```

## 各节内容指引

### 第 1 节：机台基本信息

把 `tmp/<tableId>/lobby.json` 的关键字段一字一行可拷贝列出：
- id / title / game / gameType / gameLoaderKey / operatorTheme / tableVariant
- operatorGameId / limits.{min,max,minBalanceToPlay}
- common_components_theme / dealer 样本

加上拿到的命令：

```bash
python3 scripts/pp_tables.py --launch <tableId> --curl-file scripts/luca.sh
```

### 第 2 节：协议事实速查

按表格列出（每条带来源）：

| 项 | 值 | 来源 |
|---|---|---|
| 上游协议格式 | JSON / XML | capture 第一帧 |
| 客户端版本 | 5.4.11 等 | apps/<gameType>/ 目录 |
| 客户端入口 | /desktop/<gameLoaderKey>/ | launch URL |
| `lpbet gm` 字段值 | <gameType>_desktop | main.js 验证 |
| `<ping>` 格式 | 双引号 / 单引号 / 形式 | main.js |
| 一帧多事件 | 是 / 否 | message.json 全量 |

子节："关键陷阱"标注本机台特殊点（如 baccarat_desktop ≠ speedbaccarat_desktop）。

### 第 3 节：生命周期 + 事件流

- 上游初始化序列（按 capture 实测）
- 一轮事件顺序（相邻 betsopen 间）
- 帧统计（帧数表）

### 第 4 节：字典

- betCode 数值表（BC + 名 + GR 字段 + 含义）
- 错误码表（值 + 名）
- 不参与结算的字段清单

**强制**：由 `dictionary_test.go` 守住，任何修改触发断言失败。

### 第 5 节：协议处理决策表

完整事件 → verdict 表（pass / drop / rewrite + 理由）。

### 第 6 节：服务端→客户端帧合成

- 必合成的帧清单
- 不合成的帧清单（带原因）
- 帧字段 JSON 全示例（按真实合成内容）
- 结算消息顺序

### 第 7 节：遇到的问题 + 解决方案 ⭐ 核心

每个问题按"症状 → 根因 → 修复"格式，分大类组织（协议正确性 / 资金安全 / 协议陷阱 / Redis context / 代码质量）。

格式：

```markdown
#### N. <一句话标题>

- **症状**：<codex 描述 / 用户报告>
- **根因**：<分析>
- **修复**：`commit <sha>` — <一句话解决方案>
- **依据/避坑**：<引用 known-pitfalls.md 哪条 / capture 样本 / main.js 函数>
```

**Phase 6 codex 闭环时实时追加**（不等到 Phase 8 才写）。

### 第 8 节：资金安全清单

每项可勾选：

```markdown
- [x] 下注窗口双重校验（CheckBet 内存 + Redis）
- [x] CanBet Redis 异常 fail-closed
- [x] applyBet fail-closed
- [x] 空 lpbet 加窗口校验
- [x] 整批拒清 Redis（仅非窗口类）
- [x] payout_cap 接入
- [x] BC Atoi 错误显式拒绝
- [x] bets JSON 解析失败跳过用户
- [x] GetRedisUserBets fail-closed
- [x] winners 完全丢弃 PP 视角
- [x] 多事件按优先级处理
- [x] silent error 全部 zap log
- [x] race detector 通过
```

后续对接同 gametype 机台时，**对照本清单**确认每项已实施。

### 第 9 节：客户端-后端一致性矩阵

按 [known-pitfalls G1](known-pitfalls.md#g1-对接前必做客户端展示项与后端-enforce-项交叉审查) 列表交叉审查。**每条客户端面板/弹窗显示的约束类数值/规则都必须出现**：

```markdown
| 客户端面板/弹窗显示项 | 数据来源（main.js 字段） | 后端字段 | 后端 enforce | 默认值 | 状态 |
|---|---|---|---|---|---|
| 6 行单注 min/max | `*_bet_min` / `*_bet_max` | 同字段 | ✅/❌ | 0.2/1000... | OK / P0 |
| 总投注台限 | `table_bet_min/max_limit` | 同字段 | ✅/❌ | — | OK / P0 |
| "X 倍 / €Y" 最高支付 | `maxMultiplier` / `euro_table_payout_max` | 同字段 | ✅/❌ | 20000 / 500000 | OK / P0 |
| 单注派彩 cap | `payout_bet_max_limit` | 同字段 | ✅/❌ | — | OK / P1 |
| 赔率列字面量 | 客户端硬编码 | n/a | n/a | n/a | n/a |
| 翻译文案 | translations-ui 翻译键 | n/a | n/a | n/a | n/a |
```

不允许"客户端展示一回事、后端 enforce 另一回事"。

### 第 10 节：游戏记录展示链路审查

按 [known-pitfalls H1-H10](known-pitfalls.md#h-游戏记录展示一致性) 审查。

#### 10.1 客户端调用的 history endpoint

```bash
grep -oE "/api/[a-zA-Z0-9/_-]*[Hh]istory[a-zA-Z0-9/_-]*|/api/ui/statisticHistory|fetchRoundHistory|fetchBonusHistory|/cgibin/[a-zA-Z/.]*audit[a-zA-Z/.]*" \
  server/game/pp/client/apps/<gametype>/<ver>/main.js | sort -u
```

列表 + 后端 handler 实现状态：

| endpoint | 用途 | 后端实现 | 备注 |
|---|---|---|---|
| `/api/ui/history/summary` | 玩家日盈亏汇总 | ✅ `GameHistorySummary` | 走 `b_game_transactions` 聚合 |
| `/api/ui/history/dayWise` | 玩家某天局列表 | ✅ `GameHistoryDayWise` | |
| `/cgibin/usermanagement/audit/game.jsp` | 单局 XML 详情 | ✅ `GameHistoryGameDetail` + 机台 parser | |
| `/api/ui/statisticHistory` | 机台公开开奖序列 | ✅ Redis http key 透传 | |
| `/api/fetchRoundHistory` | 玩家最近 N 局简表 | ⚠️ 兜底 `{"rounds":[]}` | 客户端**实际是否依赖**此接口要确认 |
| 机台特殊 history | bonus / round-trip / ... | ❓ | 按 grep 结果 |

#### 10.2 history 详情 XML 节点结构

机台专属 XML struct（如 `SweetBonanzaXML` / `RouletteXML`），列出**每个字段**与客户端 main.js 的对应关系：

| XML 节点 | 字段类型 | 客户端 main.js 解析路径 | 数据来源（DB） |
|---|---|---|---|
| `<gr>` | string | `additional.<gametype>.gr` | `b_game_rounds.Extra.gr` |
| `<multipliers>` | string[] | `additional.<gametype>.Multipliers` | `b_game_rounds.Extra.sbmul` |
| ... | ... | ... | ... |

#### 10.3 必须落盘的字段清单

```markdown
- [ ] `b_game_rounds.StartedAt` 在 betsopen 时刻写入（H5）
- [ ] `b_game_rounds.SettledAt` 在 settle 时刻写入
- [ ] `b_game_rounds.Result` / `ResultCode` / `BonusType` / `Multiplier` 结构化字段齐全
- [ ] `b_game_rounds.Extra` 含机台特有字段（如 sweetbonanza 的 gr/payouts/sbmul）
- [ ] `b_game_rounds.RawData` 兜底保留上游整帧
- [ ] `b_game_rounds.DealerName` / `CardData` / `RoundId`（如适用）
- [ ] `b_game_transactions.Currency` 用本局会话币种（不是 user.Currency）
- [ ] `b_game_transactions.BoosterEnabled` 等机台特殊状态
- [ ] `b_game_transactions.Stake` / `GameNetCash` / `BalanceAfter` 齐全
- [ ] `b_game_transactions.Description` 按 gameType 本地化（H6）
- [ ] `b_game_transactions.MaxCapped` 触发封顶时为 true（issue #64）
- [ ] `b_game_user_actions` 落盘玩家局内决策（H7）
```

#### 10.4 开发期验证（代码分析为准）

按 [known-pitfalls H10](known-pitfalls.md#h10-开发期通过代码分析验证不抓样本) 要求：开发阶段**没有玩家样本**，验证靠代码分析 + 单测：

```markdown
- [ ] grep main.js 列出全部 `additional.<gametype>.<field>` 解析路径
- [ ] 对照后端 `<Gametype>XML` struct 字段齐全（节点名 + 大小写一致）
- [ ] settle 路径 `round.Extra` 落齐 parser 所需字段
- [ ] parser 有 Extra → RawData 兜底链路
- [ ] 单测覆盖每种 BonusType 局型（构造假 round 走 parser，断言 XML 字段输出）
```

**禁止**写"待补：抓 N 局样本"——QA / 灰度发现弹窗渲染问题再单独立 bug 修复，不在对接 PR 范畴。

### 第 11 节：测试策略

- 测试文件清单（10+ 文件 / 测试用例数 / 覆盖率）
- 每个文件的核心断言
- 字典 parity 测试说明（重点）
- 跑测试的命令

### 第 12 节：项目级跳过项

引用 `references/project-level-skips.md` 5 项 + 本次对接哪些命中（在 design.md 里标了"已知项目级 #N" 的）。

### 第 13 节：与其他机台对比

| 维度 | 同 gametype 已对接机台 | 本机台 |
|---|---|---|
| 协议 | | |
| 赔率 | | |
| 多阶段 | | |
| 用户决策 | | |
| 路单 / 统计 | | |
| betCode 数量 | | |
| 服务端→客户端帧 | | |

不一致点（独有设计）单独列出 + 解释为什么。

### 第 14 节：部署前 checklist

```sql
-- b_tables 必备字段
INSERT INTO b_tables (...);
```

- 启动顺序
- 验证清单（DGA 推送 / init 序列 / lpbet 解析 / 一局完整流程 / 边注禁用 / 错误码触发等）

### 第 15 节：⚠️ 必看注意事项 ⭐ 核心

把对接过程中**反复踩到** + **下次容易再踩**的坑提炼成 N 条铁律（A-N）。每条：

```markdown
### A. 永远不参考老项目

- /Users/luca/work/ppgame Node.js 实现禁止参考
- 已沉淀到个人 memory feedback_no_old_project.md

### B. <下一条>
...
```

**意义**：后续对接同 gametype 机台的 Claude **只读这一节就能避开主要坑**。

## 附录

### 附录 A：commit 链

按时间倒序列出本次对接的所有 commits（含 worker 和 codex 闭环修复）：

```
<sha> <commit message>
...
```

### 附录 B：codex 反复审查 N 轮汇总

```markdown
| 轮 | label | 视角 | 找到 | 闭环 |
|---|---|---|---|---|
| 1 | agent-1-correctness | 正确性 | N🔴 + M🟡 | ✅ |
| ... |
```

---

## 维护者

文档底部：

```markdown
**对接者**：<who>
**完成时间**：<date>
**总耗时**：<rough estimate>
**下次对接同 gametype 机台时**：先读本文件**第 13 节注意事项**，节省至少一半的踩坑时间。
```

## 索引更新（同步更新 README.md）

写完本机台文档后，更新 `<repo>/docs/integration-experience/README.md` 的目录结构（添加新机台条目）。

格式：

```markdown
├── <gametype>/
│   ├── <tableId-1>.md                              ← <Title> (<状态>)
│   └── <tableId-2>.md                              ← <Title> (<状态>)
```
