# 9 Phase 工作流详细指引

每个 phase 的入口/产出/决策点/异常处理。**新 Claude 实例**按本文档应能独立完成对接。

## 环境前提（skill 触发时第一步**必须**确认）

```bash
# 1. 在 pp-game 仓库根（git rev-parse 能找到 server/ 目录）
git rev-parse --show-toplevel | xargs -I {} test -d {}/server || { echo "❌ 不在 pp-game 仓库"; exit 1; }

# 2. 必备 CLI
command -v jq          >/dev/null || { echo "❌ 缺 jq"; exit 1; }
command -v node        >/dev/null || { echo "❌ 缺 node"; exit 1; }
command -v python3     >/dev/null || { echo "❌ 缺 python3"; exit 1; }
command -v go          >/dev/null || { echo "❌ 缺 go"; exit 1; }

# 3. Playwright（fetch_client.mjs 依赖）
node -e "import('playwright')" 2>/dev/null || { echo "❌ Playwright 未装：npm install -g playwright && npx playwright install chromium"; exit 1; }

# 4. codex CLI（Phase 6 依赖）
command -v codex       >/dev/null || echo "⚠️  codex CLI 未装，Phase 6 将卡住"

# 5. luca.sh（bc.game 认证）
test -f scripts/luca.sh || { echo "❌ 缺 scripts/luca.sh"; exit 1; }
```

新 Claude 触发时第一步：cd 到 pp-game 仓库根 + 运行上述 5 项检查。

## 状态持久化（state.json）

每个 phase 完成时写入 `<repo>/tmp/<tableId>/state.json`：

```json
{
  "tableId": "bcpirpmfpeobc199",
  "repo_root": "/path/to/pp-game",
  "phase": 1,
  "status": "done",
  "base_branch": "live",                     // Phase 0 选择
  "lobby": { /* Phase 1 lobby json */ },
  "capture_dir": "tmp/<tableId>",
  "main_js": "tmp/<tableId>/clientResources/apps/.../main.js",
  "message_json": "tmp/<tableId>/message.json",
  "frame_count": 1004,
  "agent_outputs": {                         // Phase 3 输出（5 agent）
    "agent_1_dict": "tmp/<tableId>/dict.json",
    "agent_2_http": "tmp/<tableId>/http_endpoints.json",
    "agent_2_diff": "tmp/<tableId>/http_diff.md",
    "agent_3_ui":   "tmp/<tableId>/ui_rules.md",
    "agent_4_state": "tmp/<tableId>/state_machines.md",
    "agent_5_lifecycle": "tmp/<tableId>/lifecycle.md"
  },
  "design_md_path": "tmp/<tableId>/design.md",
  "worktree_path": "/path/to/pp-game/.worktrees/<branch>",
  "worktree_branch": "worktree/live/<gametype>-<tail>",
  "codex_rounds": [
    {"round": 1, "label": "agent-1", "findings": 5, "fixed": 5, "ts": "..."}
  ],
  "codex_stuck_count": 0,
  "repeated_problems": {},
  "experience_doc_path": "<repo>/docs/integration-experience/<gametype>/<tableId>.md",
  "last_updated": "<ISO ts>"
}
```

**触发恢复**：每次 skill 触发先 `cat <repo>/tmp/<tableId>/state.json`：
- 不存在 → fresh start，从 Phase 0 开始
- 存在 → 跳到 `phase + 1` 继续；`status == "failed"` 则从该 phase 重试

---

## Phase 0 — 询问主分支（**唯一主动交互**）

**入口**：fresh start（无 state.json）。

**动作**：
1. 跑 `git -C <repo_root> branch --list` 取本地分支
2. 用 `AskUserQuestion` 询问 base 分支：

```
question: "对接基于哪个主分支创建 worktree？"
header:   "Base 分支"
options:
  - label: "live"           description: "当前生产分支（推荐 — 默认；机台对接通常合到这里）"
  - label: "live-dev"       description: "线上开发分支"
  - label: "dev"            description: "主开发分支"
  - label: "pre"            description: "预发布分支（一般不直接基于这里）"
```

