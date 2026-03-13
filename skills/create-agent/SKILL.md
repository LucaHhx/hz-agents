---
name: create-agent
description: This skill should be used when the user asks to "create an agent", "add an agent", "write a subagent", "agent frontmatter", "when to use description", "agent examples", "agent tools", "agent colors", "autonomous agent", or needs guidance on agent structure, system prompts, triggering conditions, or agent development best practices for Claude Code plugins.
version: 0.2.0
---

# Agent (Subagent) Development for Claude Code

## Overview

Subagents are specialized AI assistants that handle specific types of tasks. Each subagent runs in its own context window with a custom system prompt, specific tool access, and independent permissions. When Claude encounters a task that matches a subagent's description, it delegates to that subagent, which works independently and returns results.

**Key concepts:**
- Subagents are FOR autonomous work, commands are FOR user-initiated actions
- Markdown file format with YAML frontmatter
- Triggering via description field with examples
- System prompt defines agent behavior
- Subagents cannot spawn other subagents

## Agent File Structure

### Complete Format

```markdown
---
name: agent-identifier
description: |
  Use this agent when [triggering conditions].

  <example>
  Context: [Situation description]
  user: "[User request]"
  assistant: "[How assistant should respond and use this agent]"
  <commentary>
  [Why this agent should be triggered]
  </commentary>
  </example>

model: inherit
tools: Read, Grep, Glob
---

You are [agent role description]...

**Your Core Responsibilities:**
1. [Responsibility 1]
2. [Responsibility 2]

**Analysis Process:**
[Step-by-step workflow]

**Output Format:**
[What to return]
```

## Frontmatter Fields

### 完整字段表（对齐官方文档）

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | 唯一标识符，小写字母+连字符 |
| `description` | Yes | 触发条件描述，包含 `<example>` 块 |
| `tools` | No | 逗号分隔的工具列表（如 `Read, Grep, Glob`），省略则继承全部 |
| `disallowedTools` | No | 禁止的工具列表，从继承或指定列表中移除 |
| `model` | No | `sonnet` / `opus` / `haiku` / 完整模型ID（如 `claude-opus-4-6`） / `inherit`，默认 `inherit` |
| `permissionMode` | No | 权限模式：`default` / `acceptEdits` / `dontAsk` / `bypassPermissions` / `plan` |
| `maxTurns` | No | 最大 agentic 轮次 |
| `skills` | No | 预加载的 skill 列表，完整内容注入 subagent 上下文（subagent 不继承父会话的 skills） |
| `mcpServers` | No | MCP 服务器配置（内联定义或引用已配置的服务器名） |
| `hooks` | No | 生命周期钩子（PreToolUse / PostToolUse / Stop） |
| `memory` | No | 持久化记忆范围：`user` / `project` / `local` |
| `background` | No | 是否后台运行，默认 `false` |
| `isolation` | No | 设置为 `worktree` 在临时 git worktree 中运行，获得仓库的隔离副本 |

### name (required)

Agent identifier used for namespacing and invocation.

**Format:** lowercase, numbers, hyphens only
**Length:** 3-50 characters
**Pattern:** Must start and end with alphanumeric

**Good examples:** `code-reviewer`, `test-generator`, `api-docs-writer`
**Bad examples:** `helper` (too generic), `-agent-` (starts/ends with hyphen), `my_agent` (underscores)

### description (required)

Defines when Claude should trigger this agent. **This is the most critical field.**

**Must include:**
1. Triggering conditions ("Use this agent when...")
2. Multiple `<example>` blocks showing usage
3. Context, user request, and assistant response in each example
4. `<commentary>` explaining why agent triggers

**Best practices:**
- Include 2-4 concrete examples
- Show proactive and reactive triggering
- Cover different phrasings of same intent
- Be specific about when NOT to use the agent

### tools (optional)

**格式：逗号分隔字符串（不是 YAML 数组）**

```yaml
# ✅ 正确格式
tools: Read, Write, Grep, Bash

# ❌ 错误格式
tools: ["Read", "Write", "Grep"]
```

**Default:** If omitted, agent has access to all tools

**Common tool sets:**
- Read-only analysis: `tools: Read, Grep, Glob`
- Code generation: `tools: Read, Write, Grep, Bash`
- Full access: Omit field entirely

