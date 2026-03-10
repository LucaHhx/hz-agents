---
description: "交互式项目初始化 — 从 hz-admin-base 模板创建新项目"
argument-hint: [项目名称]
---

# 交互式项目初始化

从 hz-admin-base 模板创建新项目，包含交互问答、模板拉取、定制化、数据库初始化和文档初始化。

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

### 2. 开发环境检查

自动检测必备工具，缺失时引导安装。**不逐个询问用户，而是一次性检测、汇报、修复。**

```bash
# 一次性检测所有工具
git --version 2>/dev/null
go version 2>/dev/null
node --version 2>/dev/null
npm --version 2>/dev/null
sqlite3 --version 2>/dev/null
brew --version 2>/dev/null
```

**必备工具清单：**

| 工具 | 用途 | 必需 |
|------|------|------|
| git | 拉取模板、版本管理 | 始终必需 |
| Go (1.21+) | 后端编译运行 | 始终必需 |
| Node.js (18+) + npm | 前端构建 | 有 web/ 或 client/ 时必需 |
| sqlite3 | SQLite 数据库初始化 | 选 SQLite 时必需（步骤 6 再检查） |

**检测结果处理：**

将检测结果汇总后一次性展示给用户：

```
开发环境检测：
  ✓ git 2.43.0
  ✓ Go 1.22.5
  ✗ Node.js — 未安装
  ✗ npm — 未安装
```

→ 全部通过：直接继续
→ 有缺失：给出安装方案，使用 AskUserQuestion 确认

**安装方案（macOS）：**

AskUserQuestion:
- question: "以上工具缺失，需要安装后才能继续。确认自动安装吗？"
- options:
  - "自动安装（推荐）" — 我来执行安装命令，全程自动
  - "我自己安装" — 给我命令，我手动执行后再继续

→ 自动安装流程：

**Step 1: 确保 Homebrew 可用**（所有工具的安装基础）
```bash
brew --version 2>/dev/null
```
→ 已有 → 跳到 Step 2
→ 没有 → 安装：
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```
等待完成，验证 `brew --version`

**Step 2: 用 Homebrew 安装缺失工具**（Homebrew 就绪后才执行）
```bash
# 按需执行（只装缺失的）
brew install go       # Go 缺失时
brew install node     # Node.js 缺失时
# sqlite3 macOS 自带，一般不需要安装
```

每个安装完成后验证版本号。

→ 手动安装：列出上述命令，等用户说"好了"后重新检测

**安装完成后再次验证，确保所有工具可用后才继续。**

### 3. 交互问答

**逐步引导式收集项目信息，每次只问一个问题，使用 AskUserQuestion 工具。**

如果 `$ARGUMENTS` 提供了项目名称，跳过名称询问。

> 注意：步骤 2 检测到缺少工具时已完成安装，此处无需再检查。

---

**【Q1】项目名称**（仅当 $ARGUMENTS 为空时询问）

AskUserQuestion:
- question: "请输入项目名称（英文小写，如 my-project）"
- 用于：config 中的 db-name、日志前缀、Dockerfile 路径、页面标题等

---

**【Q2】项目描述**

AskUserQuestion:
- question: "一句话描述这个项目的用途"
- options:
  - label: "后台管理系统"
    description: "通用的后台管理系统"
  - label: "自己填写"
    description: "输入你的项目描述"

---

**【Q3】项目形态**

AskUserQuestion:
- question: "选择项目形态"
- options:
  - label: "server + web（后台管理系统）"
    description: "Go 后端 + Vue 管理后台，最常用的形态"
  - label: "server + web + client（后台 + 客户端）"
    description: "额外包含一个面向用户的前端客户端"
  - label: "server（纯 API 服务）"
    description: "只有后端 API，不含任何前端"

---

**【Q4】数据库类型**

AskUserQuestion:
- question: "选择数据库类型"
- options:
  - label: "SQLite（推荐）"
    description: "零安装、文件即数据库，适合开发和个人项目"
  - label: "MySQL"
    description: "功能完善，适合生产和团队协作"

---

**【Q5】Client 技术栈**（仅当 Q3 选了"server + web + client"时询问）

AskUserQuestion:
- question: "选择客户端技术栈"
- options:
  - label: "React 19 + Vite + Tailwind CSS + Zustand（推荐）"
    description: "现代化的 React 全家桶"
  - label: "自己指定"
    description: "输入你想要的技术栈"

---

**每个问题等用户回答后再问下一个。全部收集完毕后，向用户展示确认：**

```
项目信息确认：
  名称：<name>
  描述：<description>
  形态：<form>
  数据库：<db-type>
  [客户端：<client-stack>]

