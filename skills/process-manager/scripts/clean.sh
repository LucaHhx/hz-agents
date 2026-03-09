#!/usr/bin/env bash
# 清理已停止的进程记录
# 用法: clean.sh           清理已停止的
#       clean.sh --all      清理所有记录

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

if [ "${1:-}" = "--all" ]; then
  rm -f "$PM_DIR"/*
  echo "已清理所有记录"
  exit 0
fi

cleaned=0
for f in "$PM_DIR"/*.pid; do
  name=$(basename "$f" .pid)
  pid=$(pm_pid "$name")
  if ! kill -0 "$pid" 2>/dev/null; then
    rm -f "$PM_DIR/$name".*
    echo "已清理: $name"
    cleaned=$((cleaned + 1))
  fi
done

if [ "$cleaned" -eq 0 ]; then
  echo "没有需要清理的记录"
fi
