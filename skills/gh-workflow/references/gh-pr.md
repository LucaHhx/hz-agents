---
description: 推送当前分支 + 创建 GitHub PR（head/base 交互式确认）；PR body 控制在 100 行 / 10KB
---

# /gh-pr — 推送 + 建 PR

把当前分支推到远端，再用 `gh pr create` 建 PR（或 `gh pr edit` 更新已有 PR）。**只做 push + PR，不做合并**。
合并走 `/gh-pass`。

## 尺寸 & 格式硬约束（违反必须重写）

- PR title **≤ 70 字符**，沿用仓库风格 `<type>(<scope>): <题目>`，**不**带 `(#N)`
- PR body **≤ 100 行 / 10240 bytes**（这是 reviewer 视角文档，可比 commit/squash 详细）
- body 必须用模板段（`## Summary` / `## Test plan` / `## 关联`），**不**写成一坨段落
- bullet 用 `-`（**不**用 `*` / `•` / 数字）
- **不**夹 emoji 标题；**不**写 `🤖 Generated with Claude Code` / `Co-Authored-By:` 等签名
- **不**复述每个 commit subject（reviewer 看 PR commit 列表即可）
- **不**放敏感信息（token / secret / 内部 URL）

注意：`/gh-pass` 阶段会**重写**一份 ≤ 7 行的 squash body 覆盖 PR body，所以 PR body 大小不会
污染最终 commit history。这里 100 行的预算只给 reviewer 看。

## 执行步骤

### 1. 前置检查

并行跑：

```bash
git rev-parse --is-inside-work-tree
git branch --show-current
git status --porcelain
gh auth status
```

判断：

- 不在 git 仓库 → 报错停止
- `git status --porcelain` 非空 → 报错"工作树不干净，先跑 /gh-commit 或手动处理"，停止
- `gh auth status` 失败 → 提示 `gh auth login`，停止
- 当前分支属于 `main` / `master` / `dev` / `pre` / `develop` / `release` → 报错"不能从保护分支建 PR"，停止

### 2. 交互问 head 和 base（AskUserQuestion）

**这一步禁止做分支对比** —— 不跑 `git merge-base` / `git rev-list --count` / `git log A..B` / 多分支
fetch / ahead-behind 计算。这些都是浪费 token 的"主动验证"，head/base 确定前不需要。

唯一允许的本地读取（只读分支名，不读内容）：

```bash
gh repo view --json defaultBranchRef -q .defaultBranchRef.name
git branch -r --format='%(refname:short)' | grep '^origin/' | sed 's|^origin/||' | grep -v HEAD | sort -u
```

加载工具：

```
ToolSearch({ query: "select:AskUserQuestion", max_results: 1 })
```

**第一问：head 分支**

```
AskUserQuestion({
  questions: [{
    question: "PR 的 head（源分支）用哪个？",
    header: "head",
    multiSelect: false,
    options: [
      { label: "当前分支 <BR>",     description: "用 git branch --show-current 的结果（推荐）" },
      { label: "其他分支",          description: "由我手动指定 head 分支名" }
    ]
  }]
})
```

- 选当前分支 → `HEAD_BR=<当前分支>`
- 选其他 → 二次问要哪个；用户给名后 `git rev-parse --verify origin/<name>` 校验存在

**第二问：base 分支**

选项动态生成。常见值 `dev` / `pre` / `main` / `master` / 仓库默认分支去重，最多 4 个：

```
AskUserQuestion({
  questions: [{
    question: "PR 的 base（目标分支）用哪个？",
    header: "base",
    multiSelect: false,
    options: [
      { label: "dev",          description: "（如果远端有 dev 分支）" },
      { label: "main",         description: "（如果是仓库默认分支）" },
      { label: "pre",          description: "（如果远端有 pre 分支）" },
      { label: "其他",          description: "由我手动指定 base 分支名" }
    ]
  }]
})
```

只放实际存在的远端分支为选项。仓库默认分支放第一位标注"（默认分支，推荐）"。

校验：base ≠ head；base 远端存在（`git rev-parse --verify origin/<base>`）。

**到此为止仍不做 ahead/behind 比较**。push 时 git 自身会检测 fast-forward 关系，gh pr create 也会
拒绝空 PR；不需要预先 `git rev-list --count`。

### 3. 推送 head 分支

校验 head 不是保护分支后推送：

```bash
# 黑名单：main master dev pre develop release
case "$HEAD_BR" in
  main|master|dev|pre|develop|release)
    echo "拒绝 push 到保护分支 $HEAD_BR" && exit 1 ;;
esac

git fetch origin "$BASE_BR"
git push -u origin "$HEAD_BR"
```

- push 失败（rejected / non-fast-forward）→ 停下报告，**不要** `--force` / `--force-with-lease`，让用户自己决定
- push 成功 → 进入 Step 4

### 4. 检查已有 PR

```bash
gh pr list --head "$HEAD_BR" --base "$BASE_BR" --state open --json number,url -q '.[0]'
```

