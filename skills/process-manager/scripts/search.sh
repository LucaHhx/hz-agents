#!/usr/bin/env bash
# 搜索进程日志
# 用法: search.sh <name> <pattern>
# 示例: search.sh backend "error|panic|fatal"
#       search.sh frontend "ready in|Local:"

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

if [ $# -lt 2 ]; then
  echo "用法: search.sh <name> <pattern>"
  echo "示例: search.sh backend \"error|panic|fatal\""
  exit 1
fi

name="$1"
pattern="$2"
logfile="$PM_DIR/$name.log"

if [ ! -f "$logfile" ]; then
  echo "[$name] 日志文件不存在"
  exit 1
fi

echo "--- [$name] 搜索: $pattern ---"
grep -nE "$pattern" "$logfile" || echo "(无匹配)"
