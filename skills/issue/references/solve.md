# /issue solve `<id>` — 端到端一键修复

**触发**：
- 显式：`/issue solve 60` / `/issue solve #60`
- 自然语言："修这个 issue / 帮我修 #60 / 一键修 #60 / 走 issue 修复流程 60 / end-to-end fix #60"

**与 info 的区别**：`info` 只读不改代码（分析 + 给方案 + 等用户后续手动驱动）。`solve` 是
**完整流程编排**——从读 issue → 拍方案 → 起 worktree → 改代码 → PR → CI → squash 合并 →
关 issue → 清理，全程只在 **2 个必要节点** AskUserQuestion：

1. **选方案**（info 报告完后，让用户拍板用哪个方案）
2. **合并确认**（实现 + 自测通过后，让用户回看 diff 再 OK 合并）

其他所有可预测决策（base=live、squash 文案、删远端分支、清 worktree）**用默认值，不问用户**。

## 前提

仓库必须遵循 `live` 作为主开发分支约定（pp-game 风格，见仓库 CLAUDE.md「分支说明」）。
非此约定的仓库走 [info.md](info.md) + 手动调用 using-git-worktrees / gh-pr / gh-pass，
**不**用本子命令——避免在非 live 仓库错送 base。

判断方式（前置检查）：

```bash
git ls-remote --heads origin live >/dev/null 2>&1 || {
  echo "远端无 live 分支，本仓库不适用 /issue solve；改用 /issue info + 手动流程" && exit 1
}
```

## Step 1 — 走完整 info 流程（不变）

Read [info.md](info.md) 完整跑 Step 1..4：拉详情 → 标 👀 → Project 切「修复中」→ 根因
分析 + 给 1-3 个修复方案。报告里必须明确列出方案 A/B/C，每个方案要有"改动点 / 优缺点 /
推荐度"，否则 Step 2 没法 AskUserQuestion 选。

**信息不足直接停**：`info.md` Step 4.1 已经规定 issue 缺线索（无复现 / 无代码引用）→
告诉用户"信息不全"，让用户补；本子命令在此场景也必须停下，**不进入** Step 2。

## Step 2 — AskUserQuestion 选方案（**唯一刚性确认点 1/2**）

加载工具：

```
ToolSearch({ query: "select:AskUserQuestion", max_results: 1 })
```

选项按 info 报告里的方案数动态生成（2-4 项）。**第一项**总是 info 报告推荐的方案，
标 "（推荐）"。**最后一项**总是"自由调整"用来支持用户改方案 / 加约束。

```
AskUserQuestion({
  questions: [{
    question: "选哪个修复方案？",
    header: "方案",
    multiSelect: false,
    options: [
      { label: "方案 A — <推荐方案一句话总结>", description: "<info 报告里方案 A 的改动点摘要>（推荐）" },
      { label: "方案 B — <方案二句话总结>",     description: "<改动点摘要>" },
      { label: "自由调整",                       description: "由我说明额外约束 / 改方案" }
    ]
  }]
})
```

- 用户选具体方案 → 记下 `$PLAN`（A / B / C），进入 Step 3
- 用户选"自由调整" → 让用户说约束，AI 重写方案 + 再 AskUserQuestion 一轮（最多 2 轮，
  避免无限循环；第 3 轮仍未拍板 → 报"方案尚未稳定，建议 /issue info 离线讨论"停止）

## Step 3 — 启动 worktree（**无用户输入**）

Skill 调用：

```
Skill({ skill: "using-git-worktrees", args: "基于 live 分支建 worktree 修 issue #<id>" })
```

但 using-git-worktrees 不直接接收"分支名 / base"参数 —— 它依赖 AI 在对话里把这些信息
当作上下文传过去。**本 Step 由 AI 直接执行下面命令**（而不是真的去 invoke skill），
按 using-git-worktrees 的约束做：

