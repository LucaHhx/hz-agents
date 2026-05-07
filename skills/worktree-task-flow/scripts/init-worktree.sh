#!/usr/bin/env bash
# init-worktree.sh — Phase 3: 创建 worktree-task-flow 工作区
#
# 用法:
#   bash init-worktree.sh <base-branch> <kebab-description>
#
# 示例:
#   bash init-worktree.sh live-dev sync-pre-maintenance
#
# 行为:
#   1. 验证当前在 git 仓库内
#   2. 验证 description 是 kebab-case 且 ≤40 字符
#   3. 解析 base 分支引用（本地优先；仅远程时用 origin/<base>）
#   4. 提示 .gitignore 是否含 .worktrees/（不自动改）
#   5. 在 <repo>/.worktrees/<description>/ 创建 worktree
#   6. 分支命名 worktree/<base>/<description>
#   7. 输出 key=value 五行供调用方使用（含 worktree_base / target_base 区分）
#
# 失败立即 exit 非零并打印 ERROR；脚本不修复任何问题，只做创建 + 验证。

set -euo pipefail

BASE_BRANCH="${1:?Usage: init-worktree.sh <base-branch> <kebab-description>}"
DESC="${2:?Usage: init-worktree.sh <base-branch> <kebab-description>}"

# 1. git 仓库
if ! REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null); then
    echo "ERROR: not in a git repository" >&2
    exit 1
fi

# 2. description kebab-case + 长度
if ! [[ "$DESC" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
    echo "ERROR: description '$DESC' is not kebab-case" >&2
    echo "  允许字符: a-z 0-9 -（小写字母/数字/连字符）" >&2
    echo "  例: sync-pre-maintenance / fix-currency-bug" >&2
    exit 1
fi
if (( ${#DESC} > 40 )); then
    echo "ERROR: description '$DESC' too long (${#DESC} chars > 40 max)" >&2
    exit 1
fi

# 3. 解析 base 分支引用 — 本地优先；只有远程时用 origin/<base> 作为起点
BASE_REF=""
if git rev-parse --verify --quiet "$BASE_BRANCH" >/dev/null 2>&1; then
    BASE_REF="$BASE_BRANCH"
elif git rev-parse --verify --quiet "origin/$BASE_BRANCH" >/dev/null 2>&1; then
    BASE_REF="origin/$BASE_BRANCH"
    echo "ℹ️  base '$BASE_BRANCH' 仅在 origin/ 存在，将以 origin/$BASE_BRANCH 作为 worktree 起点" >&2
else
    echo "ERROR: base branch '$BASE_BRANCH' not found locally or in origin/" >&2
    echo "  可用分支:" >&2
    git branch --list --all | head -20 >&2
    exit 1
fi

# 4. .gitignore 提示（M1：不自动改，避免污染用户 commit）
if [[ -f "$REPO_ROOT/.gitignore" ]] && ! grep -qE '^\.worktrees/?$|^\.worktrees/\*$' "$REPO_ROOT/.gitignore"; then
    echo "WARN: .gitignore 未含 '.worktrees/'，主仓库 git status 会一直看到 untracked。建议手动加：" >&2
    echo "  echo '.worktrees/' >> $REPO_ROOT/.gitignore" >&2
elif [[ ! -f "$REPO_ROOT/.gitignore" ]]; then
    echo "WARN: 仓库无 .gitignore；建议创建并加 '.worktrees/'" >&2
fi

# 5. 路径与分支名
WT_DIR="$REPO_ROOT/.worktrees/$DESC"
BRANCH="worktree/$BASE_BRANCH/$DESC"

# 6. 防重
if [[ -e "$WT_DIR" ]]; then
    echo "ERROR: worktree path already exists: $WT_DIR" >&2
    echo "  先 cleanup-worktree.sh 清理旧实例，或换一个 description" >&2
    exit 1
fi
if git rev-parse --verify --quiet "$BRANCH" >/dev/null 2>&1; then
    echo "ERROR: branch already exists: $BRANCH" >&2
    echo "  本地已有同名分支；先 git branch -D 或换 description" >&2
    exit 1
fi

# 7. 创建 worktree（输出走 stderr，stdout 留给 key=value）
mkdir -p "$REPO_ROOT/.worktrees"
git worktree add -b "$BRANCH" "$WT_DIR" "$BASE_REF" >&2

# 8. 输出供调用方解析（worktree_base 与 target_base 区分见 SKILL.md Phase 7）
cat <<EOF
worktree_path=$WT_DIR
branch=$BRANCH
worktree_base=$BASE_BRANCH
target_base=$BASE_BRANCH
base_ref=$BASE_REF
EOF
