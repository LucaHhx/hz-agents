#!/usr/bin/env bash
# archive_experience.sh — Phase 8: 生成经验文档 13 节骨架
#
# 用法: bash scripts/archive_experience.sh <tableId> [--overwrite|--backup]
#       --backup（默认）— 已存在则备份后重写
#       --overwrite     — 已存在直接覆盖
#
# 退出码: 0 OK / 1 失败

set -euo pipefail

TABLE_ID="${1:-}"
MODE="${2:---backup}"
[[ -z "$TABLE_ID" ]] && { echo "用法: $0 <tableId> [--overwrite|--backup]" >&2; exit 1; }

REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo)}"
[[ -d "$REPO_ROOT/server" ]] || { echo "❌ 不在 pp-game 仓库" >&2; exit 1; }

STATE_JSON="$REPO_ROOT/tmp/$TABLE_ID/state.json"
[[ -f "$STATE_JSON" ]] || { echo "❌ state.json 不存在" >&2; exit 1; }

GAMETYPE=$(jq -r '.lobby.gameType' "$STATE_JSON")
TITLE=$(jq -r '.lobby.title.key // .lobby.title // "未知"' "$STATE_JSON")
WORKTREE=$(jq -r '.worktree_path' "$STATE_JSON")
BRANCH=$(jq -r '.worktree_branch' "$STATE_JSON")
BASE_BRANCH=$(jq -r '.base_branch // "live"' "$STATE_JSON")
COVERAGE=$(jq -r '.coverage // "未知"' "$STATE_JSON")
CODEX_ROUNDS=$(jq -r '.codex_rounds | length' "$STATE_JSON" 2>/dev/null || echo 0)

[[ -d "$WORKTREE" ]] || { echo "❌ worktree 路径不存在: $WORKTREE" >&2; exit 1; }

# 经验文档**写到 worktree 内**（同一 PR 闭环），不是主仓库
EXP_DIR="$WORKTREE/docs/integration-experience/$GAMETYPE"
mkdir -p "$EXP_DIR"
DOC_PATH="$EXP_DIR/$TABLE_ID.md"

if [[ -f "$DOC_PATH" ]]; then
    case "$MODE" in
        --overwrite)
            ;;
        --backup|*)
            cp "$DOC_PATH" "$DOC_PATH.bak.$(date +%s)"
            echo "📦 已备份现有文档"
            ;;
    esac
fi

DATE=$(date +%Y-%m-%d)
COMMIT_LIST=$(cd "$WORKTREE" && git log --oneline "$BASE_BRANCH..HEAD" 2>/dev/null || echo "(运行时填)")

cat > "$DOC_PATH" <<EOF
# $TABLE_ID — $TITLE ($GAMETYPE) 对接经验

**机台**：$TABLE_ID · $TITLE
**对接日期**：$DATE
**实现分支**：$BRANCH（基于 $BASE_BRANCH）
**worktree 路径**：$WORKTREE
**测试覆盖率**：$COVERAGE
**codex review 轮数**：$CODEX_ROUNDS
**状态**：<TODO 总结一句话>

---

## 目录

1. [机台基本信息](#1-机台基本信息)
2. [协议事实速查](#2-协议事实速查)
3. [生命周期 + 事件流](#3-生命周期--事件流)
4. [字典](#4-字典)
5. [协议处理决策表](#5-协议处理决策表)
6. [服务端→客户端帧合成](#6-服务端客户端帧合成)
7. [遇到的问题 + 解决方案](#7-遇到的问题--解决方案)
8. [资金安全清单](#8-资金安全清单)
9. [测试策略](#9-测试策略)
10. [项目级跳过项](#10-项目级跳过项)
11. [与其他机台对比](#11-与其他机台对比)
12. [部署前 checklist](#12-部署前-checklist)
13. [⚠️ 必看注意事项](#13-必看注意事项)

---

## 1. 机台基本信息

<TODO 从 state.lobby 拷入 lobby 元信息：tableId/title/game/gameType/gameLoaderKey/operatorTheme/tableVariant/operatorGameId/limits/dealer 等>

\`\`\`bash
python3 scripts/pp_tables.py --launch $TABLE_ID --curl-file scripts/luca.sh
\`\`\`

## 2. 协议事实速查

<TODO 从 state.agent_outputs.agent_1_dict 抽：协议格式、客户端版本、客户端入口路径、lpbet gm 实际值、ping 格式、subscribe channel、是否一帧多事件>

## 3. 生命周期 + 事件流

<TODO 从 state.agent_outputs.agent_5_lifecycle 拷入>

## 4. 字典

<TODO 从 state.agent_outputs.agent_1_dict 拷入。强制由 dictionary_test.go 守住>

## 5. 协议处理决策表

<TODO 从 design.md 第 2 节拷入>

## 6. 服务端→客户端帧合成

<TODO 从 design.md 第 3 节拷入>

## 7. 遇到的问题 + 解决方案

<TODO Phase 6 codex 闭环时实时累积的修复记录。详见 references/codex-review-loop.md 格式>

## 8. 资金安全清单

<TODO 对照 references/known-pitfalls.md C 节每项打勾确认>

## 9. 测试策略

<TODO 列测试文件 + 用例数 + 字典 parity 测试说明>

## 10. 项目级跳过项

<TODO 引用 references/project-level-skips.md 5 项 + 本次命中哪些>

## 11. 与其他机台对比

<TODO 表格对比同 gametype 已对接机台 vs 本机台>

## 12. 部署前 checklist

<TODO b_tables SQL + 启动顺序 + 验证清单>

\`\`\`sql
INSERT INTO b_tables (...);
\`\`\`

## 13. ⚠️ 必看注意事项

<TODO 把对接过程反复踩到 + 下次容易再踩的坑提炼成铁律 A-N>

---

## 附录 A：commit 链（$BASE_BRANCH..HEAD）

\`\`\`
$COMMIT_LIST
\`\`\`

## 附录 B：codex 反复审查 $CODEX_ROUNDS 轮汇总

| 轮 | label | exit | findings | stuck |
|---|---|---|---|---|
$(jq -r '.codex_rounds // [] | to_entries | .[] | "| \(.key+1) | \(.value.label) | \(.value.exit_code) | \(.value.findings) | \(.value.stuck) |"' "$STATE_JSON" 2>/dev/null)

---

**对接者**：Claude
**完成时间**：$DATE
**下次对接同 gametype 机台时**：先读本文件第 13 节注意事项。
EOF

# 写 state（**不**写 done — 由主 Claude 填充 13 节后再标 done）
TMP=$(mktemp)
jq --arg p "$DOC_PATH" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   '. + {phase: 8, status: "skeleton-generated", experience_doc_path: $p, last_updated: $ts}' \
   "$STATE_JSON" > "$TMP" && mv "$TMP" "$STATE_JSON"

cat <<EOF
✅ 经验文档骨架生成
📄 $DOC_PATH

下一步：主 Claude 按 references/experience-doc-structure.md 填充 13 节，
       完成后改 state.status = "done"，commit 到 worktree。
EOF
