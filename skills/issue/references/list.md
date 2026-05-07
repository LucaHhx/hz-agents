# /issue list — 列出我的 open issue

**触发**：`/issue list` 或自然语言"列出我的 issue / open issues assigned to me / 我的待办"。

## Step 1 — 跑 list 命令

```bash
gh issue list \
  --state open \
  --assignee @me \
  --limit 50 \
  --json number,title,labels,assignees,updatedAt,url \
  | jq -r '.[] | "#\(.number)  \(.title)\n  labels: \(.labels | map(.name) | join(", "))\n  updated: \(.updatedAt)\n  \(.url)\n"'
```

## Step 2 — 输出格式给用户

按 updatedAt 倒序逐条渲染：

```
#55  Bug: Candy Drop 显示/记录 40x 但实际只按约 7x 结算
  labels: bug, Sweet Bonanza CandyLand, 通用
  updated: 2026-04-28T10:23:11Z
  https://github.com/owner/repo/issues/55
```

## Step 3 — 主动提示后续动作

末尾必须追加一句：

> 要查看哪条详情？发 issue 编号（`#60` / `60`）或 `/issue info 60`，我会读取详情、标 👀、Project 状态切"修复中"，并基于代码做根因分析给修复方案。

之后用户单独发数字（"60" / "#60" / "issue 60"）→ **自动按 info 子命令处理**，不要再追问。

## 边界

- 没有匹配 → 输出"当前仓库没有分配给你的 open issue"，不报错
- 用户要其它过滤（label / mentions / author / 全 repo）→ 用户明确说之后再加 `--label X` / `--mention @me` / `--author @me` / 去掉 `--assignee` 等参数，**不要预设**
- 默认按 updatedAt 倒序；用户要按 comments 数 / created 时间排，在 jq 里 `sort_by(...)` 即可
