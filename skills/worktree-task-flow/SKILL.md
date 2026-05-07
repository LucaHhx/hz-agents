---
name: worktree-task-flow
description: 用 git worktree 跑端到端的多 agent 串行任务流——选基础分支 → brainstorming 工作描述 → 隔离 worktree → 串行 worker 协作 → codex 独立审查 → squash 后 PR 回基础分支 → 清理。触发场景：(1) 用户明确说"用 worktree 开发/修复" / "worktree 任务流" / "走 worktree 流程"，(2) 跨分支大批量同步修复（如重构方案漏修复回填），(3) 需要独立工作区 + 团队协作 + 干净 PR 历史的复杂任务。关键词：worktree 任务、worktree 流程、worktree 开发、批量修复、worktree 团队、PR 到基础分支。
---

# Worktree Task Flow

## Overview

把"基于某个基础分支开一个 worktree、用多个 agent 串行完成一组改动、独立审查后 squash 成单 commit 并 PR 回基础分支"打包成可复用流程。每个阶段都有硬 gate，不允许跳过。

**Announce at start:** "正在使用 worktree-task-flow skill 启动隔离任务流。"

## 启动方式

用户触发后立刻进 Phase 1（不要先解释流程，先做事）：

1. 调 `AskUserQuestion` 让用户选基础分支
2. 调 `Skill(skill="brainstorming")` 进 Phase 2 与用户对齐
3. 用户确认后跑 `scripts/init-worktree.sh` 进 Phase 3

**worktree-base vs target-base 概念**（贯穿全流程）：

- **worktree-base**：worker 起步分支，所有 worker commit 都基于它（脚本里同名为 `BASE_BRANCH`）
- **target-base**：PR 的 base 分支（默认与 worktree-base 相同；用户可在 Phase 7 改）
- 例：worker 从 `live` 起步（worktree-base=live），但 PR 想合到 `live-dev`（target-base=live-dev），则需要在 squash 后 rebase 到 live-dev

**进度跟踪**：建议每个 Phase 用 `TaskCreate` 建任务、`TaskUpdate` 标 in_progress/completed，便于失败回滚定位。

## 阶段总览

```
Phase 1  AskUserQuestion 选 base 分支（必须）
Phase 2  brainstorming skill 与用户对齐工作范围（必须；用户未确认前不进 Phase 3）
Phase 3  scripts/init-worktree.sh 创建 worktree + 分支
Phase 4  多 agent 串行执行（B4/B5/B6 硬规则 + 失败回滚）
Phase 5  reviewer agent 跨 commit 总检
Phase 6  codex 独立二检（codex:rescue 或 /codex），有问题主 claude 补丁
Phase 7  自动备份 → squash（reset 到 worktree-base）→ rebase 到 target-base → push → PR
Phase 8  scripts/cleanup-worktree.sh 清理（带 PR gate）
```

每个 Phase 完成必须有可观察输出（commit sha / 报告路径 / PR URL），失败就停下来报问题，不绕开。

---

## Phase 1: 选基础分支（AskUserQuestion）

启动时先 `AskUserQuestion` 让用户选 base：

- 默认列当前仓库的关键分支：先跑 `git branch --list` 实测，从结果挑 main / master / dev / pre / live / live-dev 等
- 让用户选一个或自定义
- 验证 base 分支存在（本地或 `origin/`）— init-worktree.sh 也会再验证一次

base 分支选错会导致 rebase 时一片冲突，**必须先确认**。

---

## Phase 2: 工作描述（强制 brainstorming）

**硬 gate：必须 `Skill(skill="brainstorming")` 调用 brainstorming skill 与用户深入沟通，直到用户明确确认（"开始" / "确认" / "OK" / "嗯就这样" / "可以了" 等同义）后再进 Phase 3。** 不允许仅凭一句简短描述就开干。

brainstorming 阶段要对齐以下要素并以 markdown 形式输出到主对话供用户审阅：

