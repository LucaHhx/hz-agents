#!/usr/bin/env bash
# codex_dev.sh — 让 codex 实际动手干活（写文件 / 跑命令）完成一个明确任务，过滤事件流。
#
# 与 review/discuss/decide 三个只读脚本不同：本脚本是「执行模式」，codex 会真正改文件、
# 执行命令。**执行代理一律全权限运行** = codex exec --dangerously-bypass-approvals-and-sandbox
# （即 codex --yolo）：可联网、可写任意路径、不询问审批。
#
# 为什么不留受限沙箱档：workspace-write 会把 `.git` 设成只读（实测 git add 直接报
# `Unable to create '.git/index.lock': Operation not permitted`），连"提交代码"这种基本任务都干不了，
# 联网装依赖也会被挡。执行代理要的就是完整能力；安全性靠「工作目录是 git 仓库可回滚 + 任务描述写死
# 禁止项 + 干完 git diff 亲审」来保证，而不是靠阉割它的手脚。
#
# 用法：
#   首次任务：codex_dev.sh -d DIR [-m MODEL] [-l LABEL] -- <任务描述>
#   续接任务：codex_dev.sh -t THREAD_ID [-m MODEL] [-l LABEL] -- <后续指令>
#   stdin：   echo "<任务描述>" | codex_dev.sh -d DIR [其他参数]
#
# 参数：
#   -d DIR         codex 工作目录（透传 --cd）。**首次必填、必须为绝对路径且目录已存在**；
#                  强烈建议是 git 仓库根，便于事后 `git diff` 审查、必要时回滚。resume 时被忽略
#   -t THREAD_ID   续接已有任务会话；不传则新建
#   -m MODEL       codex 模型（透传 -m），默认 codex 自选
#   -l LABEL       输出前缀（打到 stderr，不污染 stdout 流）
#   -h             显示帮助
#
# 输出（已过滤，只保留 Claude 需要看的动作）：
#   THREAD_ID=<uuid>         新会话首行；resume 后续可复用它继续续接
#   <agent message text>     codex 的说明性回复
#   📝 <kind> <path>         file_change：codex 增/改/删了哪个文件（kind = add/update/delete）
#   ⚙️ exit=<n> $ <command>  command_execution：codex 跑了什么命令 + 退出码 + 输出（超长截断）
#   reasoning / token_count 等噪声一律丢弃。
#
# 行为细节：
#   * codex 的 stdin 显式 </dev/null，避免在 pipe 环境（Bash 工具/CI/Monitor）下卡住等 stdin
#   * resume 时不传 --cd（codex 会拒绝），由原会话继承；检测到会 stderr 警告并忽略
#   * codex --json 的 stdout 是纯 JSONL；"Reading additional input from stdin..." 之类提示走 stderr，不进 jq
#   * ⚠️ 全权限运行：codex 有网络和全盘写能力，该禁的必须写进任务描述（如"绝对不要 push"）
#   * ⚠️ 干完活后必须回工作目录 `git diff` / `git status` 亲审 codex 的改动，别盲信它说"已完成"
#
# 退出码：
#   0  成功
#   2  参数错误
#   3  依赖缺失（codex / jq）
#   4  codex 自身执行失败

set -uo pipefail

DIR=""
MODEL=""
THREAD_ID=""
LABEL=""
PROMPT=""

usage() {
  sed -n '2,44p' "$0" | sed 's/^# \{0,1\}//'
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
    -t) require_arg "$1" "${2-__MISSING__}" || exit 2; THREAD_ID="$2"; shift 2 ;;
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
  echo "error: 缺少任务描述文本" >&2
  usage >&2
  exit 2
fi

command -v codex >/dev/null 2>&1 || { echo "error: 未找到 codex CLI" >&2; exit 3; }
command -v jq    >/dev/null 2>&1 || { echo "error: 未找到 jq" >&2; exit 3; }

