#!/usr/bin/env bash
# 查看进程日志
# 用法: logs.sh <name> [--lines N] [--head] [--follow]
# 示例: logs.sh backend --lines 50
#       logs.sh backend --head
#       logs.sh backend --follow

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

if [ $# -lt 1 ]; then
  echo "用法: logs.sh <name> [--lines N] [--head] [--follow]"
  exit 1
fi

name="$1"; shift
lines=30
mode="tail"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lines|-n) lines="$2"; shift 2 ;;
    --head) mode="head"; shift ;;
    --follow|-f) mode="follow"; shift ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
done

logfile="$PM_DIR/$name.log"
if [ ! -f "$logfile" ]; then
  echo "[$name] 日志文件不存在"
  exit 1
fi

echo "--- [$name] 日志 ---"
case "$mode" in
  head)   head -n "$lines" "$logfile" ;;
  follow) tail -f "$logfile" ;;
  *)      tail -n "$lines" "$logfile" ;;
esac
