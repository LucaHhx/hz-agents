# Phase 6 — 反复 codex review 工作流

## 调用约定

```bash
bash scripts/codex_review_loop.sh <worktree_path> <round_label>
```

脚本封装：
1. 调 `bash <codex-review-skill>/scripts/codex_review.sh -d <worktree_path> -l <round_label>` + PP 专用 prompt（见下）
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

【特别关注】
1. 协议事实正确性（GR 字段反查表 / betCode 表 / 错误码值 / init 顺序与 capture 一致）
2. 结算公式正确性（payout 严格按 Up 反查表 × 押注；不参与字段不结算）
3. 跨 commit 一致性（worker-1 常量 ↔ worker-2 业务调用对齐）
4. 并发与数据一致性（mu 字段保护范围；pendingWins 顺序保证）
5. 错误处理（feedback_no_silent_fallback 铁律；fail-closed）
6. 单测充分性（4 个 capture 样本 + 边注 + 不参与字段忽略断言）
7. 字典 parity 测试是否覆盖
```

### 第 2 轮（agent-2 陷阱防御）

```
【视角】陷阱与安全视角：聚焦 PP 协议特有陷阱、并发竞态、资金流安全。

【关键陷阱清单 — 逐项验证】
1. tableId 字节级替换
2. winners 完全丢弃 PP 测试账号视角
3. 多事件单帧按优先级处理（gameresult 必须先 winners）
4. PP 视角全 drop（bet/bets/win/winningBetCodes/betSpotWin/command/pong）
5. CanBet Redis 异常返回 false
6. ping 单/双引号兼容
7. 空 lpbet 关窗后撤单防御
8. 整批拒清 Redis 仅限非窗口类
9. BC Atoi 错误显式拒绝
10. bets JSON 解析失败跳过用户
11. payout_cap 接入
12. CheckBet 内存 + Redis 双重 fail-closed
13. EnrichBetstats unwrapEnvelope
14. baccarat 不发 winningBetCodes / betSpotWin
```

### 第 3 轮（agent-3 可维护性）

```
【视角】可维护性视角：命名、分层、复杂度、重复代码、可测试性、文档、规范契合度。

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

## 闭环条件

- codex 报"**无重大问题**" → 退出循环 → 进 Phase 7
- 同问题（按 finding 描述前 30 字符 hash 计数）≥ 3 次 → 停下报告用户
- codex CLI 卡死 ≥ 3 次 → 停下报告用户

## 自主分类逻辑

每个 codex finding 按以下规则分类：

```
1. file path 在通用层（server/game/common/handlers/, runtime/, ...）？
   是 → 项目级跳过（不修，记 design.md "已知项目级 #N"）
   否 → 继续 ②

2. 命中 project-level-skips.md 5 项之一？
   是 → 项目级跳过
   否 → 继续 ③

3. file path 在本机台目录（baccarat/<tableId>/ 或 factory）？
   是 → 本机台修
        ├── 写补丁 + commit
        └── 实时记录到 docs/integration-experience/<gametype>/<tableId>.md 第 7 节
   否 → 报告（codex 似乎指向了不该指的范围）
```

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

## 报告用户的格式（停下时）

### 同问题 3 次

```
⚠️ Phase 6 停下：同一问题第 3 次出现，设计可能有根本错误

问题：<问题 hash 描述>
出现轮次：1 / 3 / 5
当前修复策略：<前两次怎么修的>
建议：人工 review 该问题的根本设计假设。

state.json 路径：tmp/<tableId>/state.json
worktree：<worktree_path>
```

### codex 卡死 3 次

```
⚠️ Phase 6 停下：codex CLI 第 3 次卡死

可能原因：
- read-only sandbox 与 ~/.codex/sessions 写入冲突
- prompt 过长导致 codex 启动慢
- 网络异常导致 codex 无法访问 OpenAI API

建议：
- 检查 codex 进程：`ps aux | grep codex`
- 重启 codex / 重置 sandbox
- 简化 prompt 重试

state.json 路径：tmp/<tableId>/state.json
已闭环 N 轮：<前 N 轮的关键 findings>
```
