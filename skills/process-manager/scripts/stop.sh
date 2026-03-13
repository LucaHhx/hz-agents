#!/usr/bin/env bash
# 终止进程（杀掉整个进程树 + 安全释放端口）
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
  local port
  port=$(pm_port "$name")

  if ! kill -0 "$pid" 2>/dev/null; then
    echo "[$name] 已经不在运行 (PID: $pid)"
    # 主进程已死，尝试清理属于我们的残留子进程占用的端口
    if [ -n "$port" ]; then
      local port_pid
      port_pid=$(pm_port_pid "$port")
      if [ -n "$port_pid" ]; then
        # 检查是否是我们的子进程
        if pm_is_descendant "$port_pid" "$pid"; then
          echo "[$name] 端口 $port 被残留子进程 PID $port_pid 占用，正在清理..."
          pm_kill_port_safe "$port" "$pid"
        else
          local port_cmd
          port_cmd=$(ps -p "$port_pid" -o comm= 2>/dev/null || echo "?")
          echo "[$name] 端口 $port 被其他进程占用: PID $port_pid ($port_cmd)，跳过"
        fi
      fi
    fi
    return 0
  fi

  # 杀掉整个进程树（先 TERM）
  echo "[$name] 正在终止进程树 (PID: $pid)..."
  pm_kill_tree "$pid" "TERM"

  # 等待最多 5 秒
  for _ in $(seq 1 10); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.5
  done

  # 仍然存活则强制杀
  if kill -0 "$pid" 2>/dev/null; then
    pm_kill_tree "$pid" "KILL"
    sleep 0.5
    echo "[$name] 已强制终止 (PID: $pid)"
  else
    echo "[$name] 已终止 (PID: $pid)"
  fi

  # 确保端口已释放（只杀属于我们进程树的）
  if [ -n "$port" ]; then
    local port_pid
    port_pid=$(pm_port_pid "$port")
    if [ -n "$port_pid" ]; then
      if pm_is_descendant "$port_pid" "$pid"; then
        echo "[$name] 端口 $port 仍被子进程占用，正在清理..."
        pm_kill_port_safe "$port" "$pid"
      else
        local port_cmd
        port_cmd=$(ps -p "$port_pid" -o comm= 2>/dev/null || echo "?")
        echo "[$name] 警告: 端口 $port 被其他进程占用: PID $port_pid ($port_cmd)"
        echo "[$name] 如需强制释放请用: kill-port.sh $port"
      fi
    fi
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
