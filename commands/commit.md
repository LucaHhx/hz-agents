---
description: 分析未提交代码，按模块/功能分类分批提交，自动生成规范的 commit message（不推送）
---

# Smart Commit - 智能分批提交

分析当前所有未提交的变更，按模块或功能维度分类，分批创建 git commit，每个 commit 附带规范的中文注释。不执行 git push。

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

### 3. 分类变更

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

### 4. 制定提交计划

Create a numbered plan listing each commit group:

```
提交计划:
1. feat(module): 描述 — file1.go, file2.go
2. fix(module): 描述 — file3.go
3. refactor(module): 描述 — file4.go, file5.go
```

Present this plan to the user and wait for confirmation before proceeding. Use AskUserQuestion tool to ask: "以上是分批提交计划，是否确认执行？如需调整请说明。"

### 5. 按计划逐个提交

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

3. Create commit with descriptive message following the project's convention:
   ```bash
   git commit -m "$(cat <<'EOF'
   type(scope): 简明描述

   - 具体变更点1
   - 具体变更点2

   Co-Authored-By: Claude <noreply@anthropic.com>
   EOF
   )"
   ```

4. Verify the commit was created:
   ```bash
   git log -1 --oneline
   ```

Then proceed to the next commit group.

### 6. 输出最终报告

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

**未推送到远程。** 如需推送请手动执行 `git push`。
```

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

- **NEVER run git push** — only create local commits
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