1. **工作目标**：要修什么 / 加什么 / 同步什么
2. **范围边界**：哪些文件/模块改，哪些明确不改
3. **拆分方案**：是否多 agent、worker 怎么分、依赖关系
4. **验收标准**：怎么算完成（测试通过 / 特定行为 / 具体 issue 关闭）
5. **风险/陷阱**：已知的耦合点、潜在冲突、规范偏移
6. **target-base**（可选）：PR 默认合到 worktree-base；如要不同则在这里明确

确认后再问一次：

```
"分支描述用 ASCII kebab-case，≤40 字符。基于上面的目标，建议：<候选>。要这样吗？"
```

### 分支描述格式硬规则

- 仅允许 `[a-z0-9]` 和 `-`（kebab-case）
- 长度 ≤ 40 字符
- 用户给中文/含特殊字符的描述时：当场提议英文 kebab，**禁止接受中文进分支名**
- 例：「同步 pre 维护修复到 live」→ `sync-pre-maintenance`

---

## Phase 3: 创建 worktree

**Phase 2 用户确认后**才允许跑：

```bash
bash <skill_dir>/scripts/init-worktree.sh <base-branch> <kebab-description>
```

脚本行为（详见 [scripts/init-worktree.sh](scripts/init-worktree.sh)）：

- 检查在 git 仓库内
- 验证 description 是 kebab-case ≤ 40 字符
- 解析 base 引用（本地优先；仅远程时用 `origin/<base>` 起点）
- 提示 `.gitignore` 是否含 `.worktrees/`（不自动改，避免污染用户 commit）
- 在 `<repo>/.worktrees/<description>/` 创建 worktree
- 分支命名 `worktree/<base>/<description>`
- 输出 5 行 key=value：`worktree_path=` / `branch=` / `worktree_base=` / `target_base=` / `base_ref=`

底层 worktree 操作可参考 `using-git-worktrees` skill；本流程在它之上加了命名约定与 gate。

---

## Phase 4: 多 agent 串行执行

### B4 串行硬规则（不允许并行）

**单 worktree 共享 git index/工作树，多 agent 同时改会冲突。** skill 强制：

- 一次只允许一个 worker agent 在 worktree 内工作
- 上一个 worker 完成 + 主 claude 验收通过 + 工作树 clean 后，才允许启动下一个
- 即使多个 worker 任务无文件交集，也必须串行（避免 git index race）

### B5 worker 产出契约（每个 worker 完成时必须报）

| 字段 | 内容 |
|---|---|
| **commit sha** | 必须有，缺即视为失败 |
| **`git show --stat HEAD`** | 改动文件清单 |
| **build 结果** | 编译/构建命令 + 是否通过 |
| **vet/lint 结果** | 静态检查 + 区分既存 vs 新增 warning |
| **test 结果** | 涉及包的测试 + PASS/FAIL 数 |
| **policy-pr / 体量预检** | 项目有则跑（如 `scripts/ci/policy-pr.mjs --stdin`），否则跳过并说明 |
| **关键决策** | 与原参考代码不同的设计选择 |

漏任意一项 → 主 claude 拒绝放下一个 worker，让当前 worker 补全或自行替补 commit。

### Worker 失败回滚

worker 中途失败（report 不全 / commit 没打成 / 改动错误）时主 claude 立刻执行：

```bash
# 1. 看 worktree 当前状态
git -C <worktree_path> status

# 2a. 工作树有未提交改动且明确要丢弃
git -C <worktree_path> restore .
git -C <worktree_path> clean -fd  # 慎用，会删 untracked

# 2b. commit 已打但要回滚
git -C <worktree_path> reset --hard HEAD~1
```

回滚后告知用户、确认下一步（重做 / 换方案 / 中止流程）。**禁止**在工作树污染状态下启动新 worker。

### B6 worker prompt 硬规则模板

每次启动 worker 时，prompt 默认必须含：

