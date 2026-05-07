#!/bin/bash
# HAB AutoCode API 封装脚本
# 用法: ./autocode.sh <command> [args...]
#
# 命令:
#   packages                    获取所有包
#   templates                   获取模板列表
#   create-package <json>       创建包
#   delete-package <id>         删除包
#   preview <json_file>         预览代码
#   create <json_file>          创建代码
#   get-db                      获取数据库列表
#   get-tables [dbName]         获取表列表
#   get-columns <tableName>     获取表字段
#   history [page] [pageSize]   获取生成历史
#   meta <id>                   获取 Meta 信息
#   rollback <id> [flags]       回滚代码
#   delete-history <id>         删除历史记录

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

if [ -z "$HAB_API_KEY" ]; then
    echo "Error: API Key not configured." >&2
    echo "  配置位置（任选其一）:" >&2
    echo "    新版（推荐）顶级 api-key 段:" >&2
    echo "      api-key:" >&2
    echo "        enabled: true" >&2
    echo "        key: \"<your-key>\"" >&2
    echo "        mode: \"write\"" >&2
    echo "    旧版 autocode.api-key:" >&2
    echo "      autocode:" >&2
    echo "        api-key: \"<your-key>\"" >&2
    exit 1
fi

# autocode 的 createTemp / createPackage / delPackage / rollback 都是写路径，
# 顶级 api-key.mode=read 会被 middleware 挡下（只有 preview/getXxx 等前缀放行）。
# 在写命令执行前提前提示，避免跑到一半才收到 401。
case "${1:-}" in
    create|createTemp|create-package|delete-package|rollback|delete-history)
        if [ "$(echo "${HAB_API_KEY_MODE:-}" | tr '[:upper:]' '[:lower:]')" = "read" ]; then
            echo "Error: api-key.mode=read，写操作会被 middleware 拒绝。" >&2
            echo "  请在 $CONFIG_FILE 将 api-key.mode 临时改为 \"write\"，重启 server 后再试。" >&2
            echo "  生成完成后建议改回 \"read\" 以保持安全边界。" >&2
            exit 1
        fi
        ;;
esac

# 通用 curl 函数
api_post() {
    local path="$1"
    local data="${2:-{}}"
    curl -s -X POST "${HAB_BASE_URL}${path}" \
        -H "Content-Type: application/json" \
        -H "x-api-key: ${HAB_API_KEY}" \
        -d "$data"
}

api_get() {
    local path="$1"
    curl -s -X GET "${HAB_BASE_URL}${path}" \
        -H "x-api-key: ${HAB_API_KEY}"
}

api_post_file() {
    local path="$1"
    local file="$2"
    curl -s -X POST "${HAB_BASE_URL}${path}" \
        -H "Content-Type: application/json" \
        -H "x-api-key: ${HAB_API_KEY}" \
        -d @"$file"
}

CMD="${1:-help}"
shift || true

case "$CMD" in
    packages)
        api_post "/autoCode/getPackage"
        ;;
    templates)
        api_get "/autoCode/getTemplates"
        ;;
    create-package)
        api_post "/autoCode/createPackage" "$1"
        ;;
    delete-package)
        api_post "/autoCode/delPackage" "{\"id\": $1}"
        ;;
    preview)
        api_post_file "/autoCode/preview" "$1"
        ;;
    create)
        api_post_file "/autoCode/createTemp" "$1"
        ;;
    get-db)
        api_get "/autoCode/getDB"
        ;;
    get-tables)
        local_db="${1:-}"
        api_get "/autoCode/getTables?dbName=${local_db}"
        ;;
    get-columns)
        api_get "/autoCode/getColumn?tableName=$1"
        ;;
    history)
        page="${1:-1}"
        pageSize="${2:-10}"
        api_post "/autoCode/getSysHistory" "{\"page\": $page, \"pageSize\": $pageSize}"
        ;;
    meta)
        api_post "/autoCode/getMeta" "{\"id\": $1}"
        ;;
    rollback)
        id="$1"
        flags="${2:-}"
        delete_api="true"
        delete_menu="true"
        delete_table="true"
        if [ "$flags" = "keep-table" ]; then
            delete_table="false"
        fi
        api_post "/autoCode/rollback" "{\"id\": $id, \"deleteApi\": $delete_api, \"deleteMenu\": $delete_menu, \"deleteTable\": $delete_table}"
        ;;
    delete-history)
        api_post "/autoCode/delSysHistory" "{\"id\": $1}"
        ;;
    help|*)
        echo "Usage: $0 <command> [args...]"
        echo ""
        echo "Commands:"
        echo "  packages                    Get all packages"
        echo "  templates                   Get template types"
        echo "  create-package <json>       Create a package"
        echo "  delete-package <id>         Delete a package"
        echo "  preview <json_file>         Preview generated code"
        echo "  create <json_file>          Generate code"
        echo "  get-db                      List databases"
        echo "  get-tables [dbName]         List tables"
        echo "  get-columns <tableName>     List columns"
        echo "  history [page] [pageSize]   List generation history"
        echo "  meta <id>                   Get meta info"
        echo "  rollback <id> [flags]       Rollback generated code"
        echo "  delete-history <id>         Delete history record"
        ;;
esac
