#!/usr/bin/env bash
# grep_client_dict.sh — Phase 3 agent-1 内部用：从 main.js 提取协议字典
#
# 用法: bash scripts/grep_client_dict.sh <capture_dir>
#       capture_dir 是 Phase 2 输出目录（含 state.json + main.js + message.json）
#
# 退出码: 0 OK / 1 失败

set -euo pipefail

CAP_DIR="${1:-}"
[[ -z "$CAP_DIR" ]] && { echo "用法: $0 <capture_dir>" >&2; exit 1; }
[[ -d "$CAP_DIR" ]] || { echo "❌ 目录不存在: $CAP_DIR" >&2; exit 1; }

STATE_JSON="$CAP_DIR/state.json"
[[ -f "$STATE_JSON" ]] || { echo "❌ state.json 不存在" >&2; exit 1; }
jq -e '.phase >= 2' "$STATE_JSON" >/dev/null || { echo "❌ state.phase < 2" >&2; exit 1; }

MAIN_JS=$(jq -r '.main_js' "$STATE_JSON")
MESSAGE_JSON=$(jq -r '.message_json' "$STATE_JSON")
TABLE_ID=$(jq -r '.tableId' "$STATE_JSON")
LOBBY_GAME_TYPE=$(jq -r '.lobby.gameType' "$STATE_JSON")
DICT_JSON="$CAP_DIR/dict.json"

[[ -f "$MAIN_JS" ]] || { echo "❌ main.js 不存在" >&2; exit 1; }
[[ -f "$MESSAGE_JSON" ]] || { echo "❌ message.json 不存在" >&2; exit 1; }

echo "🔬 字典提取 ($LOBBY_GAME_TYPE)" >&2

python3 - "$MAIN_JS" "$MESSAGE_JSON" "$LOBBY_GAME_TYPE" > "$DICT_JSON" <<'PY'
import re, json, sys
main_js, msg_json, gametype = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(main_js).read()

out = {
    "gameType": gametype,
    "main_js": main_js,
    "lpbet_format": {},
    "ping_format": "",
    "upstream_events": [],
    "betcodes": {},
    "gr_field_to_betcode": {},
    "error_codes": {},
    "init_sequence": [],
    "issues": [],
}

# 上游事件枚举（main.js 字典 r）
m = re.search(r'\{Bet:"bet",BetValidationError:"betValidationError"[^}]+\}', src)
if m:
    pairs = re.findall(r'([A-Za-z]+):"([a-zA-Z_]+)"', m.group(0))
    out["upstream_events"] = sorted({v for _, v in pairs})

# lpbet 格式（gm 拼接）
gm_literal = sorted(set(re.findall(r'gm="([a-zA-Z]+_(?:desktop|mobile))"', src)))[:5]
gm_dynamic = bool(re.search(r'gm="\'\.concat\([_a-zA-Z][^,]+,"_"\)\.concat\([^)]+\?"desktop":"mobile"', src))
out["lpbet_format"]["gm_pattern"] = "${gameType}_${desktop|mobile}" if gm_dynamic else None
out["lpbet_format"]["gm_resolved"] = f"{gametype}_desktop"
out["lpbet_format"]["gm_literals_in_main_js"] = gm_literal

# ping 格式
ping_m = re.search(r'<ping[^"]+', src)
out["ping_format"] = ping_m.group(0)[:80] if ping_m else ""

# betCode 数值表（Pp 字典）
m = re.search(r'let Pp=function\(e\)\{return\s+(.*?)return\s+e\}\(\{\}\)', src, re.DOTALL)
if m:
    for k, v in re.findall(r'e\.([A-Za-z0-9_]+)\s*=\s*(\d+)', m.group(1)):
        out["betcodes"][int(v)] = k

# GR 字段 → betCode 反查表（Up）
m = re.search(r'Up=\{([^}]+)\}', src)
if m:
    for f, bc in re.findall(r'([a-z][a-z0-9]*)\s*:\s*(\d+)', m.group(1)):
        out["gr_field_to_betcode"][f] = int(bc)

# 错误码表（qe.a 或类似）
idx = src.find('BetCodeError=1028')
if idx > 0:
    s = src.rfind('function(e){return ', 0, idx)
    if s > 0:
        chunk = src[s:s+12000]
        ret = re.search(r'function\(e\)\{return\s+(.*?return\s+e)\}', chunk, re.DOTALL)
        if ret:
            for k, v in re.findall(r'e\.([A-Za-z0-9_]+)\s*=\s*([0-9eE+]+)', ret.group(1)):
                try:
                    val = int(float(v))
                    if 100 <= val <= 999999:
                        out["error_codes"][val] = k
                except Exception:
                    pass

# message.json 初始化序列
msgs = json.load(open(msg_json))
seen = []
for m in msgs:
    try:
        p = json.loads(m["payload"])
        for k in p:
            if k not in seen:
                seen.append(k)
        if "subscribe" in p:
            break
    except Exception:
        pass
out["init_sequence"] = seen

# 异常检测
if not out["betcodes"]:
    out["issues"].append("Pp 字典 grep 不到（可能压缩多文件 / 字典命名变化 / 非 baccarat-roulette 类）")
if len(out["betcodes"]) and (len(out["betcodes"]) < 3 or len(out["betcodes"]) > 100):
    out["issues"].append(f"betCode 数量异常：{len(out['betcodes'])}")
if not out["error_codes"]:
    out["issues"].append("错误码表 grep 不到")

print(json.dumps(out, indent=2, ensure_ascii=False))
PY

# === 跨机台错误码一致性检测 ===
REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo)}"
EXP_DIR="$REPO_ROOT/docs/integration-experience"
if [[ -d "$EXP_DIR" ]]; then
    INC=$(python3 - <<PY
import json, re, os
my = json.load(open("$DICT_JSON"))
my_codes = {int(k): v for k, v in my.get("error_codes", {}).items()}
inc = []
for root, _, files in os.walk("$EXP_DIR"):
    for f in files:
        if not f.endswith(".md"): continue
        text = open(os.path.join(root, f)).read()
        for m in re.finditer(r'(\d{4,5})\s+([A-Z][A-Za-z]+)', text):
            val, name = int(m.group(1)), m.group(2)
            if val in my_codes and my_codes[val] != name:
                inc.append(f"  {f}: {val} {name} vs {my_codes[val]}")
print("\n".join(inc[:5]))
PY
)
    if [[ -n "$INC" ]]; then
        echo "❌ 错误码值与既有先例不一致 — exit（PP 协议级稳定）" >&2
        echo "$INC" >&2
        # 不强制 exit；让 agent-1 根据情况判断
        jq '.issues += ["错误码与既有先例不一致（见 stderr）"]' "$DICT_JSON" > "$DICT_JSON.tmp" && mv "$DICT_JSON.tmp" "$DICT_JSON"
    fi
fi

# 写 state.json
TMP=$(mktemp)
jq --arg dict "$DICT_JSON" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   '. + {dict_path: $dict, last_updated: $ts}' \
   "$STATE_JSON" > "$TMP" && mv "$TMP" "$STATE_JSON"

# 输出 dict.json 内容（让 agent-1 看到）
cat "$DICT_JSON"
