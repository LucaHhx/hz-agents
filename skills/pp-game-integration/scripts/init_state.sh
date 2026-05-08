#!/usr/bin/env bash
# init_state.sh — Phase 0: 用户选定 base 分支后初始化 state.json
#
# 用法: bash scripts/init_state.sh <tableId> <base_branch>
#
# 退出码: 0 OK / 1 失败

set -euo pipefail

TABLE_ID="${1:-}"
BASE_BRANCH="${2:-}"

[[ -z "$TABLE_ID" || -z "$BASE_BRANCH" ]] && {
    echo "用法: $0 <tableId> <base_branch>" >&2
    exit 1
}

REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo)}"
[[ -d "$REPO_ROOT/server" ]] || { echo "❌ 不在 pp-game 仓库" >&2; exit 1; }

# 校验 base_branch 真实存在（本地或远程）
if ! git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$BASE_BRANCH" \
   && ! git -C "$REPO_ROOT" show-ref --verify --quiet "refs/remotes/origin/$BASE_BRANCH"; then
    echo "❌ base_branch 不存在：$BASE_BRANCH" >&2
    git -C "$REPO_ROOT" branch --list >&2
    exit 1
fi

OUT_DIR="$REPO_ROOT/tmp/$TABLE_ID"
mkdir -p "$OUT_DIR"

# 同时确保 docs/integration-experience/ 目录存在（Phase 4/6 决策原则会查）
mkdir -p "$REPO_ROOT/docs/integration-experience"

STATE_JSON="$OUT_DIR/state.json"
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# 创建 / 更新 state.json
EXISTING="{}"
[[ -f "$STATE_JSON" ]] && EXISTING=$(cat "$STATE_JSON")
echo "$EXISTING" | jq \
    --arg tableId "$TABLE_ID" \
    --arg repo_root "$REPO_ROOT" \
    --arg base "$BASE_BRANCH" \
    --arg ts "$TS" \
    '. + {tableId: $tableId, repo_root: $repo_root, base_branch: $base, phase: 0, status: "done", last_updated: $ts}' \
    > "$STATE_JSON.tmp" && mv "$STATE_JSON.tmp" "$STATE_JSON"

cat <<EOF
✅ Phase 0 done
  tableId      = $TABLE_ID
  base_branch  = $BASE_BRANCH
  state.json   = $STATE_JSON

下一步：bash \$SKILL_DIR/scripts/lobby_launch.sh $TABLE_ID
EOF
