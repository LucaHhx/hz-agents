#!/usr/bin/env bash
# codex_chat.sh — 与 codex 多轮对话。新建或 resume 会话，过滤事件流。
#
# 用法：
#   首次会话：codex_chat.sh -d DIR [-m MODEL] [-s SANDBOX] [--allow-workspace-write] [--allow-danger-full-access] [-l LABEL] -- <消息>
#   续接会话：codex_chat.sh -t THREAD_ID [-m MODEL] [-l LABEL] -- <消息>
#   stdin：   echo "<消息>" | codex_chat.sh -d DIR [其他参数]
#
# 参数：
#   -d DIR        codex 工作目录（透传 --cd）。**首次会话必填、必须为绝对路径且目录已存在**；resume 时被忽略
#   -m MODEL      codex 模型（透传 -m），默认 codex 自选
#   -s SANDBOX    沙箱模式：read-only / workspace-write / danger-full-access
#                 默认 read-only。本 skill 定位是协作只读，因此：
#                   workspace-write 必须配合 --allow-workspace-write 才生效
#                   danger-full-access 必须配合 --allow-danger-full-access 才生效
#                 resume 时被忽略
#   -t THREAD_ID  续接已有会话；不传则新建（首次对话用此模式）
#   -l LABEL      输出前缀（打到 stderr，不污染 jq 过滤后的 stdout 流）
#   --allow-workspace-write     二次确认：允许 -s workspace-write
#   --allow-danger-full-access  二次确认：允许 -s danger-full-access
#   -h            显示帮助
#
# 输出（已过滤）：
#   THREAD_ID=<uuid>     仅新会话首行；resume 时也可能由 codex 再次 emit
#   <agent message text> 后续 codex 回答正文（会按段流式 emit，jq --unbuffered 保证不二次缓冲）
#   其他事件类型（reasoning / tool_call / token_count 等）一律丢弃。
#
# 行为细节：
#   * codex 的 stdin 显式 </dev/null，避免在 pipe 环境（Bash 工具/CI/Monitor）下卡住等"附加 stdin 块"
#   * resume 时不传 --cd / --sandbox（codex 会拒绝），由原会话继承；脚本检测到这俩参数会 stderr 警告并忽略
#
# 退出码：
#   0  成功
#   2  参数错误
#   3  依赖缺失（codex / jq）
#   4  codex 自身执行失败

set -uo pipefail

DIR=""
MODEL=""
SANDBOX="read-only"
THREAD_ID=""
LABEL=""
PROMPT=""
ALLOW_DANGER=0
ALLOW_WORKSPACE_WRITE=0

usage() {
  sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'
}

require_arg() {
  if [[ "${2-__MISSING__}" == "__MISSING__" ]]; then
    echo "error: $1 需要参数" >&2
    usage >&2
    return 2
  fi
  # 防止把下一个 option 当成值吞掉（例：-m -l foo）
  if [[ "$2" == -* ]]; then
    echo "error: $1 的值不能以 - 开头（看起来像另一个 option）: $2" >&2
    usage >&2
    return 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d) require_arg "$1" "${2-__MISSING__}" || exit 2; DIR="$2"; shift 2 ;;
    -m) require_arg "$1" "${2-__MISSING__}" || exit 2; MODEL="$2"; shift 2 ;;
    -s) require_arg "$1" "${2-__MISSING__}" || exit 2; SANDBOX="$2"; shift 2 ;;
    -t) require_arg "$1" "${2-__MISSING__}" || exit 2; THREAD_ID="$2"; shift 2 ;;
    -l) require_arg "$1" "${2-__MISSING__}" || exit 2; LABEL="$2"; shift 2 ;;
    --allow-danger-full-access) ALLOW_DANGER=1; shift ;;
    --allow-workspace-write) ALLOW_WORKSPACE_WRITE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; PROMPT="$*"; break ;;
    -*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) PROMPT="$*"; break ;;
  esac
done

if [[ -z "$PROMPT" && ! -t 0 ]]; then
  PROMPT="$(cat -)"
fi

if [[ -z "$PROMPT" ]]; then
  echo "error: 缺少消息文本" >&2
  usage >&2
  exit 2
fi

case "$SANDBOX" in
  read-only|workspace-write|danger-full-access) ;;
  *) echo "error: 非法 sandbox 值: ${SANDBOX}（应为 read-only / workspace-write / danger-full-access）" >&2; exit 2 ;;
esac

if [[ "$SANDBOX" == "danger-full-access" && "$ALLOW_DANGER" != "1" ]]; then
  echo "error: -s danger-full-access 必须配合 --allow-danger-full-access 才能启用（codex 会获得完整文件系统访问，慎用）" >&2
  exit 2
fi

if [[ "$SANDBOX" == "workspace-write" && "$ALLOW_WORKSPACE_WRITE" != "1" ]]; then
  echo "error: -s workspace-write 必须配合 --allow-workspace-write 才能启用（本 skill 默认只读，写权限请优先走 dev-* / unify-fix）" >&2
  exit 2
fi

command -v codex >/dev/null 2>&1 || { echo "error: 未找到 codex CLI" >&2; exit 3; }
command -v jq    >/dev/null 2>&1 || { echo "error: 未找到 jq" >&2; exit 3; }

if [[ -n "$THREAD_ID" ]]; then
  # resume 时 codex 不接受 --sandbox / --cd（由原会话继承），只允许 --json / -m / -c / -i 等
  if [[ -n "$DIR" ]]; then
    echo "warn: resume 模式下 -d/--cd 由原会话决定，已忽略" >&2
  fi
  if [[ "$SANDBOX" != "read-only" ]]; then
    echo "warn: resume 模式下 -s/--sandbox 由原会话决定，已忽略（首次会话已定为 read-only 等）" >&2
  fi
  CODEX_ARGS=(exec resume "$THREAD_ID" --json)
  [[ -n "$MODEL" ]] && CODEX_ARGS+=(-m "$MODEL")
  CODEX_ARGS+=("$PROMPT")
else
  if [[ -z "$DIR" ]]; then
    echo "error: 首次会话必须用 -d 指定工作目录（绝对路径）" >&2
    usage >&2
    exit 2
  fi
  if [[ "$DIR" != /* ]]; then
    echo "error: -d 必须是绝对路径，得到: $DIR" >&2
    exit 2
  fi
  if [[ ! -d "$DIR" ]]; then
    echo "error: -d 指定的目录不存在: $DIR" >&2
    exit 2
  fi
  CODEX_ARGS=(exec --json --sandbox "$SANDBOX" --cd "$DIR")
  [[ -n "$MODEL" ]] && CODEX_ARGS+=(-m "$MODEL")
  CODEX_ARGS+=("$PROMPT")
fi

if [[ -n "$LABEL" ]]; then
  printf '===== [%s] codex chat start =====\n' "$LABEL" >&2
fi

set -o pipefail
codex "${CODEX_ARGS[@]}" </dev/null \
  | jq -r --unbuffered '
      if .type == "thread.started" then
        "THREAD_ID=" + .thread_id
      elif .item.type == "agent_message" then
        .item.text
      else
        empty
      end
    '
status=$?

if [[ -n "$LABEL" ]]; then
  printf '===== [%s] codex chat end =====\n' "$LABEL" >&2
fi

if [[ $status -ne 0 ]]; then
  echo "error: codex 执行失败 (exit=$status)" >&2
  exit 4
fi
