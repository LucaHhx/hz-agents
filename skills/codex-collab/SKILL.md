---
name: codex-collab
description: 通过 codex CLI 让 Claude 和 codex 协作。四种用法：(1) 代码审查 — 一次性 + 并行 N 个 codex agent 做只读审查；(2) 多轮对话 — 用 thread_id resume 与 codex 续聊，用于追问 / 讨论 / 探索实现思路；(3) 决策咨询 — 把 codex 当独立 AI 顾问做方案选型 / 命名 / 架构评估，要求结构化输出；(4) 执行干活 — 用 codex_dev.sh 让 codex 实际写文件 / 跑命令完成任务，默认受控 full-auto（workspace-write，限工作目录内、不联网），需联网装依赖或跨目录写时显式 --yolo；输出流式可见（file_change / command_execution），干完 Claude 用 git diff 审查。关键词：codex 审查、codex review、codex 对话、问 codex、和 codex 聊、codex 讨论、codex 续审、codex resume、多轮对话、codex 决策、让 codex 选、codex 顾问、并行审查、未提交审查、分支对比审查、目录审查、code review、PR 审查（除非明确要求 GitHub PR review）、codex 写文件、codex 干活、codex 执行、让 codex 改代码 / 实现 / 修 bug、codex --yolo、codex full-auto。前三种默认 read-only sandbox；第四种是唯一可写模式，用完即退。
---

# Codex Collab

把 codex CLI 当作 Claude 的协作伙伴，提供五个脚本对应四种用法（前三种只读，第四种可写）：

| 模式 | 脚本 | 用途 |
|---|---|---|
| 1. 审查 | `scripts/codex_review.sh` | 一次性、并行 N 个 codex agent，只读代码审查（read-only 写死） |
| 2. 沟通 | `scripts/codex_discuss.sh` | 保持 thread_id 多轮对话；强制 codex 每轮做"上下文自检"+"轮数感知"；硬上限 `--max-rounds` 防发散 |
| 3. 决策 | `scripts/codex_decide.sh` | 一次性结构化决策；强制 codex 自己 `rg/cat` 主动读代码；上下文不足返回 `INSUFFICIENT_CONTEXT` 列出还需哪些路径 |
| 4. 执行 | `scripts/codex_dev.sh` | **唯一可写模式**：让 codex 真正写文件 / 跑命令完成任务。默认受控 full-auto（workspace-write，限工作目录内、不联网）；`--yolo` 才放开全部沙箱（联网 / 跨目录写）。输出流式显示 file_change / command_execution，干完 Claude `git diff` 审查 |
| 底层 | `scripts/codex_chat.sh` | 通用 chat 包装（被 2/3 调用）；裸调时由调用方自己拼 prompt |

**关键设计**（决策/沟通模式强制实现）：调用方提供"问题 + 入口路径"，**不直接给候选答案让 codex 选**。codex 自己用 `rg / cat` 主动探索；上下文不足时显式声明缺什么路径，由调用方补充后再调一次。这避免了"调用方喂答案 → codex 当应声虫"的退化。

## 核心约束（严格遵守）

1. **只读是默认，写是显式模式**：审查 / 沟通 / 决策 / 底层 chat 四个脚本默认 `--sandbox read-only`。
   - `codex_review.sh` 写死 read-only，不可覆盖。
   - `codex_chat.sh`（及其上层 discuss/decide）默认 read-only。临时提升权限**两扇门都要显式推开**（防误触）：
     - `-s workspace-write` 必须额外带 `--allow-workspace-write`
     - `-s danger-full-access` 必须额外带 `--allow-danger-full-access`
     不带对应 flag 直接 exit 2。
   - **要 codex 持续写文件 / 跑命令做实事，走模式 4 `codex_dev.sh`**（默认 full-auto = workspace-write，`--yolo` 才全放开沙箱），不要用 chat 硬撑写权限。`codex_dev.sh` 是本 skill 唯一定位为「可写」的脚本，用完即退回只读协作。
2. **必须过滤输出**：`codex exec --json` 会吐出大量事件流，不过滤会爆上下文。**必须**走脚本（已内置 `jq -r --unbuffered` 过滤），或在裸命令时手动加：
   ```
   | jq -r --unbuffered 'if .type == "thread.started" then "THREAD_ID=" + .thread_id elif .item.type == "agent_message" then .item.text else empty end'
   ```
