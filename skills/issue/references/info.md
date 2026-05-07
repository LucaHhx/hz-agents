# /issue info `<id>` — 读详情 + 标 👀 + 切"修复中" + 根因分析报告

**触发**：
- 显式：`/issue info 60` / `/issue info #60`
- 自然语言："看下 #60 / 详情 #60 / issue 60"
- **list 之后用户单独发数字**（"60" / "#60"）也走这里

**底线原则**：本子命令**只读不改代码**。诊断 + 给方案，最后让用户决定下一步（通常是手动改后跑 `/issue fix`）。

## Step 1 — 拉详情

```bash
gh issue view "$ID" --json number,title,body,state,labels,assignees,author,url,comments,createdAt
```

把这些信息按下面格式展示给用户：

```
#<num>  <title>
  state: open|closed
  labels: a, b
  author: @<author>
  assignees: @<u1>, @<u2>
  url: https://...

<body 完整内容>
```

body 很长（>3000 字符）时，先展示前 1500 字符 + 提示"body 还有 N 字符未展示，继续？"——**不要**默认全展开占爆 token。

## Step 2 — 标 👀（reaction，不是评论）

**重要**：是给 issue 原帖加 eyes **reaction**，不是发一条 `👀` 评论。
评论会污染 issue 时间线、@ 通知所有 watcher、且无法自动去重。

```bash
OWNER_REPO=$(gh repo view --json owner,name --jq '.owner.login + "/" + .name')
gh api -X POST repos/$OWNER_REPO/issues/$ID/reactions -f content=eyes
```

API 对同一用户重复 POST 同一 reaction 是幂等的（返回已有 reaction 的 id），不需要先查重。

成功后告诉用户"已加 👀 reaction（已读标记）"。

**反例（不要这样做）**：`gh issue comment "$ID" --body "👀"` —— 这是发评论，会触发邮件/Slack 通知，且不是 GitHub 习惯用法。

## Step 3 — Project 状态切"修复中"

读取 [project-status.md](project-status.md) 的通用流程，target 名称匹配模式：

- 中文："修复中" / "进行中"
- 英文（不区分大小写）：`in progress` / `doing` / `working`

匹配不到 → 列出全部 status 选项让用户挑，**不要**硬编码 option ID。

## Step 4 — 基于代码做根因分析（核心步骤）

这是 info 与单纯"读详情"的关键区别。**必须**做：

### 4.1 解析 issue 内容，提取分析线索

从 issue body 里抽取：
- 复现步骤 / 输入数据（XML、JSON、URL、用户操作）
- 错误现象（错误码、日志片段、截图描述）
- 涉及功能名 / 模块名 / 文件路径 / 函数名（issue 作者可能直接给了路径如 `path/to/file.go:123`）
- 关键标识符（API 路径、协议字段、配置项、表名等）

如果 issue 没有这些线索 → 告诉用户"issue 缺少 X / Y 信息，无法定位代码层"，建议补充再来。

### 4.2 在 cwd 仓库里定位代码

按线索逐个搜索：

```bash
# 例：找跟某个标识符相关的所有引用
grep -rnE "<标识符>" --include="*.go" --include="*.vue" .

# 找跟某个文件名相关的实现
find . -name "<file pattern>" -not -path "./node_modules/*" -not -path "./.git/*"
```

或者用 Read 直接读 issue 提到的具体文件:行号。

定位时必须**多文件交叉验证**——单看一个文件可能误判，要看调用链 / 配置 / 测试，构建完整事实图。

### 4.3 分析根因

读关键代码后，写下：

- **现象**：用户看到什么（基于 issue body）
- **根因**：代码里**具体哪行 / 哪段逻辑**导致这个现象（必须给 `file:line` 引用）
- **触发条件**：什么情况下会复现（边界条件、配置依赖、并发等）
- **影响范围**：这个 bug 还会影响别的什么场景

**严禁纯臆测**。每个判断都要有代码 / 日志 / issue body 里的事实支撑。

### 4.4 给修复方案

给 1~3 个方案，每个方案标明：
- 改动点（哪些文件 / 函数）
- 优缺点 / 风险
- 改动量评估
- 推荐度

格式参考：

```
## 方案 A — <一句话总结> ⭐推荐
- 改动：path/to/file.go:123 改 X 为 Y；新增 path/to/helper.go
- 优点：xxx
- 缺点：xxx
- 改动量：~30 行

## 方案 B — <一句话总结>
...
```

### 4.5 输出报告

完整报告结构：

```markdown
## issue #<num>: <title>

### 现象
<...>

### 根因
<file:line 引用 + 代码片段（关键 5-15 行）+ 一句话解释为什么这导致现象>

### 影响范围
<...>

### 修复方案
<方案 A / B / C>

### 我建议
方案 X（理由）

要按这个走吗？需要的话我可以直接动手改，改完跑 `/issue fix <id>` 收尾。
```

## 边界

- 用户上下文已经讨论过这个 issue（之前已 info 过）→ Step 4 仍然跑，但报告可以引用之前的结论，不必重复全文
- issue 是 closed → 仍然跑 Step 1/4，跳过 Step 2/3（已读 + 状态切换无意义）
- issue 不在 cwd 仓库（用户给了 `--repo` 参数）→ Step 4 没法跑（cwd 不是相关代码），只输出 Step 1 详情 + 提示用户切到对应仓库再跑