```bash
# 1) 确认 .worktrees 已被 ignore（项目本地 worktree 安全前提）
git check-ignore -q .worktrees || {
  echo ".worktrees 未在 .gitignore 中 → 不能项目本地建 worktree，改用全局路径" && exit 1
}

# 2) 派生分支名：fix/<id>-<slug>
#    slug 取自 issue title，最多 4 个英文单词或拼音 / 去标点 / kebab-case；
#    title 含中文且无明显英文关键词 → 用 issue 编号 + 截短 hash
ISSUE_TITLE=$(gh issue view "$ID" --json title -q .title)
SLUG=$(echo "$ISSUE_TITLE" | tr '[:upper:]' '[:lower:]' \
  | grep -oE '[a-z0-9]+' | head -4 | paste -sd '-' -)
[ -z "$SLUG" ] && SLUG="issue${ID}"
BR="fix/${ID}-${SLUG}"

# 3) 基于最新 origin/live 起 worktree
git fetch origin live
git worktree add ".worktrees/${BR##*/}" -b "$BR" origin/live

# 4) cd 进 worktree（后续所有命令在 worktree 内执行）
cd ".worktrees/${BR##*/}"
```

边界：
- 分支名已存在（同一 issue 二次走 solve）→ 报"分支 $BR 已存在，先 `git worktree remove` /
  `git branch -D`"，停下。**不**自动覆盖（怕丢用户半成品）。
- `.worktrees` 目录未 ignore → 用 `git worktree add ~/.config/superpowers/worktrees/<repo>/$BR ...`
  全局路径兜底（using-git-worktrees skill 的备选）。

## Step 4 — AI 实现选定方案（**无用户输入**）

在 worktree 内按 `$PLAN` 写代码。**任务范围严格限定方案 A/B/C 描述的改动点**——info 报告
方案里写"改 file.go:123" 就只改那里，不顺手做无关重构（CLAUDE.md「Surgical Changes」）。

跑自测：

```bash
# 仓库特有自测命令（pp-game：go test + go build + policy-pr 预检）
cd server && go test ./<相关包路径>/... 2>&1 | tail -10
cd server && go build ./... 2>&1 | tail -5
# policy-pr 预检（pp-game）
cd .. && git status -s | awk '{print $2}' | node scripts/ci/policy-pr.mjs --stdin
```

任一失败 → 修代码 / 拆文件（超 500 行走 CLAUDE.md「超行的拆法」）/ 让测试通过；**不要**
跳过测试 / `--no-verify`。

调试超过 3 轮还过不去测 → 停下报"实现遇到阻力 X，可能需要调整方案"，回到 Step 2 重选。

## Step 5 — AskUserQuestion 合并确认（**唯一刚性确认点 2/2**）

实现 + 自测全绿后，给用户一份 **diff 摘要 + 测试结果**，再 AskUserQuestion：

先 echo：

```bash
git diff --stat
echo "---"
git log --oneline -5  # 看上下文
echo "---"
# 测试摘要
echo "go test: <PASS / 用例数>"
echo "go build: <OK>"
echo "policy-pr: <OK>"
```

然后：

```
AskUserQuestion({
  questions: [{
    question: "实现完成，diff 看好 → 走 PR + auto squash 合并到 live？",
    header: "合并",
    multiSelect: false,
    options: [
      { label: "走",       description: "commit + push + PR + 等 CI + squash 合并 + fix 收尾（推荐）" },
      { label: "调整",     description: "由我说明哪里要改，AI 回到 Step 4 改了再回来确认" },
      { label: "取消",     description: "保留 worktree + 分支，由我手动后续；本子命令结束" }
    ]
  }]
})
```

- 走 → Step 6
- 调整 → 回 Step 4
- 取消 → 给用户保留状态 + 下一步指引，本子命令结束：

  ```
  ## /issue solve #<id> 用户取消（实现已完成，未合并）

  Worktree: <abs path>
  分支: <BR>（未 push）
  本地改动: <git diff --stat 摘要>

  ### 下一步可选

  - 继续 PR：`cd <worktree path> && git push -u origin <BR> && gh pr create --base live`
  - 改方案重跑：`/issue solve <id>` —— 提示：会基于最新 live 重新起 worktree，本次 worktree
    需手动 `git worktree remove --force` + `git branch -D <BR>` 清理
  - 彻底丢弃：上面两条命令清掉 worktree + 分支
  ```

