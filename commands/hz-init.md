---
description: "交互式项目初始化 — 从 hz-admin-base 模板创建新项目"
argument-hint: [项目名称]
---

# 交互式项目初始化

从 hz-admin-base 模板创建新项目，包含交互问答、模板拉取、定制化、数据库初始化和文档初始化。

## Implementation Steps

### 1. 预检目录与风险

检查当前目录状态：

```bash
# 检查是否是 git 仓库
git status 2>/dev/null

# 检查是否已有项目文件
ls -la server/ web/ client/ 2>/dev/null
```

- 如果目录非空且包含 server/ 或 web/ → **警告用户**
- 如果是 git 仓库且有未提交更改 → **警告用户**

→ 有风险时只问一次：

AskUserQuestion:
- question: "检测到当前目录已有项目文件/未提交更改，如何处理？"
- options:
  - "继续并覆盖" — 删除已有目录，重新初始化
  - "仅补全" — 保留现有文件，只创建缺失部分
  - "取消" — 中止初始化

→ 无风险（空目录或只有 .git）：**不输出任何内容，直接进入步骤 2**

### 2. 收集最小必要信息（3-4 个核心问题）

**逐步引导式收集项目信息，每次只问一个问题，使用 AskUserQuestion 工具。**

如果 `$ARGUMENTS` 提供了项目名称，跳过 Q1。

---

**【Q1】项目名称**（仅当 $ARGUMENTS 为空时询问）

AskUserQuestion:
- question: "请输入项目名称（英文小写，如 my-project）"
- 用于：config 中的 db-name、日志前缀、Dockerfile 路径、页面标题等

---

**【Q2】项目形态**

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

**【Q3】数据库类型**

AskUserQuestion:
- question: "选择数据库类型"
- options:
  - label: "SQLite（推荐）"
    description: "零安装、文件即数据库，适合开发和个人项目"
  - label: "MySQL"
    description: "功能完善，适合生产和团队协作"

---

**【Q4】Client 技术栈**（仅当 Q2 选了"server + web + client"时询问）

AskUserQuestion:
- question: "选择客户端技术栈"
- options:
  - label: "React 19 + Vite + Tailwind CSS + Zustand（推荐）"
    description: "现代化的 React 全家桶"
  - label: "自己指定"
    description: "输入你想要的技术栈"

---

**全部收集完毕后，展示确认摘要：**

```
项目信息确认：
  名称：<name>
  形态：<form>
  数据库：<db-type>
  [客户端：<client-stack>]
```

> **注意**：不单独询问"项目描述"。步骤 5 定制化时用项目名自动填充 `<title>` 等位置。

### 3. 按选择做定向环境检查 + MySQL 连接收集

根据步骤 2 的选择，**只检查实际需要的工具**，避免纯 server 项目被要求安装无用工具。

#### 3.1 基础工具检查（按需）

```bash
# 始终检查
git --version 2>/dev/null
go version 2>/dev/null

# 仅 web 或 client 形态时检查
node --version 2>/dev/null    # 选了 web/client 才检查
npm --version 2>/dev/null     # 选了 web/client 才检查

# 仅 SQLite 时检查
sqlite3 --version 2>/dev/null  # 选了 SQLite 才检查
```

**检测结果一次性汇总展示：**

```
开发环境检测：
  ✓ git 2.43.0
  ✓ Go 1.22.5
  [✓ Node.js 20.11.0]    ← 仅有 web/client 时显示
  [✓ npm 10.2.4]         ← 仅有 web/client 时显示
  [✓ sqlite3 3.43.2]     ← 仅选 SQLite 时显示
```

→ 全部通过：直接继续
→ 有缺失：

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

#### 3.2 MySQL 连接收集（仅选了 MySQL 时执行）

选了 MySQL 后，**不直接检测本机环境**，而是先问用户：

AskUserQuestion:
- question: "请提供 MySQL 连接信息"
- options:
  - "我有现成的 MySQL" — 已有 MySQL 在运行，直接提供连接信息
  - "没有，帮我安装一个" — 引导我安装 MySQL

---

**→ 如果用户「有现成的 MySQL」：**

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

→ 成功：「连接成功！」→ 记录连接信息，跳到步骤 4
→ 失败：告知用户具体错误（用通俗语言），引导修正：
  - "连接被拒绝" → "MySQL 服务可能没有启动，请检查"
  - "密码错误" → "密码不对，请重新输入"
  - "找不到主机" → "地址不对，请确认 MySQL 的地址"

---

**→ 如果用户「需要安装」：**

此时才检测 docker/brew，按检测结果推荐最短安装路径：

```bash
docker --version 2>/dev/null   # 检测是否有 Docker
mysql --version 2>/dev/null    # 检测是否有 MySQL
brew --version 2>/dev/null     # 检测是否有 Homebrew
```

