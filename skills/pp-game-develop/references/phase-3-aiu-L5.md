# Layer 5 AIU — 依赖全部（1）

> 进入 L5 前确保 L1-L4 全部完成 + 层间审查通过。
> L5 是 factory 注册，最简单但最关键 — 注册失败 = 整个对接不生效。

## L5.1 — FACTORY

**产物**：`server/game/pp/internal/factory/instance_factory.go`（**修改既有文件**，不新建）

**分析输入**：
- L1 ENUM（TableID 常量）
- 既有 `instance_factory.go` 结构（参考 dragontiger / baccarat6 / sweetbonanza 等已注册行）

**实现内容**：3 处改动

### 改动 1: import

按既有 alphabet 风格在 import 块加：
```go
<gametype>tid<tableId 后缀> "hab/game/pp/internal/games/<gametype>/<tableId>"
```

变量名风格：`<gametype>` + `tid` + `<tableId 后 4-6 字符>` 简短唯一。参考既有：
- `baccarat6cbcf222 "hab/game/pp/internal/games/baccarat/cbcf6qas8fscb222"`
- `dragontiger "hab/game/pp/internal/games/dragontiger/drag0ntig3rsta48"`

如同 gametype 当前只有这一张桌 → 可直接用 gametype 名（如 `dragontiger`）。

### 改动 2: `ImplementedTableIDs()` map 加一行

```go
<别名>.TableID: true,
```

### 改动 3: `NewGameInstance()` switch case 加一个 case

```go
case <别名>.TableID:
    return <别名>.New(table, vendor), nil
```

放在最后一个既有 case 之后。

## 实现约束

- **不修改任何前序 AIU 已 commit 的文件**（包括所有 internal/games/`<gametype>`/`<tableId>`/* 文件、internal/gateway/api/*；旧 `runtime/history_<gametype>.go` 已废弃，新机台不存在该路径）
- 改 `instance_factory.go` 1 个文件，3 处改动；如 L3.4/L3.5 未在自身 commit 内补 `history_factory.go` 注册，本步同时补（HISTORY_DETAIL + HISTORY_REPORT 共用同一 historyProvider 实例）

## B5 验收

- `go build ./...` PASS（**全仓库 build**，不只 factory 包）
- `go vet ./game/pp/internal/factory/...` 无新增 warning
- `go test ./game/pp/internal/factory/...` PASS（如有 test）
- 既有机台 + 新机台 build/test 全 PASS
- policy-pr：instance_factory.go ≤ 500 行

## 下游

- 跑全量 build + 全机台测试，确认不破坏既有机台
- 进 Phase 4 自问审查

## prompt 模板

```
你是 AIU-FACTORY（Layer 5），做 PP 机台 <tableId> (<gametype>) 对接的"factory 注册"工作单元。

## 工作区
- worktree: <worktree_path>
- HEAD: <head_sha>（L1-L4 全部 commit 后的 HEAD）
- 主仓库: <repo_root>

## 唯一改动文件
server/game/pp/internal/factory/instance_factory.go

## 分析阶段
- 读既有 instance_factory.go 全文
- 看 dragontiger / baccarat6 / sweetbonanza / crystalroulette 既有注册行风格
- 决定变量名（按 gametype 唯一性）+ 插入位置（按字母序或既有顺序）

## 实现阶段
3 处改动（import / ImplementedTableIDs / NewGameInstance switch case）。

## 验收
- go build ./... 全仓库 PASS
- go vet ./game/pp/internal/factory/... 无 warning
- 既有机台 + 新机台 test 全 PASS
- policy-pr ≤ 500 行

## 完成回报
1. commit sha
2. git show --stat HEAD（应仅 1 文件 / + 4 行左右）
3. build/vet/test 结果
4. 关键决策：变量名选择 / 插入位置

最后一句："等待主 claude 验收 — 这是 Layer 5 末层，进 Phase 4 自问审查"。
```
