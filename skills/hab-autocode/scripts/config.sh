#!/bin/bash
# 从 config.yaml 读取 API Key 和 server 配置
# 用法: source scripts/config.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 动态查找项目根目录（包含 server/ 目录）
# 查找顺序：
#   1. 环境变量 HAB_PROJECT_ROOT 显式指定（最高优先级）
#   2. 从 SCRIPT_DIR 向上找（支持 skill 装在项目内的 .claude/skills/ 场景）
#   3. 从当前 CWD 向上找（支持 skill 全局安装、从项目目录调用的场景）
_find_project_root() {
  local _dir="$1"
  while [ "$_dir" != "/" ] && [ -n "$_dir" ]; do
    if [ -d "$_dir/server" ]; then
      echo "$_dir"
      return 0
    fi
    _dir="$(dirname "$_dir")"
  done
  return 1
}

PROJECT_ROOT=""
if [ -n "${HAB_PROJECT_ROOT:-}" ] && [ -d "$HAB_PROJECT_ROOT/server" ]; then
  PROJECT_ROOT="$HAB_PROJECT_ROOT"
fi
if [ -z "$PROJECT_ROOT" ]; then
  PROJECT_ROOT="$(_find_project_root "$SCRIPT_DIR" || true)"
fi
if [ -z "$PROJECT_ROOT" ]; then
  PROJECT_ROOT="$(_find_project_root "$(pwd)" || true)"
fi
if [ -z "$PROJECT_ROOT" ]; then
  echo "Error: Cannot find project root (no server/ directory found)." >&2
  echo "  请从项目根目录（包含 server/ 的目录）调用 autocode.sh，" >&2
  echo "  或 export HAB_PROJECT_ROOT=/path/to/project 后再调用。" >&2
  return 1 2>/dev/null || exit 1
fi

# 优先使用 config.local.yaml，其次 config.yaml
if [ -f "$PROJECT_ROOT/server/config.local.yaml" ]; then
    CONFIG_FILE="$PROJECT_ROOT/server/config.local.yaml"
elif [ -f "$PROJECT_ROOT/server/config.yaml" ]; then
    CONFIG_FILE="$PROJECT_ROOT/server/config.yaml"
else
    echo "Error: config.yaml not found in $PROJECT_ROOT/server/" >&2
    exit 1
fi

# 读取 API Key (使用 sed -E 兼容 macOS BSD sed 和 GNU sed)
#
# 兼容两种项目配置：
#   新版（pp-game 等）：顶级 api-key 段（含 enabled/key/mode），middleware/api_key.go 统一鉴权
#     api-key:
#       enabled: true
#       key: "xxx"
#       mode: "write"        # autocode 写操作要求 mode=write
#   旧版（hz-admin-base 原始）：autocode.api-key 子字段
#     autocode:
#       api-key: "xxx"
#
# 优先读新版，读不到再 fallback 到旧版。
HAB_API_KEY=$(grep -A 10 '^api-key:' "$CONFIG_FILE" | grep -E '^[[:space:]]+key:' | head -1 | sed -E 's/.*key:[[:space:]]*"?([^"]*)"?.*/\1/' | tr -d ' ' || true)
if [ -z "$HAB_API_KEY" ]; then
    HAB_API_KEY=$(grep -A 10 '^autocode:' "$CONFIG_FILE" | grep 'api-key:' | sed -E 's/.*api-key:[[:space:]]*"?([^"]*)"?.*/\1/' | tr -d ' ' || true)
fi

# 读取顶级 api-key.mode（仅新版配置有）。mode=read 会在 middleware 层挡掉 autocode
# 的 createTemp/createPackage 等写路径，这里提前提示用户切到 write。
HAB_API_KEY_MODE=$(grep -A 10 '^api-key:' "$CONFIG_FILE" | grep -E '^[[:space:]]+mode:' | head -1 | sed -E 's/.*mode:[[:space:]]*"?([^"]*)"?.*/\1/' | tr -d ' ' || true)

# 读取 server 端口
HAB_PORT=$(grep -A 5 '^system:' "$CONFIG_FILE" | grep 'addr:' | head -1 | sed -E 's/.*addr:[[:space:]]*//' | tr -d ' ' || true)

# 读取路由前缀 (可能不存在，使用 || true 避免 pipefail 退出)
HAB_PREFIX=$(grep -A 10 '^system:' "$CONFIG_FILE" | grep 'router-prefix:' | sed -E 's/.*router-prefix:[[:space:]]*"?([^"]*)"?.*/\1/' | tr -d ' ' || true)

# 构建基础 URL
HAB_BASE_URL="http://localhost:${HAB_PORT:-9688}${HAB_PREFIX}"

export HAB_API_KEY HAB_API_KEY_MODE HAB_PORT HAB_PREFIX HAB_BASE_URL
