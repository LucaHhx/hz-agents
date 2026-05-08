# Phase 3 — agent-2 HTTP 接口纯静态分析手册

## 目录

- [铁律 — 不预设接口清单](#铁律--不预设接口清单)
- [输入 / 输出](#输入--输出)
- [分析步骤](#分析步骤)
- [grep 优化技巧](#grep-优化技巧)
- [失败处理](#失败处理)
- [与 docs/integration-experience/ 协作](#与-docsintegration-experience-协作)

## 铁律 — 不预设接口清单

**禁止**预设 PP 客户端会用某 endpoint。所有 endpoint 必须**从当次 main.js / clientResources chunks 实际发现**。本文档**不列**任何具体接口清单或"通用调用模式"，只写**分析方法**。

> 既往尝试预列"桌台配置 / 翻译 / 玩家配置 / 统计 / 历史 / 限额 / 余额 / 视频流 / 大厅"等模式 → 已删除，因为容易被误读为"必查清单"。

## 输入 / 输出

### 输入

- `<repo>/tmp/<tableId>/clientResources/apps/<gametype>/<version>/main.js`
- `<repo>/tmp/<tableId>/clientResources/**/*.js`（webpack chunks，懒加载可能含独有接口）
- `<repo>/server/api/v1/`（现有路由源文件）

### 输出

#### http_endpoints.json

```json
{
  "endpoints": [
    {
      "url_pattern": "/api/ui/savePlayerConfigGeneric",
      "method": "POST",
      "found_in": "main.js:12345",
      "request_fields": ["JSESSIONID", "ck", "url", "body.gameType"],
      "response_fields_read_by_client": ["status", "data.config"],
      "called_under_condition": "玩家修改 vibration 设置时"
    }
  ],
  "issues": []
}
```

#### http_diff.md

```markdown
# HTTP 接口缺口

## missing endpoints（必须新增 handler）
- POST /api/foo — main.js:12345 调用，server 无路由

## path mismatched（改 router）
- main.js 调 /api/v1/bar，server 注册的是 /api/v2/bar — 二选一对齐

## field gap（补字段）
- /api/ui/stats: main.js 读 `noOfGames` 字段，server 当前响应缺该字段

## 机台特殊数据（加机台分支）
- /api/<某 endpoint>: 需返回本机台特有字段
```

## 分析步骤

### Step 1: 列出所有 HTTP 调用点

```bash
rg -n 'fetch\(' <main.js + chunks>
rg -n 'axios\.(get|post|put|delete|patch)' <main.js + chunks>
rg -n '\.open\(\s*[\'"](GET|POST|PUT|DELETE|PATCH)[\'"]' <main.js + chunks>

# 字面量 URL
rg -nE '"\/(api|cgi-bin|apps|games)/[^"]+"' <main.js + chunks>
```

### Step 2: 提取每个调用点的 URL pattern

对每个命中位置，向前向后看 200 字符上下文，识别：
- **基址**：`baseUrl` / `metaServer` / `actualWebServer` / 字面量域名
- **路径**：紧跟的字符串字面量 / .concat() 拼接
- **方法**：fetch options.method / axios.METHOD / xhr.open(METHOD, ...)
- **请求体**：fetch options.body / axios POST 第 2 参数 / xhr.send(body)
- **响应字段读取**：在 .then(r => ...) 内 grep `r\.|data\.|response\.` 字段

### Step 3: 静态归一化

同一 endpoint 在多处被调用时，按 `url_pattern` 去重；动态参数（`${tableId}` 等）规范化。

### Step 4: 对比 server/api/v1/

```bash
rg -nE 'router\.(GET|POST|PUT|DELETE|PATCH)|\.(GET|POST|PUT|DELETE|PATCH)\("[^"]+"' \
    <repo>/server/api/v1/ <repo>/server/router/ <repo>/server/initialize/

rg -nE 'func \([a-zA-Z]+ \*?\w+(?:Api|Service|Handler)\) \w+' <repo>/server/api/v1/
```

把 server 提取出的路由跟客户端 endpoint 列表比对，分类：
- 客户端有 + server 有 + 路径一致 → ✅ 已覆盖
- 客户端有 + server 没 → ❌ missing endpoint
- 客户端有 + server 有但路径不一致 → ❌ path mismatched
- 客户端有 + server 有 + 路径一致 + 客户端读字段 server 不返 → ❌ field gap

### Step 5: 字段对比（深入）

对每个"server 已有"的 endpoint，看 client 实际读什么字段 vs server 实际返什么字段：

```bash
rg -nE 'c\.JSON|response\.(Ok|Fail)' <repo>/server/api/v1/ -A 10
```

如果 client 读了 server 没返回的字段 → field gap。

## grep 优化技巧

### 区分静态资源 vs API 调用

PP 静态资源域名: `client.pragmaticplaylive.net` / `assets.pragmaticplaylive.net`（已在 fetch_client.mjs 抓取）
API 调用域名: 通常 `games.pragmaticplaylive.net` / 启动 URL 的 `actual_web_server`

→ 排除静态资源命中（避免把 `.json` 翻译文件当 API 调用）。

```bash
rg -oE 'https?://[^"\s]+|"\/[a-zA-Z][^"]+"' main.js \
    | grep -v 'client.pragmaticplaylive\|assets.pragmaticplaylive'
```

### 区分自家 server 接口 vs PP 上游接口

PP 客户端可能调两类 HTTP：
1. **PP 上游官方接口**（如 PP 官方 cgi-bin）→ 我方做反向代理（PPClientProxy 等）
2. **我方实现的接口**（如 /api/ui/stats）→ 我方 server 直接处理

按调用域名区分；我方 server 改动只针对类型 2。

## 失败处理

| 情况 | 处理 |
|---|---|
| main.js 未压缩到一行 / 多 chunk 散落 | rg 多文件模式（`main.js *.js`）|
| URL 用模板字符串 + 变量 | 提取变量定义点 |
| 路径含 hash/uuid 占位符 | 归一化为 `<占位>` |
| webpack chunk 名为 hash | 不忽略，全 grep |
| server/api/v1/ 路由分散在多文件 | 顺路 grep `router/<domain>/enter.go` 找路由注册总入口 |
| **分析失败** | **不许**把"分析失败"标成"无缺口"。必须 stderr + http_endpoints.json error 字段；主 Claude 重试 1 次 / 仍失败 → fail-closed 报告用户 |

## 与 docs/integration-experience/ 协作

每次新对接的 http_endpoints.json + http_diff.md 必须**反向贡献**到 docs/integration-experience/<gametype>/<tableId>.md 第 7 节，让下次同 gametype 的对接 agent-2 能直接对照"上次发现 X 接口"，加速分析。

但**不能**把上次的接口清单当作"本次也一定有"——必须当次重新 grep 验证。
