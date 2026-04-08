---
name: pp-game
description: |
  PP Live Casino 游戏机台全流程对接。从游戏 URL 到完整后端实现的端到端流水线。
  包含：HAR 自动录制（HTTP+WS）、消息流分析、客户端代码分析、结算验证、代码实现。
  触发条件：用户提供 PP 游戏链接要求录制/分析/对接、提供 HAR 文件要求分析、
  实现新的 PP 游戏机台、调试游戏投注/结算问题。
  触发词：对接游戏、实现机台、新游戏、HAR分析、游戏开发、PP游戏、游戏结算、
  implement game、new table、game implementation、完善机台、游戏对接、
  录制HAR、record har、抓包、游戏链接、游戏URL
---

# PP 游戏机台全流程对接

从游戏 URL 到完整后端实现的端到端流水线。

## 前置知识

每次对接新机台前必须读取：
- `server/service/game/vendors/pp/games/DEVELOPMENT.md` — 完整开发指南和踩坑经验

参考已实现机台（按消息格式选最接近的）：
- JSON 格式：`games/roulette/crystalroul00001/`
- XML 格式：`games/dragontiger/drag0ntig3rsta48/`
- XML + 动态赔率：`games/megaroulette/amr251e1lxamr251/`

## 全流程（8 个阶段）

按阶段执行。每阶段完成后**自行验证数据正确性**，验证通过直接进入下一阶段，不要停下来询问用户确认。只在遇到异常或需要用户提供信息时才询问。

---

### 阶段 0：HAR 录制（用户提供游戏 URL 时）

如果用户提供的是游戏 URL 而非 HAR 文件，先录制 HAR。

**双通道架构**：录制脚本负责抓包，Claude 通过 agent-browser 操控同一浏览器。

```bash
# 1. 后台启动录制器（<this-skill-base-dir> 在 skill 触发时由系统提供）
node <this-skill-base-dir>/scripts/har_recorder.mjs "<游戏URL>" --duration=5m --cdp-port=9222 &

# 2. 等游戏加载后，通过 CDP 连接操控浏览器
agent-browser --cdp 9222 screenshot
agent-browser --cdp 9222 click "#helpIconId"   # 点帮助
agent-browser --cdp 9222 wait 5000
agent-browser --cdp 9222 click "#helpIconId"   # 关闭帮助

# 3. 下注（通过 JS 注入 PixiJS 事件）
agent-browser --cdp 9222 eval "/* 等 betting + 下注 */"

# 4. 录制器到时间自动保存 HAR
```

录制器实时汇报 JSON 事件（stdout），关注：
- `game_loaded` — 初始化序列
- `bets_open` / `bets_closed` — 投注窗口
- `game_result` — 轮次结果
- `bet_confirmed` / `win` — 投注和结算

**PP 游戏 UI 操作要点**：
- 界面是 PixiJS canvas 渲染，DOM 选择器对投注区/筹码无效
- 帮助按钮是唯一的 DOM 元素：`#helpIconId`

**投注参考**（Mega Roulette 验证通过，其他机台需实时探索适配）：

投注核心流程：选最低筹码 → 等投注期开始 → 下注 → 等开奖。
不同机台的 UI 结构、投注区命名、全局变量可能不同，需先通过 `eval` 探索确认。

```js
// 参考：Mega Roulette 投注示例
agent-browser --cdp 9222 eval "
new Promise(resolve => {
  const poll = () => {
    const t = window.CRLADATA;  // 全局状态（不同机台变量名可能不同，需探索）
    const app = window.gameApp;
    if (!t?.isBettingEnabled) { setTimeout(poll, 100); return; }
    const spot = app.betBoard.betSpots.children.find(s => s.name === 'dz_47'); // 偶数
    if (!spot?.buttonMode) { setTimeout(poll, 100); return; }
    const mkEv = target => ({ currentTarget: target, target, data: { global: { x: 0, y: 0 } }, stopPropagation: () => {} });
    const chip0 = app.bettingTools.openChips.children.find(c => c.id === 0);
    if (chip0) chip0.emit('pointerup', mkEv(chip0));
    spot.emit('pointerdown', mkEv(spot));
    spot.emit('pointerup', mkEv(spot));
    setTimeout(() => resolve('ok:pTotalbet=' + window.pTotalbet), 300);
  };
  setTimeout(() => resolve('timeout'), 90000);
  poll();
});
"
```

