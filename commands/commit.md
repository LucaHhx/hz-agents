---
description: 分析未提交代码，按模块/功能分类分批提交，自动生成规范的 commit message；完成后交互询问推送/PR
---

# Smart Commit - 智能分批提交

分析当前所有未提交的变更，按模块或功能维度分类，分批创建 git commit，每个 commit 附带规范的中文注释。本地 commit 完成后通过 AskUserQuestion 交互询问：推送 / 不推送 / 推送并 PR 到 dev；若选择"PR 到 dev"且创建成功，再追问是否继续提"dev → pre" PR。所有 push / PR 动作必须由用户明确选择后才执行。

## Implementation Steps

When this command is invoked:

### 1. 收集当前变更状态

Run the following commands to gather context:

```bash
git status
```

```bash
git diff --stat
```

```bash
git diff --stat --cached
```

```bash
git log --oneline -5
```

Capture the output for analysis. If there are no changes (working tree clean), report to user and stop.

### 2. 查看每个变更文件的具体 diff

For each modified/added/deleted file, run:

```bash
git diff <file>
```

Or for staged files:

```bash
git diff --cached <file>
```

Read the actual diff content to understand what each file changed. This is critical for writing accurate commit messages.

### 3. 本地策略预检（scripts/ci/policy-pr.mjs）

CI 会在 PR 到 `dev` / `pre` 时跑 `policy-pr`（单文件 ≤500 行、控制流嵌套 ≤3 层），
范围：`server/**.go`、`web/src/**.{js,vue}`、`worker/src/**.{ts,js}`。
**提交前先跑一次本地预检**，避免 commit 完了才发现违规要返工。

```bash
{ git diff --name-only --diff-filter=ACMR; git ls-files --others --exclude-standard; } \
  | node scripts/ci/policy-pr.mjs --stdin
```

说明：
- 第一段列 working tree 已修改/新增/删除的已跟踪文件；第二段列未跟踪（untracked）文件。
  两段合并后 policy 脚本内部会按后缀过滤，非策略范围的文件自动忽略。
- 运行在 repo root（`scripts/ci/policy-pr.mjs` 是相对路径）。如果当前 cwd 不在 root，先 `cd` 或用绝对路径。
- 若 `node` 不存在或脚本缺失：报告"本地预检不可用，跳过"，继续流程但向用户提示 CI 可能拦截。

处理违规：
- 输出 `policy-pr: checked N file(s), all within limits` → 通过，继续 Step 4。
- 输出 `violations found` + 某文件 `control depth X exceeds 3` / `N lines exceeds 500`：
  - 如果违规来自**本次 diff 的文件**（无论是否本次引入），**先修掉**再继续分类。
    重构思路参考 CLAUDE.md："Go 按职责拆多文件；Vue 抽 composable"。
  - 如果违规是文件里 pre-existing 的老代码段（不是本次引入），同样必须处理——CI
    policy 只要文件被修改就会整文件扫，不会网开一面。改法：早退 / 抽 helper 展平。
  - 修完再重跑本命令直到 all within limits。

### 4. 分类变更

Analyze all changes and group them into logical commits based on these dimensions (priority order):

1. **按功能/特性分组**: Changes that belong to the same feature or bugfix go together
2. **按模块/目录分组**: Changes in the same module or package directory
3. **按变更类型分组**: Separate refactors, new features, bug fixes, config changes, docs

Classification rules:
- Files that are tightly coupled (e.g., a handler and its test, a model and its migration) belong in the same commit
- Configuration changes (go.mod, config files) can be grouped together or attached to the feature they support
- New files (untracked) should be grouped with related modified files if they serve the same feature
- **Untracked resource directories (e.g., client/, assets/, static/) MUST be included in the commit plan** — typically as a separate `chore` commit. Do NOT skip them just because they are not code files
- If ALL changes are closely related and serve a single purpose, create ONE commit instead of forcing artificial splits

### 5. 制定提交计划

Create a numbered plan listing each commit group:

```
提交计划:
1. feat(module): 描述 — file1.go, file2.go
2. fix(module): 描述 — file3.go
3. refactor(module): 描述 — file4.go, file5.go
```

**必须用 AskUserQuestion 工具收集确认**（不要用纯文字提问，因为需要结构化选项）。
`AskUserQuestion` 是 deferred 工具，调用前先 `ToolSearch` 加载 schema：

```
ToolSearch({ query: "select:AskUserQuestion", max_results: 1 })
```

然后发起问询，建议的 question 示例：

```
AskUserQuestion({
  questions: [{
    question: "以上分批提交计划是否确认执行？",
    header: "提交计划",
    multiSelect: false,
    options: [
      { label: "确认，按计划提交", description: "依次按上述分组 stage + commit" },
      { label: "调整分组", description: "请用户说明要怎么调；不自动执行" },
      { label: "取消", description: "不做任何提交" }
    ]
  }]
})
```