确认无误后开始初始化？
```

等待用户确认后再继续。

### 4. 拉取模板

> **重要**：用户已在项目目录中执行 `/hz-init`，不能直接 clone 到当前目录。
> 每次都删除旧缓存重新 clone，确保使用最新模板。

```bash
CACHE_DIR="$HOME/.hz-templates/hz-admin-base"

# 删除旧缓存，重新 clone 最新模板
rm -rf "$CACHE_DIR"
mkdir -p "$HOME/.hz-templates"
git clone --depth 1 https://github.com/LucaHhx/hz-admin-base.git "$CACHE_DIR"

# 按选择复制
cp -r "$CACHE_DIR/server" ./server/

# 复制 web（形态 A 或 B）
if [ "$FORM" != "C" ]; then
  cp -r "$CACHE_DIR/web" ./web/
fi

# 复制完成后删除缓存
rm -rf "$CACHE_DIR"
```

如果 clone 失败（网络问题），提示用户手动 clone 或检查网络。

### 5. 项目定制化

读取 `.claude/skills/hz-project/references/init-checklist.md` 获取完整清单。

> **注意**: Go module、import 路径、全局变量前缀保持 `hab` / `HAB_` 不变。

**5.1 配置文件定制**

修改 `server/config.example.yaml`（模板参考文件，入库），只改非敏感字段：
- `autocode.module` → 项目名
- `zap.prefix` → `'[<项目名>]'`

> 敏感配置（数据库密码、JWT key）在步骤 7 通过 `config.local.yaml` 配置，不入库。

**5.2 Dockerfile 定制**

如果存在 Dockerfile，替换工作目录和二进制名。

**5.3 前端定制**（web/ 存在时）

- `web/index.html` 中的 `<title>` → 项目描述或名称
- 复制 `.env.example` 为 `.env.development`（vite serve 需要此文件）：
  ```bash
  cp web/.env.example web/.env.development
  ```
- 确保 `web/.env.development` 中 `VITE_SERVER_PORT` 与 config 中 `system.addr` 一致
- 创建 `src/plugin/` 空目录（vite-auto-import-svg 插件需要扫描此目录）：
  ```bash
  mkdir -p web/src/plugin
  ```
- 安装 npm 依赖：
  ```bash
  cd web && npm install
  ```

**5.4 Client 初始化**（形态 B 时）

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

创建 `client/.env.development`:
```bash
VITE_API_URL=http://127.0.0.1:9689  # 对应 system.api-addr
```

**5.5 编译验证**

```bash
cd server && go build ./...
```

如果编译报缺少 `tests` 包（如 `hab/service/tests`、`hab/model/tests`、`hab/api/v1/tests`、`hab/router/tests`），说明模板中的 `enter.go` 引用了 tests 子包但目录为空。需要自动创建这些空包：

```bash
# 检查 enter.go 中引用的 tests 包，按需创建
mkdir -p server/service/tests server/api/v1/tests server/router/tests server/model/tests
```

每个目录创建 `enter.go`，包含对应的空结构体（参考同级 `enter.go` 中的导入模式）。然后检查 `initialize/router_biz.go` 中是否有未实现的方法调用（如 `InitOrderRouter`），需一并创建对应的空方法文件。

**反复编译直到 `go build ./...` 通过。**

### 6. 数据库准备与初始化

参考 `.claude/skills/hz-project/modules/11-database-setup.md`。

使用 AskUserQuestion 工具进行向导式交互，所有技术操作自动完成，用户只需做选择。

---

**【第一轮】根据步骤 3 的数据库选择分流**

如果选了 SQLite → 直接跳到「SQLite 自动初始化」
如果选了 MySQL → 进入 MySQL 引导流程

---

**【SQLite 自动初始化】**

无需用户操作，自动执行：

```bash
sqlite3 server/data.db < server/docs/hab-sqlite.sql
```

告知用户：「数据库已准备好，无需额外安装任何软件」→ 跳到【管理员密码】

---

**【MySQL 引导流程 — 第二轮交互】**

AskUserQuestion:
- question: "你的电脑上是否已经安装了 MySQL 数据库？（不确定也没关系）"
- options:
  - "已经安装了" — 我已有 MySQL 在运行，可以直接使用
  - "没有 / 不确定" — 帮我安装一个（推荐）

→ 如果「已经安装了」→ 跳到【收集连接信息】
→ 如果「没有 / 不确定」→ 进入【安装 MySQL】

---

**【安装 MySQL — 第三轮交互】**

先自动检测环境：

```bash
docker --version 2>/dev/null   # 记录是否有 Docker
mysql --version 2>/dev/null    # 记录是否有 MySQL
brew --version 2>/dev/null     # 记录是否有 Homebrew
```

根据检测结果，给出**最适合的建议**（不让用户做复杂判断）：

**场景 A：检测到已有 MySQL**

→ 告知用户：「检测到你的电脑上已经有 MySQL，我们直接使用它」
→ 跳到【收集连接信息】

**场景 B：检测到已有 Docker**

→ 告知用户：「检测到你的电脑上有 Docker，我用它来安装 MySQL，这是最简单的方式」

AskUserQuestion:
- question: "请设置 MySQL 的密码（用于数据库登录，请记住这个密码）"
- options:
  - "使用默认密码 root123" — 简单好记，适合本地开发
  - "自己设置" — 输入你想要的密码

→ 自动执行：
  1. 生成 docker-compose.yml 到项目根目录（挂载 hab.sql 自动导入）
  2. `docker-compose up -d`
  3. 等待 MySQL 就绪（轮询检测，最多 60 秒）
  4. 告知用户：「MySQL 已安装并启动」
→ 跳到【管理员密码】（Docker 挂载方式已自动导入数据）

**场景 C：什么都没有（最常见）**

AskUserQuestion:
- question: "需要先安装一些基础工具。你希望用哪种方式？"
- options:
  - "一键安装（推荐）" — 我来帮你自动安装 Docker 和 MySQL，全程无需手动操作
  - "我自己安装" — 给我安装指南，我手动完成后再继续

→ 如果「一键安装」：

  **Step 1: 检测 Homebrew**

  ```bash
  brew --version 2>/dev/null
  ```

  → 有 Homebrew → 跳到 Step 2
  → 没有 Homebrew：

  AskUserQuestion:
  - question: "需要先安装 Homebrew（macOS 的软件安装工具）。这个工具是安装其他软件的基础，安装过程需要几分钟。确认安装吗？"
  - options:
    - "确认安装 Homebrew" — 将自动执行安装命令，过程中可能需要输入电脑密码
    - "取消" — 我稍后自己处理

  → 确认后执行：
  ```bash
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  ```
  → 等待完成，验证 `brew --version`
  → 失败则告知用户，建议手动操作

  **Step 2: 安装 Docker Desktop**

  AskUserQuestion:
  - question: "接下来需要安装 Docker Desktop（一个运行数据库的容器工具）。安装包约 600MB，安装后会出现一个鲸鱼图标的应用。确认安装吗？"
  - options:
    - "确认安装 Docker Desktop" — 通过 Homebrew 自动下载安装
    - "取消" — 我稍后自己处理

  → 确认后执行：
  ```bash
  brew install --cask docker
  ```

  **Step 3: 启动 Docker Desktop**

  AskUserQuestion:
  - question: "Docker Desktop 已安装完成。现在需要启动它。启动后屏幕上会弹出 Docker 的窗口，请点击「Accept」同意条款。准备好了吗？"
  - options:
    - "启动 Docker" — 将自动打开 Docker Desktop 应用
    - "等一下" — 我还没准备好

  → 确认后执行：
  ```bash
  open /Applications/Docker.app
  ```
  → 告知用户：「Docker 正在启动中，请在弹出的窗口中点击 Accept，然后等待右上角的鲸鱼图标不再转动...」
  → 轮询等待 `docker info` 成功（最多 120 秒，每 15 秒提示一次进度）
  → 成功：「Docker 已启动！」→ 回到场景 B 的 docker-compose 流程
  → 超时：告知用户「Docker 启动可能需要更长时间，请等鲸鱼图标稳定后告诉我」

→ 如果「我自己安装」：
  告知用户详细安装步骤（简洁版），并说「安装好后告诉我，我继续」
  等待用户回复后，重新检测环境

---

**【收集连接信息 — 交互】**

AskUserQuestion:
- question: "MySQL 的连接地址是？（本机安装的一般不用改）"
- options:
  - "本机默认 (127.0.0.1:3306)" — MySQL 安装在这台电脑上
  - "其他地址" — MySQL 在远程服务器上，我来填写地址

→ 如果「本机默认」→ host=127.0.0.1, port=3306
→ 如果「其他地址」→ 追问 host 和 port

AskUserQuestion:
- question: "MySQL 的登录用户名和密码？"
- options:
  - "root / root123" — 常见的本地开发默认配置
  - "自己填写" — 我来输入用户名和密码

→ 收集完毕后，自动测试连接：

```bash
mysql -h<host> -P<port> -u<user> -p<password> -e "SELECT 1"
```

→ 成功：「连接成功！」→ 继续
→ 失败：告知用户具体错误（用通俗语言），引导修正：
  - "连接被拒绝" → "MySQL 服务可能没有启动，请检查"
  - "密码错误" → "密码不对，请重新输入"
  - "找不到主机" → "地址不对，请确认 MySQL 的地址"

连接成功后，自动执行数据库初始化：

```bash
mysql -h<host> -P<port> -u<user> -p<password> \
  -e "CREATE DATABASE IF NOT EXISTS \`<project-name>\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