**每次对接新机台时，先用 eval 探索**：
1. `Object.keys(window).filter(k => k.includes('game') || k.includes('CRLA'))` — 找全局变量
2. `gameApp.betBoard.betSpots.children.map(s => s.name)` — 找投注区名称
3. `gameApp.bettingTools.openChips.children.filter(c => c.chipValue).map(c => ({id:c.id, value:c.chipValue}))` — 找筹码
4. 截图确认 UI 布局

**已知规律**：
- 事件必须是 `pointerup`(筹码) → `pointerdown`+`pointerup`(投注区)
- 不要用 `pointertap` 或直接调 `betSpotClicked`，不会真正触发投注
- `spot.buttonMode === true` 表示当前可点击（投注期）
- 投注策略因游戏类型而异，先通过截图和 eval 探索当前游戏的投注区域
- 每轮随机选择 1-2 个不冲突的注点，尽量覆盖不同 betCode
- 避免押单个数字（中奖率太低），优先选大区域注（红/黑、奇/偶、列、打等）
- 不要硬编码投注逻辑，根据实际游戏 UI 灵活判断
- **最少需要 5 次中奖**才能结束 HAR 录制（通过录制器 `win` 事件计数判断）

验证 HAR 数据完整后直接进入阶段 1。

---

### 阶段 1：HAR 分析

```bash
python3 <this-skill-base-dir>/scripts/analyze_har.py <har_path>
python3 <this-skill-base-dir>/scripts/analyze_har.py <har_path> --full
```

输出：游戏概要、消息格式、初始化序列、消息类型汇总、用户下注轮次、gameresult 赔率。

验证正确后直接进入阶段 2**

---

### 阶段 2：等待机台同步与客户端资源

告知用户需完成：管理后台添加机台、DGA 订阅、客户端资源拉取。

验证正确后直接进入阶段 3**

---

### 阶段 3：客户端代码分析

分析 `client/desktop/{gameType}/` 下的 minified JS，关注消息常量、投注方式、ping 格式、subscribe 校验、assetsUrl、投注依赖等。

验证正确后直接进入阶段 4**

---

### 阶段 4：结算流程分析

赔率验证（见 [references/odds-verification.md](references/odds-verification.md)）、结算策略、消息顺序、边界情况。

验证正确后直接进入阶段 5**

---

### 阶段 5：实现计划总结

文件清单、消息处理表、结算策略、客户端适配、风险点。

验证正确后直接进入阶段 6**

---

### 阶段 6：代码实现

按顺序：common.go → odds.go → enum.go → models → processor.go → instance.go → handle_upstream.go → handle_downstream.go → settle_and_winners.go → bet_redis.go → instance_factory.go 注册 → `go build ./...`

---

### 阶段 7：验证与优化

本地启动对比 → 投注/结算/语言测试 → 日志检查 → 优化建议。

## 脚本

| 脚本 | 说明 |
|------|------|
| `scripts/har_recorder.mjs` | HAR 录制服务：HTTP(recordHar) + WS(page.on websocket)，CDP 端口暴露浏览器 |
| `scripts/analyze_har.py` | HAR 分析：提取 WS 消息、分类、初始化序列、赔率数据 |

## 参考资料

- 开发指南：`server/service/game/vendors/pp/games/DEVELOPMENT.md`
- 赔率验证：[references/odds-verification.md](references/odds-verification.md)