按用户选择分支：
- 确认 → 进入 Step 6
- 调整 → 读取用户说明后回到 Step 4 重分组
- 取消 → 停止流程

### 6. 按计划逐个提交

For each commit group in the plan, execute sequentially:

1. Stage only the files in this group:
   ```bash
   git add <file1> <file2> ...
   ```

2. Verify staged files are correct:
   ```bash
   git diff --cached --stat
   ```
   Confirm only the intended files are staged.

3. **本批 staged 文件再次跑 policy-pr**（Step 3 已做过整体预检，此处兜底本批）：
   ```bash
   git diff --cached --name-only --diff-filter=ACMR | node scripts/ci/policy-pr.mjs --stdin
   ```
   - 通过 → 继续下一步创建 commit。
   - 违规 → 停止本批 commit（**不要** 强行 `commit --no-verify`），回到用户报告违规文件与行号，
     修复后重新 `git add` 并再次跑本步。
   - 若 Step 3 已经通过、本步又违规，通常是本批把多个独立超限文件拆分了，合批 / 调分类即可。

4. Create commit with descriptive message following the project's convention:
   ```bash
   git commit -m "$(cat <<'EOF'
   type(scope): 简明描述

   - 具体变更点1
   - 具体变更点2

   Co-Authored-By: Claude <noreply@anthropic.com>
   EOF
   )"
   ```

5. Verify the commit was created:
   ```bash
   git log -1 --oneline
   ```

Then proceed to the next commit group.

### 7. 输出最终报告

After all commits are created, show a summary:

```bash
git log --oneline -<N>
```

Where N is the number of commits just created.

Report format:

```
## Smart Commit 完成

**共创建 N 个提交:**

1. `abc1234` feat(module): 描述
2. `def5678` fix(module): 描述
...
```

### 8. 询问后续推送/PR 动作（AskUserQuestion）

所有本地 commit 完成后，**必须用 AskUserQuestion 工具问用户下一步**，
不要自行 push / create PR。先 ToolSearch 加载 AskUserQuestion schema：

```
ToolSearch({ query: "select:AskUserQuestion", max_results: 1 })
```

#### 重要语义澄清

- **"PR" = 创建 Pull Request 申请，等待人工 Review 与合并**。本流程**只负责发起
  申请**，**不做本地 merge / rebase / squash**，也不替代人工审查。合并由 reviewer
  在 GitHub 页面点 Merge 完成。
- **当前分支保持干净**：
  - 不跑 `git pull` / `git pull --rebase` / `git merge origin/dev` / `git rebase`
    把 dev 或其他人的合并内容回拉到当前分支。
  - 允许 `git fetch`（只更新远程跟踪引用，不改当前分支）。
  - 允许只读查询 `git log origin/X..origin/Y`。
- 如果 gh CLI 因为 base 分支冲突提示要本地 merge dev 再推，**不接受自动合并**：
  停止并让用户自行决定（冲突处理通常应该在 PR 页面或专门会话里做，而不是
  commit 流程里偷偷发生）。

#### 第一次问询（3 选项）

```
AskUserQuestion({
  questions: [{
    question: "本地提交已完成，下一步？",
    header: "推送/PR",
    multiSelect: false,
    options: [
      {
        label: "推送",
        description: "git push 当前分支到 origin，不创建 PR"
      },
      {
        label: "不推送",
        description: "保留在本地，由用户自行决定何时 push / PR"
      },
      {
        label: "推送并 PR 到 dev",
        description: "git push 当前分支 + gh pr create --base dev --head <当前分支>"
      }
    ]
  }]
})
```

**分支处理：**

- **推送**
  1. `git branch --show-current` 取当前分支 `$BR`
  2. `git push -u origin "$BR"`（本地分支名与远程对齐；`-u` 首次建 upstream）
  3. 严禁 push 到 `dev` / `pre`：若 `$BR in (dev, pre)` 则拒绝并告知"请用 PR 流程"
  4. 输出推送后的远程提交范围

- **不推送**
  输出「未推送到远程。如需推送请手动执行 `git push`。」结束。

- **推送并 PR 到 dev**
  1. 同"推送"步骤先 push 到 origin（**只 push 当前分支，不 pull dev 回来**）
  2. `gh auth status` 确认已登录；未登录则提示 `gh auth login` 后停止
  3. `gh pr create --base dev --head "$BR" --title "..." --body "..."`
     - title 取最显著那条 commit 的 subject（或用户指定）
     - body 用 HEREDOC 汇总本次所有 commit 摘要 + Test plan 占位；结尾附
       `🤖 Generated with [Claude Code](https://claude.com/claude-code)`
     - **不加** `--fill` 之类自动从 commit 生成 body 的参数（我们要精确控制 body）
     - **不做** 本地 merge / rebase dev；若 gh 报 base 有冲突，停止并告知用户
  4. 打印 PR URL
  5. **完成后进入下方"第二次问询"**（注意：**此时不做任何后续 git 操作**，
     特别是不要 `checkout dev` / `pull dev` 之类动作；当前分支保持原状）

