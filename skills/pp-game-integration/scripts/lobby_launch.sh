#!/usr/bin/env bash
# lobby_launch.sh — Phase 1: lobby 元信息 + 余额硬卡 + factory 已注册检测
#
# 用法: bash scripts/lobby_launch.sh <tableId>
#
# 退出码:
#   0  — pass，可进 Phase 2
#   1  — minBalanceToPlay > 6000 / launch 失败 / lobby JSON 损坏
#   2  — factory 已注册同 tableId

set -euo pipefail

TABLE_ID="${1:-}"
[[ -z "$TABLE_ID" ]] && { echo "用法: $0 <tableId>" >&2; exit 1; }

[[ "$TABLE_ID" =~ ^[a-z0-9]{8,32}$ ]] || {
    echo "❌ tableId 格式异常（应 8-32 字符小写字母+数字）：$TABLE_ID" >&2
    exit 1
}

# 自动定位 pp-game 仓库根（从当前 cwd 向上找 server/scripts/pp_tables.py）
find_repo_root() {
    local d
    d=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
    [[ -d "$d/server" && -f "$d/scripts/pp_tables.py" ]] && { echo "$d"; return 0; }
    return 1
}
REPO_ROOT="${REPO_ROOT:-$(find_repo_root || echo "")}"
[[ -d "$REPO_ROOT/server" && -f "$REPO_ROOT/scripts/pp_tables.py" ]] || {
    echo "❌ 不在 pp-game 仓库内（cwd=$PWD）；请先 cd 到仓库根，或设 REPO_ROOT" >&2
    exit 1
}

CURL_FILE="$REPO_ROOT/scripts/luca.sh"
[[ -f "$CURL_FILE" ]] || { echo "❌ 缺 $CURL_FILE（bc.game 认证）" >&2; exit 1; }

OUT_DIR="$REPO_ROOT/tmp/$TABLE_ID"
mkdir -p "$OUT_DIR"
LOBBY_JSON="$OUT_DIR/lobby.json"
STATE_JSON="$OUT_DIR/state.json"

echo "🔍 [Phase 1] lobby launch + 余额检查 + factory 检测  ($TABLE_ID)"
echo "    repo: $REPO_ROOT"

# === factory 检测（早于 launch）===
FACTORY_FILE="$REPO_ROOT/server/game/pp/internal/factory/instance_factory.go"
if [[ -f "$FACTORY_FILE" ]] && grep -q "\"$TABLE_ID\"" "$FACTORY_FILE"; then
    echo "⚠️  factory 已注册 tableId：$TABLE_ID"
    echo "    位置：$FACTORY_FILE"
    echo "    用户决定：1) 重新对接 2) 查询经验 3) 退出"
    exit 2
fi

# === pp_tables.py launch 拿 lobby ===
echo "📡 调 pp_tables.py --launch ..."
LAUNCH_OUT=$(cd "$REPO_ROOT" && python3 scripts/pp_tables.py --launch "$TABLE_ID" --curl-file "$CURL_FILE" 2>&1) || {
    echo "🔄 retry 1 次..."
    LAUNCH_OUT=$(cd "$REPO_ROOT" && python3 scripts/pp_tables.py --launch "$TABLE_ID" --curl-file "$CURL_FILE" 2>&1) || {
        echo "❌ pp_tables.py 退出非 0（retry 后仍失败）：" >&2
        echo "$LAUNCH_OUT" | tail -10 >&2
        exit 1
    }
}

# === 拉完整 lobby 条目 ===
python3 - <<PY > "$LOBBY_JSON"
import sys, json
sys.path.insert(0, "$REPO_ROOT/scripts")
import pp_tables
curl = pp_tables.parse_curl_file("$CURL_FILE")
lobby_url = pp_tables.bc_launch_from_curl(curl)
jsid = pp_tables.get_pp_session(lobby_url)
tables = pp_tables.pp_fetch_tables(jsid)
target = next((t for t in tables if t.get('id') == "$TABLE_ID" or t.get('tableId') == "$TABLE_ID"), None)
if not target:
    sys.exit(1)
print(json.dumps(target, indent=2, ensure_ascii=False))
PY

[[ -s "$LOBBY_JSON" ]] || { echo "❌ lobby JSON 拉取失败或机台不在大厅" >&2; rm -f "$LOBBY_JSON"; exit 1; }

# === 解析关键字段 ===
GAME_TYPE=$(jq -r '.gameType // empty' "$LOBBY_JSON")
GAME_LOADER_KEY=$(jq -r '.gameLoaderKey // empty' "$LOBBY_JSON")
OPERATOR_THEME=$(jq -r '.operatorTheme // empty' "$LOBBY_JSON")
OPERATOR_GAME_ID=$(jq -r '.operatorGameId // empty' "$LOBBY_JSON")
TITLE=$(jq -r '.title.key // .title // empty' "$LOBBY_JSON")
LIMIT_MIN=$(jq -r '.limits.min // empty' "$LOBBY_JSON")
LIMIT_MAX=$(jq -r '.limits.max // empty' "$LOBBY_JSON")
MIN_BALANCE=$(jq -r '.limits.minBalanceToPlay // 0' "$LOBBY_JSON")

[[ -n "$GAME_TYPE" && -n "$OPERATOR_GAME_ID" ]] || {
    echo "❌ lobby 缺关键字段（gameType=$GAME_TYPE / operatorGameId=$OPERATOR_GAME_ID）" >&2
    exit 1
}

# === 6000 硬卡 ===
if (( $(printf '%.0f' "$MIN_BALANCE" 2>/dev/null || echo 0) > 6000 )); then
    echo "❌ minBalanceToPlay = $MIN_BALANCE > 6000，**不做对接**（用户硬规则）" >&2
    exit 1
fi

# === 写 state.json（merge 已有字段，避免覆盖 base_branch 等）===
EXISTING="{}"
[[ -f "$STATE_JSON" ]] && EXISTING=$(cat "$STATE_JSON")
echo "$EXISTING" | jq --argjson lobby "$(cat "$LOBBY_JSON")" \
    --arg tableId "$TABLE_ID" \
    --arg repo_root "$REPO_ROOT" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '. + {tableId: $tableId, repo_root: $repo_root, phase: 1, status: "done", lobby: $lobby, capture_dir: "tmp/\($tableId)", last_updated: $ts}' \
    > "$STATE_JSON.tmp" && mv "$STATE_JSON.tmp" "$STATE_JSON"

# === 报告 ===
cat <<EOF
✅ Phase 1 pass

  tableId         = $TABLE_ID
  title           = $TITLE
  gameType        = $GAME_TYPE
  gameLoaderKey   = $GAME_LOADER_KEY
  operatorTheme   = $OPERATOR_THEME
  operatorGameId  = $OPERATOR_GAME_ID
  limits.min      = $LIMIT_MIN
  limits.max      = $LIMIT_MAX
  minBalanceToPlay= $MIN_BALANCE  (≤ 6000 ✓)

📄 lobby.json：$LOBBY_JSON
📄 state.json：$STATE_JSON

下一步：bash \$SKILL_DIR/scripts/fetch_capture.sh $TABLE_ID
EOF
