#!/usr/bin/env bash
# fetch_capture.sh — Phase 2: 录 PP 客户端 capture（包装 fetch_client.mjs）
#
# 用法: bash scripts/fetch_capture.sh <tableId>
#
# 注意: fetch_client.mjs 内 DURATION_MS 是 const（5min），不可通过环境变量覆盖。
#       缺关键事件时如需更长 capture，需手动改 fetch_client.mjs:38 然后重跑本脚本。
#
# 退出码: 0 OK / 1 失败 / 2 capture 不完整（帧数不足或缺关键事件）

set -euo pipefail

TABLE_ID="${1:-}"
[[ -z "$TABLE_ID" ]] && { echo "用法: $0 <tableId>" >&2; exit 1; }

REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo)}"
[[ -d "$REPO_ROOT/server" && -f "$REPO_ROOT/scripts/game_dev/fetch_client.mjs" ]] || {
    echo "❌ 不在 pp-game 仓库" >&2
    exit 1
}

OUT_DIR="$REPO_ROOT/tmp/$TABLE_ID"
STATE_JSON="$OUT_DIR/state.json"
[[ -f "$STATE_JSON" ]] || { echo "❌ state.json 不存在 — 先跑 Phase 1" >&2; exit 1; }
jq -e '.phase >= 1' "$STATE_JSON" >/dev/null || { echo "❌ state.phase < 1" >&2; exit 1; }

# Playwright 检查
node -e "import('playwright')" 2>/dev/null || {
    echo "❌ Playwright 未装：npm install -g playwright && npx playwright install chromium" >&2
    exit 1
}

echo "🎬 [Phase 2] 录 capture（5 min；fetch_client.mjs 写死 const）..."

node "$REPO_ROOT/scripts/game_dev/fetch_client.mjs" "$TABLE_ID" --output "$REPO_ROOT/tmp" 2>&1 || {
    echo "🔄 retry 1 次..."
    node "$REPO_ROOT/scripts/game_dev/fetch_client.mjs" "$TABLE_ID" --output "$REPO_ROOT/tmp" 2>&1 || {
        echo "❌ fetch_client.mjs retry 后仍失败" >&2
        exit 1
    }
}

# 验证产物
CLIENT_DIR="$OUT_DIR/clientResources"
MESSAGE_JSON="$OUT_DIR/message.json"

[[ -d "$CLIENT_DIR" ]] || { echo "❌ clientResources/ 不存在" >&2; exit 1; }
[[ -f "$MESSAGE_JSON" ]] || { echo "❌ message.json 不存在" >&2; exit 1; }

# 选最新版本 main.js（按 apps/<gametype>/<version>/ 字典序末位）
MAIN_JS=$(find "$CLIENT_DIR/apps" -name "main.js" -type f 2>/dev/null | sort | tail -1)
[[ -n "$MAIN_JS" ]] || { echo "❌ 未找到 main.js" >&2; exit 1; }

FRAME_COUNT=$(jq 'length' "$MESSAGE_JSON" 2>/dev/null || echo 0)
echo "📊 帧数：$FRAME_COUNT"

# 帧数 < 200 硬卡
if (( FRAME_COUNT < 200 )); then
    echo "❌ 帧数 $FRAME_COUNT < 200，capture 不完整" >&2
    echo "   建议手动改 fetch_client.mjs:38 把 DURATION_MS 改 10min 后重跑本脚本" >&2

    # 写 state degraded 状态
    TMP=$(mktemp)
    jq --argjson fc "$FRAME_COUNT" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '. + {phase: 2, status: "degraded", frame_count: $fc, last_updated: $ts}' \
       "$STATE_JSON" > "$TMP" && mv "$TMP" "$STATE_JSON"
    exit 2
fi

# 关键事件检查
KEY_EVENTS=("betsopen" "betsclosed" "gameresult" "winners")
MISSING=()
for evt in "${KEY_EVENTS[@]}"; do
    jq -r '.[].payload' "$MESSAGE_JSON" | grep -q "\"$evt\":" || MISSING+=("$evt")
done

if (( ${#MISSING[@]} > 0 )); then
    echo "⚠️  缺关键事件：${MISSING[*]}" >&2
    echo "   Phase 3 agent-5 反推可能能补；如反推失败，建议改 fetch_client.mjs DURATION_MS=10*60*1000 重跑本脚本" >&2
    # 不硬 exit — agent-5 main.js 反推可能找到偶发事件
fi

# 写 state.json
TMP=$(mktemp)
jq --arg main "$MAIN_JS" --arg msg "$MESSAGE_JSON" --argjson fc "$FRAME_COUNT" \
   --argjson missing "$(printf '%s\n' "${MISSING[@]}" | jq -R . | jq -s .)" \
   --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   '. + {phase: 2, status: "done", main_js: $main, message_json: $msg, frame_count: $fc, missing_events: $missing, last_updated: $ts}' \
   "$STATE_JSON" > "$TMP" && mv "$TMP" "$STATE_JSON"

cat <<EOF
✅ Phase 2 pass
  main.js     = $MAIN_JS
  message.json = $MESSAGE_JSON
  frame count = $FRAME_COUNT
  missing events = ${MISSING[*]:-<none>}

下一步：Phase 3 启动 5 个 parallel agent（见 references/parallel-team.md）
EOF
