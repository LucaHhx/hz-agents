---
description: 用 squash 合并 PR；重新写精简的 squash commit 文案，抓住压缩后的重点（body ≤ 7 行 / 1KB，git log 总长 < 10 行）
argument-hint: [PR号]
---

# /gh-pass — Squash 合并 PR

合并指定 PR（默认走 squash），**重新写**一段精简的 squash commit 文案覆盖 GitHub UI 的默认拼接。

## 尺寸 & 格式硬约束（违反必须重写）

- `--body` 文件（不含 subject）**≤ 7 行 / 1024 bytes**
- 最终 `git log -1 --format=%B` 看到的总长 = subject + 空行 + body = **< 10 行**
- subject **≤ 70 字符**，等于 PR title（gh 自动追加 ` (#N)`）

参考前置失败案例：`250d027` 的 squash body 是 **901 行 / 51KB**（默认拼接所有原始 commit），
本命令的存在就是为了**不接受**这种默认行为，把它压到 7 行内。

## 为什么要重新写文案

GitHub 默认行为：squash merge 时把 PR title + 所有原始 commit subject/body 拼到最终 commit body。
PR 大一点立刻就是几十条 commit 拼成几百行的 commit body，`git log` 卡得没法看。

`/gh-pass` 的存在就是为了 **不接受这种默认**：合并前**重写**一段抓住压缩后重点的文案，
通过 `gh pr merge --subject ... --body ...` 直接覆盖默认。

## 参数

- `$1` (可选) — PR 号。不传则取当前分支对应的 open PR。

## 执行步骤

### 1. 解析 PR 号

```bash
PR_NUM="$1"
if [ -z "$PR_NUM" ]; then
  PR_NUM=$(gh pr list --head "$(git branch --show-current)" --state open --json number -q '.[0].number')
fi
if [ -z "$PR_NUM" ] || [ "$PR_NUM" = "null" ]; then
  echo "未传 PR 号，且当前分支没有 open PR" && exit 1
fi
```

### 2. 前置检查

```bash
gh auth status
gh pr view "$PR_NUM" --json number,title,state,isDraft,mergeable,mergeStateStatus,headRefName,baseRefName,url
```

判断（**只看致命错**，CI 状态在 Step 2.5 单独处理）：

- `gh auth status` 失败 → 提示 `gh auth login`，停止
- `state` ≠ `OPEN` → 报"PR 已 #STATE，无法合并"，停止
- `isDraft` = true → 报"PR 是 draft，先 `gh pr ready` 转正"，停止
- `mergeable` = `CONFLICTING` → 报"有冲突，先解决"，停止
- `mergeable` = `UNKNOWN` → GitHub 还在算，等几秒重试一次；连续 3 次仍 UNKNOWN → 报错停止
- `mergeStateStatus` 只是参考字段，不在这里决策（CI 由 Step 2.5 处理；review 由 Step 2.6 处理）

### 2.5 等待 CI 完成（必跑，失败必须告知用户）

```bash
gh pr checks "$PR_NUM" 2>&1
```

先打印当前 check 列表给用户看（哪些 pass / pending / fail / skipping），然后：

```bash
gh pr checks "$PR_NUM" --watch --interval 10
```

`--watch` 阻塞直到所有 check 完成。期间打印进度。**禁止** 在这里跳过 / `--admin` / 用 `|| true`
吞错。

结果判断（看 `gh pr checks --watch` 的 exit code 与最终列表）：

- **全 pass / 部分 skipping** → 报告"CI 全过"，进入 Step 2.6
- **任一 fail / cancelled / timed_out** → **停下报错**，打印失败 check 名 + URL，AskUserQuestion：
  - 取消合并（推荐，让用户先修 CI）
  - 强制合并（仅当用户明确说要强合，且有权限 `--admin`；命令默认不主动建议）

  ```
  AskUserQuestion({
    questions: [{
      question: "CI 有失败：<failed check 名>。如何处理？",
      header: "CI 失败",
      multiSelect: false,
      options: [
        { label: "取消合并", description: "退出，让用户先修 CI（推荐）" },
        { label: "强制合并 --admin", description: "用户明确确认有权限且接受风险" }
      ]
    }]
  })
  ```

