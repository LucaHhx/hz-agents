#!/usr/bin/env bash
# verify.sh — Phase 7: 全量验收
#
# 用法: bash scripts/verify.sh <worktree_path> <gametype> <tableId> <base_branch>
#
# 退出码: 0 全 PASS / 1 任一失败

set -uo pipefail   # 注意：不用 -e（避免 ((PASS+=1)) 触发提前退出）

WT="${1:-}"
GT="${2:-}"
TID="${3:-}"
BASE="${4:-live}"

[[ -z "$WT" || -z "$GT" || -z "$TID" ]] && {
    echo "用法: $0 <worktree_path> <gametype> <tableId> <base_branch>" >&2
    exit 1
}

[[ -d "$WT/server" ]] || { echo "❌ $WT 不是 worktree 根" >&2; exit 1; }

PKG_DIR="$WT/server/game/pp/internal/games/$GT/$TID"
[[ -d "$PKG_DIR" ]] || { echo "❌ 包目录不存在: $PKG_DIR" >&2; exit 1; }

# 自动定位主仓库（worktree 通常在 .worktrees/<branch>）
REPO_ROOT="${REPO_ROOT:-$(echo "$WT" | sed -E 's|/\.worktrees/[^/]+$||')}"
[[ -d "$REPO_ROOT/server" ]] || REPO_ROOT="$WT"  # fallback
STATE_JSON="$REPO_ROOT/tmp/$TID/state.json"

cd "$WT/server"

PASS=0
FAIL=0
declare -a FAIL_DETAILS

echo "🔬 [Phase 7] 全量验收 ($GT/$TID, base=$BASE)"

# 1. build
echo -n "1. go build ./...           "
if go build ./... 2>&1 | head; then
    echo "✅"
    PASS=$((PASS + 1))
else
    echo "❌"
    FAIL=$((FAIL + 1))
    FAIL_DETAILS+=("build")
fi

# 2. vet
echo -n "2. go vet $GT 包            "
VET_OUT=$(go vet "./game/pp/internal/games/$GT/..." 2>&1 || true)
if [[ -z "$VET_OUT" ]]; then
    echo "✅"
    PASS=$((PASS + 1))
else
    echo "⚠️"
    echo "$VET_OUT" | head -5 | sed 's/^/    /'
    FAIL=$((FAIL + 1))
    FAIL_DETAILS+=("vet warning")
fi

# 3. test -race -count=3
echo -n "3. test -race -count=3      "
if go test -race -count=3 "./game/pp/internal/games/$GT/$TID/..." 2>&1 | tail -2; then
    echo "✅"
    PASS=$((PASS + 1))
else
    echo "❌"
    FAIL=$((FAIL + 1))
    FAIL_DETAILS+=("test race")
fi

# 4. cover ≥ 25%
echo -n "4. coverage ≥ 25%           "
COVER=$(go test -cover "./game/pp/internal/games/$GT/$TID/..." 2>&1 | tail -1 | grep -oE '[0-9.]+%' | head -1 | tr -d '%' || echo 0)
if (( $(echo "${COVER:-0} >= 25" | bc -l 2>/dev/null || echo 0) )); then
    echo "✅ ($COVER%)"
    PASS=$((PASS + 1))
else
    echo "❌ ($COVER% < 25%)"
    FAIL=$((FAIL + 1))
    FAIL_DETAILS+=("cover $COVER%")
fi

# 5. policy-pr
echo -n "5. policy-pr                "
cd "$WT"
if [[ -f "$REPO_ROOT/scripts/ci/policy-pr.mjs" ]]; then
    POLICY_OUT=$(git diff --name-only --diff-filter=ACMR "$BASE..HEAD" 2>/dev/null | node "$REPO_ROOT/scripts/ci/policy-pr.mjs" --stdin 2>&1 || true)
    if echo "$POLICY_OUT" | grep -q "all within limits"; then
        echo "✅"
        PASS=$((PASS + 1))
    else
        echo "❌"
        echo "$POLICY_OUT" | tail -5 | sed 's/^/    /'
        FAIL=$((FAIL + 1))
        FAIL_DETAILS+=("policy-pr")
    fi
else
    echo "⚠️ skip (policy-pr.mjs 不存在)"
fi

echo
echo "=== $PASS pass / $FAIL fail ==="

# 写 state
if [[ -f "$STATE_JSON" ]]; then
    TMP=$(mktemp)
    jq --argjson pass $PASS --argjson fail $FAIL --arg cov "${COVER}%" \
       --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '. + {phase: 7, status: (if $fail == 0 then "done" else "failed" end), verify_pass: $pass, verify_fail: $fail, coverage: $cov, last_updated: $ts}' \
       "$STATE_JSON" > "$TMP" && mv "$TMP" "$STATE_JSON"
fi

if (( FAIL > 0 )); then
    echo "❌ 失败详情：${FAIL_DETAILS[*]}"
    exit 1
fi

echo "✅ Phase 7 全部 PASS — 进 Phase 8 经验文档归档"
