# Phase 6 — 反复 codex review 工作流

## 调用约定

```bash
bash scripts/codex_review_loop.sh <worktree_path> <round_label>
```

脚本封装：
1. 调 `bash <codex-collab-skill>/scripts/codex_review.sh -d <worktree_path> -l <round_label>` + PP 专用 prompt（见下）
2. 解析输出 jsonl，提取 🔴 / 🟡 / 🟢 findings
3. 写到 `state.codex_rounds[]`
4. 若 codex CLI 卡死（>10min 无 agent_message）→ kill + state.codex_stuck_count++
5. 退出码：0 = clean / 1 = 有 findings / 2 = 卡死

## PP 专用 prompt 模板（每轮迭代调整）

### 第 1 轮（agent-1 正确性）

```
你是一名严格的代码审查者，只审查、不修改任何文件。按 🔴/🟡/🟢 分类输出，每条 file:line 描述+修复建议。

【视角】正确性视角：聚焦逻辑正确性、边界条件、并发、数据一致性、错误处理。

【审查目标】分支 <branch> 相对 live 的全部改动（git diff live...HEAD）。这是 PP <gameType> 机台 <tableId> 对接。

【客户端代码】协议字段事实必须对照客户端 JS 验证（不可只凭 struct 注释推断）：
- 主 JS 目录：tmp/<tableId>/clientResources/desktop/<gameType>/
- 关键 grep 命令：
  grep -an "placeBet\|lpbet\|pbet\|betcode\|betCode\|amt\|amount" tmp/<tableId>/clientResources/desktop/<gameType>/chunk-*.js
  grep -an "betValidationError\|placebetError\|commandReply\|optErrorCode\|code" tmp/<tableId>/clientResources/desktop/<gameType>/chunk-*.js
- dict.json 记录的协议字段只是 Phase 3 的分析快照，**不是绝对权威**；发现与客户端 JS 不符时，以 JS 字面量为准

【特别关注】
1. XML struct 字段与客户端 JS 实际发送/解析的属性名是否逐一匹配（不可从其他机台照抄 struct）
2. 下注 XML 格式：pbet / lpbet / placebets 三种格式是否都支持（短属性 amt/bc vs 长属性 amount/betcode）
3. 协议事实正确性（GR 字段反查表 / betCode 表 / 错误码值 / init 顺序与 capture 一致）
4. 结算公式正确性（payout 严格按 Up 反查表 × 押注；不参与字段不结算）
5. 跨 commit 一致性（worker-1 常量 ↔ worker-2 业务调用对齐）
6. 并发与数据一致性（mu 字段保护范围；pendingWins 顺序保证）
7. 错误处理（feedback_no_silent_fallback 铁律；fail-closed）
8. 单测充分性（4 个 capture 样本 + 边注 + 不参与字段忽略断言）
9. 字典 parity 测试是否覆盖
```

### 第 2 轮（agent-2 陷阱防御）

```
【视角】陷阱与安全视角：聚焦 PP 协议特有陷阱、并发竞态、资金流安全。

【客户端代码】协议字段事实必须对照客户端 JS 验证：
- 主 JS 目录：tmp/<tableId>/clientResources/desktop/<gameType>/
- 重点文件：chunk-EQLH3F6G.js（公共 service / placeBet 构建）、chunk-P62NSKTU.js（socket 常量）
- 验证方法：grep -an "betValidationError\|placebetError\|code\|betCode\|extendedErrorCode" + 追踪 socketData 字段访问

【关键陷阱清单 — 逐项验证】
1. tableId 字节级替换
2. winners 处理（pass 透传 winner[] 或 rewrite 合并我方覆盖；**不可完全丢弃** — 见 known-pitfalls B2 修正版）
3. 多事件单帧按优先级处理（gameresult 必须先 winners）
4. PP 视角全 drop（bet/bets/win/winningBetCodes/betSpotWin/command/pong）
5. CanBet Redis 异常返回 false
6. ping 单/双引号兼容
7. 空 lpbet/pbet/placebets 关窗后撤单防御（三种下注格式均须覆盖）
8. 整批拒清 Redis 仅限非窗口类
9. BC Atoi 错误显式拒绝
10. bets JSON 解析失败跳过用户
11. payout_cap 接入
12. CheckBet 内存 + Redis 双重 fail-closed
13. EnrichBetstats unwrapEnvelope
14. baccarat 不发 winningBetCodes / betSpotWin
15. **struct 字段照抄陷阱**：对照 JS grep 确认每个 XML 属性名精确无误（大小写、驼峰），不可信任 struct 注释
```

