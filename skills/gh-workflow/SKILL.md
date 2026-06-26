---
name: gh-workflow
description: GitHub CLI workflow for local commit batching, PR creation/update, and squash merge with strict message/body size limits and safety guardrails. Use when the user invokes or asks for /gh-commit, /gh-pr, /gh-pass, gh commit batching, pushing the current branch and creating a PR, updating an existing PR, waiting for PR checks, or squash-merging a PR with a concise final commit message.
---

# GitHub Workflow

Use this skill to run the repository's three GitHub workflows:

- `gh-commit`: analyze uncommitted changes, group them by logical unit, and create local commits only.
- `gh-pr`: push a clean feature branch and create or update a GitHub PR.
- `gh-pass`: wait for checks/review state, then squash-merge a PR with a rewritten concise squash commit.

## Workflow Selection

Read exactly one reference file for the requested operation:

- Local commit batching, "commit these changes", `/gh-commit`: read [references/gh-commit.md](references/gh-commit.md).
- Push/create/update PR, "open a PR", `/gh-pr`: read [references/gh-pr.md](references/gh-pr.md).
- Squash merge/pass PR, "merge this PR", `/gh-pass`: read [references/gh-pass.md](references/gh-pass.md).

If the user asks for an end-to-end GitHub flow, run the workflows in this order:

1. `gh-commit` for local commits when the working tree is dirty.
2. `gh-pr` after the working tree is clean.
3. `gh-pass` only after the user asks to merge or pass a PR.

## Shared Rules

Follow the selected reference file exactly for command sequence, size checks, and stopping conditions. These rules apply across all three workflows:

- Keep responsibilities separate: commits do not push or create PRs; PR creation does not merge; squash merge does not edit local code.
- Do not use `git add .`, `git add -A`, `--no-verify`, `--force`, `--force-with-lease`, `git pull`, `git merge`, `git rebase`, or `git reset --hard`.
- Do not write AI signatures such as `Generated with Claude Code` or `Co-Authored-By` unless the repository already requires them.
- Preserve the fixed option order shown in the reference files when asking the user to choose an action.
- Treat dirty worktrees, sensitive files, merge conflicts, failed CI, rejected pushes, and GitHub auth failures as stop-and-report conditions unless the selected reference explicitly allows a follow-up question.

## Size Limits

Always write temporary message/body files and check line and byte limits before running the final git or gh command:

- Commit messages: total message <= 9 lines and <= 1024 bytes; subject <= 70 characters.
- PR bodies: <= 100 lines and <= 10240 bytes.
- Squash merge bodies: <= 7 lines and <= 1024 bytes; final `git log -1 --format=%B` must stay under 10 lines.

If a generated message exceeds its limit, rewrite it before proceeding. Do not bypass the limit.

## Interaction Notes

The original command docs mention `AskUserQuestion`. In environments without that exact tool, ask the same question plainly in chat, preserving the option labels and order from the reference file.

After completing a workflow, report the exact commits, PR URL, merge result, or reason for stopping.