3. **审查默认并行 3 个**：审查模式相同指令并行启动 3 个 codex agent 再去重汇总；沟通和决策模式默认就 1 个（多轮对话不并行）。
4. **`-d DIR` 首次会话必填且必须是已存在的绝对路径**：脚本会做三重校验（非空 / `/` 开头 / 目录存在），失败 exit 2。**resume 时不允许传 `-d` / `-s`**（codex 会拒绝），由原会话继承，脚本检测到会 stderr 警告并忽略。
5. **thread_id 完全显式**：脚本不持久化 thread_id。Claude 自己负责把 `THREAD_ID=xxx` 记到 TaskList 或本轮内部状态，下一轮 resume 时通过 `-t` 显式传回。脚本不读任何"上次会话"文件。
6. **流式接收要用 Monitor，不是 Bash**：`agent_message` 是段级流式（codex 每段思考完整时 emit 一条），脚本 jq 已 `--unbuffered`。但 Bash 工具会等命令完成才返回整段输出，看不到中间流；要让 Claude 段段收到，必须用 **Monitor 工具**包装命令（每行 stdout 触发一次事件通知）。用户在自己终端跑则直接看到流式。
   **无 Monitor 时的 fallback**：用户在真实终端直接运行脚本仍可看到 jq `--unbuffered` 的段级输出；如果调用框架（Bash 工具 / 其他 LLM agent harness / CI）会缓冲 stdout，则只能等命令结束拿整段结果。如需观察进度，由调用方自行把 stdout/stderr `tee` 到日志文件并 `tail -f`。

## 模式 1：审查工作流

### Step 1 — 确认审查范围

把用户请求映射到三种场景之一：

| 场景 | 触发关键词 | 必要参数 |
|---|---|---|
| 未提交审查 | "审一下当前改动 / 未提交 / staged / WIP / 这次的修改" | 仓库根目录 |
| 分支对比 | "审 PR / 对比 dev / `xxx` 分支相对 `yyy`" | `BASE`、`HEAD` 分支名，仓库根 |
| 路径审查 | "审 `server/service/foo/` / 这个目录 / 这个模块" | 目标路径，仓库根 |

如果用户没说清楚，**先问清楚**再启动 codex（codex 启动有成本，不要瞎跑）。

### Step 2 — 组装 prompt

打开 `references/prompts.md` 取对应模板，把占位符替换好。模板已经包含：

- 通用注入头（强调"只审不改"、按 🔴/🟡/🟢 分类输出）
- 场景专用上下文要求（git diff / 路径范围 / 关注点）
- 可选的"视角差异化"段，用来让 N 个 agent 互补

### Step 3 — 并行启动 codex

**默认开 3 个 Agent (subagent_type=general-purpose) 并行**，每个 agent 调用一次 `bash scripts/codex_review.sh`。在**同一条消息**里发出 3 个 Agent tool call 才能真正并行（不是顺序）。

每个 sub-agent 的 prompt 里要明确告诉它：

- 调用脚本的完整命令（`bash <skill-dir>/scripts/codex_review.sh -d <repo> -l agent-N -- '<prompt>'`）
- 把 codex 的整段输出原样返回，不要二次总结、不要省略
- 不需要它做任何代码修改

脚本路径取决于安装位置，常见为：
```
/Users/luca/.claude/skills/codex-collab/scripts/codex_review.sh
```
（也可能解析成 `/Users/luca/github/LucaHhx/hz-agents/skills/codex-collab/scripts/codex_review.sh`，两条路径等价。）

### Step 4 — 汇总

3 个 agent 全部返回后，按 `references/aggregation.md` 规则合并：

- 解析每条结论为 `(severity, file, line, desc, fix)`
- 按 `(file, line, desc 前缀)` 近似去重，多 agent 共同提到的标 `_(N agents)_`
- 严重度冲突取更高
- 按 🔴 / 🟡 / 🟢 分桶，文件名+行号排序
- 输出到用户

如果用户明确说"原样并列展示"，跳过去重，直接 `## Agent 1` / `## Agent 2` / `## Agent 3` 三段贴出来。

### 直接调用 review 脚本（不通过 sub-agent 时）

少数情况下不需要并行（如用户说"审一下就行，不用并行"），可在主 agent 里直接 Bash 一次：

```
bash /Users/luca/.claude/skills/codex-collab/scripts/codex_review.sh \
  -d /Users/luca/work/pp-game \
  -- '审查当前未提交代码，只审不改，按 🔴/🟡/🟢 分类'
```

review 脚本特性：