- 有结果 → 走"更新已有 PR"分支（Step 6）
- 无结果 → 走"新建 PR"分支（Step 5）

### 5. 新建 PR：准备 title + body

#### Title 规则

- 沿用仓库 commit 风格 `<type>(<scope>): <题目>`，≤ 70 字符
- 取材自 `git log $BASE_BR..$HEAD_BR --format='%s'`：
  - 单 commit → 直接用 subject
  - 多 commit → 概括为单句，type/scope 取主导项
- **不**带 `(#N)`（合并时 gh 会自动补）
- **不**用罗列分隔符 `+` 堆砌多 scope（除非确实没法浓缩，且仍 ≤ 70 字符）

#### Body 模板（硬上限 100 行 / 10240 bytes）

```
## Summary
- <要点 1：WHAT + WHY，1 行>
- <要点 2>
- <要点 3，3-5 条>

## 改动详情
（可选段，按需展开；多个子系统联动时分块更清晰）

### server/
- <要点>

### web/
- <要点>

## Test plan
- [ ] <验证项 1>
- [ ] <验证项 2>
- [ ] <验证项 3>

## 风险与回滚
- 风险：<潜在影响 / 灰度范围>
- 回滚：revert 此 PR 即可 / 需配合 <X>

## 关联
- closes #<issue 号>（若有）
- 上下游 PR #<PR 号>（若有）
```

段落都可选，按改动量取舍。小改动直接 Summary + Test plan + 关联 三段足够（≤ 20 行）。

#### 写到临时文件 + 自检（**硬上限 100 行 / 10240 bytes**）

```bash
mkdir -p .git/gh-pr
cat > .git/gh-pr/body.md <<'EOF'
<上面模板填好>
EOF

LINES=$(wc -l < .git/gh-pr/body.md)
BYTES=$(wc -c < .git/gh-pr/body.md)
if [ "$LINES" -gt 100 ] || [ "$BYTES" -gt 10240 ]; then
  echo "PR body 超限：$LINES 行 / $BYTES bytes（上限 100 / 10240），重写"
  # 砍可选段（改动详情 / 风险与回滚），把长说明拆成 docs/* 链接
fi
```

超限必须重写，**不要**放过。

#### 创建 PR

```bash
gh pr create \
  --base "$BASE_BR" \
  --head "$HEAD_BR" \
  --title "<title>" \
  --body-file .git/gh-pr/body.md
```

参数：

- **不**用 `--fill` / `--fill-first`（避免 gh 从 commit 自动拼 body）
- **不**用 `--draft`（除非用户明确说要 draft）

### 6. 更新已有 PR

```bash
gh pr edit "<PR_NUM>" --title "<新 title>" --body-file .git/gh-pr/body.md
```

更新前用 AskUserQuestion 确认要不要覆盖原 title / body（已有 PR 可能 reviewer 已经看过）：

```
AskUserQuestion({
  questions: [{
    question: "PR #<N> 已存在，如何处理？",
    header: "已存在 PR",
    multiSelect: false,
    options: [
      { label: "覆盖 title + body",    description: "用本次生成内容替换" },
      { label: "只补 commit 列表",     description: "保留原 title/body，只 push 让 commit 自动同步" },
      { label: "取消",                description: "什么都不做" }
    ]
  }]
})
```

### 7. 输出最终报告

```
## /gh-pr 完成

PR: <URL>
head: <HEAD_BR> → base: <BASE_BR>
title: <title>
body: <LINES> 行 / <BYTES> bytes

下一步：等 CI / reviewer，然后 `/gh-pass <N>` squash 合并。
```

### 8. 清理

```bash
rm -rf .git/gh-pr/
```

## 安全铁律

- **AskUserQuestion 选项顺序按本文档模板固定，禁止按场景倒**。用户已养成肌肉记忆，会习惯性选第一项；调换会误操作。"推荐"放 description 里说，不要靠重排
- **严禁** push 到 `main` / `master` / `dev` / `pre` / `develop` / `release`
- **严禁** `--force` / `--force-with-lease` —— push 被拒就停下让用户处理
- **严禁** `git pull` / `merge` / `rebase` 把 base 分支拉回 head —— 让 reviewer 在 PR 页面解决冲突，或用户自己专门处理
- **严禁** `--no-verify` 绕过 pre-push hook
- **gh** 未登录 / 不可用 → 停下提示，不要回退到"裸 git push 后跳过 PR"
- PR body **必须** ≤ 100 行 / ≤ 10240 bytes，超了重写不放过

## 错误处理

- `gh pr create` 失败（base 冲突 / 权限 / 标签缺失）→ 报具体错误，**不**自动重试，让用户介入
- push 被拒（non-fast-forward）→ 报告"远端有你本地没的提交"，让用户决定是 rebase 还是放弃；**不**自己 `--force`
- 网络问题 → 报错停止，不静默吞错