mysql -h<host> -P<port> -u<user> -p<password> <project-name> < server/docs/hab.sql
```

告知用户：「数据库已创建并导入初始数据」

---

**【管理员密码 — 交互】**

AskUserQuestion:
- question: "设置后台管理系统的登录密码（账号固定为 admin）"
- options:
  - "使用默认密码 123456" — 简单好记，后续可在系统中修改
  - "自己设置密码" — 输入你想要的登录密码

→ 如果自定义密码：
  1. 自动生成 bcrypt hash：`cd server && go run ./cmd/hashpw/main.go <新密码>`
  2. 执行 UPDATE（根据数据库类型选择工具）：
     - MySQL: `mysql ... -e "UPDATE sys_users SET password='<hash>' WHERE username='admin';"`
     - SQLite: `sqlite3 server/data.db "UPDATE sys_users SET password='<hash>' WHERE username='admin';"`
  3. 告知用户：「管理员密码已设置」

→ 最终确认：
  ```
  数据库准备完成！
  - 数据库类型：MySQL / SQLite
  - 管理员账号：admin
  - 管理员密码：***（你设置的密码）
  请记住这些信息，后续登录系统时需要使用。
  ```

### 7. 生成 config.local.yaml

基于 `server/config.example.yaml` 复制为 `server/config.local.yaml`，覆盖以下字段：

> 完整配置参考 `server/config.example.yaml`（所有字段带中文注释）。
> 极简配置参考 `server/config.minimal.yaml`（只需 db-type + jwt key）。

**通用配置：**
- `jwt.signing-key` → 新生成 UUID（`uuidgen`）
- `autocode.module` → <project-name>
- `zap.prefix` → `'[<project-name>]'`

**SQLite 时：**
- `system.db-type` → sqlite
- **必须确保 `sqlite:` 配置段存在**（如果 config.example.yaml 中没有，需要添加）：
  ```yaml
  sqlite:
    db-name: data
    path: ""
    max-idle-conns: 10
    max-open-conns: 100
    log-mode: info
  ```
  > 如果缺少此段，`GormSqlite()` 会因为 `Dbname == ""` 返回 nil，导致服务启动时 panic。

**MySQL 时：**
- `system.db-type` → mysql
- `mysql.path` → <host>
- `mysql.port` → "<port>"
- `mysql.db-name` → <project-name>
- `mysql.username` → <user>
- `mysql.password` → <password>

> config.local.yaml 在 .gitignore 中，含敏感信息不入库。
> 同时保留 config.example.yaml 作为模板参考（已入库）。

### 8. 初始化 Git（如需）

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

# Database
server/data.db

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

### 9. 调用 PM 初始化业务需求

启动 hz-pm agent，通过 brainstorming 与用户确定业务需求，初始化 docs/：

```
Task tool:
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

