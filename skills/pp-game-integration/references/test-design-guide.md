# Phase 5 — 测试设计指引

**不是代码模板**。每次按真实 capture / 字典 / 业务逻辑写测试。本文档只规定**测试设计原则**和**必测场景清单**。

## 总原则（来自 go-unit-testing skill）

- **contract-first** — 测的是**接口契约**而不是私有 helper 的 trivial 实现
- **真实数据** — capture 验证过的样本，不要造虚假 happy path
- **不 mock 自己的代码** — 用真实 struct + 真实数据
- **断言意图而非实现细节** — 修改实现不应破坏测试

## 必测场景清单（按文件分组）

### payout_test.go — 结算公式

**必测**：
- [ ] 至少 4 个不同 `result` 的 capture 样本（如 baccarat：庄赢 / 庄6 赢 / 闲赢 / 和局退本）
- [ ] 至少 1 项边注（PerfectPair / PlayerPair / Super6 等）
- [ ] **不参与结算字段断言**（baccarat 的 bnc/pnc/bg/sm；roulette 类似的不参与字段）—  设这些字段为非零值，断言主三注结果**不受影响**
- [ ] UnknownBetCode（押 betCode 999 → 0）
- [ ] 守卫参数（amount=0 / 负 amount → 0）
- [ ] InvalidField（GR 字段值非数字 → 0）

**测试样本来源**：从 `tmp/<tableId>/message.json` 截取真实 gameresult 帧的字段值。

### validate_test.go / check_bet_test.go — 下注校验

**必测**：
- [ ] BC 非数字 → ErrBetCodeInvalid
- [ ] BC 不在白名单 → ErrBetCodeError
- [ ] BC 在 disabledSidebets → ErrBetNotAllowed
- [ ] amount < min → ErrDidntMeetMinimumBetLimit
- [ ] amount > max → ErrMaximumBetLimitExceeded
- [ ] 边界值（amount = min / amount = max）→ 通过
- [ ] CheckBet 窗口未开 → ErrBetNotOnTime
- [ ] CheckBet gameID 不匹配 → 拒
- [ ] 业务专属规则（如 baccarat PlayerBonus 须先押 Player）

### dictionary_test.go — 字典 parity

**必测**（**所有机台必有**）：
- [ ] BC* 常量数量与设计一致（防止漏定义）
- [ ] 每个 GR 字段反查指向正确的 BC（间接验证：构造 GR 字段=1.0 → Calculate(BC, 1, gr) 必须 = 1.0）
- [ ] 错误码值与 main.js qe.a 一致（关键的 10+ 项抽样）
- [ ] 桌台元数据常量（TableID / GameType / GameLoaderKey / UpstreamFmt / UpstreamGameCode / ResultEventKey）

**意义**：任何后续修改 BC* 数值或 Up 反查表都自动断言失败。

### dispatch_*_test.go — 协议层

**必测**：
- [ ] orderKeysByPriority — gameresult 必须排在 winners 前
- [ ] remarshalKeptKeys — 多 key 单帧的输出顺序 + 不重复包装 envelope
- [ ] PP 视角全 drop（bet/bets/win/winningBetCodes/betSpotWin/command/pong/上游 winners 单测）
- [ ] tableId 替换（用非 baccarat 帧避开 DB 路径）
- [ ] init cache 写入 + cacheGet 读取一致

**避免**：HandleUpstream 的 OnGameResult / OnWinners 路径调用 DB —— 单测无 DB 实例会失败。这部分留给集成测试，dispatch 单测**避开** gameresult / winners 帧（用 timer / table 等代替）。

### parse_*_test.go — 协议解析

**必测**：
- [ ] amt 边界（0 / 负值 / 非数字 / 正常）
- [ ] 缺字段（缺 amt / 缺 bc）
- [ ] FreeChip 节点跳过（bettype="FB"）
- [ ] malformed XML（缺 `/>` / 缺闭标签）
- [ ] 多个 `<bet>` 节点解析

### xml_util_test.go — XML 工具

**必测**：
- [ ] extractXMLAttr 双引号
- [ ] extractXMLAttr 单引号（PP 历史踩坑）
- [ ] extractXMLAttr 缺 attr
- [ ] xmlRootTag 多种格式

### bet_window_test.go — 窗口状态机

**必测**：
- [ ] 默认 close
- [ ] gameID 空 → false
- [ ] gameID 不匹配 → false
- [ ] gameID 匹配 → true

### disablesidebets_test.go — 禁用边注

**必测**：
- [ ] CSV 解析（"14,15,18,19" → map）
- [ ] 重复推送覆盖（不累加）
- [ ] 空字符串清空所有禁用
- [ ] 解析失败保留之前状态
- [ ] 非数字 token 跳过

## 命名约定

- 测试函数：`Test<Type>_<Scenario>` 或 `Test<Func>_<Scenario>`
- capture 样本变量：`gr_<Score>_<Result>`（如 `grBanker6` / `grPlayer7Natural`）
- 表驱动测试：`cases := []struct{ name string; ... }`

## 不要测的（go-unit-testing skill 强调）

- ❌ 私有 helper 的 trivial 实现（splitCSV 内部循环、xmlRootTag 字符扫描细节）
- ❌ nil-check 测（`if x == nil { return nil }` 这种返回 nil 的边界）
- ❌ mock-feeds-mock 测（mock 一个 PlaceBet 然后断言它被调用）
- ❌ trivially-true 断言（`assert.True(true)`）
- ❌ 编译器已经守住的事（结构体字段类型 / interface 实现）

## 覆盖率目标

- baccarat / roulette / sweetbonanza 这种核心机台：**≥ 25%**
- 含 capture 验证样本 + 字典 parity + 边界 + 协议层 robustness 即可达标
- 不强求 80%（业务路径很多走 DB / Redis，单测无法覆盖）

## 跑测试的命令

```bash
cd server
go test -race -count=3 ./game/pp/internal/games/<gametype>/<tableId>/...
go test -cover ./game/pp/internal/games/<gametype>/<tableId>/...
```
