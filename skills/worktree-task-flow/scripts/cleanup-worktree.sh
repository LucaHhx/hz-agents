#!/usr/bin/env bash
# cleanup-worktree.sh — Phase 8: 清理 worktree-task-flow 工作区
#
# 用法:
#   bash cleanup-worktree.sh <worktree-path> [branch-name]
#
# 示例:
#   bash cleanup-worktree.sh /Users/luca/work/pp-game/.worktrees/sync-pre-maintenance
#
# 安全 gate（任一不满足立即中止）:
#   1. worktree 工作树必须 clean
#   2. 推断分支名（默认从 HEAD 取，可由参数 2 覆盖）
#   3. PR 状态：OPEN 或 MERGED 才允许清理；CLOSED/不存在则警告但允许（可被参数化）
#   4. 备份分支（<branch>-backup）：仅 PR MERGED 才删，其他状态保留
#
# 失败立即 exit 非零并打印 ERROR；不强行覆盖。

set -euo pipefail

WT_DIR="${1:?Usage: cleanup-worktree.sh <worktree-path> [branch-name]}"
BRANCH_OVERRIDE="${2:-}"

# 1. worktree 路径存在
if [[ ! -d "$WT_DIR" ]]; then
    echo "ERROR: worktree not found: $WT_DIR" >&2
    exit 1
fi

# 2. 推断分支名
if [[ -n "$BRANCH_OVERRIDE" ]]; then
    BRANCH="$BRANCH_OVERRIDE"
else
    BRANCH=$(git -C "$WT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
    if [[ -z "$BRANCH" || "$BRANCH" == "HEAD" ]]; then
        echo "ERROR: cannot resolve branch from $WT_DIR (detached HEAD?)" >&2
        echo "  请显式传分支名: cleanup-worktree.sh <path> <branch>" >&2
        exit 1
    fi
fi

# 3. tree 干净
DIRTY=$(git -C "$WT_DIR" status --porcelain)
if [[ -n "$DIRTY" ]]; then
    echo "ERROR: worktree has uncommitted changes:" >&2
    echo "$DIRTY" >&2
    echo "  先 commit / stash / 丢弃后再清理" >&2
    exit 1
fi

# 4. PR 状态（gh 可用时）
PR_STATE=""
if command -v gh >/dev/null 2>&1; then
    PR_STATE=$(gh pr list --head "$BRANCH" --state all --limit 1 \
        --json state --jq '.[0].state // ""' 2>/dev/null || true)
    case "$PR_STATE" in
        "")
            echo "WARN: no PR found for $BRANCH (skill 通常要求先 PR 再清理；继续 cleanup)" >&2
            ;;
        OPEN|MERGED)
            echo "ℹ️  PR state for $BRANCH: $PR_STATE" >&2
            ;;
        *)
            echo "ERROR: PR for $BRANCH is $PR_STATE; aborting cleanup" >&2
            echo "  CLOSED 状态需要用户确认（可能是放弃的 PR）；如确认要清理可用 git worktree remove --force" >&2
            exit 1
            ;;
    esac
else
    echo "WARN: gh CLI not available; PR 状态未验证，继续清理" >&2
fi

# 5. 主仓库路径（worktree 共享 .git，commondir 指向主仓库 .git 目录）
MAIN_GIT_DIR=$(git -C "$WT_DIR" rev-parse --git-common-dir)
MAIN_REPO=$(dirname "$MAIN_GIT_DIR")

# 6. 删 worktree
git -C "$MAIN_REPO" worktree remove "$WT_DIR" 2>&1
echo "✅ removed worktree: $WT_DIR"

# 7. 删本地工作分支
if git -C "$MAIN_REPO" rev-parse --verify --quiet "$BRANCH" >/dev/null 2>&1; then
    git -C "$MAIN_REPO" branch -D "$BRANCH" 2>&1
    echo "✅ deleted local branch: $BRANCH"
fi

# 8. 备份分支（PR MERGED 才删）
BACKUP="${BRANCH}-backup"
if git -C "$MAIN_REPO" rev-parse --verify --quiet "$BACKUP" >/dev/null 2>&1; then
    if [[ "$PR_STATE" == "MERGED" ]]; then
        git -C "$MAIN_REPO" branch -D "$BACKUP" 2>&1
        echo "✅ deleted backup branch (PR merged): $BACKUP"
    else
        echo "ℹ️  kept backup branch: $BACKUP (PR state: ${PR_STATE:-none}; merged 后可手动 git branch -D 清掉)"
    fi
fi

echo ""
echo "🎉 cleanup done. 远程分支 origin/$BRANCH 未动（PR 依赖；合并后由 GitHub 删）。"
