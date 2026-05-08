#!/usr/bin/env bash
# codex_review_loop.sh — Phase 6: 单轮 codex review（AI 包装器，**非确定性**）
#
# 用法: bash scripts/codex_review_loop.sh <worktree_path> <round_label> <base_branch>
#
# 退出码:
#   0 — codex 报"无重大问题"
#   1 — 有 findings → 主 claude 解析 + 修
#   2 — codex 卡死

set -euo pipefail

WT="${1:-}"
LABEL="${2:-round-1}"
BASE_BRANCH="${3:-live}"

[[ -z "$WT" || ! -d "$WT" ]] && {
    echo "用法: $0 <worktree_path> <round_label> <base_branch>" >&2
    exit 1
}

CODEX_REVIEW_SKILL="${CODEX_REVIEW_SKILL:-/Users/luca/.claude/skills/codex-review}"
[[ -x "$CODEX_REVIEW_SKILL/scripts/codex_review.sh" ]] || {
    echo "❌ codex-review skill 不存在: $CODEX_REVIEW_SKILL/scripts/codex_review.sh" >&2
    exit 1
}

# 选 prompt 视角
case "$LABEL" in
    *correctness*|round-1)
        VIEW="正确性视角：聚焦逻辑正确性、边界条件、并发、数据一致性、错误处理。"
        ;;
    *traps*|round-2)
        VIEW="陷阱与安全视角：聚焦 PP 协议特有陷阱、并发竞态、资金流安全。"
        ;;
    *maintainability*|round-3)
        VIEW="可维护性视角：命名、分层、复杂度、重复代码、可测试性、文档、规范契合度。"
        ;;
    *confirm*|*final*)
        VIEW="只看新引入 bug 或漏修。明确忽略项目级架构问题。无问题就回'无重大问题'。"
        ;;
    *)
        VIEW="综合 — 协议正确性 + 资金安全 + 跨 commit 一致性。"
        ;;
esac

PROMPT_FILE=$(mktemp)
cat > "$PROMPT_FILE" <<EOF
你是一名严格的代码审查者，**只审查、不修改任何文件**。仅输出审查结论，禁止生成补丁、禁止运行写入命令。

请按以下严重度分类输出：
- 🔴 must-fix（正确性 / 安全 / 数据丢失 / 接口契约破坏）
- 🟡 should-fix（可读性差 / 易踩坑 / 潜在性能问题 / 代码规范明显违反）
- 🟢 nice-to-have（命名、注释、风格、小重构建议）
每条结论格式：\`<文件>:<行号> — 描述 — 修复建议\`。
若无问题请直接说「无重大问题」。

【视角】$VIEW

【审查目标】当前 worktree 相对 ${BASE_BRANCH} 分支的全部改动（git diff ${BASE_BRANCH}...HEAD）。这是 PP 机台对接代码。
EOF

OUTPUT_DIR="$WT/codex-output"
mkdir -p "$OUTPUT_DIR"
LABEL_SAFE=$(echo "$LABEL" | tr -c 'a-zA-Z0-9-' '-')
OUTPUT_FILE="$OUTPUT_DIR/$LABEL_SAFE.md"

echo "🤖 codex review: $LABEL (base=$BASE_BRANCH)"

START_TS=$(date +%s)
TMP_OUT=$(mktemp)

(
    cat "$PROMPT_FILE" | bash "$CODEX_REVIEW_SKILL/scripts/codex_review.sh" \
        -d "$WT" -l "$LABEL_SAFE" 2>&1
) > "$TMP_OUT" &
CODEX_PID=$!

TIMEOUT=720  # 12 min
LAST_SIZE=0
LAST_CHANGE=$(date +%s)
STUCK=0

while kill -0 "$CODEX_PID" 2>/dev/null; do
    sleep 5
    NOW=$(date +%s)
    if (( NOW - START_TS > TIMEOUT )); then
        echo "⚠️  codex 总时长超 12min，kill"
        kill "$CODEX_PID" 2>/dev/null || true
        STUCK=1
        break
    fi
    SIZE=$(wc -c < "$TMP_OUT" 2>/dev/null || echo 0)
    if (( SIZE != LAST_SIZE )); then
        LAST_SIZE=$SIZE
        LAST_CHANGE=$NOW
    elif (( NOW - LAST_CHANGE > 300 )); then
        echo "⚠️  codex 5min 无输出，判定卡死"
        kill "$CODEX_PID" 2>/dev/null || true
        STUCK=1
        break
    fi
done

wait "$CODEX_PID" 2>/dev/null || true
mv "$TMP_OUT" "$OUTPUT_FILE"
rm -f "$PROMPT_FILE"

# 自动更新 state.json（以 worktree 路径推回主仓库 tmp）
REPO_ROOT="${REPO_ROOT:-$(echo "$WT" | sed -E 's|/\.worktrees/[^/]+$||')}"
TABLE_ID=$(basename "$WT" | grep -oE '[a-z0-9]{8,32}$' || echo)
STATE_JSON=""
if [[ -n "$TABLE_ID" && -d "$REPO_ROOT/tmp/$TABLE_ID" ]]; then
    STATE_JSON="$REPO_ROOT/tmp/$TABLE_ID/state.json"
fi

update_state() {
    local exit_code=$1
    local findings=$2
    [[ -f "$STATE_JSON" ]] || return 0
    TMP=$(mktemp)
    jq --arg label "$LABEL_SAFE" --argjson exit_code $exit_code --argjson findings $findings \
       --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       --argjson stuck $STUCK \
       '.codex_rounds = (.codex_rounds // []) + [{
           label: $label, exit_code: $exit_code, findings: $findings, ts: $ts, stuck: ($stuck > 0)
       }]
        | .codex_stuck_count = (.codex_stuck_count // 0) + $stuck
        | .last_updated = $ts' \
       "$STATE_JSON" > "$TMP" && mv "$TMP" "$STATE_JSON"
}

if (( STUCK == 1 )); then
    update_state 2 0
    echo "❌ codex 卡死  (累计 $(jq -r '.codex_stuck_count // 0' "$STATE_JSON" 2>/dev/null || echo "?") 次)"
    exit 2
fi

if grep -q "无重大问题" "$OUTPUT_FILE" 2>/dev/null; then
    update_state 0 0
    echo "✅ codex clean"
    exit 0
fi

# 计 findings — 按行内 emoji 出现次数（不要求行首）
FOUND=$(grep -cE '🔴|🟡|🟢' "$OUTPUT_FILE" 2>/dev/null || echo 0)
update_state 1 $FOUND

echo "📊 findings 总数：$FOUND"
echo "📄 完整输出：$OUTPUT_FILE"
echo "下一步：主 claude 解析 → 按 references/codex-review-loop.md 决策每条 finding"
exit 1
