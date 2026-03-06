#!/bin/bash
# 从 config.yaml 读取 API Key 和 server 配置
# 用法: source scripts/config.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../../" && pwd)"
CONFIG_FILE="$PROJECT_ROOT/server/config.yaml"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: config.yaml not found at $CONFIG_FILE" >&2
    exit 1
fi

# 读取 API Key (使用 grep + sed，不依赖 yq)
HAB_API_KEY=$(grep -A 10 '^autocode:' "$CONFIG_FILE" | grep 'api-key:' | sed 's/.*api-key:\s*"\?\([^"]*\)"\?.*/\1/' | tr -d ' ')

# 读取 server 端口
HAB_PORT=$(grep -A 5 '^system:' "$CONFIG_FILE" | grep 'addr:' | head -1 | sed 's/.*addr:\s*//' | tr -d ' ')

# 读取路由前缀
HAB_PREFIX=$(grep -A 10 '^system:' "$CONFIG_FILE" | grep 'router-prefix:' | sed 's/.*router-prefix:\s*"\?\([^"]*\)"\?.*/\1/' | tr -d ' ')

# 构建基础 URL
HAB_BASE_URL="http://localhost:${HAB_PORT:-9688}${HAB_PREFIX}"

export HAB_API_KEY HAB_PORT HAB_PREFIX HAB_BASE_URL