### 第 3 轮（agent-3 可维护性）

```
【视角】可维护性视角：命名、分层、复杂度、重复代码、可测试性、文档、规范契合度。

【客户端代码参考路径】tmp/<tableId>/clientResources/desktop/<gameType>/
（用于核验 struct 注释来源是否有据可查，注释里的 chunk 文件名和行号应可验证）

【对照规范】
- DEVELOPMENT.md 第八章 8.1-8.6（Processor 嵌入 EventHandler / NewGameInstanceBase / Redis key 走 enum.go）
- DEVELOPMENT.md 5.0（translations-help 不是单机台事实）
- CLAUDE.md 注释最少铁律
- policy-pr 单文件 ≤ 500 行 / 嵌套 ≤ 3 层
- feedback_struct_only.md（禁 raw 字符串拼 JSON）
- feedback_no_old_project.md（禁参考 ppgame）
- feedback_runtime_vs_dev_data.md（区分开发资料 vs 运行时配置）
- feedback_no_silent_fallback.md（禁静默吞错）
```

### 第 4+ 轮（confirm-clean）

```
请只看是否有新引入 bug 或漏修，明确忽略以下项目级架构问题（与 crystalroul/sweetbonanza 一致）：
1. handlers.SubmitBets 幂等锁缺失
2. /bet 异步 vs gameresult 顺序 race
3. settle_persist.go 通用层缺陷
4. NamespaceGameId 未应用
5. payout 用 float64

无问题就回"无重大问题"。
```

## 闭环条件（**硬上限 + 写 unresolved[]，绝不停下问用户、绝不调 gh**）

- codex 报"**无重大问题**" → 退出循环 → 进 Phase 7
- **跑满 10 轮**（Phase 6 硬上限）→ 自动整理剩余 finding → 追加 `state.unresolved[]`（category="round-cap-leftover"）→ 进 Phase 7
- 同问题（按 finding 描述前 30 字符 hash 计数）**≥ 3 次** → **追加 `state.unresolved[]`**（category="repeated-N-times"）+ 标记该问题 `repeated_problems[hash].filed=true` + 后续轮跳过该 hash → 继续
- codex CLI **卡死 ≥ 3 次** → **追加 `state.unresolved[]`**（category="stuck-3-times"，desc="codex CLI 环境异常 — Phase 6 卡死 3 次"）+ 进 Phase 7（已修部分提交即可，剩余靠测试反馈）
- **绝不再"停下报告用户"**（铁律 1：完全无人值守）；**绝不再调用 gh issue / gh pr**（铁律 8/9：仅 worktree 范围）

## 自主决策矩阵（每个 finding 必须三步分流）

```
Step 1：项目级跳过判断（命中即跳过，不再考虑后续步骤）
   - file path 在 server/game/common/{handlers,runtime,merchantclient}/?
   - 命中 project-level-skips.md 5 项之一？
   - 与本 worktree 已修的项目级 commit 重复？
   - 同 hash 已 ≥ 2 次重提？
   命中 → 跳过 + 第 1 次提及时一次性记入经验文档第 10 节"项目级跳过状态"
   否则 → Step 2

Step 2：影响范围分级（按 SKILL.md §自主决策矩阵 small/medium/large）
   - 改动行数预估
   - 是否跨机台联动
   - 是否涉及新抽象 / 新表 / 新 API
   - 是否纯协议正确性（main.js 字面量驱动）

Step 3：执行
   - small（≤ 50 行 / 本机台 / 无新抽象） → 立即修 + commit + 经验文档第 7 节实时记录
   - medium（50-200 行）：
     * 资金安全必要 → 修
     * 否则 → 追加 state.unresolved[] + 经验文档第 15 节"follow-up 摘要"
   - large（> 200 行 / 跨机台 / 新表 / 新 API） → 追加 state.unresolved[] + 第 15 节
```