#### 限制子 agent 生成

使用 `Agent(agent_type)` 语法限制可生成的 subagent 类型：

```yaml
# 只允许生成 worker 和 researcher 两种 subagent
tools: Agent(worker, researcher), Read, Bash

# 允许生成任意 subagent
tools: Agent, Read, Bash

# 省略 Agent 则完全禁止生成 subagent
tools: Read, Bash
```

注意：此限制仅对通过 `claude --agent` 运行的主线程 agent 有效。Subagent 本身不能再生成 subagent。

### disallowedTools (optional)

工具黑名单，从继承或指定的工具列表中移除：

```yaml
tools: Read, Grep, Glob, Bash
disallowedTools: Write, Edit
```

### model (optional)

```yaml
model: inherit    # 继承父会话模型（默认值）
model: sonnet     # Claude Sonnet
model: opus       # Claude Opus
model: haiku      # Claude Haiku
model: claude-opus-4-6  # 完整模型 ID
```

**Recommendation:** Use `inherit` unless agent needs specific model capabilities.

### permissionMode (optional)

控制 subagent 的权限处理方式：

| Mode | Behavior |
|------|----------|
| `default` | 标准权限检查，弹出提示 |
| `acceptEdits` | 自动接受文件编辑 |
| `dontAsk` | 自动拒绝权限提示（已明确允许的工具仍有效） |
| `bypassPermissions` | 跳过所有权限检查（谨慎使用） |
| `plan` | Plan 模式（只读探索） |

如果父会话使用 `bypassPermissions`，则会优先生效且不可被覆盖。

### skills (optional)

预加载 skill 内容到 subagent 上下文：

```yaml
skills:
  - api-conventions
  - error-handling-patterns
```

完整的 skill 内容会被注入 subagent 上下文，而不仅仅是使其可调用。Subagent 不继承父会话的 skills，必须显式列出。

### memory (optional)

给 subagent 一个持久化目录，跨会话保留知识：

```yaml
memory: user      # ~/.claude/agent-memory/<name>/    — 所有项目共享
memory: project   # .claude/agent-memory/<name>/      — 项目级，可提交版本控制
memory: local     # .claude/agent-memory-local/<name>/ — 项目级，不入版本控制
```

启用后：
- 系统提示包含读写记忆目录的指令
- 包含 `MEMORY.md` 的前 200 行
- 自动启用 Read, Write, Edit 工具

### hooks (optional)

在 subagent frontmatter 中定义生命周期钩子：

```yaml
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "./scripts/validate-command.sh"
  PostToolUse:
    - matcher: "Edit|Write"
      hooks:
        - type: command
          command: "./scripts/run-linter.sh"
```

支持的事件：`PreToolUse`（工具执行前）、`PostToolUse`（工具执行后）、`Stop`（subagent 完成时，运行时转为 SubagentStop）。

### mcpServers (optional)

给 subagent 配置 MCP 服务器：

```yaml
mcpServers:
  # 内联定义：仅此 subagent 可用
  - playwright:
      type: stdio
      command: npx
      args: ["-y", "@playwright/mcp@latest"]
  # 引用已有配置
  - github
```

内联定义的服务器在 subagent 启动时连接、完成时断开。

### background (optional)

```yaml
background: true  # 始终后台运行此 subagent
```

### isolation (optional)

```yaml
isolation: worktree  # 在临时 git worktree 中运行
```

## Agent 存放位置（优先级）

| Location | Scope | Priority |
|----------|-------|----------|
| `--agents` CLI flag | 当前会话 | 1（最高） |
| `.claude/agents/` | 当前项目 | 2 |
| `~/.claude/agents/` | 所有项目 | 3 |
| Plugin `agents/` 目录 | 启用插件的项目 | 4（最低） |

同名 subagent 以高优先级为准。

## /agents 命令

运行 `/agents` 可以：
- 查看所有可用 subagent（内置、用户、项目、插件）
- 创建新 subagent（引导式或 Claude 生成）
- 编辑现有 subagent 配置和工具访问
- 删除自定义 subagent

命令行列出所有 subagent：`claude agents`

## System Prompt Design

The markdown body becomes the agent's system prompt. Write in second person, addressing the agent directly.