## Step 6 — commit + push + 建 PR（**无用户输入**）

```bash
# 暂存所有变更（限定在 Step 4 实际改的文件，禁止 git add -A）
git add <step4 改的文件清单>

# Commit subject 沿用仓库风格 <type>(<scope>): #<issue> <题目>
# subject 来自 issue title 的精简化（≤70 字符）；body ≤ 7 行 / 1KB（与 gh-pass 上限一致）
git commit -m "$(cat <<EOF
<type>(<scope>): #${ID} <题目精简>

<1 句话总结：做了什么 + 为什么>

- <要点 1>
- <要点 2>
- <要点 3>

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"

# push head 分支
git push -u origin "$BR"

# 建 PR：base=live，head=$BR，body 走 gh-pr 模板（Summary / Test plan / 风险与回滚 / 关联）
# body ≤ 100 行 / 10KB；title=commit subject 去 (#N)
PR_BODY=$(cat <<'EOF'
## Summary
- <要点 1>
- <要点 2>

## 改动详情
- <可选段>

## Test plan
- [x] <自测项 1>
- [x] <自测项 2>
- [ ] <pre 环境验收项>

## 风险与回滚
- 风险：<...>
- 回滚：revert 此 PR 即可

## 关联
- closes #<id>
EOF
)
gh pr create --base live --head "$BR" --title "<title>" --body "$PR_BODY"
```

参数硬约束（与 gh-pr.md 一致）：
- **不**用 `--draft` / `--fill` / `--fill-first`
- title ≤ 70 字符，**不**带 `(#N)`
- body ≤ 100 行 / 10KB（自检超限砍可选段）

push 被拒（非 fast-forward）→ 停下让用户处理，**不** `--force`。

## Step 7 — 等 CI（**无用户输入；CI 失败必停**）

```bash
PR_NUM=$(gh pr list --head "$BR" --base live --state open --json number -q '.[0].number')
gh pr checks "$PR_NUM"           # 先 echo 当前状态
gh pr checks "$PR_NUM" --watch --interval 10
```

判断（与 gh-pass.md Step 2.5 一致）：

- **全 pass / skipping** → Step 8
- **任一 fail / cancelled / timed_out** → 停下报错 + 给下一步指引（**不**自动跳过 / `--admin`）：

  ```
  ## /issue solve #<id> 阻塞：CI 失败

  PR: #<PR_NUM> <URL>
  失败 check: <名称 + URL>
  Worktree: <path>（保留）

  ### 下一步可选

  - 修 CI 后重跑：`cd <worktree path>` 修代码 → `git commit --amend` 或新 commit →
    `git push` 触发新一轮 CI → 通过后 `/gh-pass <PR_NUM>` 完成合并 → 再 `/issue fix <id>`
  - 强制合并（高风险）：`gh pr merge <PR_NUM> --squash --admin`（仅当你有权限 + 确认 CI
    失败是 flake / 与本改动无关）
  - 取消：`gh pr close <PR_NUM> --delete-branch`、`git worktree remove --force <path>`
  ```

  然后 AskUserQuestion（修 / 强合 / 取消）让用户选；选完按选项执行。
- `--watch` 超时 → 报错停止 + 提示用户去 GitHub Actions 页面看具体情况

## Step 8 — squash merge（**无用户输入**）

squash body 走 gh-pass.md 上限：**≤ 7 行 / 1024 bytes**，由 AI 基于 PR title + commits +
files 概览生成（不复用 Step 6 的 PR body，那个 100 行太长）。

