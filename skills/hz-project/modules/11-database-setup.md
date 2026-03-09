# 11 - 数据库准备与初始化

## 数据库选择

| 类型 | 适用场景 | 优点 | 缺点 |
|------|---------|------|------|
| SQLite | 开发/个人项目/快速体验 | 零安装、文件即数据库 | 不支持并发写 |
| MySQL | 生产/团队协作/正式项目 | 功能完善、生态成熟 | 需要安装服务 |

## MySQL 环境准备

### 已有 MySQL

收集连接信息（host, port, user, password）→ 测试连接：

```bash
mysql -h<host> -P<port> -u<user> -p<password> -e "SELECT VERSION();"
```

### 没有 MySQL — Docker 方式（推荐）

#### 检测 Docker

```bash
docker --version
```

#### 协助安装 Docker（macOS）

```bash
brew install --cask docker
open /Applications/Docker.app
# 等待启动完成
docker info
```

#### 启动 MySQL 容器

**docker-compose.yml（默认推荐，生成到项目根目录）：**

```yaml
version: '3.8'
services:
  mysql:
    image: mysql:8
    container_name: <project-name>-mysql
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: <password>
      MYSQL_DATABASE: <project-name>
      MYSQL_CHARSET: utf8mb4
      MYSQL_COLLATION: utf8mb4_general_ci
    ports:
      - "3306:3306"
    volumes:
      - mysql-data:/var/lib/mysql
      - ./server/docs/hab.sql:/docker-entrypoint-initdb.d/init.sql
    command: --character-set-server=utf8mb4 --collation-server=utf8mb4_general_ci
volumes:
  mysql-data:
```

> 关键：挂载 hab.sql 到 /docker-entrypoint-initdb.d/，容器首次启动自动导入。

```bash
docker-compose up -d
# 等待 MySQL 就绪（约 10-20 秒）
docker-compose logs mysql | tail -5
```

**docker run 简单版：**

```bash
docker run -d --name <project-name>-mysql \
  -e MYSQL_ROOT_PASSWORD=<password> \
  -e MYSQL_DATABASE=<project-name> \
  -p 3306:3306 \
  mysql:8 --character-set-server=utf8mb4 --collation-server=utf8mb4_general_ci
```

### 没有 MySQL — 直接安装

```bash
brew install mysql
brew services start mysql
mysql_secure_installation
```

## 数据库初始化

### MySQL（非 Docker 挂载方式时）

```bash
mysql -h<host> -P<port> -u<user> -p<password> \
  -e "CREATE DATABASE IF NOT EXISTS \`<project-name>\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
mysql -h<host> -P<port> -u<user> -p<password> <project-name> < server/docs/hab.sql
```

### SQLite

```bash
sqlite3 server/data.db < server/docs/hab-sqlite.sql
```

## 自定义管理员密码

默认密码：123456

自定义方式：导入 SQL 后用对应工具执行 UPDATE：

```bash
# 先用 Go 生成 bcrypt hash
cd server && go run ./cmd/hashpw/main.go <新密码>
# 然后 UPDATE
# MySQL:
mysql -h<host> -P<port> -u<user> -p<password> <db> -e "UPDATE sys_users SET password='<hash>' WHERE username='admin';"
# SQLite:
sqlite3 server/data.db "UPDATE sys_users SET password='<hash>' WHERE username='admin';"
```

## 验证

```sql
SELECT COUNT(*) FROM sys_users;       -- 1
SELECT COUNT(*) FROM sys_base_menus;  -- 28+
SELECT COUNT(*) FROM sys_apis;        -- 127+
SELECT COUNT(*) FROM sys_authorities; -- 2
```
