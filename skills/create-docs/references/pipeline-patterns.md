# 流水线共享模式

> 本文件定义 5 个流水线命令（hz-init, unify-doc-review, cmd-autocode, unify-dev, unify-fix）的共享模式。
> 命令文件可引用此处定义，避免重复。

## 1. 参数解析模式

所有命令读取 `$ARGUMENTS`，拆分为 **需求标识** 和 **用户指令** 两部分：

**拆分规则**: 取第一个 token（空格分隔）作为需求标识，剩余部分作为 `USER_INSTRUCTIONS`。

示例:
- `/command 7 先实现后端` → 需求标识=`7`, USER_INSTRUCTIONS=`先实现后端`
- `/command 7` → 需求标识=`7`, USER_INSTRUCTIONS=空
- `/command` → 需求标识=空, USER_INSTRUCTIONS=空

**需求匹配**（用需求标识部分）：
- **需求标识为空** → 扫描 `docs/` 下所有需求目录（排除 project.md, tasks.md, CHANGELOG.md, fixes/），使用 AskUserQuestion 列出让用户选择
- **需求标识非空** → 按顺序尝试:
  1. 精确匹配: `docs/{需求标识}/` 存在？
  2. ID 匹配: `docs/{需求标识}-*/` 存在？
  3. 短名匹配: `docs/*-{需求标识}/` 存在？
  4. 全部失败 → 报错，列出可用需求目录，**停止执行**
- **匹配到多个** → 使用 AskUserQuestion 列出候选让用户选择

## 2. Git 提交模式

流水线命令完成后的标准 Git 提交流程：

1. 运行 `git status` + `git diff --stat` 展示变更概要
2. 使用 AskUserQuestion 询问用户是否提交:
   - 选项: 提交 / 不提交 / 修改后再提交
3. 用户批准后提交:
   - commit message 格式: `<type>(<REQ_NAME>): <command> <描述>`
4. **绝不自动提交**，必须等待用户明确批准

## 3. 团队清理模式

团队工作完成后的标准清理流程：

1. 发送 shutdown_request 给所有团队成员
2. 等待成员确认关闭
3. 执行 TeamDelete 清理团队

## 4. 前置检查模式

使用 `docs.py check` 进行前置文件检查：

```bash
python3 .claude/skills/create-docs/scripts/docs.py check <req-name> --phase <phase>
```

phase 取值: review-tech / review-ui / review-all / dev / dev-full / qa

输出 JSON: `{"pass": bool, "missing": [], "warnings": [], "suggested_fix": "..."}`

- `pass: false` → 输出缺失项和修复建议，**停止执行**
- `pass: true` → 继续下一步

## 5. Agent 启动前置读取

所有 agent 的 prompt 中应包含标准的前置读取指令：

```
先读取 create-docs skill 的 SKILL.md (.claude/skills/create-docs/SKILL.md) 了解文档规范和 CLI 用法。
再读取 references/tech-stack.md (.claude/skills/create-docs/references/tech-stack.md) 了解项目技术栈。
再读取 references/update-guide.md (.claude/skills/create-docs/references/update-guide.md) 了解更新规则。
```

Tech Lead 额外读取:
```
再读取 hab-temp skill (.claude/skills/hab-temp/SKILL.md) 了解模板架构规范。
再读取 hab-autocode skill (.claude/skills/hab-autocode/SKILL.md) 了解 AutoCode API 用法。
```
