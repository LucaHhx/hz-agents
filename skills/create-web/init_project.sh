#!/usr/bin/env bash
# Dark Dashboard Kit - 项目初始化脚本
# 用法: bash init_project.sh <项目名称> [目标目录]
# 示例: bash init_project.sh my-dashboard .
#       bash init_project.sh my-app /Users/me/projects

set -euo pipefail

# ========================================
# 参数解析
# ========================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_DIR="$(cd "$SCRIPT_DIR/../assets/template" && pwd)"

PROJECT_NAME="${1:-}"
TARGET_DIR="${2:-.}"

if [ -z "$PROJECT_NAME" ]; then
  echo "❌ 请提供项目名称"
  echo ""
  echo "用法: bash $0 <项目名称> [目标目录]"
  echo "示例: bash $0 my-dashboard ."
  echo "      bash $0 my-app ~/projects"
  exit 1
fi

# 验证项目名称格式 (kebab-case)
if ! echo "$PROJECT_NAME" | grep -qE '^[a-z][a-z0-9-]*$'; then
  echo "❌ 项目名称格式错误: $PROJECT_NAME"
  echo "   请使用 kebab-case 格式 (如: my-dashboard)"
  exit 1
fi

# ========================================
# 创建项目
# ========================================

PROJECT_PATH="$(cd "$TARGET_DIR" 2>/dev/null && pwd)/$PROJECT_NAME"

if [ -d "$PROJECT_PATH" ]; then
  echo "❌ 目录已存在: $PROJECT_PATH"
  exit 1
fi

echo "🚀 创建项目: $PROJECT_NAME"
echo "   位置: $PROJECT_PATH"
echo ""

# 复制模板
cp -r "$TEMPLATE_DIR" "$PROJECT_PATH"

# 替换占位符
if [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS sed
  find "$PROJECT_PATH" -type f \( -name "*.json" -o -name "*.html" -o -name "*.tsx" -o -name "*.ts" \) \
    -exec sed -i '' "s/__APP_NAME__/$PROJECT_NAME/g" {} +
  find "$PROJECT_PATH" -type f \( -name "*.json" -o -name "*.html" -o -name "*.tsx" -o -name "*.ts" \) \
    -exec sed -i '' "s/__APP_TITLE__/$PROJECT_NAME/g" {} +
else
  # Linux sed
  find "$PROJECT_PATH" -type f \( -name "*.json" -o -name "*.html" -o -name "*.tsx" -o -name "*.ts" \) \
    -exec sed -i "s/__APP_NAME__/$PROJECT_NAME/g" {} +
  find "$PROJECT_PATH" -type f \( -name "*.json" -o -name "*.html" -o -name "*.tsx" -o -name "*.ts" \) \
    -exec sed -i "s/__APP_TITLE__/$PROJECT_NAME/g" {} +
fi

echo "✅ 项目文件已创建"

# ========================================
# 安装依赖
# ========================================

cd "$PROJECT_PATH"

if command -v bun &>/dev/null; then
  echo "📦 使用 bun 安装依赖..."
  bun install
elif command -v pnpm &>/dev/null; then
  echo "📦 使用 pnpm 安装依赖..."
  pnpm install
elif command -v npm &>/dev/null; then
  echo "📦 使用 npm 安装依赖..."
  npm install
else
  echo "⚠️  未检测到包管理器，请手动运行 npm install"
fi

# ========================================
# 完成
# ========================================

echo ""
echo "✅ 项目 '$PROJECT_NAME' 创建成功!"
echo ""
echo "📁 项目结构:"
echo "   $PROJECT_PATH/"
echo "   ├── src/"
echo "   │   ├── components/   # UI 组件库"
echo "   │   ├── context/      # 状态管理"
echo "   │   ├── utils/        # 工具函数"
echo "   │   ├── App.tsx       # 根组件"
echo "   │   └── styles.css    # 设计系统"
echo "   └── package.json"
echo ""
echo "🎬 启动开发:"
echo "   cd $PROJECT_PATH"
echo "   npm run dev"
echo ""
echo "🔑 默认登录: admin / 123456"