**场景 A：检测到已有 MySQL**

→ 告知用户：「检测到你的电脑上已经有 MySQL，我们直接使用它」
→ 回到上方「有现成的 MySQL」流程收集连接信息

**场景 B：检测到已有 Docker**

→ 告知用户：「检测到你的电脑上有 Docker，我用它来安装 MySQL，这是最简单的方式」

AskUserQuestion:
- question: "请设置 MySQL 的密码（用于数据库登录，请记住这个密码）"
- options:
  - "使用默认密码 root123" — 简单好记，适合本地开发
  - "自己设置" — 输入你想要的密码

→ 记录密码，Docker 安装动作纳入步骤 4 执行计划

**场景 C：什么都没有（最常见）**

→ 需要安装 Docker，记录安装动作纳入步骤 4 执行计划

AskUserQuestion:
- question: "请设置 MySQL 的密码（用于数据库登录，请记住这个密码）"
- options:
  - "使用默认密码 root123" — 简单好记，适合本地开发
  - "自己设置" — 输入你想要的密码

→ 记录密码和安装需求

### 4. 一次性展示执行计划并确认

将**所有待执行动作**合并为一个执行计划，只做**一次确认**：

```
执行计划：
  📦 拉取 hz-admin-base 模板
  📁 创建 server/ web/ 目录
  [🔧 安装缺失工具：Docker Desktop、Node.js]    ← 有缺失时才显示
  [🐳 Docker 安装并启动 MySQL]                   ← Docker MySQL 时才显示
  💾 初始化 <SQLite/MySQL> 数据库
  ⚙️ 生成配置文件
  🔨 编译验证

[需要你操作的地方：]                              ← 有人工步骤时才显示
  [• Docker 安装后需点击「Accept」同意条款]

确认开始？
```

AskUserQuestion:
- question: "以上是执行计划，确认开始？"
- options:
  - "开始" — 执行上述所有步骤
  - "取消" — 中止初始化

### 5. 执行初始化（里程碑播报）

合并所有执行动作，按里程碑播报进度。总步骤数根据实际需要动态计算。

**只在必须人工介入时暂停**（如 Docker Accept 弹窗），其余全自动。

---

#### [N/M] 安装缺失工具（仅有缺失时执行）

> 此步骤仅在步骤 3 检测到缺失工具且步骤 4 计划中包含安装动作时执行。

**安装 Docker Desktop**（需要 Docker 安装 MySQL 时）：

```bash
# 确保 Homebrew 可用
brew --version 2>/dev/null || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 安装 Docker Desktop
brew install --cask docker

# 启动 Docker Desktop
open /Applications/Docker.app
```

→ 告知用户：「Docker 正在启动中，请在弹出的窗口中点击 Accept，然后等待右上角的鲸鱼图标不再转动...」
→ 轮询等待 `docker info` 成功（最多 120 秒，每 15 秒提示一次进度）
→ 成功：继续下一步
→ 超时：告知用户「Docker 启动可能需要更长时间，请等鲸鱼图标稳定后告诉我」

**安装其他缺失工具**：

```bash
brew install go       # Go 缺失时
brew install node     # Node.js 缺失时
```

每个安装完成后验证版本号。

---

#### [N/M] 拉取模板

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

---

#### [N/M] 项目定制化

> **注意**: Go module、import 路径、全局变量前缀保持 `hab` / `HAB_` 不变。

**定制化清单**（从 hz-admin-base 模板创建项目后必须修改）：

| # | 项目 | 文件 | 修改内容 |
|---|------|------|---------|
| 1 | AutoCode module | `server/config.example.yaml` | `autocode.module` → 项目名 |
| 2 | 日志前缀 | `server/config.example.yaml` | `zap.prefix` → `'[<project>]'` |
| 3 | Dockerfile 工作目录 | `Dockerfile` | `/srv/hab` → `/srv/<project>` |
| 4 | Dockerfile 二进制名 | `Dockerfile` | 按项目命名（默认为 `hab`） |
| 5 | 页面标题 | `web/index.html` | `<title>` 改为项目名称 |
| 6 | 前端端口 | `web/.env.example` | 按需调整 `VITE_CLI_PORT` |

**配置文件定制**

修改 `server/config.example.yaml`（模板参考文件，入库），只改非敏感字段：
- `autocode.module` → 项目名
- `zap.prefix` → `'[<项目名>]'`

> 敏感配置（数据库密码、JWT key）在步骤 5 生成配置文件环节通过 `config.local.yaml` 配置，不入库。

**Dockerfile 定制**

如果存在 Dockerfile，替换工作目录和二进制名。

**前端定制**（web/ 存在时）

