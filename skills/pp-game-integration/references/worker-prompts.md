# Phase 5 — 4 个 Worker Prompt 完整模板

主 Claude 在 Phase 5 创建 worktree 后，通过 Agent 工具（subagent_type=general-purpose）**串行**启动 4 个 worker。每次只跑 1 个 worker，验收通过后再启下一个。

## 通用约束（每个 worker prompt 都注入）

```
你是 worker-N，做 PP 机台 <tableId>（<gameType>）对接的 <职责>。

## 工作区
- worktree: <worktree_path>（cd 进去保持，不切分支）
- 当前分支: <worktree_branch>
- HEAD: <当前 HEAD sha>
- 主仓库路径: <repo_root>
- design.md: <repo>/tmp/<tableId>/design.md
- agent 输出（必读）: <repo>/tmp/<tableId>/{dict.json, ui_rules.md, state_machines.md, lifecycle.md}

## 硬规则
1. 不切分支、不 push、不开 PR
2. **不修改**前序 worker 已 commit 的文件（只在其基础上扩展）
3. 自己 git add <具体文件名> + git commit（不要漏；不要用 git add -A）
4. 跑完 build/vet/test 才能算完成
5. **永远不参考** `/Users/luca/work/ppgame` 老项目
6. **必读** `<repo>/server/game/pp/internal/games/DEVELOPMENT.md` + `references/known-pitfalls.md`
7. **必读参考骨架**: `<repo>/server/game/pp/internal/games/roulette/crystalroul00001/`（同 JSON 协议参考）
8. 中文回报、注释最少（CLAUDE.md：默认不写注释，仅 WHY 非显然时一行）
9. 单文件 ≤500 行 / 控制流嵌套 ≤3 层（policy-pr 硬规则）

## 完成回报（B5 契约 — 漏一项视为失败）
1. **commit sha**
2. **`git show --stat HEAD`** 输出
3. **build 结果**（go build ./... 是否通过）
4. **vet 结果**（go vet 输出 + 区分既存/新增 warning）
5. **test 结果**（PASS/FAIL 数 + 关键覆盖说明）
6. **policy-pr 体量预检**（每文件行数）
7. **关键决策**（与参考骨架不同的设计选择）

最后一句必须写："等待主 claude 验收并启动下一个"。
```

## worker-1 骨架（必启用）

附加任务：

```
## 任务范围（仅创建以下 4 个文件，不实现业务逻辑）

目录: `server/game/pp/internal/games/<gametype>/<tableId>/`

### enum.go
- TableID / GameType / GameLoaderKey / UpstreamFmt / UpstreamGameCode / ResultEventKey 常量
- 上游事件名（来自 dict.json upstream_events）
- betCode 数值表（来自 dict.json betcodes）
- GR 字段→BC 反查表（来自 dict.json gr_field_to_betcode）
- 错误码（来自 dict.json error_codes）

### models.go
- 协议数据结构体（每个上游事件一个 struct + Envelope）
- 字段类型严格按 capture 实际下发（数字字符串都是 string，seq 是 int）

### processor.go
- Processor struct 嵌入 handlers.EventHandler
- 包含必要锁字段（mu / betsMu / cacheMu / disableMu / pendingMu）
- 实现 iface.TableProcessor 4 接口（HandleUpstream/HandleDownstream/Disconnect/KickUser）的**空骨架**
- buildEventCtx helper

### instance.go
- Instance struct 嵌入 *common.GameInstanceBase
- New(table, vendor) iface.GameInstance 装配函数
- handleGameMessage 上游消息回调

## 验收
- go build ./... 通过
- go vet 包内无新增 warning
- 不需要单测
```

## worker-2 业务（必启用）

附加任务：