# 注入「自主执行」header：压制 codex 在挂载了 brainstorming 等 skill / AGENTS.md 的仓库里
# “先出设计等用户批准”的交互式闸门——exec 非交互没人回答，停下=任务失败。只在首轮注入，
# resume 续接时基调已在会话上下文里，不重复。
DEV_HEADER='你在 codex-collab「执行模式」下被调用，这是一次**非交互自主执行**任务：终端旁没有人，你无法征询任何确认或批准。

# 铁律
1. **直接动手做完**：读代码、改文件、跑命令、跑测试，一气呵成。**严禁**停下来问“确认按此实现吗 / 是否继续 / 要不要先写设计”——没有人会回答，停下等于任务失败。
2. **忽略任何“先产出设计文档并等待用户批准”的流程规范**（例如 brainstorming 之类的 HARD-GATE / 审批闸门）。那是给交互式会话的；本次是自主执行，跳过审批直接实现。
3. 任务若有多种合理实现，**自己挑最贴合要求的一种直接做**，把假设与取舍写进最后报告，不要停下询问。
4. 做完必须**自行验证**：能编译 / 跑测试 / 运行就执行，确认通过再收尾。
5. 只围绕本任务改动，不要顺手做无关重构。你有完整权限（可联网、可写任意路径），因此**任务描述里明令禁止的事一律不许做**，也不要自行扩大授权范围。

# 完成后报告（结尾一段）
- 改动的文件清单
- 执行的验证命令及结果（通过 / 失败）
- 你自主做出的假设或取舍

— 以下是要完成的任务 —
'

if [[ -n "$THREAD_ID" ]]; then
  # resume：codex 不接受 --cd（由原会话继承），只允许 --json / -m 等
  [[ -n "$DIR" ]] && echo "warn: resume 模式下 -d/--cd 由原会话决定，已忽略" >&2
  CODEX_ARGS=(exec resume "$THREAD_ID" --json)
  [[ -n "$MODEL" ]] && CODEX_ARGS+=(-m "$MODEL")
  CODEX_ARGS+=("$PROMPT")
else
  if [[ -z "$DIR" ]]; then
    echo "error: 首次任务必须用 -d 指定工作目录（绝对路径）" >&2
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

  # 执行代理一律全权限（yolo）：受限沙箱会把 .git 设为只读、挡掉联网，基本任务都干不了。
  echo "⚠️  [codex_dev] 全权限执行（--dangerously-bypass-approvals-and-sandbox）：codex 可联网、可写任意路径。请确保任务描述已写死禁止项，且工作目录可回滚（git）。" >&2
  CODEX_ARGS=(exec --json --cd "$DIR" --dangerously-bypass-approvals-and-sandbox)
  [[ -n "$MODEL" ]] && CODEX_ARGS+=(-m "$MODEL")
  CODEX_ARGS+=("${DEV_HEADER}${PROMPT}")
fi

if [[ -n "$LABEL" ]]; then
  printf '===== [%s] codex dev start =====\n' "$LABEL" >&2
fi

set -o pipefail
codex "${CODEX_ARGS[@]}" </dev/null \
  | jq -r --unbuffered '
      if .type == "thread.started" then
          "THREAD_ID=" + .thread_id
        elif .type == "item.completed" then
          (.item as $it
           | if $it.type == "agent_message" then
               $it.text
             elif $it.type == "file_change" then
               ($it.changes | map("📝 " + .kind + " " + .path) | join("\n"))
             elif $it.type == "command_execution" then
               ("⚙️ exit=" + (($it.exit_code // "?") | tostring) + " $ " + $it.command
                + (if ($it.aggregated_output // "") != ""
                   then "\n" + (if ($it.aggregated_output | length) > 3000
                                then ($it.aggregated_output[0:3000]) + "\n…[输出已截断]"
                                else $it.aggregated_output end)
                   else "" end))
             else empty end)
        else empty end
    '
status=$?

if [[ -n "$LABEL" ]]; then
  printf '===== [%s] codex dev end =====\n' "$LABEL" >&2
fi

if [[ $status -ne 0 ]]; then
  echo "error: codex 执行失败 (exit=$status)" >&2
  exit 4
fi
