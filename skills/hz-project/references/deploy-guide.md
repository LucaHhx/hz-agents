# 部署指南详解

## 模式一：本地直接运行

最简单的开发模式，适合日常开发调试。

```bash
# 后端
cd server
cp config.example.yaml config.yaml  # 首次需要
go build -o server . && ./server

# 管理后台
cd web
npm install
npm run serve

# 客户端前端（如有）
cd client
npm install
npm run dev
```

## 模式二：本地 Docker

### docker-compose.yml 模板

```yaml
version: '3.8'

services:
  server:
    build:
      context: .
      dockerfile: server/Dockerfile
    ports:
      - "${APP_PORT:-9688}:9688"
    volumes:
      - ./server/config.yaml:/srv/app/config.yaml
    restart: unless-stopped

  nginx:
    image: nginx:alpine
    ports:
      - "${WEB_PORT:-8091}:80"
    volumes:
      - ./web/dist:/usr/share/nginx/html
      - ./nginx.conf:/etc/nginx/conf.d/default.conf
    depends_on:
      - server
    restart: unless-stopped
```

### 带 MySQL 的版本

```yaml
services:
  mysql:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: ${DB_PASSWORD:-password}
      MYSQL_DATABASE: ${DB_NAME:-myproject}
    volumes:
      - mysql_data:/var/lib/mysql
    ports:
      - "3306:3306"

  server:
    build:
      context: .
      dockerfile: server/Dockerfile
    depends_on:
      - mysql
    environment:
      - DB_HOST=mysql

volumes:
  mysql_data:
```

## 模式三：远程 Docker 部署

### 部署流程

#### 1. 收集信息

需要以下信息：
- 目标名称（dev / prod / staging）
- SSH 连接：主机、端口、用户名、密钥路径
- 远程部署路径
- 应用端口
- 域名（生产环境）

#### 2. 检查远程环境

```bash
SSH_CMD="ssh -i $SSH_KEY -p $SSH_PORT $SSH_USER@$SSH_HOST"

# 检查 Docker
$SSH_CMD "docker --version && docker compose version"

# 检查端口占用
$SSH_CMD "netstat -tlnp | grep :$APP_PORT"

# 检查 Nginx
$SSH_CMD "nginx -v 2>&1 || docker exec nginx nginx -v 2>&1"

# 检查磁盘空间
$SSH_CMD "df -h /"
```

#### 3. 生成部署脚本

开发环境模板（`deploy/dev.sh`）：

```bash
#!/bin/bash
set -e

# ============ 配置 ============
SSH_KEY="~/.ssh/key"
SSH_USER="user"
SSH_HOST="192.168.0.228"
SSH_PORT=22
REMOTE_DIR="~/my-project"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PORT=9000

SSH_CMD="ssh -i $SSH_KEY -p $SSH_PORT $SSH_USER@$SSH_HOST"

echo "========================================="
echo "  项目部署脚本 (dev)"
echo "========================================="

# 1. 构建前端
echo "[1/3] 构建前端..."
cd "$PROJECT_DIR/web"
npm run build

# 2. 同步文件
echo "[2/3] 同步文件到远程..."
$SSH_CMD "mkdir -p $REMOTE_DIR"
rsync -avz --delete \
  --exclude 'node_modules' \
  --exclude '.git' \
  --exclude '.claude' \
  --exclude 'server/server' \
  --exclude 'server/logs' \
  --exclude 'docs' \
  --exclude 'deploy' \
  -e "ssh -i $SSH_KEY -p $SSH_PORT" \
  "$PROJECT_DIR/" "$SSH_USER@$SSH_HOST:$REMOTE_DIR/"

# 3. 远程构建启动
echo "[3/3] 远程 Docker 构建启动..."
$SSH_CMD "
  cd $REMOTE_DIR
  export APP_PORT=$APP_PORT
  docker compose down 2>/dev/null || true
  docker compose up -d --build
"

echo "========================================="
echo "  部署完成！"
echo "  地址: http://$SSH_HOST:$APP_PORT"
echo "========================================="
```

生产环境模板（`deploy/prod.sh`）：

