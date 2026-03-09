#!/usr/bin/env bash
# 终止进程
# 用法: stop.sh <name>        终止指定进程
#       stop.sh --all          终止所有进程

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

stop_one() {
  local name="$1"
  if [ ! -f "$PM_DIR/$name.pid" ]; then
    echo "[$name] 未找到"
    return 1
  fi

  local pid
  pid=$(pm_pid "$name")

  if ! kill -0 "$pid" 2>/dev/null; then
    echo "[$name] 已经不在运行"
    return 0
  fi

  kill "$pid" 2>/dev/null
  for _ in $(seq 1 10); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.5
  done

  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null
    echo "[$name] 已强制终止 (PID: $pid)"
  else
    echo "[$name] 已终止 (PID: $pid)"
  fi
}

if [ $# -eq 0 ]; then
  echo "用法: stop.sh <name>    或    stop.sh --all"
  exit 1
fi

if [ "$1" = "--all" ]; then
  pids=("$PM_DIR"/*.pid)
  if [ ${#pids[@]} -eq 0 ]; then
    echo "没有管理中的进程"
  else
    for f in "${pids[@]}"; do
      name=$(basename "$f" .pid)
      stop_one "$name"
    done
  fi
else
  stop_one "$1"
fi
