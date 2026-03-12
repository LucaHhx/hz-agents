# 模块 09 — 部署指南

## 概述

支持三种部署模式：本地直接运行、本地 Docker、远程 Docker。

详细部署配置和脚本模板见 `references/deploy-guide.md`。

## 部署模式速览

### 1. 本地直接运行

最简单的开发模式：

```bash
# 后端
cd server
go build -o hab . && ./hab

# 前端 (web)
cd web
npm install && npm run serve

# 前端 (client，如有)
cd client
npm install && npm run dev
```

### 2. 本地 Docker

使用 docker-compose 一键启动：

```bash
docker compose up -d --build
```

包含：server + nginx（静态文件服务）+ 可选 mysql/redis。

### 3. 远程 Docker

完整的远程部署流程：

1. 本地构建前端
2. rsync 同步文件到远程
3. 远程 docker-compose 构建并启动
4. 配置 Nginx 反向代理

## 部署脚本

每个部署目标生成一个脚本：

```
deploy/
├── dev.sh              # 开发服务器部署脚本
├── prod.sh             # 生产服务器部署脚本
└── servers.yaml        # 连接配置
```

### servers.yaml 格式

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
    nginx: host        # host / docker / shared-docker
    ssl: acme
```

## Nginx 配置

三种场景：

| 场景 | nginx 字段 | 说明 |
|------|-----------|------|
| Docker 内 | docker | 开发环境，nginx 在 compose 中 |
| 宿主机 | host | 生产环境，nginx 直接安装在服务器 |
| 容器化共享 | shared-docker | 多站点共享 nginx 容器 |

## 快速开始

```bash
# 1. 本地开发
cd server && go run .
cd web && npm run serve

# 2. 想部署到远程？
# 参考 references/deploy-guide.md 获取完整步骤
```