- `-d DIR` 透传给 codex `--cd`，**必填、必须是绝对路径且目录已存在**（脚本三重校验）
- `-m MODEL` 选模型（默认 codex 自己挑）
- `-l LABEL` 给输出加前缀，并行时区分用
- 自动加 `--sandbox read-only`、`--json`、`jq` 过滤
- `prompt` 通过 `--` 之后的位置参数传，或 stdin 管道传

## 模式 2：沟通工作流（多轮对话）

适用场景：

- 用户说"问问 codex / 让 codex 看看 / 和 codex 讨论一下 X"
- 审查后就某条结论追问 codex 细节（"刚那条 SQL 注入的修复方案展开讲讲"）
- 探索性讨论（设计选型、bug 根因排查、实现思路）— 你需要一个**独立的 AI 视角**，但**不需要它改代码**

**强制使用 `codex_discuss.sh`**（不是裸调 codex_chat.sh）— 它注入了"轮数感知 + 每轮上下文自检"的 prompt header，要求 codex 每轮先确认 message 含具体路径/数据/引用，否则要求调用方补充而不是瞎答。最后一轮强制 `closing` 或 `unresolved`。

### Step 1 — 启动会话（首轮）

不传 `-t`，脚本自动新建。Claude 必须从输出里抓取 `THREAD_ID=...`，记到 TaskList 或本轮回复的内部状态里。

```
bash /Users/luca/.claude/skills/codex-collab/scripts/codex_discuss.sh \
  -d /Users/luca/github/LucaHhx/hz-agents \
  --round 1 --max-rounds 3 \
  -- '我们要讨论 X 问题。
关联文件：path/to/file.go:42 / path/to/other.md
现状：...
请先确认你看到的入口路径，再分析。'
```

输出形如（codex 每轮回复尾部带 `discussion_status: ...`）：
```
THREAD_ID=019e0ac8-...
本轮焦点：...
本轮分析：...（含 file:line 引用）
下一步建议：...
discussion_status: in-progress
```

### Step 2 — 续接会话（后续轮）

用上一轮拿到的 thread_id，通过 `-t` 显式传入。**resume 时不要再传 `-d`**（codex 不接受，由首轮决定），脚本会 stderr 警告并忽略：

```
bash /Users/luca/.claude/skills/codex-collab/scripts/codex_discuss.sh \
  -t 019e0ac8-... \
  --round 2 --max-rounds 3 \
  -- '基于刚才的上下文，针对 X 我新增了 path/to/Y.go 这个文件，请看 ...'
```

### Step 3 — 解析状态行 + 决定下一步

每轮回复尾部 `discussion_status:` 三选一：
- `in-progress` — 准备 round + 1 的 message（补 codex 要求的路径），resume
- `closing` — 已收敛，按 codex 给的"下一步动作"执行；写状态记录
- `unresolved` — 不收敛，回退到默认规则 + 写 `unresolved` 记录（不再续接）

把 codex 的最终结论或讨论摘要转给用户/写回业务 state。`THREAD_ID=` 保留在内部状态用于 resume。

### codex_discuss.sh 脚本特性

- `-d DIR` 首轮必填、已存在的绝对路径；resume 时被忽略
- `-t THREAD_ID` 续接（不传则新建）
- `--round N --max-rounds M` 都必填，正整数；注入 prompt header 让 codex 自知"还能聊几轮"
- `-m MODEL` 选模型
- `-l LABEL` stderr 前缀
- 内部调 `codex_chat.sh`（默认 read-only，sandbox 升级需走底层 chat 的 flag）

### 底层 chat 脚本（codex_chat.sh）

裸 chat 不带任何 prompt 模板，给"既不是审查、也不是结构化决策、也不是受控多轮"的特殊场景用（很少需要）：

- `-d DIR` 透传 `--cd`，首轮必填、已存在的绝对路径；resume 时被忽略
- `-m MODEL` 选模型
- `-s SANDBOX` 沙箱模式（默认 `read-only`；`workspace-write` 必须加 `--allow-workspace-write`；`danger-full-access` 必须加 `--allow-danger-full-access`）；resume 时被忽略
- `--allow-workspace-write` / `--allow-danger-full-access` 二次确认开关
- `-t THREAD_ID` 续接（不传则新建）
- `-l LABEL` stderr 前缀
- jq filter 同时保留 `thread.started` 的 thread_id 和 `agent_message` 文本
- prompt 通过 `--` 后的位置参数或 stdin 传入

## 模式 3：决策工作流（让 codex 当顾问）