### 10. 输出总结

向用户展示：

```
========================================
  项目初始化完成！
========================================

项目名称: <name>
项目形态: server + web [+ client]
数据库:   MySQL (Docker) / SQLite
管理员:   admin / ******

项目结构:
  server/     — Go 后端 (hab 框架)
  web/        — Vue 3 管理后台
  [client/]   — React 客户端
  docs/       — 项目文档
  .claude/    — hz-agents 链接

启动验证:
  1. cd server && HAB_CONFIG=config.local.yaml go run .   # 启动后端
  2. cd web && npm run serve                               # 启动管理后台
  3. 浏览器打开 http://localhost:<VITE_CLI_PORT> → 用 admin 登录

流水线下一步:
  4. /review-tech                  — Tech Lead 创建技术方案
  5. /review-ui                    — UI 设计师产出设计稿（自定义页面）
  6. /review-all                   — 三端文档对齐评审（推荐）
  7. /cmd-autocode                 — 生成 CRUD 模块代码
  8. /unify-dev                    — 全团队协作开发
  9. /review-qa                    — QA 验收测试

查看流水线状态:
  python3 .claude/skills/create-docs/scripts/docs.py pipeline
========================================
```

## Important Notes

- 模板拉取每次都删除旧缓存（`~/.hz-templates/hz-admin-base`）重新 `git clone --depth 1`，确保始终使用最新模板，再复制到项目目录，避免覆盖 .claude/ 等已有内容
- Go module、import 路径、全局变量前缀统一保持 `hab` / `HAB_`，**不做替换**
- Client 目录不从模板复制（模板中没有 client/），用 create-vite 新建
- `config.example.yaml` 只含非敏感配置（入库），`config.local.yaml` 含数据库密码和 JWT key（不入库）
- SQLite 数据库文件 `server/data.db` 在 .gitignore 中，不入库
- Docker 方式安装 MySQL 时，docker-compose.yml 会挂载 hab.sql 自动导入，无需手动执行 SQL