```
你是 worker <名称>，做 <具体任务>。

## 工作区
- worktree: <worktree_path>（cd 进去并保持，不要切分支）
- 当前分支: <branch>
- HEAD: <当前 HEAD sha>
- 主仓库路径: <repo-root>（如需对照源分支历史可用 `git -C <repo-root> log/show`，否则忽略）

## 硬规则
1. 不要切分支、不 push、不开 PR
2. 自己 git add <具体文件名> + git commit（不要漏；不要用 git add -A）
3. 跑完所有验收（build/vet/test/policy-pr）才能算完成
4. 漏 commit / 漏验收视为失败，主 claude 拒绝并退回让你补
5. 不修改之前 worker 已 commit 的内容（只在其基础上扩展）
6. 不引入未要求的"顺手清理"或新功能

## 完成回报
按 B5 契约输出全部 7 项，最后一句"等待主 claude 验收并启动下一个"。
```

### 预检命令探测（agent 自适应）

skill **不**写死项目预检命令。worker 在 worktree 根目录自行探测：

- 有 `go.mod` → `go build ./...` / `go vet ./...` / `go test ./<改动包>/...`
- 有 `package.json` 且含 `lint`/`test` script → `npm run lint && npm test`
- 有 `Cargo.toml` → `cargo build && cargo test`
- 有 `scripts/ci/*.mjs` 或类似 → 主动跑（如 `policy-pr.mjs --stdin`）
- 都没有 → 报告"无可识别预检"并跳过

预检失败立刻停下来报问题，**禁止**绕开或注释跳过。

---

## Phase 5: Reviewer 跨 commit 总检

所有 worker 完成后，启动一个**独立的 reviewer agent**（general-purpose subagent，只读不写）：

- 跑全量 `<语言栈预检> ./...`
- 抽查每个 commit 的关键文件 diff，对照原始任务清单
- 跨 commit 一致性：同一字段/函数在多 commit 间命名/类型/契约一致
- 输出 `/tmp/<branch>-review.md`，结论：通过 / 警告 / 不通过

### 不通过的处理路径

reviewer 报"不通过"时主 claude 二选一：

**A. 让对应 worker 重做**（适合大问题）：
```bash
# 找到出错的 commit
git -C <worktree_path> log --oneline <worktree-base>..HEAD
# 回退到出错前一个
git -C <worktree_path> reset --hard <good-commit-sha>
# 重新启动该 worker（带 reviewer 反馈）
```

**B. 主 claude 直接补丁**（适合小漏 / codex 风格的 followup）：
```bash
# 在 worktree 内直接改文件 → git add → git commit
# message 写明 "fix(<scope>-followup): reviewer 反馈 XXX"
```

补丁/重做后 reviewer 再跑一遍，直至通过。

---

## Phase 6: codex 独立二检

reviewer 通过后做 codex 独立审查（codex 没有此次会话上下文，能给真正独立视角）：

**调用方式**（任选一）：

1. 用 `Skill(skill="codex:rescue")` 让 codex 做 review（推荐）
2. 用 `Agent` 工具：subagent_type 设为 `codex:codex-rescue`，prompt 含分支名 + 工作区路径 + 关键文件
3. 让用户手动跑 `/codex` 命令

**codex 不可用时**（CLI 没装 / 配置失败）：跳过 Phase 6，明确告知用户"codex 审查跳过，建议人工 review 后进 Phase 7"，不阻塞流程。

codex 反馈：
- **无问题** → 直接进 Phase 7
- **有问题** → 主 claude 直接补丁修复并 commit；**作为新 commit 加入分支历史**（不要改之前 worker 的 commit），squash 时一并扁平化

经验：codex 的独立视角经常发现真 bug，甚至发现源分支也漏的隐藏问题——值得一跑。

---

## Phase 7: squash + rebase + PR

### A1 自动备份（硬 gate）

squash/rebase **前必须**先建备份分支：

```bash
git -C <worktree_path> branch <branch>-backup HEAD
```

任何后续步骤失败可 `git reset --hard <branch>-backup` 回滚。

### A3 冲突预判（rebase 前必看）

```bash
# 看 target-base 比 worktree-base 多了哪些 commit
git -C <worktree_path> log --oneline <worktree-base>..<target-base>
```