把 codex 当**独立 AI 顾问**做单点决策，比如方案选型、命名建议、架构评估、A/B 比较。

**强制使用 `codex_decide.sh`**（不是裸调 codex_chat.sh）— 它注入了"上下文足够性自检"的 prompt header，强制 codex：
1. 主动 `rg / cat` 调用方提供的入口路径
2. 主动对照同领域先例 / 经验文档
3. 给出**有 file:line 依据**的决策，不允许"对/错"二选一回答
4. 上下文不足时显式输出 `INSUFFICIENT_CONTEXT` 列出还需哪些路径

调用方提供"问题 + 入口路径"，**不提供候选答案让 codex 选**。

### 何时用决策而不是沟通

- 用户给了你一个二选一/多选一的选择，希望第三方意见
- 你需要 codex 给一个**可机读**的结论，方便你后续按它的回答执行（比如"决策 1: X / 决策 2: Y"）
- 一次到位，不需要多轮辩论

如果用户想"和 codex 反复讨论"，走沟通模式。

### Step 1 — 写决策 body（脚本会自动注入"上下文自检 + 输出格式"header）

调用方只写 body，不要重复 header（脚本已注入）：

```
## 背景
<问题域 / 现状 / 约束 / 限制条件>
**关键文件入口路径**（让 codex 自己 cat / rg）：
- path/to/file1.go:42（关注 funcA 实现）
- path/to/spec.md（§2 协议表）
- docs/integration-experience/<gametype>/（同领域先例）

## 决策点
**决策 A：<问题>**
候选：<A1 / A2 / A3，或允许 codex 自定义>。判断标准：<列出>

**决策 B：<问题>**
<同上>
```

注意：**不要写完整答案让 codex 当应声虫**，给候选+判断标准+入口路径，让 codex 自己读代码后给有依据的选择。

### Step 2 — 跑一次 decide

```
bash /Users/luca/.claude/skills/codex-collab/scripts/codex_decide.sh \
  -d <repo-root> \
  -l <可选标签> \
  -- '<上面的 decision body>'
```

### Step 3 — 解析并执行

codex 输出形如：

```
THREAD_ID=...
决策 A：<选定项>
理由：<引用具体 file:line / grep 结果>
依据来源：<列出实际读过的文件>
具体落地：<改哪个文件 / 写哪个字段>
```

或上下文不足时：

```
决策：INSUFFICIENT_CONTEXT
已探索：...
还缺：- <文件 1>...
建议下一步：调用方在 background 补全后再调一次
```

如果是 `INSUFFICIENT_CONTEXT`，调用方应：补充缺失路径到 background 中，重新调一次 `codex_decide.sh`（新会话即可，决策是一次性的，不需 resume）。

把最终决策原样转给用户/写回业务 state。决策是一次性的，不需要持久化 thread_id（除非用户要追问 — 那转沟通模式起新会话或 resume）。

## 模式 4：执行工作流（让 codex 动手干活）

前三种模式 codex 只读、只说不做。**执行模式让 codex 真正改文件、跑命令**，完成一个**明确、可验收**的任务：修一个已定位的 bug、生成脚手架、按模板批量改、装依赖后跑测试等。

**强制使用 `codex_dev.sh`**（不要用 chat + `--allow-workspace-write` 硬撑）。它相对 chat 的区别：
- 默认权限就是 **full-auto**（`--sandbox workspace-write`），开箱即写，不用叠 flag；
- jq 过滤器**额外保留 `file_change` / `command_execution` 事件**，让你实时看到 codex 改了哪些文件、跑了什么命令、退出码多少，而不只是它最后说了什么。

### 何时用执行模式 vs 退回 dev-agent

- ✅ 任务边界清晰、能一句话说清「改成什么样 + 怎么验证」→ 交给 `codex_dev.sh` 一把梭，干完你 `git diff` 审。
- ✅ 你想要一个**独立实现视角**跑通某个改动，再和自己的实现对比。
- ❌ 需要跨多文件反复试错、边写边和用户确认设计 → 那是 `hz-backend` / `hz-frontend` / `unify-fix` 的活，不要硬塞给 codex 单次执行。

### 两档权限（默认够用，yolo 是显式升级）

| 档位 | 传参 | codex 能做什么 | 用在 |
|---|---|---|---|
| 默认 full-auto | 不加 flag | 读写**工作目录内**文件、跑命令；**默认不联网**、不能写目录外 | 绝大多数「改本仓库代码」任务 |
| `--yolo` | 加 `--yolo` | 放开全部沙箱 = `--dangerously-bypass-approvals-and-sandbox`：可联网、可写任意路径 | 装依赖（npm/pip 联网）、跨目录写、需要访问外部资源 |

