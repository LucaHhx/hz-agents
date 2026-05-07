---
name: issue
description: 通用 GitHub issue 操作工具，基于 gh CLI 在当前 git 仓库内查询/管理 issue。触发场景：(1) /issue list 或自然语言"列出我的 issue" 列出我被分配的 open issue (2) /issue info ID 或用户单独发一个 issue 编号（如 "#60" / "60"）读详情 + 标 👀 + Project 状态切"修复中" + 基于当前仓库代码做根因分析并给修复方案报告（不动代码） (3) /issue fix ID 或自然语言"修复完成 #id / fix #id" 写修复评论 + 改 assignee 为发起人 + Project 状态切"待验收"。每个子命令执行前先 Read 对应的 references/CMD.md 拿完整规范。
---

# Issue Skill

通用 GitHub issue 操作。基于 `gh` CLI，工作在**当前 git 仓库**（`gh` 自动从 `origin` remote 推断 owner/repo）。

## 设计原则：按需加载子命令文档

本 SKILL.md **只做路由**，每个子命令的详细实现单独放在 `references/<cmd>.md`。
**执行某个子命令前，先 Read 对应的 `references/<cmd>.md` 拿到完整规范**，不要根据本文件的简介揣测实现。
这样做避免不同子命令的细节互相串扰。

## 前置检查（每次执行子命令前都跑）

```bash
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "当前目录不是 git 仓库"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "请先 gh auth login"; exit 1; }
```

任一失败 → 立即报告用户原因并停止，不要 fallback 猜 repo。

涉及 Project v2 状态修改时还需要 `read:project` + `project` scope；
缺权限时让用户跑：`gh auth refresh -s read:project,project`。

## 子命令路由表

| 触发 | 子命令 | 必读 references |
|------|--------|------------------|
| `/issue list`、"列出我的 issue / open issues assigned to me / 我的待办" | list | [references/list.md](references/list.md) |
| `/issue info <id>`、"看下 #id / 详情 #id / issue 60"、**list 之后用户只发数字（如 "60" / "#60"）** | info | [references/info.md](references/info.md) |
| `/issue fix <id>`、"修复完成 #id / fix #id / 提交 #id 修复" | fix | [references/fix.md](references/fix.md) |

**路由规则**：

1. 解析用户输入决定触发哪个子命令
2. **Read 该子命令对应的 `references/<cmd>.md`**（一次只读一个）
3. 按 references 文件里的 Step 1/2/... 执行

**Project 状态切换是 info / fix 共享逻辑**，需要时再 Read [references/project-status.md](references/project-status.md)。

## 后续子命令扩展约定

新增子命令时：

1. 在 `references/` 下新建 `<新命令>.md`，放完整 Step 1/2/... 实现
2. 在本 SKILL.md "子命令路由表"追加一行（触发词 + 命令名 + references 链接）
3. **不要**把详细实现塞回本 SKILL.md，保持本文件 ≤200 行

**已规划但未实现**（用户问起按"后续补充"答）：
- `comment <id>` — 写普通评论
- `close / reopen <id>` — 改状态
- `assign <id> <user>` — 手动改 assignee（fix 已包含自动改回发起人）

## gh CLI 通用注意事项

- **不要**用 `gh issue view --json projectItems` 直接读 project：默认 token 缺 `read:project` scope，会返回空数组。需要 project 操作时用 `gh api graphql`。
- **跨仓库**：用户明确指定 owner/repo 时加 `--repo owner/name`，不要默认跨仓库。
- **`@me`**：`--assignee @me` / `--mention @me` / `--author @me` 都被解析为当前登录用户。
- **Project 状态选项命名因项目而异**（"修复中" / "In Progress" / "Doing" 都可能）：按字符串包含匹配，找不到时报告候选选项让用户挑，不要硬编码 option ID。