如本地无 live 分支（用户在别的分支工作）→ `--list` 自然不会有 → 走 fallback：让用户自由选当前任意分支。

**写 state**：
```bash
bash $SKILL_DIR/scripts/init_state.sh <tableId> <用户选择的 base>
```
脚本会校验 base 真实存在 + 创建 `tmp/<tableId>/state.json` + `mkdir -p docs/integration-experience/`。

**过渡**：自动 Phase 1。

---

## Phase 1 — lobby 元信息 + 6000 卡门槛 + factory 已注册检测

**入口**：state.phase = 0 done。

**动作**：
```bash
bash $SKILL_DIR/scripts/lobby_launch.sh <tableId>
```
脚本内部：
1. 调 `python3 <repo>/scripts/pp_tables.py --launch <tableId> --curl-file <repo>/scripts/luca.sh`
2. 解析 lobby JSON 写到 `<repo>/tmp/<tableId>/lobby.json`
3. 提取关键字段：`gameType / gameLoaderKey / operatorTheme / operatorGameId / limits.{min,max,minBalanceToPlay}`
4. **6000 硬卡**：`minBalanceToPlay > 6000` → exit 1 + 报告
5. **factory 检测**：grep `<repo>/server/game/pp/internal/factory/instance_factory.go` 是否含 tableId → 已注册 → exit 2 + 报告
6. 写 state.json (phase=1, status=done, lobby={...})

**决策点处理**：
| 情况 | 处理 |
|---|---|
| `pp_tables.py` 退出非 0 | retry 1 次；再失败 exit + 报告 |
| `minBalanceToPlay > 6000` | **直接 exit**（用户硬规则）|
| factory 已注册同 tableId | **exit + 报告**（用户决定重新对接 / 查询经验 / 退出，唯一一处停下询问的边界场景）|
| lobby JSON 缺 operatorGameId 或 gameType | exit + 报告（DGA 订阅必需）|

**过渡**：成功 → 自动 Phase 2。

---

## Phase 2 — 抓 capture（fetch_client.mjs）

**入口**：state.phase = 1 done。

**动作**：
```bash
bash $SKILL_DIR/scripts/fetch_capture.sh <tableId> [duration_min]   # 默认 5
```
脚本内部：
1. 调 `node <repo>/scripts/game_dev/fetch_client.mjs <tableId> --output <repo>/tmp`
2. 检查产物：
   - `<repo>/tmp/<tableId>/clientResources/apps/<gameType>/<version>/main.js` 存在
   - `<repo>/tmp/<tableId>/message.json` 存在 + 帧数 ≥ 200
3. 检查关键事件出现：`betsopen` / `betsclosed` / `gameresult` / `winners` 各 ≥ 1 帧
4. 写 state.json (phase=2 done, main_js=..., message_json=..., frame_count=N)

**重要**：fetch_client.mjs **只录**：
- 客户端静态资源（pragmaticplaylive CDN + .js/.json/.html）→ `clientResources/`
- 游戏 WS 上游消息（framereceived）→ `message.json`