**禁止**：
- ❌ 把 codex 所有 finding 都修（最贵、最慢、最容易引入回归）
- ❌ 反复 prompt 用户"X 项怎么推进"（铁律 1：完全无人值守）
- ❌ 任何 `gh issue create` / `gh pr create` 调用（铁律 8/9：仅 worktree）
- ❌ medium-非必要 finding 仍尝试修（应直接 unresolved[]）
- ❌ 项目级问题第 2/3 次提及时还在 commit message 里详细解释（已记录的不重复，state.unresolved[] 自带索引即可）

## state.unresolved[] 写入模板（替代原 gh issue create）

每次触发 unresolved 条件时，**追加**到 `tmp/<tableId>/state.json` 的 `unresolved[]`：

```jsonc
{
  "id": "unresolved-<uuid>",
  "phase": 6,
  "category": "repeated-N-times | stuck-3-times | large-impact | round-cap-leftover | medium-non-essential | project-level-recurring | codex-script-failed",
  "source": {
    "round": 7,
    "label": "agent-2-traps",
    "finding": {"file": "...", "line": 42, "desc": "codex finding 原文"}
  },
  "verdict": {
    "impact": "small | medium-非必要 | large | project-level",
    "fund_safety": false,
    "repeat_count": 3
  },
  "suggested_action": "跨机台联动需独立设计 | 缺 capture 样本待生产数据 | 与项目级 #N 合并 | scope cap 已达 10 轮硬顶 | 同问题 3 次重提，根本设计需 review",
  "snapshot": {
    "state_json": "tmp/<tableId>/state.json",
    "worktree": "<worktree_path>"
  },
  "created_at": "ISO-8601"
}
```

写入命令样例（jq）：

```bash
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
jq --arg ts "$TS" \
   --arg id "unresolved-$(uuidgen | tr A-Z a-z)" \
   '.unresolved += [{"id": $id, "phase": 6, "category": "round-cap-leftover", "created_at": $ts, ...}]' \
   tmp/<tableId>/state.json > tmp/<tableId>/state.json.tmp \
&& mv tmp/<tableId>/state.json.tmp tmp/<tableId>/state.json
```

Phase 8 经验文档第 15 节自动从 `state.unresolved[]` 渲染摘要表，供用户在流程外手动决定（建 issue / 排期 / 忽略）。

## 实时决策记录格式

每次本机台修补后立刻追加到 `docs/integration-experience/<gametype>/<tableId>.md` 第 7 节：

```markdown
#### N. <一句话标题>

- **症状**：<codex 描述>
- **根因**：<分析>
- **修复**：`commit <sha>` — <一句话解决方案>
- **依据/避坑**：<引用 known-pitfalls.md 哪条 / capture 哪个样本 / main.js 哪个函数>
```

## 状态字段（state.json）

```json
{
  "codex_rounds": [
    {
      "round": 1,
      "label": "agent-1-correctness",
      "started_at": "...",
      "finished_at": "...",
      "verdict": "review-required",
      "findings": [
        {"severity": "🔴", "file": "...", "line": 42, "desc": "...", "action": "fixed", "commit": "abc123"},
        {"severity": "🟡", "file": "...", "line": 88, "desc": "...", "action": "skipped-project-level"}
      ]
    }
  ],
  "codex_stuck_count": 0,
  "repeated_problems": {
    "winners-merge-pp-view": {"count": 1, "rounds": [1]}
  }
}
```

## 已废弃的"停下报告用户"设计

> ⚠️ 历史设计：同问题 3 次 / codex 卡死 3 次时停下问用户。
>
> **已废弃**（与铁律 1/9 冲突 — 用户明确反馈"不要一直找询问询问"）。现在全部走"自动写 state.unresolved[] + 继续"，**永远不停下，绝不调 gh**。
>
> Phase 6 完成时 state.json 标 `phase: 6, status: "done"`，即使有未修 finding 也不算失败 — 由 issue 跟踪 + 测试阶段反馈驱动后续修复。
