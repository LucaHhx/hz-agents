---
description: "交互式项目初始化 — 从 hz-admin-base 模板创建新项目"
argument-hint: [项目名称]
---

# 交互式项目初始化

从 hz-admin-base 模板创建新项目，包含交互问答、模板拉取、定制化和文档初始化。

## Implementation Steps

### 1. 检测当前目录

检查当前目录状态：

```bash
# 检查是否是 git 仓库
git status 2>/dev/null

# 检查是否已有项目文件
ls -la server/ web/ client/ 2>/dev/null
```

- 如果目录非空且包含 server/ 或 web/ → **警告用户**，确认是否覆盖
- 如果是 git 仓库且有未提交更改 → **警告用户**，建议先提交
- 空目录或只有 .git → 安全继续

### 2. 交互问答

使用 brainstorming 方式收集项目信息。如果 `$ARGUMENTS` 提供了项目名称，跳过名称询问。

**必须收集的信息：**

**① 项目名称**
- 英文小写，如 `my-project`
- 用于：config 中的 db-name、日志前缀、Dockerfile 路径、页面标题等

**② 项目描述**
- 一句话描述项目用途

**③ 项目形态**（多选一）
- A: server + web（纯后台管理系统）← 默认
- B: server + web + client（后台 + 客户端）
- C: server（纯 API 服务）

**④ 数据库类型**（多选一）
- A: SQLite ← 默认（轻量，无需额外服务）
- B: MySQL
- C: PostgreSQL

**⑤ client 技术栈**（仅形态 B 需要）
- A: React 19 + Vite + Tailwind CSS + Zustand ← 默认推荐
- B: 其他（用户指定）

**等待用户确认所有选项后再继续。**

### 3. 拉取模板

```bash
# 创建临时目录
TEMP_DIR=$(mktemp -d)

# 拉取模板
git clone --depth 1 https://github.com/LucaHhx/hz-admin-base.git "$TEMP_DIR/template"

# 按选择复制
cp -r "$TEMP_DIR/template/server" ./server/

# 复制 web（形态 A 或 B）
if [ "$FORM" != "C" ]; then
  cp -r "$TEMP_DIR/template/web" ./web/
fi

# 清理
rm -rf "$TEMP_DIR"
```

如果 clone 失败（网络问题），提示用户手动 clone 或检查网络。

### 4. 项目定制化

读取 `.claude/skills/hz-project/references/init-checklist.md` 获取完整清单。

> **注意**: Go module、import 路径、全局变量前缀保持 `hab` / `HAB_` 不变。

**4.1 配置文件定制**

复制 `server/config.example.yaml` 为 `server/config.yaml`，修改：
- `system.db-type` → 用户选择的数据库类型
- `mysql.db-name` → 项目名（MySQL 时）
- `jwt.signing-key` → 新生成的 UUID（`uuidgen`）
- `autocode.module` → 项目名
- `zap.prefix` → `'[<项目名>]'`

**4.2 Dockerfile 定制**

如果存在 Dockerfile，替换工作目录和二进制名。

**4.3 前端定制**（web/ 存在时）

- `web/index.html` 中的 `<title>` → 项目描述或名称
- `web/.env` 中的端口配置（按需调整）

**4.4 Client 初始化**（形态 B 时）

```bash
# 使用 create-vite 创建客户端
npm create vite@latest client -- --template react-ts

# 安装 Tailwind CSS
cd client
npm install
npm install -D tailwindcss @tailwindcss/vite

# 安装状态管理
npm install zustand axios react-router-dom
```

**4.5 验证**

```bash
# 编译检查
cd server && go build ./...
```

### 5. 链接 hz-agents

```bash
# 创建 .claude 目录
mkdir -p .claude

# 生成 link.sh
cat > .claude/link.sh << 'SCRIPT'
#!/bin/bash
set -e
HZ_AGENTS="/Users/luca/work/hz-agents"

# 创建目标目录
mkdir -p skills commands agents

# 链接所有组件
for dir in skills commands agents; do
  if [ -d "$HZ_AGENTS/$dir" ]; then
    for item in "$HZ_AGENTS/$dir"/*; do
      ln -sf "$item" "$dir/$(basename "$item")"
    done
  fi
done

echo "hz-agents 链接完成"
SCRIPT
chmod +x .claude/link.sh

# 执行链接
cd .claude && bash link.sh && cd ..

# 生成 settings.local.json
cat > .claude/settings.local.json << 'JSON'
{
  "permissions": {
    "allow": [
      "Bash(npm:*)",
      "Bash(npx:*)",
      "Bash(go:*)",
      "Bash(python3:*)",
      "Bash(docker:*)",
      "Bash(git:*)",
      "Bash(cd:*)",
      "Bash(mkdir:*)",
      "Bash(cp:*)",
      "Bash(mv:*)",
      "Bash(rm:*)",
      "Bash(ls:*)",
      "Bash(cat:*)",
      "Bash(grep:*)",
      "Bash(find:*)",
      "Bash(sed:*)",
      "Bash(chmod:*)"
    ]
  }
}
JSON
```

### 6. 初始化 Git（如需）

```bash
# 如果不是 git 仓库
if ! git rev-parse --git-dir > /dev/null 2>&1; then
  git init
  # 创建 .gitignore
  cat > .gitignore << 'EOF'
# Dependencies
node_modules/

# Build
server/server
web/dist/
client/dist/

# Config (contain secrets)
server/config.yaml
server/config.local.yaml

# Logs
server/log/
*.log

# IDE
.idea/
.vscode/
*.swp

# OS
.DS_Store
Thumbs.db

# Docker
docker-compose.override.yml
EOF
fi
```

### 7. 调用 PM 初始化业务需求

启动 hz-pm agent，通过 brainstorming 与用户确定业务需求，初始化 docs/：

```
Agent tool:
  subagent_type: "hz-pm"
  prompt: |
    先读取 create-docs skill 的 SKILL.md (.claude/skills/create-docs/SKILL.md) 了解文档规范。

    这是一个新项目，刚完成模板初始化。请和用户协作完成业务需求定义：

    1. 使用 brainstorming skill 与用户讨论：
       - 项目要解决什么问题？
       - 目标用户是谁？
       - 核心功能有哪些？
       - MVP 范围是什么？
    2. 用户确认后，执行文档初始化：
       - 运行 docs.py init 初始化 docs/
       - 完善 docs/project.md
       - 使用 docs.py req 创建需求目录
       - 填写 plan.md 和 tasks.md

    所有主要决策必须由用户确认。
```

### 8. 输出总结

向用户展示：

```
========================================
  项目初始化完成！
========================================

项目名称: <name>
项目形态: server + web [+ client]
数据库:   SQLite / MySQL / PostgreSQL

项目结构:
  server/     — Go 后端 (hab 框架)
  web/        — Vue 3 管理后台
  [client/]   — React 客户端
  docs/       — 项目文档
  .claude/    — hz-agents 链接

下一步建议:
  1. cd server && go run .        # 启动后端
  2. cd web && npm run serve      # 启动管理后台
  3. /review-tech                  # Tech Lead 做技术方案
  4. /unify-dev                    # 全团队协作开发
========================================
```

## Important Notes

- 模板拉取使用 `git clone --depth 1`，可靠且不需要 GitHub token
- Go module、import 路径、全局变量前缀统一保持 `hab` / `HAB_`，**不做替换**
- Client 目录不从模板复制（模板中没有 client/），用 create-vite 新建
- hz-agents 路径在 link.sh 中硬编码，用户换机器需要修改