**不录** HTTP API 流量（cgi-bin / api/ui/* 不抓 HAR）→ Phase 3 agent-2 用纯静态分析（详见 [http-analysis.md](http-analysis.md)）。

**决策点处理**：
| 情况 | 处理 |
|---|---|
| fetch 退出非 0 | retry 1 次；再失败 exit |
| 缺关键事件 | DURATION_MS=10 重抓（最多 1 次）；再不到 → 进 Phase 3 让 agent-5 反推（main.js 可能能找到）|
| `apps/<gameType>/` 多版本 | 选最新（按目录字典序末位）|

**过渡**：成功 → 自动 Phase 3。

---

## Phase 3 — 客户端深度分析（**5 agent 并行**）

**入口**：state.phase = 2 done。

**动作**：按 [parallel-team.md](parallel-team.md) 启动 **5 个 general-purpose subagent 在同一条消息中并行**（不是顺序）。

| Agent | 输入 | 输出 |
|---|---|---|
| agent-1 协议字典 | main.js | tmp/<tableId>/dict.json |
| agent-2 HTTP 接口 | main.js + clientResources chunks + server/api/v1/ | tmp/<tableId>/http_endpoints.json + tmp/<tableId>/http_diff.md |
| agent-3 UI/投注规则 | main.js | tmp/<tableId>/ui_rules.md |
| agent-4 决策/状态机 | main.js | tmp/<tableId>/state_machines.md |
| agent-5 上游消息生命周期 | message.json + main.js | tmp/<tableId>/lifecycle.md |

**主 Claude 整合职责**：
1. 等 5 个 agent 全部返回（asyncio）
2. 验证产出文件存在
3. 查 docs/integration-experience/<gametype>/*.md 对照已有先例（如 dict 错误码值跟既有不一致 → exit）
4. 写 state.agent_outputs

**决策点处理**：见 [parallel-team.md](parallel-team.md) 各 agent 的失败处理。

**过渡**：5 agent 全部成功 → 自动 Phase 4。

---

## Phase 4 — 协议设计（含 HTTP 缺口）

**入口**：state.phase = 3 done。

**动作**：基于 5 agent 输出 + docs/integration-experience/ 先例，主 Claude 写 `<repo>/tmp/<tableId>/design.md`，必含：

1. **机台元信息总览**（lobby + 协议事实）
2. **协议处理决策表** — 对每个事件标 pass/drop/rewrite + 理由（参考 [protocol-decision-table.md](protocol-decision-table.md)）
3. **服务端→客户端帧合成清单** — 哪些必须自合成（参考 [frame-synthesis.md](frame-synthesis.md)）
4. **HTTP 接口缺口分析**（来自 agent-2 的 http_diff.md）
   - missing endpoints — 必须新增
   - path mismatched — 必须改 router
   - field gap — 必须补字段
   - 机台特殊数据 — 加机台分支
5. **测试覆盖计划** — 按 [test-design-guide.md](test-design-guide.md)
6. **预期跳过的项目级问题** — 引用 [project-level-skips.md](project-level-skips.md)

**决策点处理**：
| 情况 | 处理 |
|---|---|
| 决策无先例 + known-pitfalls.md 也无 | 按 skill 设计原则自主决定（不停下问用户）|
| 决策与 docs/integration-experience/ 同 gametype 不一致 | 在 design.md 注明"为什么本机台特殊" |
| HTTP 接口缺口 → worker-3 是否需要 | http_diff.md 有任意 missing/mismatched/field-gap → 必须加 worker-3 HTTP（Phase 5）|

**过渡**：design.md 写完 → 自动 Phase 5（**不审，不询问用户**）。

---

## Phase 5 — worktree + worker 实现

**入口**：state.phase = 4 done。

**动作**：直接 bash 调用 worktree-task-flow skill 的 init 脚本（**绕过它的 brainstorming 阶段**，因为 design.md 已写好）：

```bash
bash /Users/luca/.claude/skills/worktree-task-flow/scripts/init-worktree.sh \
    "$(jq -r .base_branch tmp/<tableId>/state.json)" \
    "$(jq -r .lobby.gameType tmp/<tableId>/state.json)-$(echo <tableId> | tail -c 9)"
# 输出含 worktree_path / branch / worktree_base / target_base
```

记录到 `state.worktree_path` / `state.worktree_branch`。

**worker 拆分**（按 design.md + http_diff.md）：

| Worker | 文件 | 验收 | 启用条件 |
|---|---|---|---|
| worker-1 骨架 | enum.go / models.go / processor.go / instance.go | go build 过 | 必启用 |
| worker-2 业务 | upstream_*.go / downstream_*.go / bet_*.go / settle.go / payout.go | build/vet/test/policy-pr 全过 + payout 单测 | 必启用 |
| **worker-3 HTTP 接口** | server/api/v1/<相关>/handler.go + router 注册 + service 改动 | 新增 HTTP 接口 build 过 + 客户端能访问 | **仅 http_diff 有缺口时启用** |
| worker-4 注册 | factory/instance_factory.go | build 全过 | 必启用 |

**worker 启动方式**：见 [worker-prompts.md](worker-prompts.md) — 4 个 worker 完整 prompt 模板（含通用约束 + 各 worker 任务范围 + B5 验收契约）。主 Claude 用 jq 读 state.json 字段替换占位符后通过 Agent tool 启动 general-purpose subagent，**串行**执行（一个完成验收后才启下一个）。**不进** worktree-task-flow 的 brainstorming/squash/PR gate。

**决策点处理**：
| 情况 | 处理 |
|---|---|
| worker 失败 | git reset --hard worktree-base + 重启该 worker |
| 单文件 > 500 行 | 按职责自由拆（参考 docs/integration-experience/ 同类先例的拆分模式）|

**过渡**：worker 全部 commit → 自动 Phase 6。

---

## Phase 6 — codex review（**硬上限 10 轮，绝不停下**）

**入口**：state.phase = 5 done。

**动作**：循环（**最多 10 轮**）：
```bash
WT=$(jq -r .worktree_path tmp/<tableId>/state.json)
BASE=$(jq -r .base_branch tmp/<tableId>/state.json)
bash $SKILL_DIR/scripts/codex_review_loop.sh "$WT" "round-N" "$BASE"
```
**注意**：`codex_review_loop.sh` 是 **AI 包装器**（非确定性），它内部调 codex CLI 做 AI 推理。该脚本会自动更新 `state.codex_rounds[]` / `state.codex_stuck_count`。

**循环逻辑**（按 SKILL.md §自主决策矩阵 + [codex-review-loop.md](codex-review-loop.md) 三步分流）：
1. 跑 codex review，提取 🔴 / 🟡 / 🟢 findings
2. 主 Claude 对每个 finding 自主三步分流：
   - **Step 1 项目级跳过判断** — 命中则跳过 + 第 1 次提及时记入经验文档第 10 节
   - **Step 2 影响范围分级** — small / medium-资金必要 / medium-非必要 / large
   - **Step 3 执行**：
     - small → 立即修 + commit + 经验文档第 7 节实时记录
     - medium 资金必要 → 修
     - medium 非必要 / large → **`gh issue create` + 经验文档第 15 节"follow-up issue 列表"**
3. 跑下一轮；codex 报"无重大问题" → 退出循环

**自动建 issue 触发条件**（绝不停下问用户）：
| 情况 | 处理 |
|---|---|
| codex CLI 卡死 | state.codex_stuck_count++；继续下一轮 |
| codex_stuck_count ≥ 3 | **自动 `gh issue create`**（标题"codex CLI 环境异常 — Phase 6 卡死 3 次"）+ 进 Phase 7 |
| 同一问题 hash ≥ 3 次 | **自动 `gh issue create`** + state.repeated_problems[hash].auto_filed=true + 后续轮跳过 → 继续 |
| 跑满 10 轮仍有未修 finding | **整理剩余 → 自动 `gh issue create`** → 进 Phase 7 |
| finding 命中 large 等级 | **立即 `gh issue create`** + 第 15 节登记 → 不在本 PR 修 |
| finding 命中 medium 非必要 | **`gh issue create`** + 第 15 节登记 → 不在本 PR 修 |

**禁止**：
- ❌ 跑超过 10 轮（硬上限，不可逾越）
- ❌ "停下报告用户" 措辞 — 已与铁律 1/9 冲突
- ❌ 把 codex 所有 finding 都修
- ❌ 重复提及已建 issue 的项目级问题

**过渡**：codex clean / 跑满 10 轮 / stuck 3 次 / 任一终止条件 → 自动 Phase 7（无论是否有未修 finding，由 issue 跟踪即可）。

---

## Phase 7 — 全量验收

**入口**：state.phase = 6 done。

**动作**：
```bash
WT=$(jq -r .worktree_path tmp/<tableId>/state.json)
GT=$(jq -r .lobby.gameType tmp/<tableId>/state.json)
BASE=$(jq -r .base_branch tmp/<tableId>/state.json)
bash $SKILL_DIR/scripts/verify.sh "$WT" "$GT" <tableId> "$BASE"
```
脚本内部：
1. `cd <worktree>/server && go build ./...`
2. `go vet ./game/pp/internal/games/<gametype>/...`（无新增 warning）
3. `go test -race -count=3 ./game/pp/internal/games/<gametype>/<tableId>/...`
4. `go test -cover` ≥ 25%
5. `git diff --name-only --diff-filter=ACMR <base>..HEAD | node scripts/ci/policy-pr.mjs --stdin`

**决策点处理**：
| 情况 | 处理 |
|---|---|
| 任一 FAIL | 自动诊断 + 修 + 回 Phase 6 跑一轮 codex |
| cover < 25% | 自动按 [test-design-guide.md](test-design-guide.md) 补单测 |
| policy-pr 报某文件超 500 行 | 自由拆，拆完回 Phase 6 |

**过渡**：全 PASS → 自动 Phase 8。

---

## Phase 8 — 经验文档归档

**入口**：state.phase = 7 done。

**动作**：
```bash
bash $SKILL_DIR/scripts/archive_experience.sh <tableId> --backup
```
脚本写经验文档骨架到 `<worktree>/docs/integration-experience/<gametype>/<tableId>.md`（**worktree 内**，与机台代码一起 commit）。state 标 `status=skeleton-generated`，主 Claude 填充 13 节后改 `status=done`。
脚本生成 `<repo>/docs/integration-experience/<gametype>/<tableId>.md` 13 节骨架（来自 [experience-doc-structure.md](experience-doc-structure.md)），主 Claude 按以下来源**填充**每节：

| 节 | 来源 |
|---|---|
| 1. 机台基本信息 | state.lobby |
| 2. 协议事实速查 | state.agent_outputs.agent_1_dict |
| 3. 生命周期 | state.agent_outputs.agent_5_lifecycle |
| 4. 字典 | state.agent_outputs.agent_1_dict |
| 5. 协议处理决策表 | tmp/<tableId>/design.md 第 2 节 |
| 6. 服务端→客户端帧合成 | tmp/<tableId>/design.md 第 3 节 |
| 7. 遇到的问题 + 解决方案 | Phase 6 实时累积的 codex finding 修复记录 |
| 8. 资金安全清单 | 按 [known-pitfalls.md](known-pitfalls.md) 检查每项 |
| 9. 测试策略 | state.worktree_path 内的测试文件 |
| 10. 项目级跳过项 | tmp/<tableId>/design.md 第 6 节 |
| 11. 与其他机台对比 | docs/integration-experience/<gametype>/*.md 已有 |
| 12. 部署前 checklist | state.lobby + 默认 b_tables SQL 模板 |
| 13. 必看注意事项 | 总结本次 Phase 6 学到的新坑 |

**附加动作**：
- 更新 `<repo>/docs/integration-experience/README.md` 索引
- commit 到 worktree（`docs(integration-experience): <gametype>/<tableId> 对接经验`）
- 写 state.json (phase=8 status=done)

**过渡**：完成 → 报告用户。

---

## 完成报告模板

```
✅ <gametype>/<tableId> 对接完成

worktree:    worktree/<base>/<gametype>-<tail>
commits:     N
新增文件:     N
测试覆盖率:   X.X%
codex 轮数:   N（直到"无重大问题"）
HTTP 接口改动: M（新增 X / 修改 Y / 字段补 Z）
跳过项:      P 项项目级
经验文档:    docs/integration-experience/<gametype>/<tableId>.md

未做：PR / 部署（铁律 8：用户决定时机）
```
