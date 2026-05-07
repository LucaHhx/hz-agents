# /issue fix `<id>` — 写修复评论 + 改 assignee 为发起人 + 切"待验收"

**触发**：`/issue fix 60` / `/issue fix #60` / 自然语言"修复完成 #60 / fix #60 / 提交 60 修复"。

**前提**：通常已经在当前会话里完成了代码修改 + commit。fix 子命令负责把"修复完成"这件事**广播**到 issue / project / assignee。

## Step 1 — 收集修复说明 body

按优先级取：

1. **当前会话已讨论过修复方案** → 基于上下文写评论 body（推荐：用本文末尾的[模板](#修复评论模板)，引用具体改动文件 + 修复要点）
2. **用户主动提供 body 文本或 markdown 文件路径** → 直接用
3. **没有上下文** → **询问用户**修复内容，**不要**自动从 git log 拼造（容易写错关键点）

把 body 写到 `/tmp/issue-fix-<id>.md`。

## Step 2 — 拉发起人 + 当前 assignees

```bash
gh issue view "$ID" --json author,assignees \
  --jq '{author: .author.login, assignees: [.assignees[].login]}'
```

记下：
- `$AUTHOR` — issue 创建者（fix 完成后要把 assignee 转给这个人）
- `$ASSIGNEES` — 当前所有 assignees（除发起人外都要 remove）

## Step 3 — 写修复评论

```bash
gh issue comment "$ID" --body-file /tmp/issue-fix-<id>.md
```

成功后打印评论 URL 给用户。

## Step 4 — 调整 Assignees

把当前 assignee 全部移除（除发起人本身），添加发起人：

```bash
ARGS=(--add-assignee "$AUTHOR")
for u in $ASSIGNEES; do
  if [ "$u" != "$AUTHOR" ]; then
    ARGS+=(--remove-assignee "$u")
  fi
done
gh issue edit "$ID" "${ARGS[@]}"
```

边界：
- 发起人本身就是当前唯一 assignee → 跳过整步并告知用户
- 发起人不接受 assignee（罕见，比如 bot）→ 让 GitHub 自己拒绝再报错

## Step 5 — Project 状态切"待验收"

读取 [project-status.md](project-status.md) 的通用流程，target 名称匹配模式：

- 中文："待验收" / "验收中" / "待 QA" / "待测试" / "QA"
- 英文（不区分大小写）：`pending review` / `for review` / `to verify` / `qa` / `ready for qa`

注意每个项目"完成"语义不同（"待验收" vs "验收通过"是两个不同状态），按字符串匹配最像"等待人工验收"的那个；找不到时列全部选项让用户挑。

## Step 6 — 输出汇总

```
## /issue fix #<id> 完成

| 操作 | 结果 |
|------|------|
| 修复评论 | <comment url> |
| Assignee → @<author> | ✅ |
| Project "<title>" 状态 → 待验收 | ✅ |
```

## 修复评论模板

参考 issue #55/#56 的修复评论结构（已被验收），通用模板：

```markdown
## 修复方式

**根因**：<一两句说清问题真因，引用具体 file:line>

**修复点**：

1. <子改动 1：用了什么机制 / 涉及函数 / 文件>
2. <子改动 2>
3. ...

## 改动文件

| 文件 | 改动 |
|------|------|
| `path/to/file.go` | <一句话描述> |
| `path/to/other.go` | <一句话描述> |

## 验收

- ✅ <验收点 1>
- ✅ <验收点 2>
- ✅ <验收点 3>
```

模板原则：
- 评论聚焦"改了什么 + 怎么验"，**不需要**列每行 commit hash / diff（PR 页面已有）
- 改动文件表用一行总结每个文件的语义变化
- 验收清单跟 issue body 里的"验收标准"逐条对齐（如果 issue 给了的话）