```bash
#!/bin/bash
set -e

# ============ 配置 ============
SSH_KEY="~/.ssh/key"
SSH_USER="root"
SSH_HOST="example.com"
SSH_PORT=2220
REMOTE_DIR="/root/my-project"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DOMAIN="example.com"

SSH_CMD="ssh -i $SSH_KEY -p $SSH_PORT $SSH_USER@$SSH_HOST"

echo "========================================="
echo "  项目部署脚本 (prod)"
echo "  域名: $DOMAIN"
echo "========================================="

# 1. 构建前端
echo "[1/5] 构建 web..."
cd "$PROJECT_DIR/web"
npx vite build --base /admin/

# 2. 构建客户端前端（如有）
if [ -d "$PROJECT_DIR/client" ]; then
  echo "[2/5] 构建 client..."
  cd "$PROJECT_DIR/client"
  npm run build
fi

# 3. 同步文件
echo "[3/5] 同步文件..."
$SSH_CMD "mkdir -p $REMOTE_DIR"
rsync -avz --delete \
  --exclude 'node_modules' \
  --exclude '.git' \
  --exclude '.claude' \
  --exclude 'server/server' \
  --exclude 'server/logs' \
  --exclude 'docs' \
  --exclude 'deploy' \
  -e "ssh -i $SSH_KEY -p $SSH_PORT" \
  "$PROJECT_DIR/" "$SSH_USER@$SSH_HOST:$REMOTE_DIR/"

# 4. 部署静态文件 + Nginx
echo "[4/5] 部署静态文件和 Nginx..."
$SSH_CMD "
  mkdir -p /srv/www/$DOMAIN/admin
  rm -rf /srv/www/$DOMAIN/admin/*
  cp -r $REMOTE_DIR/web/dist/* /srv/www/$DOMAIN/admin/

  if [ -d $REMOTE_DIR/client/dist ]; then
    mkdir -p /srv/www/$DOMAIN/frontend
    rm -rf /srv/www/$DOMAIN/frontend/*
    cp -r $REMOTE_DIR/client/dist/* /srv/www/$DOMAIN/frontend/
  fi

  # 重载 Nginx
  nginx -t && nginx -s reload 2>/dev/null || \
  docker exec nginx nginx -t && docker exec nginx nginx -s reload
"

# 5. 启动后端
echo "[5/5] 启动后端服务..."
$SSH_CMD "
  cd $REMOTE_DIR
  docker compose -f docker-compose.prod.yml down 2>/dev/null || true
  docker compose -f docker-compose.prod.yml up -d --build
"

echo "========================================="
echo "  部署完成！"
echo "  站点: https://$DOMAIN"
echo "========================================="
```

#### 4. servers.yaml 配置

```yaml
targets:
  dev:
    host: 192.168.0.228
    port: 22
    user: MINI1
    key: ~/.ssh/key
    remote_dir: ~/my-project
    app_port: 9000
    mode: docker

  prod:
    host: example.com
    port: 2220
    user: root
    key: ~/.ssh/key
    remote_dir: /root/my-project
    domain: example.com
    mode: docker-prod
    nginx: host          # host / docker / shared-docker
    ssl: acme
```

## Nginx 配置模板

### 开发环境（Docker 内）

```nginx
server {
    listen 80;

    # 管理后台
    location / {
        root /usr/share/nginx/html;
        try_files $uri $uri/ /index.html;
    }

    # API 代理
    location /api/ {
        proxy_pass http://server:9688;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

### 生产环境（宿主机 Nginx + HTTPS）

```nginx
server {
    listen 80;
    server_name example.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name example.com;

    ssl_certificate /path/to/fullchain.cer;
    ssl_certificate_key /path/to/domain.key;
    ssl_protocols TLSv1.2 TLSv1.3;

    gzip on;
    gzip_types text/plain text/css application/json application/javascript;

    # 客户端前端（如有）
    location / {
        root /srv/www/example.com/frontend;
        try_files $uri $uri/ /index.html;
    }

    # 管理后台
    location /admin/ {
        alias /srv/www/example.com/admin/;
        try_files $uri $uri/ /admin/index.html;
    }

    # API 代理
    location /api/ {
        proxy_pass http://127.0.0.1:9688;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # 健康检查
    location /health {
        proxy_pass http://127.0.0.1:9688;
    }
}
```

### 容器化共享 Nginx（多站点）

适用于一台服务器部署多个项目、共享一个 Nginx 容器的场景。
每个项目生成独立的 `.conf` 文件，放入 Nginx 容器的 `conf.d/` 目录。
