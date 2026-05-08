# Phase 3 — 5 个并行 agent 启动模板

## 目录

- [占位符替换（必读）](#占位符替换必读)
- [通用约束（每个 agent prompt 都注入）](#通用约束每个-agent-prompt-都注入)
- [agent-1 协议字典](#agent-1-协议字典)
- [agent-2 HTTP 接口](#agent-2-http-接口)
- [agent-3 UI / 投注规则](#agent-3-ui--投注规则)
- [agent-4 决策 / 状态机](#agent-4-决策--状态机)
- [agent-5 上游消息生命周期](#agent-5-上游消息生命周期)
- [主 Claude 整合](#主-claude-整合)

## 重要约束

- **必须并行** — 同一消息发 5 个 Agent tool 调用（不是顺序 5 次）
- **每个 agent 独立** — 自己读 main.js / 自己 grep / 自己写输出文件
- **每个 agent 不写代码** — 只产出分析文件（json / md）
- **每个 agent 失败不阻塞别的** — 主 Claude 整合时按缺失项重启该 agent

---

## 占位符替换（必读）

启动 5 个 agent 前，主 Claude **必须**用 `jq` 从 `state.json` 读出实际值，把 prompt 模板里的 `<...>` 占位符全部字符串替换成真实值。**不能直接把模板原样发给 subagent**（会把字面量 `<repo_root>` 当目录名找）。

```bash
SKILL_DIR=<由 SKILL.md 触发后第一步导出的环境变量>
STATE_JSON=$REPO_ROOT/tmp/$TABLE_ID/state.json

REPO_ROOT=$(jq -r .repo_root "$STATE_JSON")
TABLE_ID=$(jq -r .tableId "$STATE_JSON")
GAMETYPE=$(jq -r .lobby.gameType "$STATE_JSON")
MAIN_JS=$(jq -r .main_js "$STATE_JSON")
MESSAGE_JSON=$(jq -r .message_json "$STATE_JSON")
CAPTURE_DIR="$REPO_ROOT/tmp/$TABLE_ID"
```

把 prompt 里的下列占位符全部替换：
- `<skill_dir>` → `$SKILL_DIR`
- `<repo_root>` → `$REPO_ROOT`
- `<tableId>` → `$TABLE_ID`
- `<gametype>` → `$GAMETYPE`
- `<main_js_path>` → `$MAIN_JS`
- `<message_json_path>` → `$MESSAGE_JSON`
- `<capture_dir>` → `$CAPTURE_DIR`

替换后才能作为 Agent tool 的 `prompt` 参数。

---

## 通用约束（每个 agent prompt 都注入）

```
你是 PP 机台对接 Phase 3 的 agent-N。**只产出分析文件，不写代码**。

skill 路径: <skill_dir>
仓库根: <repo_root>
机台 ID: <tableId>
gameType: <gametype>

铁律:
1. 不修改任何代码
2. 不读取 /Users/luca/work/ppgame 老项目
3. 只读当次 capture（main.js / message.json / clientResources）
4. 输出文件必须落到指定位置
5. 失败时 stderr 输出"agent-N: <错误描述>"+ 写空文件到输出位置
6. **必读项目内方法论 + 既有经验**（按 agent 职责选）：
   - `<repo_root>/docs/integration-experience/common/client-rules-analysis.md` — 客户端规则分析方法论（4 类规则矩阵；agent-3 必读）
   - `<repo_root>/docs/integration-experience/common/history-display-analysis.md` — 历史链路分析方法论（5 类入口 + XML parser；agent-2 必读）
   - `<repo_root>/docs/integration-experience/<gametype>/*.md` — 同 gametype 已有先例（任一 agent 都应读，作为字段命名 / 协议偏差对照）
   - `<repo_root>/docs/integration-experience/<其他 gametype>/<最近一次>.md` — 跨 gametype 参考（首次对接同 gametype 时尤其重要，看相邻协议家族实测）

**事先列出已读文件**：在产出文件开头一段写"📚 参考来源"列出实际读了的方法论文档 + 经验文档，便于后续审查溯源。
```

---

## agent-1 协议字典

```
<通用约束>

输入文件:
  - main.js: <main_js_path>
  - message.json: <message_json_path>
  - 既有先例: <repo_root>/docs/integration-experience/<gametype>/

输出文件: <capture_dir>/dict.json

任务:
1. 跑 `bash <skill_dir>/scripts/grep_client_dict.sh <capture_dir>` 生成 dict.json
2. 验证 dict.json 完整性:
   - betcodes 数量 3-50 之间
   - error_codes 至少 10 项
   - upstream_events 含 betsopen/betsclosed/gameresult/winners
   - lpbet_format.gm_pattern 是动态拼接（非字面量）
3. 跨机台一致性检查:
   - 与既有 docs/integration-experience/<gametype>/*.md 已有错误码值对比，**任意不一致都是硬错误**（PP 协议级稳定）
4. 输出 dict.json 完整内容到 stdout 末尾

格式参考: <skill_dir>/references/client-analysis.md
失败处理: 写空 {} 到输出文件 + stderr 输出"agent-1: <错误描述>"
```

---

## agent-2 HTTP 接口（含 history endpoint **预审查**）

```
<通用约束>

输入:
  - main.js: <main_js_path>
  - clientResources 全部 .js chunks: <capture_dir>/clientResources/apps/**/*.js
  - server 现有路由: <repo_root>/server/api/v1/
  - **必读方法论**: <repo_root>/docs/integration-experience/common/history-display-analysis.md（§1.1 5 类历史入口 + §2 分析步骤）

输出:
  - <capture_dir>/http_endpoints.json
  - <capture_dir>/http_diff.md（**新增 §history-prelim 节**：5 类历史入口客户端调用情况）

**铁律**: 禁止凭空假设 PP 客户端会用某 endpoint。所有 endpoint 必须**从 main.js 字面量或调用代码反推**。详见 <skill_dir>/references/http-analysis.md。

任务:
1. grep main.js + clientResources/**/*.js 内**所有** fetch / axios / XMLHttpRequest 调用
2. 提取每个调用的 URL（含动态拼接的 base + path）
3. 反推请求参数 + 响应字段（从 .then(r => r.foo) 之类的代码里看读了哪些字段）
4. 列出 server/api/v1/ 现有路由（grep 路由文件）
5. 对比客户端清单 vs server 清单，输出 http_diff.md:
   - missing endpoints（客户端调用但 server 没注册）
   - path mismatched（路径不一致）
   - field gap（响应字段缺）
   - 机台特殊数据（同 endpoint 但本机台需要不同字段）
6. **history endpoint 预审查**（按 history-display-analysis.md §1.1）：grep 5 类入口在 main.js 中的命中情况
   - /api/ui/history/{summary,dayWise}
   - /cgibin/.../audit/game.jsp
   - /api/ui/statisticHistory
   - /api/fetchRoundHistory / /v2/fetchRoundHistoryByWS
   - 机台特殊 endpoint
   并对每项标 ✅命中 / ❌未命中 / ⚠️待确认；后端 grep 实现状态（GameHistorySummary / Detail / parser 等）

工作方式: 用 rg / cat / bash 读文件，用 python 统计/分析。
失败处理: **不许**把"分析失败"标成"无缺口"。失败时输出 {"endpoints": [], "error": "<原因>"} 到 http_endpoints.json + stderr。失败状态由主 Claude 决定是否重试。
```

---

## agent-3 UI / 投注规则（**含 4 类规则矩阵预产出**）

```
<通用约束>

输入:
  - main.js: <main_js_path>
  - **必读方法论**: <repo_root>/docs/integration-experience/common/client-rules-analysis.md（§2 4 类规则框架 + §4 矩阵模板）
  - 翻译表: <repo_root>/server/game/pp/client/apps/translations-ui/latest/zh/{core,<gametype>}.json（如存在）

输出: <capture_dir>/ui_rules.md（**含 §X 客户端-后端一致性矩阵预产出**）

任务: 从 main.js 提取下列规则（**只列发现的**，不预设；按 client-rules-analysis.md §2 4 类框架）:

A. **下注限额规则**（每 betCode min/max + 总台限）
   - 按 §A.1-A.5 grep betLimits / *_bet_min / table_bet_min/max_limit
   - 列字段映射表（客户端 il 枚举 ↔ tableConfig 字段名 ↔ 兜底默认 ↔ 渲染行名）
B. **派彩封顶规则**（MAXIMUM_PAYOUT_V* + maxMultiplier + euroTablePayoutMax + table_payout_max）
   - 按 §B.1-B.4 grep + 列客户端 fallback 表（如 maxMultiplier ?? 2e4）
   - 必须三路取 min（known-pitfalls G3）
C. **bet code 合法性 + 行为规则**
   - 客户端 il 枚举 vs 后端 BC 枚举
   - 联动规则（押 X 必须先押 Y / Bonus 主投注前置）
   - 特殊收费（Booster / 等）
D. **UI 状态机规则**
   - 投注窗口 / decision 窗口 / 倒计时

**输出 §矩阵预产出**：按 client-rules-analysis.md §4 模板列一张完整矩阵（每行：客户端展示项 / tableConfig 字段 / 后端 enforce 现状（暂标 ?）/ 默认值 / 差距等级 P0/P1/OK）。后端 enforce 列在 Phase 4 design.md 时由主 Claude 实际 grep server 后填实。

5. 动态阈值（如 "X 局后禁用 Y 边注"，如有）
6. 客户端特殊状态机（如 NotAllBetsAccepted 处理）

格式: markdown，每条规则带 main.js 出处（行号或函数名）。

grep 模式参考: <skill_dir>/references/client-analysis.md（"3.5 betCode 体系" 与 "3.6 用户交互指令"）。
失败处理: 写"agent-3: <错误>" 到输出文件。
```

---

## agent-4 决策 / 状态机

```
<通用约束>

输入: main.js: <main_js_path>
输出: <capture_dir>/state_machines.md

任务: 提取下列状态机和决策机制（只列发现的）:

1. 用户决策（如 candy_drop 选球 / booster 切换 / squeeze peel）
   - 触发时机
   - WS 指令格式
   - 客户端硬编码时长（grep setTimer / setTimeout）
   - 超时分支
2. Bonus 阶段状态机（如 sweetbonanza 的 sweet spins / bubble surprise）
3. Reconnect 流程（switch / session / DuplicatedConnection）

格式: markdown + 状态转移图（mermaid 或 ASCII）。

如本机台无决策机制（如简单 baccarat / roulette）→ 写"无决策机制"即可。
失败处理: 写"agent-4: <错误>"。
```

---

## agent-5 上游消息生命周期

```
<通用约束>

输入:
  - message.json: <message_json_path>
  - main.js: <main_js_path>（事件字典反查用）

输出: <capture_dir>/lifecycle.md

任务:
1. 帧总数 + 按事件名分组的帧数统计
2. 上游初始化序列（顺序读到第一个 subscribe）
3. 一轮事件顺序（相邻 betsopen 间）
4. 一帧多事件检测（哪些帧含多个 key）
5. 关键事件（betsopen/betsclosed/gameresult/winners）的实际样本（每事件 1 个完整 payload）
6. 偶发事件（如 switch / canceled）的出现率与样本

工作方式: python3 解析 message.json，按需输出统计。

格式: markdown + 关键样本 JSON 块。
失败处理: 写"agent-5: <错误>"。
```

---

## 主 Claude 整合

5 agent 全部返回后:

### 1. 检查所有输出文件存在 + 非空
```bash
for f in dict.json http_endpoints.json http_diff.md ui_rules.md state_machines.md lifecycle.md; do
    test -s "<capture_dir>/$f" || echo "❌ 缺 $f"
done
```

### 2. 失败 agent 重启
单独重启失败的 agent（不并行；只补失败的那个）。

### 3. 写 state.json
```bash
jq --arg dict "$CAPTURE_DIR/dict.json" \
   --arg http_ep "$CAPTURE_DIR/http_endpoints.json" \
   --arg http_diff "$CAPTURE_DIR/http_diff.md" \
   --arg ui "$CAPTURE_DIR/ui_rules.md" \
   --arg sm "$CAPTURE_DIR/state_machines.md" \
   --arg lc "$CAPTURE_DIR/lifecycle.md" \
   --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   '. + {
     phase: 3, status: "done",
     agent_outputs: {
       agent_1_dict: $dict,
       agent_2_http_endpoints: $http_ep,
       agent_2_http_diff: $http_diff,
       agent_3_ui: $ui,
       agent_4_state: $sm,
       agent_5_lifecycle: $lc
     },
     last_updated: $ts
   }' "$STATE_JSON" > "$STATE_JSON.tmp" && mv "$STATE_JSON.tmp" "$STATE_JSON"
```

### 4. 跨 agent 一致性检查
- dict.json 的事件名 vs lifecycle.md 的实际帧名（应一致；不一致 → 字典或 capture 不全）
- dict.json 的 betCode 表 vs ui_rules.md 的投注位映射（同 betCode 应同名）
- http_endpoints.json vs server 路由（http_diff.md 应正确反映）

### 5. 进 Phase 4 写 design.md 时**全用** 5 个文件作为事实依据。

## 错误处理

| 情况 | 处理 |
|---|---|
| agent-1 失败 | 单独重启 agent-1（dict 是后续核心依赖）|
| agent-2 失败 | 单独重启；3 次失败 → 报告用户（不允许把失败当无缺口）|
| agent-3/4/5 失败 | 单独重启；如反复失败 → 在 design.md 注"<某项> 待补"，进 Phase 5 不阻塞 |
| 5 agent 全失败 | 报告用户（capture 可能损坏）|
