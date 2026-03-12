#!/bin/bash
# 从 config.yaml 读取 API Key 和 server 配置
# 用法: source scripts/config.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 动态查找项目根目录（包含 server/ 目录）
_dir="$SCRIPT_DIR"
PROJECT_ROOT=""
while [ "$_dir" != "/" ]; do
  if [ -d "$_dir/server" ]; then
    PROJECT_ROOT="$_dir"
    break
  fi
  _dir="$(dirname "$_dir")"
done
if [ -z "$PROJECT_ROOT" ]; then
  echo "Error: Cannot find project root (no server/ directory found)" >&2
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
HAB_API_KEY=$(grep -A 10 '^autocode:' "$CONFIG_FILE" | grep 'api-key:' | sed -E 's/.*api-key:[[:space:]]*"?([^"]*)"?.*/\1/' | tr -d ' ')

# 读取 server 端口
HAB_PORT=$(grep -A 5 '^system:' "$CONFIG_FILE" | grep 'addr:' | head -1 | sed -E 's/.*addr:[[:space:]]*//' | tr -d ' ')

# 读取路由前缀 (可能不存在，使用 || true 避免 pipefail 退出)
HAB_PREFIX=$(grep -A 10 '^system:' "$CONFIG_FILE" | grep 'router-prefix:' | sed -E 's/.*router-prefix:[[:space:]]*"?([^"]*)"?.*/\1/' | tr -d ' ' || true)

# 构建基础 URL
HAB_BASE_URL="http://localhost:${HAB_PORT:-9688}${HAB_PREFIX}"

export HAB_API_KEY HAB_PORT HAB_PREFIX HAB_BASE_URL
