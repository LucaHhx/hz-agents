# Layer 1 AIU — 无依赖（3 并行）

> 进入 L1 前确保 Phase 0 / 1 / 2 已 done。
> L1 是整个对接的协议事实基础，下游全部依赖；ENUM 失败 = block 整层。

## L1.1 — ENUM

**产物**：`server/game/pp/internal/games/<gametype>/<tableId>/enum.go`

**分析输入**（按需读，不读全部）：
- `tmp/<tid>/message.jsonl` recv 帧抽事件名集 + send 帧抽 bc 集
- `tmp/<tid>/tableConfig.jsonl` `.betCode` 字段
- `tmp/<tid>/clientResources/.../main.js` grep `Qp` 枚举 / errorCode 字面量 / `tf`/`nf` 映射表 / 罕见事件名

**实现内容**：
- `TableID / GameType / GameLoaderKey / UpstreamGm / OperatorTheme / OperatorGameId` 常量
- 上游事件名常量（按 dict 全集）
- bc 枚举（PP `Qp` 枚举，注意可能乱序）
- face value ↔ bc 双向映射（megawheel 等需要：FaceValueToBC / BCToFaceValue）
- errorCode 全集常量（≥ 30 项典型；不 import 其他机台 — known-pitfalls I2）
- Redis key 前缀（pp:bets:`<TableID>`:`<gameId>` 等，统一走 enum）
- 默认值常量（G2：DefaultMaxMultiplier=20000 / DefaultEuroTablePayoutMax=500000）

**B5 验收**：
- `go build ./game/pp/internal/games/<gametype>/<tableId>/...` PASS
- `go vet` 无新增 warning
- 单测可后置（DICT/dictionary_test 在 L2 之后）

**下游消费**：所有后续 AIU

---

## L1.2 — DICT

**产物**：`tmp/<tableId>/dict.json`（**非代码，是分析备忘文件**）

**分析输入**：
- 全 5 capture 文件（事件名 / 字段类型全集）
- main.js 补 capture 没出现的偶发事件（canceled / session / decisionError / switch / duplicated_connection 等）

**实现内容**（JSON 结构）：
```jsonc
{
  "gametype_literal": {...},
  "upstream_events": { "betsopen": {...}, ... },  // 每事件含 _capture_evidence 或 _main_js_evidence
  "downstream_actions": [...],
  "betcodes": [...],
  "error_codes": [...],
  "lpbet_format": {...},
  "frame_envelope": {...},
  "_sources": ["..."],
  "_conflicts": [...]   // capture 与 main.js 冲突时列出（capture 为准）
}
```

**B5 验收**：JSON 合法 + jq parse 过 + 关键字段非空

**下游消费**：codex review prompt 数据源 + 经验文档第 4 节

---

## L1.3 — ERRCODE

**产物**：`tmp/<tableId>/error_codes.md`（**非代码，是分析文档**）

**分析输入**：
- `tmp/<tid>/message.jsonl` 实际触发的 betValidationError 帧（通常 2-5 个组合）
- main.js grep 所有 errorCode 字面量（30-50 个全集）
- main.js client switch 分支（rejectBet 清筹码 / sessionTimeout 弹窗 / generic alert / 静默）
- `extendedErrorCode` 触发器（**仅 9018 InvalidToken 触发 SESSION_TIMEOUT** — known-pitfalls I3 dragontiger 教训）

**实现内容**（3 节 markdown）：
1. **errorCode 全集表**：码值 / 名称 / 客户端 switch 分支 / extendedErrorCode 触发关系
2. **客户端展示形式表**：rejectBet / sessionTimeout / generic alert / 静默
3. **后端调用路径建议表**：
   - `parseBets` 失败 → `ErrCodeInvalidBetFormat`
   - 窗口关闭 → `ErrCodeBetNotOnTime`
   - BC 不在白名单 → `ErrCodeUnknownBetCode`
   - 单注超限 → `ErrCodeBetTooLow/TooHigh`
   - 台限超 → `ErrCodeTableLimitExceeded`
   - InvalidToken → `ErrCodeInvalidToken` + `extendedErrorCode="9018"`
   - FreeChip 未实现 → `ErrCodeFreeChipUnknownError`（B11）

**B5 验收**：3 节齐全 + 至少 30 项 errorCode 列出

**下游消费**：DOWNSTREAM_BET / SETTLE / CHECK_BET 调用错误码时参考

---

## AIU prompt 模板（按 L1 通用，每 AIU 各替换）

```
你是 AIU-<NAME>（Layer 1），做 PP 机台 <tableId> (<gametype>) 对接的"分析 + 实现 <产物>"工作单元。

## 工作区
- worktree: <worktree_path>（cd 保持，不切分支）
- 当前分支: <worktree_branch>
- HEAD: <head_sha>（worker-1 起点）
- 主仓库: <repo_root>

## 分析阶段（in-context）

### 输入（按 source 优先级读，**不读全部**）
1. capture（事实最高权威）：
   - <list 本 AIU 需要的具体文件 + 读哪部分>
2. main.js（capture 缺失时补）：
   - 关键 grep：<具体命令>
3. 上游 AIU 产物：L1 无上游
4. 既有 server 骨架参考：
   - <dragontiger / baccarat6 对应文件>

### 分析任务（具体 1-3 个问题）
<本 AIU 特化的任务>

## 实现阶段

### 目标文件
<具体路径>

### 实现要点
<本 AIU 实现内容清单>

### 实现约束
1. 单文件 ≤ 500 行（超就拆，但仍属本 AIU）
2. 注释最少（默认不写，仅 WHY 非显然时一行）
3. 不读 /Users/luca/work/ppgame 老项目
4. 协议铁律遵守（B/C/G/I 节）

### 验收
1. go build PASS
2. go vet 无新增 warning
3. 本 AIU 需要的单测 PASS（若有）
4. policy-pr ≤ 500 行
5. git commit

## 完成回报（B5 契约）
1. commit sha
2. git show --stat HEAD
3. build/vet/test 结果
4. 关键决策（与既有骨架差异 / 与 capture 验证情况）

最后一句："等待主 claude 验收并启动 Layer N+1"
```
