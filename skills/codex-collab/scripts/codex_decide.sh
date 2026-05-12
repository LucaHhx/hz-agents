#!/usr/bin/env bash
# codex_decide.sh — 一次性结构化决策包装器（codex-collab 通用脚本）
#
# 把 codex 当独立 AI 顾问做单点决策。**强制 codex 主动读代码并自检上下文是否充分**，
# 不允许只看 prompt 摘要给"对/错"式回答。
#
# 适用场景：调用方（人 / 上层 skill / agent）有一个决策点（A vs B vs C），希望
# codex 用自己的视角和实际代码给最终判断，而不是开放讨论。
#
# 用法：
#   codex_decide.sh -d DIR [-m MODEL] [-l LABEL] -- <decision_body>
#   echo "<decision_body>" | codex_decide.sh -d DIR [其他参数]
#
# decision_body 格式（调用方负责写，**不需要包含自检指令**——脚本已注入）：
#   ## 背景
#   <state / 设计草稿 / 关键文件入口路径，列出来即可，让 codex 自己 cat>
#
#   ## 决策点
#   决策 1：<question>
#   候选：A / B / C
#   判断标准：<列出，便于 codex 评估>
#
# 参数：
#   -d DIR     codex 工作目录（必填、绝对路径、存在）
#   -m MODEL   codex 模型（可选）
#   -l LABEL   stderr label 前缀（可选）
#   -h         显示帮助
#
# 输出：codex_chat.sh 的 stdout（首行 THREAD_ID + 后续 agent_message）。
# 调用方解析每段决策的 markdown 代码块；INSUFFICIENT_CONTEXT 块表示需要补路径再调一次。
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
MODEL=""
LABEL=""
BODY=""

usage() {
  sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d) DIR="${2-}"; shift 2 ;;
    -m) MODEL="${2-}"; shift 2 ;;
    -l) LABEL="${2-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; BODY="$*"; break ;;
    -*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) BODY="$*"; break ;;
  esac
done

if [[ -z "$BODY" && ! -t 0 ]]; then
  BODY="$(cat -)"
fi

[[ -z "$BODY" ]] && { echo "error: 缺少决策内容" >&2; usage >&2; exit 2; }
[[ -z "$DIR"  ]] && { echo "error: -d DIR 必填" >&2; usage >&2; exit 2; }

DECISION_HEADER='你是独立 AI 顾问。这是 codex-collab 决策模式的**一次性结构化决策**请求，**禁止追问、禁止开放讨论**。

# 铁律：上下文足够性自检（必须先做）

在给决策前，你**必须**做以下三步主动探索（你在 read-only sandbox 下可以用 `rg` / `cat` / `sed` 读任意路径）：

1. **读完 background 列出的所有文件路径**（不是只看摘要）：state / 设计草稿 / 关联代码 / 历史记录等
2. **主动 grep / cat 验证背景描述**：例如对照实际函数签名、字段定义、错误码表，而不是只信摘要
3. **对照已有先例 / 经验文档**：如果该领域有 `docs/` / `references/` / 历史 commit，主动查阅

**只有完成上述三步仍不足以决策**，才能输出 `INSUFFICIENT_CONTEXT` 块。

# 决策原则

- 调用方给你的是**问题 + 入口路径**（哪个文件、哪个函数、哪个 state 字段），不是答案
- 你的任务是**自己读完路径**，扩展 grep / cat，**给出有依据的最终判断**
- **禁止**给"对/错"二选一简单回答而不引用具体 `file:line` 或代码片段作为证据
- **禁止**直接复述调用方候选项原话作为"理由"，必须用自己的话总结
- 如果候选项均不合理，可自定义第三个选项，但要清楚说明为何放弃 A/B/C

# 输出格式（严格按 markdown 代码块）

**上下文充分**（已完成主动探索）：

```
决策：<选定项或自定义文本>
理由：<必须引用具体 file:line / grep 结果 / 经验文档章节作为依据>
依据来源：<列出你实际读过的文件 + 关键 grep 命令>
具体落地：<要改哪个文件、写哪个字段、或调用哪个脚本>
```

多个决策按 `决策 A` / `决策 B` / `决策 C` 编号，每个独立一组代码块。

**上下文不足**（主动探索后仍不够）：

```
决策：INSUFFICIENT_CONTEXT
已探索：<列出你已读过的文件 + 已 grep 的命令 + 已对照的先例>
还缺：
- <具体文件 1 的路径，以及为什么需要它>
- <具体函数 2 的引用 (file:line)，以及希望看到的代码段>
- <具体数据 3 的样本或字段定义>
建议下一步：调用方在 background 补全上述路径后再调一次本脚本；或调用方主动贴出函数实现 / 数据样本
```

# 禁止

- ❌ 不读文件直接根据 background 摘要给决策
- ❌ 给"对/错"二元简单回答而不引用具体证据
- ❌ 拒绝用 rg / cat 主动验证（你在 read-only sandbox 下可以读任何路径）
- ❌ 把调用方候选项原话当作"理由"复述

— 以下是决策内容 —
'

PROMPT="${DECISION_HEADER}
${BODY}"

ARGS=(-d "$DIR")
[[ -n "$MODEL" ]] && ARGS+=(-m "$MODEL")
[[ -n "$LABEL" ]] && ARGS+=(-l "$LABEL")
ARGS+=(-- "$PROMPT")

exec bash "$CHAT_SH" "${ARGS[@]}"