`--yolo` 会 stderr 打醒目警告。**能用默认就别上 yolo**。默认档遇到联网/越界操作会「失败并把错误返回给 codex」，不会卡住等审批（exec 非交互，本就不询问）。

需要多个可写目录但不想全放开时，用 `--add-dir /abs/path`（可重复）扩展白名单，比 yolo 安全。

### Step 1 — 首次派活

工作目录**强烈建议是 git 仓库根**（干完能 `git diff` 审 codex 的改动）：

```
bash /Users/luca/.claude/skills/codex-collab/scripts/codex_dev.sh \
  -d /Users/luca/work/pp-game \
  -l dev-fix \
  -- '修复 server/service/foo/bar.go 里 CalcPayout 的边界 bug：当 bet 为 0 时应返回 0 而非 panic。
补一个表驱动单测覆盖 bet=0 / 正常 / 超大值三种，然后 go test ./server/service/foo/ 验证通过。'
```

联网/跨目录才升级：

```
bash .../codex_dev.sh -d /Users/luca/work/proj --yolo \
  -- '安装 zod 依赖并把 src/schema.ts 改成用 zod 校验，pnpm test 通过。'
```

输出（已过滤，流式）形如：
```
THREAD_ID=019e...
我会先定位函数，再补测试。
📝 update /Users/luca/work/pp-game/server/service/foo/bar.go
📝 add /Users/luca/work/pp-game/server/service/foo/bar_test.go
⚙️ exit=0 $ /bin/zsh -lc 'go test ./server/service/foo/'
ok  ...  0.312s
已完成：修复了 bet=0 分支并补齐单测，全部通过。
```

### Step 2 — 续接同一任务（可选）

拿首次输出的 `THREAD_ID`，用 `-t` 续接（**resume 不要再传 `-d` / `--yolo` / `--add-dir`**，由原会话继承，脚本会 stderr 警告并忽略）：

```
bash .../codex_dev.sh -t 019e... -l dev-fix2 \
  -- '刚才的测试漏了负数 bet，补一个 case 并重跑。'
```

### Step 3 — 审查 codex 的改动（必做，别盲信）

codex 干完后**回到工作目录用 `git diff` / `git status` 亲自过一遍**它的改动，不要因为它说"已完成"就照单全收。必要时把 diff 再喂给**模式 1 审查**做一轮独立 review，形成「codex 写 → codex（另一视角）审 → 你定夺」的闭环。

### 流式观察（关键：让你/Claude 边跑边看）

`codex exec` 每完成一段就 emit 一个事件，脚本 jq 已 `--unbuffered`，所以**段级流式就绪**。但能不能实时看到取决于谁在收：

- **用户在自己终端直接跑脚本** → 直接看到 file_change / command_execution 逐条刷出。
- **Claude 想边跑边收**（而不是等命令整段返回）→ 必须用 **Monitor 工具**包装命令（每行 stdout = 一条通知）。直接用 Bash 工具会缓冲到命令结束才一次性返回，看不到中间过程。
- **两边都想看** → 脚本输出 `tee` 到日志文件，用户 `tail -f` 那个文件：
  ```
  bash .../codex_dev.sh -d /repo -- '...' 2>&1 | tee /tmp/codex_dev.log
  ```

### codex_dev.sh 脚本特性小结

- `-d DIR` 首次必填、已存在的绝对路径（建议 git 根）；resume 时忽略
- `-t THREAD_ID` 续接任务
- `--yolo` 放开全部沙箱（默认不加 = full-auto workspace-write）
- `--add-dir DIR` 扩展可写目录（可重复，绝对路径且存在）；yolo 下忽略
- `-m MODEL` / `-l LABEL` 同其他脚本
- 输出流式保留 `agent_message` / `file_change` / `command_execution`，命令输出超 3000 字符尾部截断
- 退出码 0/2/3/4 同其他脚本

## 常见误用 / 坑