- `web/index.html` 中的 `<title>` → 项目名称
- 从模板复制本地环境文件（这些文件不入库，在 `.gitignore` 中）：
  ```bash
  cp web/.env.example web/.env.dev          # vite serve --mode dev 使用
  cp web/.env.example web/.env.development  # vite serve 默认使用
  ```
- 修改 `web/.env.dev` 和 `web/.env.development` 中 `VITE_SERVER_PORT` 与 config 中 `system.addr` 一致
- 创建 `src/plugin/` 空目录（vite-auto-import-svg 插件需要扫描此目录）：
  ```bash
  mkdir -p web/src/plugin
  ```
- 安装 npm 依赖：
  ```bash
  cd web && npm install
  ```

**Client 初始化**（形态 B 时）

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

---

#### [N/M] 初始化数据库

**SQLite 路径：**

```bash
sqlite3 server/data.db < server/docs/hab-sqlite.sql
```

**MySQL + Docker 路径**（步骤 3 中确认需要 Docker 安装时）：

1. 生成 docker-compose.yml 到项目根目录（挂载 hab.sql 自动导入）
2. `docker-compose up -d`
3. 等待 MySQL 就绪（轮询检测，最多 60 秒）

**MySQL + 已有连接路径**（步骤 3 中收集了连接信息时）：

```bash
mysql -h<host> -P<port> -u<user> -p<password> \
  -e "CREATE DATABASE IF NOT EXISTS \`<project-name>\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
mysql -h<host> -P<port> -u<user> -p<password> <project-name> < server/docs/hab.sql
```

**管理员密码**（内联在数据库初始化环节中）：

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

---

#### [N/M] 生成配置文件

> **重要**：所有配置字段都有代码级默认值（`server/config/defaults.go`），
> `config.local.yaml` 只需写入与默认值不同的字段和敏感信息。
> 配置模板参考 `server/config.minimal.yaml`，完整配置参考 `server/config.example.yaml`。

**基于 `server/config.minimal.yaml` 生成 `server/config.local.yaml`：**

1. 读取 `server/config.minimal.yaml` 作为基础模板
2. 根据用户选择的数据库类型修改：
   - **SQLite**：模板默认即为 SQLite，取消注释 `jwt.signing-key` 并填入 `uuidgen` 生成的值（如需覆盖默认自动生成）
   - **MySQL**：将 `system.db-type` 改为 `mysql`，取消注释 MySQL 配置段并填入步骤 3 收集的连接信息（host、port、db-name、username、password）
3. 写入 `server/config.local.yaml`

> config.local.yaml 在 .gitignore 中，含敏感信息不入库。
> 同时保留 config.example.yaml 作为模板参考（已入库）。

---

#### [N/M] 编译验证

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

---

#### [N/M] 初始化 Git（如需）

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

### 6. 收尾分层输出

**第一屏（关键信息）：**

```
✅ 项目初始化完成！

启动命令：
  cd server && HAB_CONFIG=config.local.yaml go run .   # 启动后端
  cd web && npm run serve                               # 启动管理后台

访问：http://localhost:<VITE_CLI_PORT>
账号：admin / ******
```

**第二屏（后续指引）：**

```
后续流水线:
  → /team-docs — 文档协作评审（PM + Tech + UI 三方评审与对齐）（推荐下一步）
  → /team-dev        — 全团队协作开发
  → /unify-fix        — 智能 Bug 修复

单独执行（按需）:
  /review-tech    — Tech Lead 创建技术方案
  /review-ui      — UI 设计师产出设计稿
  /review-qa      — QA 验收测试

查看流水线状态：
  python3 .claude/skills/create-docs/scripts/docs.py pipeline
```

### 7. 可选：继续需求梳理

AskUserQuestion:
- question: "是否现在继续进入需求梳理和 docs 初始化？"
- options:
  - "继续" — 启动 PM 协助完成业务需求定义
  - "稍后再说" — 结束初始化，后续需要时再执行

→ 如果「继续」：

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

→ 如果「稍后再说」：结束初始化。

## Important Notes

- 模板拉取每次都删除旧缓存（`~/.hz-templates/hz-admin-base`）重新 `git clone --depth 1`，确保始终使用最新模板，再复制到项目目录，避免覆盖 .claude/ 等已有内容
- Go module、import 路径、全局变量前缀统一保持 `hab` / `HAB_`，**不做替换**
- Client 目录不从模板复制（模板中没有 client/），用 create-vite 新建
- `config.example.yaml` 只含非敏感配置（入库），`config.local.yaml` 含数据库密码和 JWT key（不入库）
- SQLite 数据库文件 `server/data.db` 在 .gitignore 中，不入库
- Docker 方式安装 MySQL 时，docker-compose.yml 会挂载 hab.sql 自动导入，无需手动执行 SQL
