# 模块 10 — 常见问题

## 概述

开发过程中的常见问题和解决方案。详细排查步骤见 `references/troubleshooting.md`。

## 快速 FAQ

### Q1: 符号链接失效，skill/command 找不到

```bash
cd .claude && bash link.sh
```

如果 link.sh 中的 hz-agents 路径不对，手动修正：
```bash
# 查看当前路径
cat .claude/link.sh | grep HZ_AGENTS

# 修正为实际路径
sed -i '' 's|HZ_AGENTS=.*|HZ_AGENTS="/actual/path/to/hz-agents"|' .claude/link.sh
```

### Q2: config.yaml 找不到

后端启动时报 `Fatal error config file`：
1. 确认在 `server/` 目录下运行
2. 检查 `config.yaml` 是否存在（从 `config.example.yaml` 复制）
3. 或设置环境变量指定路径：`export HAB_CONFIG=/path/to/config.yaml`

### Q3: 端口冲突

默认端口占用排查：

| 端口 | 服务 | 排查 |
|------|------|------|
| 9688 | 后端主服务 | `lsof -i :9688` |
| 9689 | 后端 API | `lsof -i :9689` |
| 8091 | web 管理后台 | `lsof -i :8091` |
| 8093 | client 前端 | `lsof -i :8093` |

修改端口：后端改 `config.yaml` 的 `system.addr`，前端改 `.env` 的 `VITE_CLI_PORT`。

### Q4: Agent 执行失败

检查 `settings.local.json` 权限配置：
```json
{
  "permissions": {
    "allow": ["Bash(*)", "Read(*)", "Write(*)", "Edit(*)"],
    "deny": []
  }
}
```

### Q5: Docker 构建失败

常见原因：
- **CGO 问题**：SQLite 需要 CGO，Dockerfile 中需 `CGO_ENABLED=1`
- **GOPROXY**：国内需设置 `GOPROXY=https://goproxy.cn,direct`
- **node_modules**：确保 `.dockerignore` 包含 `node_modules`
- **多阶段构建**：确认 builder 阶段安装了 gcc（SQLite 编译需要）

### Q6: 前端代理不通

检查 `web/vite.config.js` 中的 proxy 配置：
- `target` 端口是否与后端 `system.addr` 一致
- 后端是否已启动

### Q7: 数据库迁移失败

- SQLite：检查文件权限和磁盘空间
- MySQL：确认数据库已创建、用户权限正确
- 查看 `server/log/` 目录下的日志文件

### Q8: AutoCode API Key 无效

1. 确认 `config.yaml` 中 `autocode.api-key` 已设置且非空
2. 重启 server 使配置生效
3. 请求头中使用 `x-api-key` 而非 `Authorization`

### Q9: 多端项目前端任务标签混乱

确保 `frontend/tasks.md` 中每个任务都有 `[web]` 或 `[client]` 标签。
参考 `modules/05-multi-endpoint.md` 了解标签规范。
