#!/usr/bin/env bash
# pm 公共函数和变量

PM_DIR="/tmp/claude-pm"
mkdir -p "$PM_DIR"
shopt -s nullglob

# 检查进程是否存活
pm_is_running() {
  local name="$1"
  [ -f "$PM_DIR/$name.pid" ] && kill -0 "$(cat "$PM_DIR/$name.pid")" 2>/dev/null
}

# 获取进程 PID
pm_pid() {
  cat "$PM_DIR/$1.pid" 2>/dev/null
}

# 获取进程命令
pm_cmd() {
  cat "$PM_DIR/$1.cmd" 2>/dev/null || echo "?"
}

# 获取进程工作目录
pm_cwd() {
  cat "$PM_DIR/$1.cwd" 2>/dev/null || echo "?"
}

# 获取进程端口
pm_port() {
  cat "$PM_DIR/$1.port" 2>/dev/null || echo ""
}

# 递归杀掉进程树（PID + 所有子孙进程）
pm_kill_tree() {
  local pid="$1"
  local signal="${2:-TERM}"

  # 先收集所有子进程（深度优先）
  local children
  children=$(pgrep -P "$pid" 2>/dev/null) || true

  for child in $children; do
    pm_kill_tree "$child" "$signal"
  done

  kill -"$signal" "$pid" 2>/dev/null || true
}

# 检查端口是否被占用，返回占用该端口的 PID
pm_port_pid() {
  local port="$1"
  lsof -ti :"$port" 2>/dev/null | head -1
}

# 检查某个 PID 是否是指定根进程的子孙
pm_is_descendant() {
  local target_pid="$1"
  local root_pid="$2"
  local current="$target_pid"

  # 向上追溯父进程，最多 20 层防死循环
  for _ in $(seq 1 20); do
    [ "$current" = "$root_pid" ] && return 0
    [ "$current" = "1" ] || [ "$current" = "0" ] && return 1
    current=$(ps -p "$current" -o ppid= 2>/dev/null | tr -d ' ') || return 1
    [ -z "$current" ] && return 1
  done
  return 1
}

# 安全释放端口（仅杀掉属于指定根进程的子孙）
# 用法: pm_kill_port_safe <port> <root_pid>
pm_kill_port_safe() {
  local port="$1"
  local root_pid="$2"
  local pids
  pids=$(lsof -ti :"$port" 2>/dev/null) || true

  if [ -z "$pids" ]; then
    return 0
  fi

  local killed=0
  for pid in $pids; do
    if pm_is_descendant "$pid" "$root_pid"; then
      local cmd_name
      cmd_name=$(ps -p "$pid" -o comm= 2>/dev/null || echo "?")
      kill "$pid" 2>/dev/null || true
      echo "  终止子进程: PID $pid ($cmd_name)"
      killed=$((killed + 1))
    fi
  done

  if [ "$killed" -eq 0 ]; then
    return 1  # 端口被非我们的进程占用
  fi

  # 等待最多 3 秒
  for _ in $(seq 1 6); do
    remaining=$(lsof -ti :"$port" 2>/dev/null) || true
    [ -z "$remaining" ] && return 0
    sleep 0.5
  done

  # 仍有残留则只强制杀我们的
  remaining=$(lsof -ti :"$port" 2>/dev/null) || true
  for pid in $remaining; do
    if pm_is_descendant "$pid" "$root_pid"; then
      kill -9 "$pid" 2>/dev/null || true
      echo "  强制终止子进程: PID $pid"
    fi
  done
}

# 强制释放端口（kill-port.sh 专用，用户显式调用）
# 会杀掉端口上的所有进程，不做归属检查
pm_kill_port_force() {
  local port="$1"
  local pids
  pids=$(lsof -ti :"$port" 2>/dev/null) || true

  if [ -z "$pids" ]; then
    echo "端口 $port 未被占用"
    return 0
  fi

  for pid in $pids; do
    local cmd_name
    cmd_name=$(ps -p "$pid" -o comm= 2>/dev/null || echo "?")
    kill "$pid" 2>/dev/null || true
    echo "已发送 TERM 信号: PID $pid ($cmd_name)"
  done

  # 等待最多 3 秒
  for _ in $(seq 1 6); do
    remaining=$(lsof -ti :"$port" 2>/dev/null) || true
    [ -z "$remaining" ] && break
    sleep 0.5
  done

  # 仍有残留则强制杀
  remaining=$(lsof -ti :"$port" 2>/dev/null) || true
  if [ -n "$remaining" ]; then
    for pid in $remaining; do
      kill -9 "$pid" 2>/dev/null || true
      echo "已强制终止: PID $pid"
    done
  fi
}