```bash
# 写 squash body 到 worktree 的 .git/gh-pr/body.md（注意 worktree 的 .git 是文件不是目录，
# 真实 gitdir 在 <repo>/.git/worktrees/<wt>/）
REAL_GITDIR=$(git rev-parse --git-dir)
mkdir -p "$REAL_GITDIR/gh-pass"
cat > "$REAL_GITDIR/gh-pass/body.md" <<'EOF'
<1 句话总结>

- <要点 1>
- <要点 2>
- <要点 3>

关联：closes #<id>
EOF

# 自检 ≤ 7 行 / ≤ 1024 bytes（超限砍 bullet 直至合规）
LINES=$(wc -l < "$REAL_GITDIR/gh-pass/body.md")
BYTES=$(wc -c < "$REAL_GITDIR/gh-pass/body.md")
[ "$LINES" -le 7 ] && [ "$BYTES" -le 1024 ] || { echo "squash body 超限"; exit 1; }

# 合并
TITLE=$(gh pr view "$PR_NUM" --json title -q .title)
gh pr merge "$PR_NUM" --squash \
  --subject "$TITLE" \
  --body-file "$REAL_GITDIR/gh-pass/body.md"
```

**不**用 `--admin` / `--auto` / `--delete-branch`。删分支单独走 Step 9。

合并失败 → 报错停止（保留 worktree + 分支让用户排查）。

## Step 9 — 删远端分支（**无用户输入**）

合并成功后默认删远端，**不**问用户。理由：分支已 merged，远端保留只是噪音；用户真要回滚
走 `git revert <squash sha>`，与远端分支无关。

```bash
git push origin --delete "$BR" 2>&1 | tail -3
```

删失败（已被别处删 / 权限）→ 仅 warn，不阻断后续 Step 10/11。

## Step 10 — /issue fix 收尾（**无用户输入**）

不真去 Skill invoke fix —— 直接执行 fix.md 的 Step 1..5 逻辑（避免 Skill 之间反复 ping
pong；fix.md 的核心是发评论 + 改 assignee + 切 Project 状态）：

```bash
# 1) 拉发起人 + 当前 assignees
META=$(gh issue view "$ID" --json author,assignees --jq '{author: .author.login, assignees: [.assignees[].login]}')
AUTHOR=$(echo "$META" | jq -r .author)

# 2) 写修复评论：基于 Step 4 实际改动 + Step 6 commit + Step 8 squash sha
SQUASH_SHA=$(gh pr view "$PR_NUM" --json mergeCommit -q .mergeCommit.oid)
cat > /tmp/issue-fix-${ID}.md <<EOF
## 修复方式

**根因**：<info Step 4.3 写过的 1-2 句根因，引用 file:line>

**修复点**：

1. <Step 4 实际改动 1>
2. <Step 4 实际改动 2>
3. <Step 4 实际改动 3，可选>

## 改动文件

| 文件 | 改动 |
|------|------|
| \`<file 1>\` | <一句话> |
| \`<file 2>\` | <一句话> |

## 验收

- ✅ <自测项 1>
- ✅ <自测项 2>
- ⏳ <pre 环境复测项>

## 关联

- PR #${PR_NUM}（已 squash merged 到 live：commit \`${SQUASH_SHA:0:8}\`）
EOF

# 3) 发评论
gh issue comment "$ID" --body-file /tmp/issue-fix-${ID}.md

# 4) Assignee 调整：移除当前所有非 author，加上 author
ARGS=(--add-assignee "$AUTHOR")
echo "$META" | jq -r '.assignees[]' | while read u; do
  [ "$u" != "$AUTHOR" ] && ARGS+=(--remove-assignee "$u")
done
gh issue edit "$ID" "${ARGS[@]}"

# 5) Project 状态切「待验收」（Read project-status.md 拿到 mutation 模板；option 名匹配
#    "待验收" / "to verify" / "pending review" / "qa"）
```

详细 Project 状态切换逻辑见 [project-status.md](project-status.md) Step A..D。

## Step 11 — 清理 worktree + 本地分支（**无用户输入**）

