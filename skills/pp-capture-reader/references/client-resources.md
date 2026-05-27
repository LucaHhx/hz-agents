# clientResources/ — PP 客户端静态资源镜像

`fetch_client.mjs` 按 URL path 把命中白名单（root domain `pragmaticplaylive.net` + 启动链接根域 + WS 根域；ext `.js / .json / .html`）的响应**全量落盘**。字体 / 图 / CSS / 音视频不抓（对协议分析无用）。

## 标准目录树

```
clientResources/
├── desktop/<frontend>/               # 主游戏入口（HTML + 极少量 JS）
│   └── index.html                    # 由 main.js / shell chunk 实际渲染游戏
├── apps/
│   ├── shell/static/js/              # 应用 shell（启动器、SPA 路由）
│   ├── gor/<ver>/                    # 🔑 GOR runtime（Game Over / Roulette）— roulette / gor 类机台核心
│   │   ├── main.js                   # 入口
│   │   ├── *.<hash>.js               # webpack chunk（含协议常量 / betCode / 错误码）
│   │   └── release.json              # 版本信息
│   ├── gameplay/<ver>/               # slot 类核心（sweetbonanza / gates of olympus slot 等）
│   ├── translations-ui/latest/<lang>/   # 🔑 UI 文案翻译（按 gametype 分文件）
│   │   ├── core.json
│   │   ├── roulette.json / baccarat.json / ...
│   │   └── table_name.json
│   ├── translations-help/latest/<lang>/ # 🔑 游戏规则 / paytable 文案
│   │   ├── common.json
│   │   ├── <gametype>.json           # 通用 gametype（如 roulette.json）
│   │   └── <variantgametype>.json    # 变种（如 gatesofolympusroulette.json / megaroulette.json）
│   ├── feature-flags/<ver>/          # feature toggle manifest
│   └── video/<ver>/                  # 视频播放器
└── （hall 渠道下还会出现渠道随机域的 chunk，路径同 PP CDN 形态）
```

> **`<frontend>` 怎么定**：`tableConfig.params.frontend_roulette` / `frontend_*` 字段。`<gametype>` 在 SKILL.md / 启动链接 query / capture 目录名变体（去末尾数字）里能找到。`<ver>` 是 PP 内部版本号，每次部署可能变。

## 各目录用途速查

| 目录 | 关键文件 | 用来回答 |
|---|---|---|
| `desktop/<frontend>/index.html` | inline `<script>` + meta | 客户端入口 chunk 引用、feature flag 内联值 |
| `apps/gor/<ver>/main.js` + chunks | `*.[hash].js` | betCode 编码、lpbet 构造、错误码、协议常量、雷电触发逻辑 |
| `apps/gor/<ver>/release.json` | `{ version, ... }` | 协议版本（出问题时对照 PP changelog） |
| `apps/translations-help/latest/<lang>/<gametype>.json` | nested key 树 | 规则文本（"最近获胜结果"、"自动局"等） |
| `apps/translations-help/latest/<lang>/<variantgametype>.json` | 同上 | 变种特有玩法说明（如 Gates of Olympus 雷电规则） |
| `apps/translations-ui/latest/<lang>/<gametype>.json` | UI 按钮 / tooltip 文本 | UI 文案；不含协议信息 |
| `apps/translations-ui/latest/<lang>/table_name.json` | `{<tableId>: "<人类可读名>"}` | tableId ↔ 桌台展示名（多语言） |
| `apps/feature-flags/<ver>/<gametype>.manifest.json` | feature flag 列表 | 该 gametype 启用了哪些行为 |
| `apps/video/<ver>/` | 播放器实现 | 一般不关心 |

## 找 betCode / 协议常量（grep main.js）

`apps/gor/<ver>/main.js` + chunks 是 webpack bundle，通常 **minified**。直接读不可行，grep 模式可：

```bash
GOR_DIR=clientResources/apps/gor/1.2.2

# 1) betcode / bc 常量定义
grep -oE '"bc":[0-9]+|betcode:[0-9]+|BET_CODE_[A-Z_]+' "$GOR_DIR"/*.js | sort -u | head -30

# 2) 错误码枚举（PP 错误是字符串常量）
grep -oE '"ERR_[A-Z_]+"|errorCode:"[^"]+"' "$GOR_DIR"/*.js | sort -u | head -30

# 3) 协议事件 key 列表（client 侧 dispatch）
grep -oE '"betsopen"|"betsclosed"|"gameresult"|"timer"|"bets"|"winningBetCodes"|"luckyWin"|"gorRng"|"gorBonusReady"' "$GOR_DIR"/*.js | sort -u

# 4) 雷电倍率上限 / 触发概率（一般不在 main.js，在 chunk 里）
grep -lE 'lightning|bonusNo|gorBonus' "$GOR_DIR"/*.js
```

> **不要试图反编 webpack 看完整源码**。grep 常量 + 交叉对照 `message.txt` 实际帧就足以理解协议。代码反编属于性价比极低的活儿。

## translations-help（规则文案）

`<gametype>.json` 是嵌套 key 树，结构按章节 → 段落：

```jsonc
{
  "lastWinningResults": {
    "title": "最近获胜结果",
    "winningResults": "...",
    "bonusMultiplierOnTop": "..."
  },
  "lastWinningCombinations": { ... },
  "paytable": { ... },          // 🔑 赔率表文案（有时含具体倍率数字）
  "rules": { ... },
  "bonus": { ... },             // 雷电 / 奖励玩法说明
  // ...
}
```

**翻译文件是通用文档，不是单机台事实**（同一 gametype 多个桌共享同一个 translations-help 文件）。**单机台实际启用的玩法 / 赔率必须以 `tableConfig.params` + `gameDetail.txt` `<bet><description>` + `message.txt` `gameresult.mul` 实际值为准**。translations-help 里写的 "倍率最高 10000x" 不代表当前桌台开启了 10000x。

## 常见坑

| 坑 | 现象 | 处理 |
|---|---|---|
| 找不到 `apps/gor/<ver>/` | 该机台不是 GOR 类（如 slot / blackjack） | 看 `apps/gameplay/<ver>/` 或其他 runtime 目录；`tableConfig.params.tableVariant` 反查 runtime 名 |
| 翻译只抓到一种语言 | capture 是 lang=en 跑的，其它语言客户端没触发懒加载 | 重抓 capture 加 `--lang zh` / 修脚本顶部 `lang` 默认值；或事后从 PP CDN 手动拉 |
| translations-help 数字 ≠ tableConfig 实际限额 | 翻译是通用文档 | 以 `tableConfig.params.*_max` 为准 |
| `<frontend>` 目录里只有 index.html | 主入口是 SPA shell，业务在 apps/* 里 | 跟着 index.html 内 inline `<script>` 引用追 apps 目录 |
| 部分 `.js` 文件名带 hash | webpack chunk hash 每次部署都变 | grep 内容不要依赖文件名；按 pattern 跨文件 grep |
| `release.json` 版本号和 `<ver>` 目录名不一致 | 路径用部署版本，release.json 是构建版本 | 一般无影响；要精确对齐去 PP changelog 查 |
| 漏抓某个 host | shutdown 输出"跳过的资源 host top 10" | 把该 host 根域加进 `fetch_client.mjs` 顶部 `allowedRootDomains` 重抓 |
