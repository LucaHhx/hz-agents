#!/usr/bin/env bash
# 重启进程（使用之前保存的命令和工作目录）
# 用法: restart.sh <name>

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

if [ $# -lt 1 ]; then
  echo "用法: restart.sh <name>"
  exit 1
fi

name="$1"

if [ ! -f "$PM_DIR/$name.cmd" ] || [ ! -f "$PM_DIR/$name.cwd" ]; then
  echo "[$name] 缺少命令或工作目录信息，无法重启"
  exit 1
fi

command=$(pm_cmd "$name")
cwd=$(pm_cwd "$name")

# 先停止
"$SCRIPT_DIR/stop.sh" "$name" 2>/dev/null || true
sleep 1

# 再启动
"$SCRIPT_DIR/start.sh" "$name" "$command" --cwd "$cwd"
