#!/usr/bin/env bash
# 列出所有管理中的进程
# 用法: list.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

pids=("$PM_DIR"/*.pid)
if [ ${#pids[@]} -eq 0 ]; then
  echo "没有管理中的进程"
  exit 0
fi

for f in "${pids[@]}"; do
  name=$(basename "$f" .pid)
  pid=$(pm_pid "$name")
  cmd=$(pm_cmd "$name")
  cwd=$(pm_cwd "$name")
  port=$(pm_port "$name")

  if kill -0 "$pid" 2>/dev/null; then
    status="\033[32mrunning\033[0m"
  else
    status="\033[31mstopped\033[0m"
  fi

  port_info=""
  if [ -n "$port" ]; then
    port_info="  Port: $port"
  fi

  printf "  %-20s %b  PID: %-8s%s  %s\n" "$name" "$status" "$pid" "$port_info" "$cmd"
  printf "  %-20s %s\n" "" "cwd: $cwd"
done
