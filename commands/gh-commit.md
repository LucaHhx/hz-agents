---
description: 分析未提交变更，按模块/功能分类，分批创建本地 commit（不 push、不建 PR）
---

# /gh-commit — 智能分批本地提交

把当前所有未提交变更（已修改 / 已暂存 / 未跟踪）按逻辑单元分类，分批 stage + commit，
每个 commit 附 `<type>(<scope>): <题目>` 规范信息。**只做本地 commit，不 push、不建 PR、不问后续**。

push 走 `/gh-pr`，合并走 `/gh-pass`，职责单一。

## 尺寸 & 格式硬约束（违反必须重写）

单个 commit message **总行数 ≤ 9（即 < 10 行）**、**字节数 ≤ 1024**。结构：

```
<type>(<scope>): <题目>          ← 第 1 行：subject，≤ 70 字符，无句末标点
                                  ← 第 2 行：空行（subject 有 body 时必填）
- <要点 1>                        ← 第 3-9 行：body bullets，每行 ≤ 80 字符
- <要点 2>
- <要点 3>
```

- subject 必须 `<type>(<scope>): <题目>` 三段式，type 见下方 type 表，scope 用模块/目录名
- body 可省略（琐碎改动）；如有则用 `-` bullet，最多 7 条
- **不**用 `*` / `•` / 数字编号开头
- **不**写 `Co-Authored-By: Claude` / `🤖 Generated with Claude Code` 等签名（除非仓库历史本来就有）
- **不**在 body 里放完整文件路径列表（reviewer 看 `git show` 即可）

每个 commit 落地前用 wc 自检（见 Step 6.4），超限就重写、砍 bullet 数，**不放过**。

## 执行步骤

### 1. 收集变更状态

并行跑：

```bash
git status
git diff --stat
git diff --cached --stat
git log --oneline -5
```

若 working tree 干净（status 空 + 无 untracked）→ 报告"无可提交变更"，停止。

### 2. 读每个改动文件的真实 diff

对每个改动文件跑 `git diff <file>`（或 staged 的 `git diff --cached <file>`），**读完再写 commit message**。
不要凭文件名猜内容。

### 3. 仓库自适应预检（policy-pr.mjs）

仅在仓库根存在 `scripts/ci/policy-pr.mjs` 时跑（多数仓库没有，直接跳过）：

```bash
if [ -f scripts/ci/policy-pr.mjs ]; then
  { git diff --name-only --diff-filter=ACMR; git ls-files --others --exclude-standard; } \
    | node scripts/ci/policy-pr.mjs --stdin
fi
```

- 输出 `all within limits` → 通过，进入 Step 4
- 输出 `violations found`（控制流嵌套 / 单文件行数 / 等）→ **停下报告**，让用户先修。
  不要绕过、不要 `--no-verify`、不要在本命令里强行改超限代码

脚本不存在 / `node` 不存在 → 静默跳过，继续。

### 4. 分类变更（按逻辑单元分组）

优先级（从高到低）：

1. **按功能/特性**：同一 feature / bugfix 的多文件一起
2. **按模块/目录**：同一包/目录的紧耦合改动一起（如 handler + 它的 test、model + 它的 migration）
3. **按变更类型**：重构、新功能、bug 修复、配置变更、文档拆开

规则：

- 紧耦合文件必须同 commit
- 配置类变更（go.mod / package.json / 配置文件）可单独分组，也可挂到它支持的 feature
- **untracked 资源目录（如 client/ / assets/ / static/）必须纳入计划**，通常单独一个 `chore` commit。
  不要因为不是代码文件就跳过
- 全部改动若紧密相关只服务一个目的 → 一个 commit，不要硬拆

### 5. 展示提交计划（不预确认，直接进入提交）

把分类结果用文字列出来给用户看，**不**调 AskUserQuestion 等确认：

```
提交计划：
1. feat(module): 描述 — file1.go, file2.go
2. fix(module): 描述 — file3.go
3. chore(client): 资源同步 — client/foo/, client/bar/
```

直接进入 Step 6 逐个提交。

理由：本地 commit 是**可逆**的（`git reset --soft HEAD~N` 可撤回），不像 push / PR 有外部副作用，
不需要每次预确认。用户中途想停 → 直接打断；提交完不满意 → `git reset` / `git commit --amend` 改。

**例外**——以下情况停下问用户，**不**直接提交：