```bash
# 回到主仓库根（worktree 是 cwd 当前所在）
REPO_ROOT=$(git rev-parse --show-superproject-working-tree 2>/dev/null \
  || git -C "$(git rev-parse --git-common-dir)/.." rev-parse --show-toplevel)
cd "$REPO_ROOT"

# 删 worktree（强制：因为合并完已经无意义保留，且远端分支也已删）
git worktree remove --force ".worktrees/${BR##*/}"

# 删本地分支
git branch -D "$BR"
```

清理失败（worktree 内有未提交改动 / 锁文件）→ 仅 warn 给出手动命令，**不**阻断流程结束。

## Step 12 — 输出最终汇总 + 下一步提示

汇总 + **明确告诉用户接下来该干什么**——成功流程的下一步可能是被动等待（验收），也可能是
主动行动（部署正式服 / 修下一个 issue）。提示要给具体命令，不给空话。

```
## /issue solve #<id> 完成

| 阶段 | 结果 |
|------|------|
| 方案 | 方案 <PLAN> — <一句话> |
| Worktree | <path>（已清理） |
| PR | #<PR_NUM> <URL> → MERGED |
| Squash commit | <sha> |
| 远端分支 | 已删 |
| Issue 评论 | <comment URL> |
| Assignee | @<author>（原 @<self> 已移除） |
| Project 状态 | 修复中 → 待验收 |

### 下一步

- **被动等待**：@<author> 在 pre / prod 环境复测，Project 状态会切「验收通过」/「验收失败」
- **若验收失败**：重跑 `/issue solve <id>`（会基于最新 live 重新起 worktree，沿用本次根因 + 选别的方案）
- **部署正式服**（pp-game 风格仓库）：`gh pr create --base prod --head live` 让 deploy-prod.yml 自动发版
  —— 但**别立刻发**，先让 @<author> 在 pre 验过再走 prod
- **修下一个 issue**：`/issue list` 看待办 → 单发 issue 编号继续；或直接 `/issue solve <下一个 id>`
```

下一步提示要**条件化**——根据本次实际情况裁剪。例如：
- 仓库无 `prod` 分支 → 不提部署正式服
- closingIssuesReferences 还关了别的 issue → 也提"已自动关闭 #X #Y，无需手动操作"
- Step 7 CI 含 `deploy-pre.yml` 已跑 → 提"pre 环境已自动部署，可直接复测"

## 边界 / 失败保护

- **任一 Step 异常中断**（CI fail / merge fail / 等）→ **不要**自动 cleanup worktree +
  分支。让用户能在中断现场用 `git diff` / `gh pr view` 排查。最终汇总要清楚说明
  "Worktree 保留在 <path>，分支保留为 <BR>"，并给出"修完手动 `gh pr merge ...` /
  `/issue solve <id>` 重跑"的指引。
- **Step 5 用户选"取消"** → 同上：保留状态，输出指引，结束。
- **issue 关联多个 Project** → project-status.md 已规定遍历每个 Project；本 Step 10 沿用。
- **远端 live 在 Step 7 期间被推送新 commit** → squash merge 会失败（base 漂移）。
  报错让用户决定是 rebase / 重跑 / 走手动 `gh pr merge`。**不**自动 rebase（CLAUDE.md
  「不碰别人提交」）。
- **issue 是 closed** → 仍允许 solve（用户可能要补修历史 issue）；info Step 2/3 已对
  closed 做兼容（跳过 reaction + 状态切换）。

## 安全铁律

- **不**自动 push 到 `live` / `main` / `prod`：head 分支必须是 `fix/<id>-<slug>`，PR 把
  改动送到 live；live 自己不做 commit。
- **不**用 `--force` / `--no-verify` / `--admin`（除非用户明确说要强合且接受风险）。
- **不**自动跳过 CI 失败 / merge 冲突 / 测试失败——必停 + AskUserQuestion 或报错。
- **不**改 issue body / 标题 / 标签——只发评论 + 改 assignee + 切 Project 状态。
- **不**在 worktree 外的代码上做改动（防 cross-worktree 污染）。
