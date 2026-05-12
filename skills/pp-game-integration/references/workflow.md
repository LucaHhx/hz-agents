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

## Phase 0 — 自动选 base 分支（**完全无人值守**）

**入口**：fresh start（无 state.json）。

**动作**：直接调脚本，不再问用户。脚本按以下优先级自动选 base：

```bash
bash $SKILL_DIR/scripts/init_state.sh <tableId>
# 可选环境变量覆盖：PP_BASE_BRANCH=live-dev bash ... <tableId>
# 可选位置参数覆盖：bash ... <tableId> <override_base>
```

优先级链（首个命中即选）：
1. **resume-from-state**：已有 `state.base_branch`（恢复点继续）
2. **env-PP_BASE_BRANCH**：环境变量 `$PP_BASE_BRANCH`
3. **current-branch-whitelisted**：当前 git branch 在白名单内（`live` / `live-dev` / `dev` / `pre`）
4. **whitelist-fallback**：依次试 `live` → `live-dev` → `dev` → `pre`，取首个真实存在的
5. **fail-closed**：都不存在 → 写 `state.status=failed`、`failure_reason=no-usable-base-branch`，exit 2

脚本同时初始化新字段（首次创建时）：

```jsonc
{
  "base_branch_selection": {"reason": "...", "picked_at": "..."},
  "codex_decisions":   [],
  "codex_discussions": [],
  "codex_budget_guard": {"decision_calls": 0, "discussion_rounds": 0, "max_discussion_rounds_per_trigger": 3},
  "unresolved":        [],
  "already_registered": false
}
```

**过渡**：自动 Phase 1（status=done）；fail-closed 时整个流程结束。

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

**决策点处理**（铁律 1：无人值守，全自动）：
| 情况 | 处理 |
|---|---|
| `pp_tables.py` 退出非 0 | retry 1 次；再失败写 `state.status=failed` + `failure_reason="lobby-launch-failed"` + 结束 |
| `minBalanceToPlay > 6000` | **直接 exit**（用户硬规则，铁律 4）+ `state.status=failed` + `failure_reason="balance-cap-6000"` |
| factory 已注册同 tableId | **自动 skip-this-table**：**只写** `tmp/<tableId>/state.json`（`already_registered=true` / `status=skipped` / `skip_reason="factory-already-registered"` / `experience_doc_path` 指向已存在的同 tableId 经验文档）；**不创建 worktree、不修改 docs/integration-experience/、不跑 Phase 2-8**（铁律 8：仅 worktree 内才能改文档；skip 路径无 worktree，因此不动文档）；流程结束 |
| lobby JSON 缺 operatorGameId 或 gameType | 写 `state.status=failed` + `failure_reason="lobby-missing-required-fields"` + 结束（DGA 订阅必需）|