- **`--watch` 超时**（手动 Ctrl-C 或 gh 自身退出非 0 且无具体失败）→ 报告"等待异常，请手动查 PR 检查页面"，停止

### 2.6 检查 Reviewer 审查状态（**告知，不阻塞**）

```bash
gh pr view "$PR_NUM" --json reviewDecision,reviewRequests,latestReviews
```

判断并**告知用户**（不自动停下）：

- `reviewDecision = APPROVED` → 报告"已通过 review"
- `reviewDecision = CHANGES_REQUESTED` → 报告"有 reviewer 要求改动"，AskUserQuestion 让用户决定继续还是停
- `reviewDecision = REVIEW_REQUIRED` 且 `latestReviews` 为空 → 报告"还没人审查"，AskUserQuestion
- `reviewDecision = null`（仓库无 review 规则）→ 视为 OK，继续

不要自我假设 review 是否必需 —— 远端 branch protection 规则会在最终 `gh pr merge` 阶段拒绝，
我们的责任是**告知**用户当前状态。

### 3. 拉 PR 元数据 + 改动概览

```bash
gh pr view "$PR_NUM" --json title,body,commits,files,additions,deletions,labels,closingIssues
gh pr diff "$PR_NUM" --name-only
git log "origin/<base>..origin/<head>" --format='%h %s'
```

读取：

- PR title / body（参考但**不直接复用** body，body 通常已结构化但仍可能太啰嗦）
- commits 列表（数量 + 每个 subject，帮助归纳要点）
- files 列表（按目录分组，归纳影响面：server/ / web/ / worker/ / docs/ / ...）
- additions / deletions（改动规模感）
- closingIssues（关联 issue）
- labels（如 `breaking-change` / `needs-migration`，要在 body 里标出来）

### 4. 生成 squash 文案（**这是命令核心产出**）

#### Subject 规则

- 直接取 PR title
- **不**带 `(#N)` —— `gh pr merge` 会让 GitHub 自动补 ` (#N)`
- ≤ 70 字符

#### Body 模板（硬上限 7 行 / 1024 bytes）

```
<1 句话总结：本 PR 整体意图，让 git log -1 一眼看懂为什么有这次改动>

- <要点 1：WHAT 变了 + 必要的 WHY>
- <要点 2>
- <要点 3，最多 3-4 条>

关联：PR #<N>，closes #<issue>（若有）
```

7 行的预算分配（含空行）：

```
行 1: 1 句话总结
行 2: 空行
行 3-5: 3 条变更要点 bullet（紧凑情况）/ 行 3-6 共 4 条（较宽情况）
行 6 或 7: 空行
行 7 或最后: 关联 PR/issue
```

不要为了塞内容多塞 bullet —— 4 条是上限。装不下就**砍掉次要**的，不是延行。

#### 写要点（squash 文案的灵魂）

- **要点 ≠ commit subject 复述**。要点是把 N 个 commit 归纳成 3-5 条有信息量的变更
- 顺序：业务变更 → 协议/接口变更 → 重构 → 配置/文档 → 数据/资源
- 每条 ≤ 80 字符，单行
- 不要 "Improved X" / "Updated Y" 这种空话；要说**变成什么样了**
- 跨模块的连带改动放一条，不要按目录拆要点

#### 反例（不要这么写）

```
* feat(megaroulette): L1.1 ENUM ...
* docs(megaroulette): L1.2 DICT ...
* fix(megaroulette): L1.1 ENUM 修 ...
* refactor(fetch_client): 重构 PP ...
Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
---------
（901 行……）
```

#### 写到临时文件 + 自检（**硬上限 7 行 / 1024 bytes**）

