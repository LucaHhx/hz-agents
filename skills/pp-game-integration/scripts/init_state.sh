#!/usr/bin/env bash
# init_state.sh — Phase 0: 自动选 base 分支并初始化 state.json
#
# 自动选择优先级（铁律 1：完全无人值守，不再问用户）：
#   1. 已有 state.base_branch（恢复点）
#   2. 环境变量 $PP_BASE_BRANCH
#   3. 当前 git branch（仅当在白名单 live/live-dev/dev/pre 中）
#   4. 白名单回退顺序：live → live-dev → dev → pre
#   5. 都不存在 → fail-closed，写 state.status=failed
#
# 用法: bash scripts/init_state.sh <tableId> [<override_base_branch>]
#   override_base_branch 可选；传了就跳过自动选择，但仍校验该分支真实存在
#
# 退出码: 0 OK / 1 失败 / 2 fail-closed（无任何可用 base）

set -euo pipefail

TABLE_ID="${1:-}"
OVERRIDE_BASE="${2:-}"

[[ -z "$TABLE_ID" ]] && {
    echo "用法: $0 <tableId> [<override_base_branch>]" >&2
    exit 1
}

REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo)}"
[[ -d "$REPO_ROOT/server" ]] || { echo "❌ 不在 pp-game 仓库" >&2; exit 1; }

OUT_DIR="$REPO_ROOT/tmp/$TABLE_ID"
mkdir -p "$OUT_DIR"
STATE_JSON="$OUT_DIR/state.json"

# 工具：检查分支是否真实存在（本地或远程）
branch_exists() {
    local b="$1"
    git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$b" \
        || git -C "$REPO_ROOT" show-ref --verify --quiet "refs/remotes/origin/$b"
}

# 自动选 base_branch
WHITELIST=(live live-dev dev pre)
SELECTION_REASON=""
BASE_BRANCH=""

if [[ -n "$OVERRIDE_BASE" ]]; then
    BASE_BRANCH="$OVERRIDE_BASE"
    SELECTION_REASON="override-arg"
elif [[ -f "$STATE_JSON" ]] && jq -e '.base_branch' "$STATE_JSON" >/dev/null 2>&1; then
    BASE_BRANCH=$(jq -r '.base_branch' "$STATE_JSON")
    SELECTION_REASON="resume-from-state"
elif [[ -n "${PP_BASE_BRANCH:-}" ]]; then
    BASE_BRANCH="$PP_BASE_BRANCH"
    SELECTION_REASON="env-PP_BASE_BRANCH"
else
    CURRENT=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    for b in "${WHITELIST[@]}"; do
        if [[ "$CURRENT" == "$b" ]]; then
            BASE_BRANCH="$CURRENT"
            SELECTION_REASON="current-branch-whitelisted"
            break
        fi
    done
    if [[ -z "$BASE_BRANCH" ]]; then
        for b in "${WHITELIST[@]}"; do
            if branch_exists "$b"; then
                BASE_BRANCH="$b"
                SELECTION_REASON="whitelist-fallback"
                break
            fi
        done
    fi
fi

# 校验
if [[ -z "$BASE_BRANCH" ]] || ! branch_exists "$BASE_BRANCH"; then
    TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    EXISTING="{}"
    [[ -f "$STATE_JSON" ]] && EXISTING=$(cat "$STATE_JSON")
    echo "$EXISTING" | jq \
        --arg tableId "$TABLE_ID" \
        --arg repo_root "$REPO_ROOT" \
        --arg ts "$TS" \
        '. + {tableId: $tableId, repo_root: $repo_root, phase: 0, status: "failed", failure_reason: "no-usable-base-branch", last_updated: $ts}' \
        > "$STATE_JSON.tmp" && mv "$STATE_JSON.tmp" "$STATE_JSON"
    echo "❌ fail-closed：找不到任何可用 base 分支（白名单：${WHITELIST[*]}）" >&2
    git -C "$REPO_ROOT" branch --list >&2
    exit 2
fi

mkdir -p "$REPO_ROOT/docs/integration-experience"

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EXISTING="{}"
[[ -f "$STATE_JSON" ]] && EXISTING=$(cat "$STATE_JSON")

# 初始化字段（含 codex 协作扩展）
echo "$EXISTING" | jq \
    --arg tableId "$TABLE_ID" \
    --arg repo_root "$REPO_ROOT" \
    --arg base "$BASE_BRANCH" \
    --arg reason "$SELECTION_REASON" \
    --arg ts "$TS" \
    '. + {
        tableId: $tableId,
        repo_root: $repo_root,
        base_branch: $base,
        base_branch_selection: {reason: $reason, picked_at: $ts},
        phase: 0,
        status: "done",
        last_updated: $ts
    }
    | .codex_decisions   //= []
    | .codex_discussions //= []
    | .codex_budget_guard //= {decision_calls: 0, discussion_rounds: 0, max_discussion_rounds_per_trigger: 3}
    | .unresolved        //= []
    | .already_registered //= false' \
    > "$STATE_JSON.tmp" && mv "$STATE_JSON.tmp" "$STATE_JSON"

cat <<EOF
✅ Phase 0 done
  tableId       = $TABLE_ID
  base_branch   = $BASE_BRANCH
  selection     = $SELECTION_REASON
  state.json    = $STATE_JSON
  字段已初始化  = codex_decisions[] / codex_discussions[] / codex_budget_guard / unresolved[] / already_registered

下一步：bash \$SKILL_DIR/scripts/lobby_launch.sh $TABLE_ID
EOF