- ❌ 不加 jq 过滤直接 `codex exec --json`：事件流刷屏，会瞬间吃掉几千行上下文。
- ❌ 用 chat/review 让 codex "顺便修一下"：这些是只读模式。要 codex 真改文件走**模式 4 `codex_dev.sh`**（明确、可验收的任务）；复杂、需反复试错的开发仍退回 `hz-backend` / `hz-frontend` / `unify-fix`。
- ❌ 并行 3 个 review agent 但没在同一条消息里发出 3 个 tool call：会变成串行，慢 3 倍。
- ❌ `--cd` 用相对路径 / 省略：codex 可能跑在意外目录上，审错文件。
- ❌ resume 时传 `--cd` 或 `--sandbox`：codex 会报错 `unexpected argument`；这俩参数只在首次会话生效，由原会话继承。脚本已自动处理（resume 路径不传），但你**裸跑 codex 命令时必须自己注意**。
- ❌ 直接把 review 输出贴给用户：必须先按 `references/aggregation.md` 去重分类，否则同一处问题会被列 3 次。
- ❌ 对话续接时忘记传 `-t THREAD_ID`：会变成全新会话，codex 没有上文记忆，回答驴唇不对马嘴。
- ❌ 把 thread_id 当成跨会话长效标识：codex 会话本质是临时的，不要让它跨 Claude 会话续接（跨会话用 review 重新跑就行）。
- ❌ 决策 prompt 没带输出格式约束：codex 可能写一大篇分析，你解析不出明确决策。**一定要用反引号代码块限定输出格式**。
- ❌ 用 Bash 工具直接调脚本期望看到流式：Bash 工具会等命令完成才一次性返回，看不到中间段落。要让 Claude 段段收到，**必须用 Monitor 工具**（每行 stdout = 一个事件通知）。用户在自己终端运行不受影响。
- ❌ 在 zsh / bash 终端里粘贴带反斜杠续行的命令，反斜杠后有空格会让续行失效：`-d ...` 会被当成独立命令报 `command not found`。**长命令推荐单行或用 `<<'EOF'` heredoc 喂 stdin**。
- ❌ 执行模式（codex_dev.sh）干完就照单全收：codex 可能读到工作区的 AGENTS.md / skill 而跑偏，或验证不充分。**必做 `git diff` 亲审**，重要改动再走模式 1 做独立 review。
- ❌ 无脑上 `--yolo`：yolo = 放开全部沙箱（联网 + 全盘写）。默认 full-auto（workspace-write）已能改本仓库文件，能用默认就别 yolo；只是多几个可写目录就用 `--add-dir`。
- ⚠️ codex 若挂了 skill（`~/.codex/skills` 软链本仓库 skills）：执行任务时会先读 brainstorming 等 skill，受其"先出设计等批准"HARD-GATE 影响**停下征询确认**（exec 非交互没人回答 = 任务失败）。`codex_dev.sh` 已内置「自主执行 header」压制此行为，别删。
- ⚠️ **维护脚本者注意（本次踩坑实录）**：① macOS 无 `timeout`/`gtimeout` 命令，脚本别依赖（超时交给调用方，如 Bash 工具的 timeout / Monitor 的 timeout_ms）；② `codex exec` **不接受** `-a/--ask-for-approval`，full-auto 只需 `--sandbox workspace-write`（exec 非交互本就不询问审批）；③ macOS 自带 bash 3.2，`set -u` 下展开**空数组** `"${arr[@]}"` 报 `unbound variable`，要先 `[[ ${#arr[@]} -gt 0 ]]` 守卫；④ codex `--json` 每行**已是 JSON 对象**，jq 里**别加** `fromjson`（那是把字符串解析成 JSON 的，对已是对象的输入会报错、被 `?` 吞成 empty，导致过滤后 stdout 全空）。

## 文件索引

- `scripts/codex_review.sh` — 一次性审查 + jq 过滤（read-only 写死）
- `scripts/codex_chat.sh` — 底层通用 chat 包装（新建 + resume），默认 read-only 可覆盖；裸调用罕见
- `scripts/codex_discuss.sh` — 多轮沟通（强制轮数感知 + 每轮自检），调底层 chat
- `scripts/codex_decide.sh` — 一次性决策（强制上下文自检 + 主动 rg/cat + 不足返 INSUFFICIENT_CONTEXT），调底层 chat
- `scripts/codex_dev.sh` — **执行模式（唯一可写）**：让 codex 真写文件 / 跑命令。默认 full-auto（workspace-write），`--yolo` 放开全部沙箱，`--add-dir` 扩展可写目录；注入自主执行 header 压制"先确认"；流式输出 file_change / command_execution；支持 `-t` resume 续接任务
- `references/prompts.md` — 三种审查场景的 prompt 模板 + 通用注入头
- `references/aggregation.md` — 多 agent 审查结果去重和分类规则