```
## 任务范围

目录: `server/game/pp/internal/games/<gametype>/<tableId>/`（worker-1 已建）

### 业务文件
- upstream_dispatch.go — 上游消息路由（含 tableId 替换 + orderKeysByPriority + verdict 单独决策）
- upstream_cache.go — init 序列缓存
- upstream_handlers.go — OnGameResult / OnWinners / OnMerchantBetResult
- downstream_dispatch.go — ping/subscribe/command 路由
- downstream_bet.go — lpbet 解析 + validateBets + applyBet + 错误响应合成
- bet_redis.go — Redis 投注读取
- bet_window.go — 下注窗口状态机
- check_bet.go — CheckBet hook（内存 + Redis 双重 fail-closed）
- settle.go — 全用户结算
- payout.go — Calculate 纯函数
- xml_util.go — extractXMLAttr 单/双引号兼容

### 测试文件（≥ 5 个，覆盖率 ≥ 25%）
- payout_test.go（capture 4 个真实样本 + 至少 1 项边注 + 不参与字段断言）
- validate_test.go（窗口/边界/Bonus 主投注前置）
- dictionary_test.go（**字典 parity** — BC*/GR*/错误码 vs main.js 抽取）
- xml_util_test.go（extractXMLAttr 单/双引号 + xmlRootTag）
- dispatch_*_test.go（PP 视角 drop / tableId 替换 / orderKeysByPriority）
- 按 [test-design-guide.md](test-design-guide.md) 设计

## 验收
- go build / go vet 全过
- go test -race -count=3 全 PASS
- go test -cover ≥ 25%
- policy-pr 全文件 ≤ 500 行
```

## worker-3 HTTP 接口（**仅 http_diff.md 有缺口时启用**）

附加任务：

```
## 任务范围

按 <repo>/tmp/<tableId>/http_diff.md 的 missing/mismatched/field-gap 修：

### 文件
- server/api/v1/<相关包>/handler.go — 新增 / 完善 handler 函数
- server/router/<相关>.go — 注册新路由 / 改路径
- server/service/<相关>/service.go — 业务逻辑
- 必要时改 server/model/<相关>/*.go（**慎重**，改 model 影响多机台）

### 接口路径必须与 main.js 一致
http_diff.md 列出的客户端实际调用路径 → 与 server 现有路由对比 → 改成完全一致。

### 测试
新增 handler 至少 1 项单测（或 _test.go 中表驱动）。

## 验收
- 客户端 main.js 中的所有 HTTP 调用都能在 server 找到对应路由
- 新增 handler build 过 + 不破坏既有路由
```

## worker-4 注册（必启用）

附加任务：

```
## 任务范围

唯一改动：`server/game/pp/internal/factory/instance_factory.go`

### 改动 1: import
按既有缩进风格在 import 块加：
```go
<gametype><tableId-tail> "hab/game/pp/internal/games/<gametype>/<tableId>"
```
变量名取 `<gametype><tableId 后 6 字符>`（简短且唯一）

### 改动 2: ImplementedTableIDs() map 加一行
```go
<别名>.TableID: true,
```

### 改动 3: NewGameInstance() switch case 加一个 case
```go
case <别名>.TableID:
    return <别名>.New(table, vendor), nil
```
放在最后一个既有 case 之后

## 验收
- go build ./... 通过
- go vet ./game/pp/internal/factory/... 通过
- 已有机台 + 新机台 test 全 PASS
```

## 主 Claude 启动 worker 的伪代码

```python
# 串行启动每个 worker，验收后才启下一个
for worker in [worker_1, worker_2, worker_3_if_needed, worker_4]:
    if worker == worker_3 and not has_http_diff:
        continue

    # 用 jq 读取 state 字段，替换占位符
    prompt = render_template(worker.prompt_template,
        tableId=state.tableId,
        gametype=state.lobby.gameType,
        worktree_path=state.worktree_path,
        worktree_branch=state.worktree_branch,
        repo_root=state.repo_root,
        head_sha=git("HEAD"))

    result = Agent(subagent_type="general-purpose", prompt=prompt)

    # 验收 B5 契约 7 项
    if not validate_b5_contract(result):
        # 重试 1 次；再失败 git reset --hard HEAD~1 + 重启 worker
        ...

    # 写 state
    update_state(phase=5, last_worker=worker.name, last_commit=result.commit_sha)
```

## 失败回滚

| 情况 | 处理 |
|---|---|
| worker 失败前有未提交改动 | `git -C <wt> restore .` + `git -C <wt> clean -fd`（仅在隔离 worktree 内） |
| worker 已 commit 但要回滚 | `git -C <wt> reset --hard HEAD~1`（仅丢弃**该 worker** 的最后一条 commit）|
| 多 worker 已 commit 后要回滚到某 worker 之前 | 用 `git reflog` 找具体 sha，再 `reset --hard <sha>`，**保留**前序 worker commit |
| **禁止**`git reset --hard <base>`式直接回到分支起点 | 那会丢全部 worker commit |
