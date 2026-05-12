#!/usr/bin/env bash
# codex_review.sh — 用 codex exec 跑只读代码审查，过滤掉非 agent_message 的噪声输出。
#
# 用法：
#   codex_review.sh -d DIR [-m MODEL] [-l LABEL] -- <审查指令文本>
#   echo "<审查指令>" | codex_review.sh -d DIR [-m MODEL] [-l LABEL]
#
# 参数：
#   -d DIR     审查时 codex 的工作目录（透传给 codex 的 --cd），**必填且为绝对路径**
#   -m MODEL   指定 codex 模型（透传 -m），默认不传由 codex 选
#   -l LABEL   日志/输出前缀，便于多 agent 并行时区分（默认无前缀）
#   -h         显示此帮助
#
# 行为：
#   * 强制使用 --json + sandbox=read-only，禁止 codex 写文件 / 执行修改
#   * 用 jq 只保留 agent_message 文本，其他事件类型全部丢弃，避免污染上下文
#   * jq 加 --unbuffered，每段 agent_message 流式刷出
#   * codex 的 stdin 显式 </dev/null，避免在 pipe 环境（Bash 工具/CI）下卡住等"附加 stdin 块"
#   * 找不到 codex / jq 时报错并退出
#
# 退出码：
#   0  成功输出审查结论
#   2  参数错误
#   3  依赖缺失（codex / jq）
#   4  codex 自身执行失败

set -uo pipefail

DIR=""
MODEL=""
LABEL=""
PROMPT=""

usage() {
  sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'
}

require_arg() {
  if [[ "${2-__MISSING__}" == "__MISSING__" ]]; then
    echo "error: $1 需要参数" >&2
    usage >&2
    return 2
  fi
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
    -l) require_arg "$1" "${2-__MISSING__}" || exit 2; LABEL="$2"; shift 2 ;;
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
  echo "error: 缺少审查指令文本" >&2
  usage >&2
  exit 2
fi

if [[ -z "$DIR" ]]; then
  echo "error: -d DIR 必填（codex 工作目录），且应为绝对路径" >&2
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

command -v codex >/dev/null 2>&1 || { echo "error: 未找到 codex CLI" >&2; exit 3; }
command -v jq    >/dev/null 2>&1 || { echo "error: 未找到 jq" >&2; exit 3; }

CODEX_ARGS=(exec --json --sandbox read-only --cd "$DIR")
[[ -n "$MODEL" ]] && CODEX_ARGS+=(-m "$MODEL")
CODEX_ARGS+=("$PROMPT")

if [[ -n "$LABEL" ]]; then
  printf '===== [%s] codex review start =====\n' "$LABEL" >&2
fi

set -o pipefail
codex "${CODEX_ARGS[@]}" </dev/null \
  | jq -r --unbuffered 'select(.item.type == "agent_message") | .item.text'
status=$?

if [[ -n "$LABEL" ]]; then
  printf '===== [%s] codex review end =====\n' "$LABEL" >&2
fi

if [[ $status -ne 0 ]]; then
  echo "error: codex exec 失败 (exit=$status)" >&2
  exit 4
fi
