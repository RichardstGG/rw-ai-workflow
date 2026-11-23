#!/usr/bin/env bash
# usage: cleanup.sh N   (run inside the main checkout, after the PR is merged)
# Removes the worktree and the merged local branch, prunes, and deletes the task state. Logs are kept.
set -euo pipefail
. "$(dirname "$0")/lib.sh"; rw_load
n=${1:?issue number}; cd "$RW_MAIN"
wt=$RW_WORKTREES/issue-$n
if [ -d "$wt" ]; then git worktree remove "$wt"; fi
git fetch -q --prune
if git merge-base --is-ancestor "ai/issue-$n" "origin/$RW_BASE"; then git branch -D "ai/issue-$n"
else echo "ai/issue-$n is not in origin/$RW_BASE (squash merge, or not merged yet): branch and state kept; delete with git branch -D if sure" >&2; exit 1; fi
rm -f "$RW_STATE/issue-$n.env"
echo "cleaned issue-$n (logs kept in $RW_LOGS/issue-$n)"