#### 第二次问询（仅在"PR 到 dev"成功后触发）

```
AskUserQuestion({
  questions: [{
    question: "PR 到 dev 已创建，是否继续提 PR：dev → pre？",
    header: "升级 pre",
    multiSelect: false,
    options: [
      {
        label: "提 PR dev → pre",
        description: "gh pr create --base pre --head dev；合并后触发 deploy-pre 部署"
      },
      {
        label: "暂不提 pre",
        description: "等 dev PR 评审/合并后再决定；结束流程"
      }
    ]
  }]
})
```

**分支处理：**

- **提 PR dev → pre**
  1. `git fetch origin dev pre`（只更新远程跟踪引用 `origin/dev` / `origin/pre`，
     **不改当前分支**；**严禁 `git pull` / `merge` / `rebase` 回当前分支**）
  2. 检查 dev 比 pre 是否领先：`git log origin/pre..origin/dev --oneline | head -20`
     - 结果为空：告知"dev 未领先 pre，无可合并内容"，**不创建空 PR**
     - 有内容：进入下一步
  3. `gh pr create --base pre --head dev --title "chore: dev → pre" --body "..."`
     - body 放 "dev 领先 pre 的 commit 列表" + 部署影响说明占位
     - 这是"创建申请"，**不触发合并**；合并由 reviewer 在 GitHub 页面完成
  4. 打印 PR URL
  5. 全程**不切换分支**，不在当前分支执行任何 merge / rebase / pull

- **暂不提 pre**：输出"流程结束，可等 dev PR 合并后再手动操作。"

### 注意

- 严禁直接 push 到 `dev` / `pre`，必须走 PR（项目约定，见 CLAUDE.md 本地预检章节）
- 创建 PR 前 `gh auth status` 确认登录；未登录即停止并提示
- 若 `gh` 不可用（未安装 / 非 GitHub 仓库），退回"不推送"行为并提示用户手动操作

## Commit Message Convention

Follow the project's existing style: `type(scope): 描述`

**type 类型:**
- `feat`: 新功能或功能增强
- `fix`: 修复 bug
- `refactor`: 重构代码（不改变功能）
- `chore`: 构建、配置、依赖等杂项
- `docs`: 文档变更
- `style`: 代码格式调整（不影响逻辑）
- `test`: 测试相关
- `perf`: 性能优化

**scope**: Use the module or directory name (e.g., `game`, `api`, `proxy`, `router`, `config`)

**描述**: Use Chinese, concise and specific, describe WHAT changed and WHY

**Body**: Include bullet points listing specific changes when the commit covers multiple files or non-trivial changes

## Important Notes

- **Push / PR 必须先经 Step 8 的 AskUserQuestion**，不允许自行 push 或创建 PR
- **PR = 创建申请等待审查**。本流程**不做本地 merge**，也不代替 reviewer 合并；
  合并动作一律由 reviewer 在 GitHub PR 页面点 Merge 完成
- **当前分支保持干净**：流程中只允许 `git add / commit / push / fetch / log / diff`
  与 `gh pr create`；**严禁** `git pull` / `git merge` / `git rebase` /
  `git checkout <其他分支>` / `git reset --hard` 等会把别人的提交或合并结果带回
  当前分支的动作
- **绝不 push 到 `dev` / `pre`**：项目约定强制走 PR 审查（policy-pr / build-* 闸门）
- **禁止 `--force` / `--force-with-lease` push**，除非用户明确要求
- **NEVER use `git add .` or `git add -A`** — always stage specific files
- **NEVER commit files that look like secrets** (.env, credentials, keys) — warn the user if such files are detected
- **DO NOT create empty commits**
- **DO NOT force artificial splits** — if changes are logically one unit, commit them together
- **ALWAYS read the actual diff** before writing the commit message — do not guess based on filenames alone
- **ALWAYS wait for user confirmation** of the commit plan before executing
- If a commit fails (e.g., pre-commit hook), investigate and fix the issue, then create a NEW commit (do not amend)

## Error Handling

If git add or git commit fails:
- Report the specific error to the user
- Show which files were affected
- Ask the user how to proceed

If pre-commit hooks modify files:
- Re-stage the modified files
- Create a new commit attempt
- If hooks fail 3 times on the same commit, stop and ask the user
