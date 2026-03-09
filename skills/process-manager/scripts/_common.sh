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
