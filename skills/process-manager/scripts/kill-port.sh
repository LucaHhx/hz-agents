#!/usr/bin/env bash
# 强制释放指定端口
# 用法: kill-port.sh <port> [port2 port3 ...]
# 示例: kill-port.sh 8888
#       kill-port.sh 8888 8080 3000

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

if [ $# -eq 0 ]; then
  echo "用法: kill-port.sh <port> [port2 port3 ...]"
  echo "示例: kill-port.sh 8888"
  echo "      kill-port.sh 8888 8080 3000"
  exit 1
fi

for port in "$@"; do
  echo "=== 端口 $port ==="
  pids=$(lsof -ti :"$port" 2>/dev/null) || true

  if [ -z "$pids" ]; then
    echo "未被占用"
    continue
  fi

  # 显示占用详情
  echo "占用进程:"
  for pid in $pids; do
    cmd_name=$(ps -p "$pid" -o comm= 2>/dev/null || echo "?")
    cmd_full=$(ps -p "$pid" -o args= 2>/dev/null || echo "?")
    echo "  PID: $pid  ($cmd_name)  $cmd_full"
  done

  # 强制释放（用户显式调用，允许杀任意进程）
  pm_kill_port_force "$port"
  echo "已释放"
done