**过渡**：成功 → 自动 Phase 2；skip / failed → 流程结束（不报错，由调用方读 state 判断）。

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
3. 查 docs/integration-experience/<gametype>/*.md 对照已有先例（如 dict 错误码值跟既有不一致 → 不直接 exit；走"冲突沟通"流程）
4. 写 state.agent_outputs

**决策点处理**：见 [parallel-team.md](parallel-team.md) 各 agent 的失败处理。

**🤝 冲突沟通**（codex 沟通模式 — Phase 3 触发点）：
当 5 个 agent 产出互相矛盾、`message.json` 与 `main.js` 字面量解释冲突、或重启单个 agent 后仍不一致：

```bash
# 首轮（新会话）
bash $CODEX_COLLAB/scripts/codex_discuss.sh \
  -d "$REPO_ROOT" \
  --round 1 --max-rounds 3 \
  -l "phase3-conflict-<short_id>" \
  -- "<把冲突点 + 涉及文件路径 + 各 agent 不同结论喂进来>"

# 抓输出里的 THREAD_ID=...，写入 state.codex_discussions[<id>].thread_id
# 后续轮 resume：
bash $CODEX_COLLAB/scripts/codex_discuss.sh \
  -t "<thread_id>" \
  --round N --max-rounds 3 \
  -- "<下一轮追问>"
```

**退出条件**：codex 回复中含 `discussion_status: closing` → 写 state.codex_discussions[id].status="closed" + summary；或 `discussion_status: unresolved` / 达 3 轮仍 in-progress → 写 `state.unresolved[]`（category="codex-discuss-no-converge"）+ Claude 按 fail-closed（最保守的 agent 结论）继续。

**过渡**：5 agent 全部成功（含冲突收敛后） → 自动 Phase 4。

---

## Phase 4 — 协议设计（**必含 §客户端-后端一致性矩阵 + §历史链路审查**）

**入口**：state.phase = 3 done。

**必读输入**（写 design.md 前主 Claude 读全）：
- 5 agent 产出（含 agent-3 ui_rules.md 的 §矩阵预产出 + agent-2 http_diff.md 的 §history-prelim 节）
- **`<repo>/docs/integration-experience/common/client-rules-analysis.md`**（§2 4 类规则 + §4 矩阵输出格式）
- **`<repo>/docs/integration-experience/common/history-display-analysis.md`**（§2 5 步分析 + §3 落盘字段清单 + §5 输出格式）
- `<repo>/docs/integration-experience/<gametype>/*.md`（同 gametype 先例）— 至少读最近一篇看节号约定
- references/{protocol-decision-table.md, frame-synthesis.md, known-pitfalls.md}

**动作**：主 Claude 写 `<repo>/tmp/<tableId>/design.md`，**必含**（顺序按下表）：

| § | 必含内容 | 来源 |
|---|---|---|
| 1 | 机台元信息总览 | lobby.json |
| 2 | 协议处理决策表 — 每事件 pass/drop/rewrite + 理由 | protocol-decision-table.md |
| 3 | 服务端→客户端帧合成清单 | frame-synthesis.md |
| 4 | HTTP 接口缺口分析 | agent-2 http_diff.md |
| 5 | 测试覆盖计划 | test-design-guide.md |
| 6 | 预期跳过的项目级问题 | project-level-skips.md |
| **7** | **客户端-后端一致性矩阵**（4 类 A 限额 / B 派彩封顶 / C bet code / D UI 状态机；按 client-rules-analysis.md §4 完整模板；后端 enforce 列必须实际 grep server 填实，**不允许写"待 Phase 5 worker 实现时再查"**）| **client-rules-analysis.md + agent-3 矩阵预产出** |
| **8** | **历史链路审查**（5 类 endpoint 实现状态 + 详情 XML 字段映射表 + 落盘字段清单 §3 三个表逐项 ✅/❌ + 单测覆盖清单；按 history-display-analysis.md §5 完整模板）| **history-display-analysis.md + agent-2 §history-prelim** |
| 9 | worker 拆分（按缺口大小划 worker-1/2/3/4） | 综合 |

**§7 §8 必须在 Phase 4 完整产出**（之前的设计错误：放到 Phase 8 才补 → codex review 阶段才暴露 history XML parser 缺失 / Description i18n 缺失等真实缺口）。

**决策点处理**：
| 情况 | 处理 |
|---|---|
| 决策无先例 + known-pitfalls.md 也无 | 按 skill 设计原则自主决定（不停下问用户）|
| 决策与 docs/integration-experience/ 同 gametype 不一致 | 在 design.md 注明"为什么本机台特殊" |
| HTTP 接口缺口 → worker-3 是否需要 | http_diff.md 有任意 missing/mismatched/field-gap → 调 codex 决策（见下"决策模式"）|
| §7 矩阵发现 P0 缺口（客户端承诺、后端无 enforce） | 调 codex 决策（worker 修 vs 写 unresolved[]） |
| §8 历史链路发现 baccarat/<gametype> XML parser 缺失 | 同上：调 codex 决策 |

**🤖 决策模式**（codex 决策点 — Phase 4 触发）：
当遇到 (a) 协议处理 pass/drop/rewrite 选择不确定，(b) HTTP/history 缺口分流，(c) §7/§8 P0 缺口处理，调用 codex_decide.sh 一次性决策：

```bash
bash $CODEX_COLLAB/scripts/codex_decide.sh \
  -d "$REPO_ROOT" \
  -l "phase4-decide" \
  -- "$(cat <<EOF
## 背景
gameType: <gametype> / tableId: <tableId>
设计草稿：tmp/<tableId>/design.md（已写到 §X）
关联文件：tmp/<tableId>/{dict.json, http_diff.md, ui_rules.md, lifecycle.md}
经验先例：docs/integration-experience/<gametype>/

## 决策点
决策 1：<具体问题，如 "winners 字段是 pass / drop / rewrite-merge"，列候选 + 判断标准>
决策 2：<下一个问题，如 "HTTP /history 接口本轮启 worker-3 还是写 unresolved[]"，列候选 + 判断标准>
EOF
)"
```

**写回**：把 codex 输出的每个决策块解析为 `state.codex_decisions[]` 的一条记录（id/phase=4/timing/question/options/selected/rationale/inputs/written_to/created_at），并把决策结果同步进 design.md 第 2/4/7/8 节的"依据"列。

**🤝 沟通模式**（design 草稿空洞 — Phase 4 触发）：
当 design.md 出现 `?` / `待确认` / `无先例` 关键空洞，且影响 worker 范围：

```bash
bash $CODEX_COLLAB/scripts/codex_discuss.sh \
  -d "$REPO_ROOT" \
  --round 1 --max-rounds 2 \
  -l "phase4-design-gap" \
  -- "<贴 design.md 当前草稿 + 具体空洞条目 + 备选方向>"
```

**退出条件**：codex `discussion_status: closing` 给出"补哪些 worker / 哪些写 unresolved[] / 哪些跳过" → 写 state + 更新 design.md；`unresolved` 或达 2 轮 → Claude 按资金安全优先自行落判 + 写 state.unresolved[]。

**fallback**：codex_decide.sh / codex_discuss.sh 超时 / 不可解析 → Claude 按 known-pitfalls.md + design 默认规则决策 + 写 state.unresolved[]（category="codex-script-failed"）。

**过渡**：design.md 写完（含完整 §7 §8）→ 自动 Phase 5（**不审，不询问用户**）。

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
| worker 启动前路径不确定（A "复用同类机台结构" vs B "抽公共 helper"） | 调 codex_decide.sh 一次性决策（见下） |
| worker 卡 ≥10min 无有效 diff / 失败 ≥2 次 | 调 codex_discuss.sh 多轮根因（见下，≤3 轮）|
| 单 worker 失败首次 | git reset --hard worktree-base + 重启该 worker |
| 单文件 > 500 行 | 按职责自由拆（参考 docs/integration-experience/ 同类先例的拆分模式）|

**🤖 决策模式**（worker 路径选择 — Phase 5 触发）：

```bash
bash $CODEX_COLLAB/scripts/codex_decide.sh \
  -d "$REPO_ROOT" \
  -l "phase5-worker-path" \
  -- "## 背景
worker: <worker-N>
design.md 第 9 节: <复制相关段>
同 gametype 先例: <列文件路径 + 一句话差异>

## 决策
决策 1：worker 路径 A "复用 <gametype> 既有结构" vs B "抽到 common 新 helper"
判断标准：A 改动 ≤50 行 / 不影响其他机台 → 优选；B 涉及 ≥2 机台联动 → 必须先写 unresolved[] 不实施"
```

**🤝 沟通模式**（worker 卡死 — Phase 5 触发，≤3 轮）：

```bash
bash $CODEX_COLLAB/scripts/codex_discuss.sh \
  -d "$REPO_ROOT" \
  --round 1 --max-rounds 3 \
  -l "phase5-worker-stuck-<worker-N>" \
  -- "worker-<N> 卡 / 失败 2 次。
当前 diff: <git diff 摘要>
失败日志: <最后 50 行>
prompt: <worker prompt 摘要>
请帮诊断根因 + 给出可执行修复路径。"
```

**退出条件**：`discussion_status: closing` → 按 codex 建议执行；`unresolved` 或达 3 轮 → Claude 回退到 git reset 重启 + 写 state.unresolved[]。

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
     - medium 非必要 / large → **追加 `state.unresolved[]`**（铁律 9：禁 issue）+ 经验文档第 15 节摘要标注
3. 跑下一轮；codex 报"无重大问题" → 退出循环

**自动写 unresolved[] 触发条件**（绝不停下问用户，绝不调用 gh issue）：
| 情况 | 处理 |
|---|---|
| codex CLI 卡死 | state.codex_stuck_count++；继续下一轮 |
| codex_stuck_count ≥ 3 | **追加 `state.unresolved[]`**（category="stuck-3-times"）+ 进 Phase 7 |
| 同一问题 hash ≥ 3 次 | **追加 `state.unresolved[]`**（category="repeated-N-times"）+ state.repeated_problems[hash].filed=true + 后续轮跳过 → 继续 |
| 跑满 10 轮仍有未修 finding | **整理剩余 → 追加 `state.unresolved[]`**（category="round-cap-leftover"）→ 进 Phase 7 |
| finding 命中 large 等级 | **追加 `state.unresolved[]`**（category="large-impact"）+ 第 15 节登记 → 不在本 worktree 修 |
| finding 命中 medium 非必要 | **追加 `state.unresolved[]`**（category="medium-non-essential"）+ 第 15 节登记 → 不在本 worktree 修 |

**禁止**：
- ❌ 跑超过 10 轮（硬上限，不可逾越）
- ❌ "停下报告用户" 措辞 — 已与铁律 1 冲突
- ❌ 调用 `gh issue create` / `gh pr create` 等任何仓库协作面操作（铁律 8/9）
- ❌ 把 codex 所有 finding 都修
- ❌ 重复提及已写 unresolved[] 的项目级问题

**过渡**：codex clean / 跑满 10 轮 / stuck 3 次 / 任一终止条件 → 自动 Phase 7（无论是否有未修 finding，由 unresolved[] 跟踪即可）。

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
| 首次 FAIL | Claude 自动诊断 + 修 + 回 Phase 6 跑一轮 codex |
| 失败 ≥2 次 / 失败类型横跨测试-实现-policy 边界 | 调 codex_decide.sh 做根因分类（见下） |
| codex 决策仍不收敛 | 调 codex_discuss.sh 多轮讨论（≤2 轮，见下）|
| cover < 25% | 自动按 [test-design-guide.md](test-design-guide.md) 补单测 |
| policy-pr 报某文件超 500 行 | 自由拆，拆完回 Phase 6 |

**🤖 决策模式**（verify 失败根因分类 — Phase 7 触发）：

```bash
bash $CODEX_COLLAB/scripts/codex_decide.sh \
  -d "$REPO_ROOT" \
  -l "phase7-verify-fail" \
  -- "## 背景
worktree: <worktree_path>
gametype: <gametype> / tableId: <tableId>
verify.sh 失败输出（最后 100 行）：
\`\`\`
<paste>
\`\`\`
最近一轮 codex review 摘要：tmp/<tableId>/codex-output/round-<N>.md

## 决策
决策 1：失败根因分类
候选 A：实现 bug（worker 代码错）
候选 B：测试断言错误（断言与 main.js Up 反查表不一致）
候选 C：policy-pr 拆分问题（单文件超限）
候选 D：设计遗漏（design.md §X 缺）

决策 2：下一步动作
候选 A：回 Phase 6 修代码
候选 B：补/改测试断言
候选 C：拆文件
候选 D：回 Phase 4 修 design"
```

写回 `state.codex_decisions[]` + `state.verify_failures[].decision_id` 关联。

**🤝 沟通模式**（决策仍不收敛 / 失败根因复杂 — Phase 7 触发，≤2 轮）：

```bash
bash $CODEX_COLLAB/scripts/codex_discuss.sh \
  -d "$REPO_ROOT" \
  --round 1 --max-rounds 2 \
  -l "phase7-verify-rootcause" \
  -- "<verify 失败 + 决策模式给出的初步分类 + Claude 自己尝试的修复 / 失败结果>"
```

**退出条件**：`closing` → 按建议回 Phase 6/4 / 拆文件 / 改测试；`unresolved` 或达 2 轮 → 写 `state.unresolved[]`（category="verify-no-converge"）+ 流程进 Phase 8（带未修 finding 归档）。

**过渡**：全 PASS → 自动 Phase 8；2 轮讨论后仍未收敛 → 也进 Phase 8（unresolved 已写）。

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