- 输出为空 → target-base = worktree-base，rebase 无操作（直接 push）
- 输出几个 commit → 看它们改了什么文件 (`git -C <wt> show --stat <sha>`)，与本次 worktree 改动是否重叠
- 重叠多 → 警告用户冲突风险，让用户确认是否继续

### squash 操作（关键：reset 到 worktree-base 不是 target-base）

```bash
cd <worktree_path>
git reset --soft <worktree-base>   # ⚠️ 必须用 worktree-base，所有 worker 改动 staged
git commit -m "<合并 message>"     # 重新打一个 commit
# 仅当 target-base != worktree-base 时才 rebase：
git rebase <target-base>
```

**为什么 reset 到 worktree-base 而不是 target-base**：worker commit 是基于 worktree-base 一路 fast-forward 上来的；如果 reset 到 target-base，会把 target-base..worktree-base 之间的 commit 也拉进 staging（不属于本次工作），导致 squash 内容污染。

### squash message 模板

```
<type>(<scope>): <一句话总结>

<3-6 行背景说明：为什么需要这个改动、对应什么问题/issue>

修复:
- <bullet 1>
- <bullet 2>
- ...

变更范围: N 文件 +X -Y（含 K 个测试文件 M 个测试函数全 PASS）；
build / vet / policy-pr 全过。

Squash 自:
  <sha1> <type>(<scope>): <短描述 1>
  <sha2> <type>(<scope>): <短描述 2>
  ...

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

**硬要求**：
- `Co-Authored-By` trailer **必须有**
- 列出 `Squash 自:` 块（来源 commit sha + 短描述）便于追溯

### 推送 + PR

```bash
git -C <worktree_path> push -u origin <branch>
gh pr create --base <target-base> --head <branch> \
    --title "<≤70 字符的 PR title>" \
    --body "$(cat <<'EOF'
## Summary
<3 个 bullet 概括>

## Test plan
- [x] build/vet/test/policy-pr 全过
- [x] reviewer 总检通过
- [x] codex 二检通过（如适用）

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

**硬要求**：
- PR title **≤70 字符**（CLAUDE.md 项目级硬规则；超长部分写到 body）
- PR body 用 HEREDOC 含 Summary + Test plan
- 对齐项目 CLAUDE.md 既有 PR 规范（如有）

---

## Phase 8: cleanup（F10 安全 gate）

PR 创建后用户确认要清理时：

```bash
bash <skill_dir>/scripts/cleanup-worktree.sh <worktree_path> [branch-name]
```

脚本行为（详见 [scripts/cleanup-worktree.sh](scripts/cleanup-worktree.sh)）：

- 检查 worktree 工作树 clean
- 检查 PR 状态（OPEN / MERGED 才允许清理；CLOSED 中止）
- 删 worktree
- 删本地工作分支
- 备份分支：PR MERGED 才删；OPEN 状态下保留
- 远程分支不动（PR 依赖）

**远程分支后续**：PR merge 后 GitHub 通常自动删 head 分支（如启用了"Automatically delete head branches"）。如未自动删，用户手动：
```bash
git push origin --delete <branch>
```

`gh` 不可用时输出 WARN 但允许继续（用户自行确认 PR 状态）。

---

## 端到端检查清单（启动前自查）

- [ ] Phase 1：用户已选 base 分支，分支验证通过
- [ ] Phase 2：brainstorming 完整覆盖 6 要素 + target-base，用户明确确认"开始"
- [ ] Phase 3：worktree 创建成功，5 行 key=value 输出
- [ ] Phase 4：每个 worker 都有 commit sha + 完整验收 + 主 claude 验收通过；失败已正确回滚
- [ ] Phase 5：reviewer 通过（不通过则按 A/B 路径补救）
- [ ] Phase 6：codex 通过 / 跳过（不可用时已警告用户）
- [ ] Phase 7：备份分支已建，squash reset 到 worktree-base，rebase 到 target-base 0 冲突或冲突已解决，PR title ≤70 + body 完整 + Co-Authored-By trailer
- [ ] Phase 8：清理在用户确认后执行，安全 gate 通过

任意一个 Phase 失败立刻停下报告，不允许"先做下一步看看"。