```bash
mkdir -p .git/gh-pass
cat > .git/gh-pass/body.md <<'EOF'
<上面模板填好>
EOF

LINES=$(wc -l < .git/gh-pass/body.md)
BYTES=$(wc -c < .git/gh-pass/body.md)
if [ "$LINES" -gt 7 ] || [ "$BYTES" -gt 1024 ]; then
  echo "squash body 超限：$LINES 行 / $BYTES bytes（上限 7 / 1024），重写"
fi
```

**超限必须重写**：先砍非核心 bullet，再缩单行长度，**不放过**。
目标是 `git log -1 --format=%B` 看到的总长 = subject + 空行 + body **< 10 行**。

### 5. AskUserQuestion 让用户确认文案

加载工具：

```
ToolSearch({ query: "select:AskUserQuestion", max_results: 1 })
```

先把生成的 subject 和 body 完整 echo 到终端，再发起：

```
AskUserQuestion({
  questions: [{
    question: "Squash 合并 PR #<N>，文案确认？",
    header: "Squash 合并",
    multiSelect: false,
    options: [
      { label: "合并",     description: "用上面文案 gh pr merge --squash --subject ... --body-file ..." },
      { label: "调整文案", description: "由我说明怎么调，不合并" },
      { label: "取消",     description: "什么都不做" }
    ]
  }]
})
```

- 合并 → Step 6
- 调整 → 回到 Step 4 重写
- 取消 → 清理临时文件后停止

### 6. 执行合并

```bash
TITLE="<PR title 去掉可能的 (#N)>"

gh pr merge "$PR_NUM" \
  --squash \
  --subject "$TITLE" \
  --body-file .git/gh-pass/body.md
```

参数：

- 默认 `--squash`（命令名就是 pass = squash 通过）
- **不**用 `--merge` / `--rebase`（如果用户真要别的合并方式，手动 gh 或 GitHub UI）
- **不**用 `--admin` 绕过保护规则（除非用户明确要求）
- **不**用 `--auto`（等队列里慢慢轮的话用户自己挂 auto-merge）
- **不**用 `--delete-branch`（删分支单独问，见 Step 7）

### 7. 合并后：清理远端分支 + 对应本地 worktree

**选项顺序固定为「删除 / 保留」**，下面模板不要换。用户已养成肌肉记忆，第一项必须是「删除」。
即使该分支是 `live` / `main` / 长期分支等"显然该保留"的情况，也不要把「保留」挪到第一位 ——
顺序稳定优先于"推荐项靠前"。

> head 分支常是 `worktree-task-flow` / `pp-game-develop` 建的隔离 worktree（签出在 `.worktrees/<name>`）。
> 合并后远端分支 + 本地 worktree + 本地分支都成了死物，「删除」一次清干净。

```
AskUserQuestion({
  questions: [{
    question: "合并完成，是否删除远端 head 分支 <HEAD_BR>（+ 对应本地 worktree/分支）？",
    header: "删分支",
    multiSelect: false,
    options: [
      { label: "删除", description: "gh pr <N> 已 merged：删远端分支 + 移除对应本地 worktree + 本地分支，干净点" },
      { label: "保留", description: "远端分支 / worktree / 本地分支都保留，自己之后处理" }
    ]
  }]
})
```

- 保留 → 跳过（什么都不动）
- 删除 → 依次执行：
  1. **删远端**：`git push origin --delete "$HEAD_BR"`（或 `gh api -X DELETE "repos/{owner}/{repo}/git/refs/heads/$HEAD_BR"`）
  2. **清对应本地 worktree**（若 head 分支有 worktree 签出）：
     ```bash
     # git worktree list --porcelain 里找 head 分支对应的 worktree 路径
     WT_PATH=$(git worktree list --porcelain | awk -v b="refs/heads/$HEAD_BR" '
       /^worktree /{p=substr($0,10)} /^branch /{if($2==b) print p}')
     CUR=$(git rev-parse --show-toplevel)
     if [ -n "$WT_PATH" ] && [ "$WT_PATH" != "$CUR" ]; then
       git worktree remove "$WT_PATH"   # 工作区脏 / 加锁会拒绝（非 0），见下
     fi
     ```
  3. **删本地分支**：worktree 移除成功后 `git branch -D "$HEAD_BR"`（squash merge 后本地视角未 merged，故 `-D` 强删；分支已合入远端，安全）。