Subagents receive **only** this system prompt（加上基本环境信息如工作目录），**不会**收到完整的 Claude Code system prompt。

### Standard template

```markdown
You are [specific role] specializing in [specific domain].

**Your Core Responsibilities:**
1. [Primary responsibility]
2. [Secondary responsibility]

**[Task Name] Process:**
1. [First concrete step]
2. [Second concrete step]

**Quality Standards:**
- [Standard 1 with specifics]
- [Standard 2 with specifics]

**Output Format:**
Provide results structured as:
- [Component 1]
- [Component 2]

**Edge Cases:**
Handle these situations:
- [Edge case 1]: [Specific handling approach]
```

### Best Practices

✅ **DO:**
- Write in second person ("You are...", "You will...")
- Be specific about responsibilities
- Provide step-by-step process
- Define output format
- Include quality standards
- Address edge cases
- Keep under 10,000 characters

❌ **DON'T:**
- Write in first person
- Be vague or generic
- Omit process steps
- Leave output format undefined
- Skip quality guidance

## Creating Agents

### Method 1: /agents 命令（推荐）

1. 运行 `/agents`
2. 选择 **Create new agent**
3. 选择作用域（User-level 或 Project-level）
4. 选择 **Generate with Claude** 或手动创建
5. 选择工具、模型、颜色
6. 保存（无需重启即可使用）

### Method 2: Manual Creation

1. 选择存放位置（`.claude/agents/` 或 `~/.claude/agents/`）
2. 创建 `agent-name.md` 文件
3. 编写 frontmatter（name + description 必填）
4. 编写 system prompt
5. 用 `scripts/validate-agent.sh` 验证

### Method 3: CLI Flag（临时使用）

```bash
claude --agents '{
  "code-reviewer": {
    "description": "Expert code reviewer. Use proactively after code changes.",
    "prompt": "You are a senior code reviewer...",
    "tools": ["Read", "Grep", "Glob", "Bash"],
    "model": "sonnet"
  }
}'
```

## Validation Rules

### Identifier
- 3-50 characters
- Lowercase letters, numbers, hyphens only
- Must start and end with alphanumeric

### Description
- 10-5,000 characters
- Must include triggering conditions and examples
- Best: 200-1,000 characters with 2-4 examples

### System Prompt
- 20-10,000 characters
- Best: 500-3,000 characters
- Clear responsibilities, process, output format

## Disabling Specific Subagents

在 settings 的 `deny` 数组中添加 `Agent(subagent-name)`:

```json
{
  "permissions": {
    "deny": ["Agent(Explore)", "Agent(my-custom-agent)"]
  }
}
```

或使用 CLI flag：`claude --disallowedTools "Agent(Explore)"`

## Quick Reference

### Minimal Agent

```markdown
---
name: simple-agent
description: Use this agent when... Examples: <example>...</example>
---

You are an agent that [does X].

Process:
1. [Step 1]
2. [Step 2]

Output: [What to provide]
```

### Frontmatter Fields Summary

| Field | Required | Format | Example |
|-------|----------|--------|---------|
| name | Yes | lowercase-hyphens | `code-reviewer` |
| description | Yes | Text + examples | `Use when... <example>...` |
| tools | No | Comma-separated string | `Read, Grep, Glob` |
| disallowedTools | No | Comma-separated string | `Write, Edit` |
| model | No | inherit/sonnet/opus/haiku/full ID | `inherit` |
| permissionMode | No | Permission mode name | `default` |
| maxTurns | No | Integer | `50` |
| skills | No | YAML list | `- skill-name` |
| mcpServers | No | YAML list | See above |
| hooks | No | YAML object | See above |
| memory | No | user/project/local | `user` |
| background | No | Boolean | `false` |
| isolation | No | worktree | `worktree` |

## Additional Resources

### Reference Files

- **`references/system-prompt-design.md`** - Complete system prompt patterns
- **`references/triggering-examples.md`** - Example formats and best practices
- **`references/agent-creation-system-prompt.md`** - The exact prompt from Claude Code

### Example Files

- **`examples/complete-agent-examples.md`** - Full agent examples (code-reviewer, debugger, data-scientist, db-reader)

### Utility Scripts

- **`scripts/validate-agent.sh`** - Validate agent file structure
