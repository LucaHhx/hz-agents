#!/usr/bin/env bash
# codex_discuss.sh — 多轮沟通包装器（codex-collab 通用脚本）
#
# 在 codex_chat.sh 之上注入"轮数感知 + 每轮上下文自检"的 prompt header，
# 强制 codex 在指定 max-rounds 内收敛（closing），或明确 unresolved。
#
# 适用场景：调用方需要和 codex 多轮探讨复杂问题（设计冲突 / 卡死 root cause），
# 但要避免无限发散和无人值守场景下烧 codex 余额。
#
# 用法：
#   首轮：codex_discuss.sh -d DIR --round 1 --max-rounds M [-l LABEL] -- <message>
#   续接：codex_discuss.sh -t THREAD_ID --round N --max-rounds M [-l LABEL] -- <message>
#   stdin：echo "<message>" | codex_discuss.sh -d DIR --round N --max-rounds M
#
# 参数：
#   -d DIR          codex 工作目录（首轮必填、绝对路径、存在）；resume 时被忽略
#   -t THREAD_ID    续接已有讨论；不传则新建
#   --round N       本轮序号（1-based；调用方递增）— 注入 prompt
#   --max-rounds M  本次讨论硬上限 — 注入 prompt
#   -m MODEL        codex 模型（可选）
#   -l LABEL        stderr label 前缀（可选）
#   -h              显示帮助
#
# codex 每轮回复尾部必须带状态行：
#   discussion_status: in-progress  — 还需继续，调用方 round + 1 后 resume
#   discussion_status: closing      — 已收敛，调用方写状态后退出讨论
#   discussion_status: unresolved   — 无法收敛，调用方按 fallback 处理
#
# 退出码：
#   0 成功 / 2 参数错误 / 3 依赖缺失 / 4 codex 失败

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHAT_SH="$SCRIPT_DIR/codex_chat.sh"

[[ -x "$CHAT_SH" ]] || {
  echo "error: 找不到同目录的 codex_chat.sh: $CHAT_SH" >&2
  exit 3
}

DIR=""
THREAD_ID=""
MODEL=""
LABEL=""
ROUND=""
MAX_ROUNDS=""
BODY=""

usage() {
  sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d) DIR="${2-}"; shift 2 ;;
    -t) THREAD_ID="${2-}"; shift 2 ;;
    -m) MODEL="${2-}"; shift 2 ;;
    -l) LABEL="${2-}"; shift 2 ;;
    --round) ROUND="${2-}"; shift 2 ;;
    --max-rounds) MAX_ROUNDS="${2-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; BODY="$*"; break ;;
    -*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) BODY="$*"; break ;;
  esac
done

if [[ -z "$BODY" && ! -t 0 ]]; then
  BODY="$(cat -)"
fi

[[ -z "$BODY"       ]] && { echo "error: 缺少 message" >&2; usage >&2; exit 2; }
[[ -z "$ROUND"      ]] && { echo "error: --round 必填" >&2; usage >&2; exit 2; }
[[ -z "$MAX_ROUNDS" ]] && { echo "error: --max-rounds 必填" >&2; usage >&2; exit 2; }
[[ "$ROUND" =~ ^[0-9]+$ && "$MAX_ROUNDS" =~ ^[0-9]+$ ]] || {
  echo "error: --round 和 --max-rounds 必须是正整数" >&2; exit 2;
}

DISCUSS_HEADER="这是 codex-collab 多轮沟通模式的讨论。

**本轮：第 ${ROUND} / ${MAX_ROUNDS} 轮**

# 铁律：每轮先做上下文自检

每轮回复**必须**先确认：
1. 调用方本轮提供的 message 含有具体路径 / 数据 / 引用？还是只有抽象描述？
2. 你是否需要先 \`rg\` / \`cat\` 路径才能给出有质量的分析？（在 read-only sandbox 下可读任意路径）
3. 你能否给出**有依据**的分析（引用 file:line / 数据样本），还是只能给猜测？

如果只能给猜测 → **本轮回复必须明确要求调用方补上下文**，并标 \`discussion_status: in-progress\` 等下一轮提供。**不要瞎答**。

# 输出结构

每轮回复严格按以下结构：

1. **本轮焦点**（1-2 句确认上下文）
2. **本轮分析或追问**（基于实际 cat/rg 的代码或调用方提供的具体数据；不能凭空发散）
3. **下一步建议**（如已可执行）
4. **状态行**（最后单独一行，必须三选一）：
   - \`discussion_status: in-progress\`  — 信息或讨论仍需继续
   - \`discussion_status: closing\`      — 已可收敛，给出最终建议结论 + 下一步具体动作
   - \`discussion_status: unresolved\`   — 在剩余轮数内无法收敛，建议调用方回退到默认规则 / 写 unresolved 记录

# 硬约束

- 第 ${MAX_ROUNDS} 轮（最后一轮）**禁止** \`in-progress\`，必须 \`closing\` 或 \`unresolved\`
- 不要无限发散；focus on 收敛
- 调用方场景一般是无人值守流程，**不能让用户介入**——你和调用方两个 AI 自己解决

— 以下是本轮 message —
"

PROMPT="${DISCUSS_HEADER}
${BODY}"

ARGS=()
if [[ -n "$THREAD_ID" ]]; then
  ARGS+=(-t "$THREAD_ID")
else
  [[ -z "$DIR" ]] && { echo "error: 首轮（无 -t）必须传 -d DIR" >&2; exit 2; }
  ARGS+=(-d "$DIR")
fi
[[ -n "$MODEL" ]] && ARGS+=(-m "$MODEL")
[[ -n "$LABEL" ]] && ARGS+=(-l "$LABEL")
ARGS+=(-- "$PROMPT")

exec bash "$CHAT_SH" "${ARGS[@]}"