**安全护栏（铁律）**：
- `WT_PATH == CUR`（当前所在 / 主 worktree）→ **绝不移除**，跳过 worktree + 本地分支清理（只删远端），告知用户。
- `git worktree remove` 默认拒绝**脏工作区 / 加锁** worktree → **不擅自 `--force`**；残留就如实告知用户"有未提交改动/锁，手动 `git worktree remove --force <path>` 后再 `git branch -D`"。
- head 分支无对应 worktree（普通分支 PR）→ 跳过第 2 步，本地分支按需 `git branch -D`（删失败不强求，告知即可）。

### 8. 输出最终报告

```bash
gh pr view "$PR_NUM" --json mergedAt,mergeCommit -q '{at: .mergedAt, sha: .mergeCommit.oid}'
```

```
## /gh-pass 完成

PR #<N>: <URL>  → MERGED at <time>
squash commit: <sha>  
title: <title> (#<N>)
body: <LINES> 行 / <BYTES> bytes

远端 head 分支 <HEAD_BR>：<已删除 / 已保留>
本地 worktree <WT_PATH>：<已移除 / 无 / 跳过(当前 worktree) / 残留(脏，需手动 --force)>
本地分支 <HEAD_BR>：<已删除 / 已保留>

对比一下：默认 squash 拼接通常 500+ 行 / 30KB+，本次精简到 <LINES> 行 body / <BYTES> bytes
（git log 总长 < 10 行）。
```

### 9. 清理

```bash
rm -rf .git/gh-pass/
```

## 安全铁律

- **AskUserQuestion 选项顺序按本文档模板固定，禁止按场景倒**。用户已养成肌肉记忆，会习惯性选第一项；调换会误操作。"推荐"放 description 里说，不要靠重排
- **不**用 `--admin` 绕过保护规则 / required reviewers / required checks，除非用户明确要求
- **不**用 `--force` / `--force-with-lease`（merge 流程不该需要 force）
- 本地 worktree / 分支清理**仅在 Step 7 用户明确选「删除」时**做，且只针对 head 分支；绝不动当前 / 主 worktree（`WT_PATH==CUR` 跳过）
- `git worktree remove` **不擅自 `--force`**：脏工作区 / 锁 → 如实告知用户手动处理，不替用户丢未提交改动
- **不**碰当前 working tree 的分支（保持原状）
- **不**做 `git pull` / `merge` / `rebase` 把别人的提交带回本地（合并是远端动作）
- gh 未登录 → 停下提示
- mergeable=CONFLICTING → 让用户先解决冲突，**不**尝试自动 rebase
- CI 没过 / 审查不足（mergeStateStatus 异常）→ AskUserQuestion 让用户决定，**不**自动 `--admin` 跳过

## 错误处理

- `gh pr merge` 失败：
  - `Pull request is not mergeable` → 报告原因，让用户处理冲突 / 审查 / CI
  - `Resource not accessible` → 权限不足，提示用户用更高权限账号或找管理员
  - `Required status checks` 没过 → 停下让用户等 CI 或修复
  - 其他错误 → 原样报错，**不**自动重试

- 文案重写循环超过 3 次还超限 → 停下报"PR 改动太大，建议人工写 body 或拆分 PR"

## 与 /gh-commit、/gh-pr 的关系

```
/gh-commit  →  本地分批 commit（每条 commit message ≤ 9 行 / 1KB）
/gh-pr      →  push + 建 PR（PR body ≤ 100 行 / 10KB；给 reviewer 看）
/gh-pass    →  squash 合并（squash body ≤ 7 行 / 1KB；git log 总长 < 10 行）
```

三个命令各管一段，职责单一。`/gh-pass` 解决"squash commit 巨大导致 git log 卡顿"的根因——
**默认 GitHub 拼接被本命令的 `--subject` + `--body-file` 完全覆盖**，最终 commit body 始终在硬上限内。