- 计划里**任何 commit** 涉及疑似敏感文件（`.env` / `credentials*` / `*.key` / `*.pem` / `id_rsa*`）
- 计划里某个 commit 跨越 ≥ 5 个目录或 ≥ 20 个文件（分类很可能不对，先让用户看一眼）
- diff 里出现**用户未明确提及**的大段删除（> 100 行），怕误删

这些场景用 AskUserQuestion 单独问，不要硬走。

### 6. 按计划逐个 stage + commit

对计划里每一组依次执行：

1. **只 stage 本组文件**（用具体文件名，**严禁** `git add .` / `git add -A`）：

   ```bash
   git add <file1> <file2> ...
   ```

2. 校验 stage 结果：

   ```bash
   git diff --cached --stat
   ```

   只有本组文件 staged 才继续。

3. **本批兜底预检**（仅当 Step 3 跑过 policy-pr）：

   ```bash
   git diff --cached --name-only --diff-filter=ACMR | node scripts/ci/policy-pr.mjs --stdin
   ```

   违规则停下让用户修。修完重新 `git add` 再跑本步。**不要** `--no-verify`。

4. **先把 commit message 写到临时文件 + wc 自检**（硬上限 9 行 / 1024 bytes）：

   ```bash
   mkdir -p .git/gh-commit
   cat > .git/gh-commit/msg.txt <<'EOF'
   type(scope): 简明题目（中文，≤ 70 字符）

   - 具体变更点 1
   - 具体变更点 2
   EOF

   LINES=$(wc -l < .git/gh-commit/msg.txt)
   BYTES=$(wc -c < .git/gh-commit/msg.txt)
   SUBJ_LEN=$(head -1 .git/gh-commit/msg.txt | wc -c)
   if [ "$LINES" -gt 9 ] || [ "$BYTES" -gt 1024 ] || [ "$SUBJ_LEN" -gt 71 ]; then
     echo "commit message 超限：$LINES 行 / $BYTES bytes / subject $SUBJ_LEN 字符"
     echo "上限 9 行 / 1024 bytes / subject ≤ 70 字符。重写。"
     # 砍 bullet 数 / 缩短表述，再次自检
   fi
   ```

   超限**不**放过，重写到合规为止。多文件改动归纳不下来 → 提示可能要拆 commit。

5. 用临时文件创建 commit：

   ```bash
   git commit -F .git/gh-commit/msg.txt
   ```

6. 校验 commit 成功：

   ```bash
   git log -1 --oneline
   ```

7. 进入下一组。

### 7. 输出最终报告

```bash
git log --oneline -<N>
```

格式：

```
## gh-commit 完成

共创建 N 个提交：
1. abc1234 feat(module): 描述
2. def5678 fix(module): 描述
...

下一步：/gh-pr 发起 PR，或继续本地修改。
```

**到此结束**。**不**问 push，**不**建 PR。

## Commit Message 规范

格式：`<type>(<scope>): <题目>`

**type**:
- `feat` — 新功能 / 功能增强
- `fix` — 修复 bug
- `refactor` — 重构（不改行为）
- `chore` — 构建 / 配置 / 依赖 / 资源同步
- `docs` — 文档
- `style` — 纯格式
- `test` — 测试
- `perf` — 性能

**scope**: 模块或目录名（如 `game`、`api`、`router`、`config`）

**题目**: 中文，简洁具体，说 WHAT + 必要的 WHY

**body**: 多文件或非平凡改动时用 bullet 列要点；琐碎改动可省略

不写 `🤖 Generated with Claude Code` / `Co-Authored-By: Claude` 等签名（除非仓库历史本来就有）。

## 安全铁律

- **严禁** `git pull` / `git merge` / `git rebase` / `git checkout <他分支>` / `git reset --hard` —— 这些会把别人的提交带回当前分支。本命令只做 add / commit / 只读 git log/diff
- **严禁** `git add .` / `git add -A` —— 永远显式列文件
- **严禁** `--no-verify` 绕过 hook —— hook 失败先看原因再修
- **严禁** `--amend` 改已有 commit —— 失败重新建 NEW commit
- **检测到敏感文件** (`.env` / `credentials*` / `*.key` / `*.pem` / `id_rsa*`) → 警告并从计划剔除，请用户确认后再决定
- **不创建空 commit**
- **不硬拆逻辑单元**

## 错误处理

`git add` / `commit` 失败：

- 报具体错误 + 受影响文件
- 询问用户怎么办，不自行重试

pre-commit hook 改了文件：

- 重新 `git add` 修改过的文件，再次 commit
- 同一 commit hook 失败 3 次 → 停下让用户介入
