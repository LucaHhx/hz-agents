# Layer 5 AIU — 依赖全部（1）

> 进入 L5 前确保 L1-L4 全部完成 + 层间审查通过。
> L5 是 factory 注册 + DB 模板，最简单但最关键 — 注册失败 = 整个对接不生效。

## L5.1 — FACTORY

**产物**：
- `server/game/evo/internal/factory/instance_factory.go`（**修改既有文件**，不新建）
- DB 模板：`b_tables` 行 + `b_table_currency_configs` 行（写进经验文档部署 checklist，**不自动执行**）

**分析输入**：
- L1 ENUM（Variant 字段约定）+ L2 PROCESSOR（NewProcessor 签名）
- 既有 `instance_factory.go` 全文（roulette `buildRouletteInstance` 范例）

**实现内容**：

### 改动 1: import 新族 core 包
```go
import (
    ...
    <gametype>core "hab/game/evo/internal/games/<gametype>/<gametype>core"
)
```

### 改动 2: `implementedTables()` map 加一行（键 = **original_id 裸 id**，不带 evo 前缀）
```go
func implementedTables() map[string]bool {
    return map[string]bool{
        "vctlz20yfnmp1ylr": true,   // roulette 既有（裸 id）
        "<新裸 tableId>":     true,   // 新桌
    }
}
```
> 🔴 **键是 `original_id`（裸 id），不是 `b_tables.code`**——实际代码 `instance_factory.go` 注释坐实「键必须用 original_id」：后台同步弹窗 `buildPreviewItem` 按 `PreviewTable.TableID(=original_id)` 比对，误用 code 会让所有 EVO 桌错显「未实现」（已修历史坑）。与 `newGameInstance` switch 的 `table.OriginalId` **同口径**。裸 id 可能是 operator 风格（如 `IceFishing000001`）而非 vctlz hash，直接原样作键。

### 改动 3: `newGameInstance()` switch 加 case（switch 的是 **`table.OriginalId`**=裸 tableId）
```go
func newGameInstance(table *business.Table) (iface.GameInstance, error) {
    switch table.OriginalId {
    case tableVctlz:                       // 既有 roulette
        return buildRouletteInstance(table), nil
    case "<新裸 tableId>":                  // 新桌
        return build<Gametype>Instance(table), nil
    }
    return nil, fmt.Errorf("evo 机台 %q 未实现", table.OriginalId)
}
```

### 改动 4: 新族 `buildXxxInstance`（新游戏族才写；复用既有 core 的新桌走既有 buildXxxInstance）
```go
func build<Gametype>Instance(table *business.Table) iface.GameInstance {
    variant := <gametype>core.Variant{
        TableID:    table.Code,        // 带 evo 前缀，我方索引
        PPTableID:  table.OriginalId,  // 裸 EVO tableId，协议帧用
        GameType:   gameTypeOf(table),
        TableLabel: table.Name,
    }
    limits := runtime.Load<Gametype>Limits(global.HAB_DB, table.ID, "")  // USD 兜底，结算按 ctx.UserCurrency 细化
    proc := <gametype>core.NewProcessor(variant, limits)
    proc.SetBalanceSource(runtime.PlayerBalance)   // 🔴 缺它余额恒 0 → LOW BALANCE
    betSvc := &runtime.SeamlessBetService{}
    return runtime.NewEvoInstance(table, proc, betSvc)
}
```

### DB 模板（写进经验文档部署 checklist）
```sql
-- b_tables：vendor_type='evo'、code='evo'+裸id、original_id=裸id、enabled=true
INSERT INTO b_tables (vendor_type, code, original_id, name, game_type, enabled, failover_group_id) VALUES
  ('evo', 'evo<裸id>', '<裸id>', '<桌名>', '<gametype>', 1, <group>);
-- b_table_currency_configs：各币种限红 + currencyMult（L4.5 CURRENCY_CONFIG 产出）
```
> 大厅 allowlist 从 `b_tables enabled=true` 自动刷新订阅，**不改大厅代码**。

## 实现约束
- **不修改任何前序 AIU 已 commit 的文件**（games/<gametype>/<gametype>core/* 全部、gateway/*、runtime/*）
- 改 `instance_factory.go` 1 个文件（import + implementedTables + switch + build 函数）
- **bootstrap 零改**：`bootstrap/run.go` 经 `import _ "hab/game/evo/internal/factory"` 触发 init() 自动注册，新族包被 factory import 即生效

## B5 验收
- `go build ./...` PASS（**全仓库 build**）
- `go vet ./game/evo/internal/factory/...` 无新增 warning
- `go test ./game/evo/...` PASS（既有 roulette + 新族全 PASS）
- policy-pr：instance_factory.go ≤ 500 行
- DB 模板写进经验文档（不执行；本地验证用 mysql-operator 连 config.local.yaml）

## 下游
- 跑全量 build + 全 EVO 测试，确认不破坏既有 roulette
- 进 Phase 4 铁律核对

## prompt 模板
```
你是 AIU-FACTORY（Layer 5），做 EVO <gametype> 桌 <evo_table_id> 对接的"factory 注册 + DB 模板"工作单元。

## 工作区：worktree <worktree_path> · HEAD <head_sha>（L1-L4 全 commit 后）· 主仓库 <repo_root>
## 唯一改动文件：server/game/evo/internal/factory/instance_factory.go
## 分析：读既有 instance_factory.go（buildRouletteInstance 范例）；确定 import 别名 + switch 位置
## 实现：import + implementedTables(键=original_id 裸id) + switch(on OriginalId=裸id) + buildXxxInstance + DB 模板写经验文档
## 验收：go build ./... 全仓库 PASS / go vet / 既有 roulette + 新族 test 全 PASS / policy-pr ≤500 行
## 完成回报（B5）：1.commit sha 2.git show --stat HEAD（仅 1 文件）3.build/vet/test 结果 4.关键决策（别名/插入位置/DB 模板）
最后一句："等待主 claude 验收 — 末层，进 Phase 4 铁律核对"
```
