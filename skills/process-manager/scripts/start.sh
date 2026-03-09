#!/usr/bin/env bash
# 启动后台进程
# 用法: start.sh <name> <command> [--cwd <dir>] [--env "K=V K2=V2"]
# 示例: start.sh backend "go run ." --cwd ./server --env "HAB_CONFIG=config.local.yaml"

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

if [ $# -lt 2 ]; then
  echo "用法: start.sh <name> <command> [--cwd <dir>] [--env \"K=V K2=V2\"]"
  echo "示例: start.sh backend \"go run .\" --cwd ./server --env \"HAB_CONFIG=config.local.yaml\""
  exit 1
fi

name="$1"; shift
command="$1"; shift
cwd="$PWD"
env_vars=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cwd) cwd="$2"; shift 2 ;;
    --env) env_vars="$2"; shift 2 ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
done

# 转为绝对路径
cwd="$(cd "$cwd" && pwd)"

# 检查重复
if pm_is_running "$name"; then
  echo "[$name] 已在运行 (PID: $(pm_pid "$name"))"
  echo "如需重启请用: restart.sh $name"
  exit 1
fi

# 构建启动命令（带环境变量）
run_cmd="$command"
if [ -n "$env_vars" ]; then
  run_cmd="env $env_vars $command"
fi

# 启动
cd "$cwd"
nohup bash -c "$run_cmd" > "$PM_DIR/$name.log" 2>&1 &
pid=$!
echo "$pid" > "$PM_DIR/$name.pid"
echo "$run_cmd" > "$PM_DIR/$name.cmd"
echo "$cwd" > "$PM_DIR/$name.cwd"

echo "[$name] 已启动 (PID: $pid)"
echo "[$name] 命令: $run_cmd"
echo "[$name] 目录: $cwd"
echo "[$name] 日志: $PM_DIR/$name.log"
