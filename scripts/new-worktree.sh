#!/usr/bin/env bash
# usage: new-worktree.sh N [base-branch]   (run inside the main checkout) -> prints $RW_WORKTREES/<owner>__<repo>/issue-N
set -euo pipefail
. "$(dirname "$0")/lib.sh"; rw_load
n=${1:?issue number}; base=${2:-$RW_BASE}
wt=$RW_WT/issue-$n
mkdir -p "$RW_WT"
git fetch -q origin "$base"
if git rev-parse -q --verify "refs/heads/ai/issue-$n" >/dev/null; then
  git worktree add "$wt" "ai/issue-$n" >&2  # Apply review: reuse the existing branch
else
  git worktree add --no-track -b "ai/issue-$n" "$wt" "origin/$base" >&2
fi
if [ -f "$wt/.gitmodules" ]; then git -C "$wt" submodule update --init --recursive >&2; fi
touch "$wt/.write-test" && rm "$wt/.write-test"
# Codex reads sandbox settings from the worktree's .codex/config.toml (excluded via .git/info/exclude by ai-setup).
# Extra writable roots (SDKs, package caches) come from config.sh; the sandbox can write but not create them.
roots=()
for d in "${RW_WRITABLE_ROOTS[@]}"; do mkdir -p "$d"; roots+=("\"$d\""); done
mkdir -p "$wt/.codex"
printf '[sandbox_workspace_write]\nnetwork_access = %s\nwritable_roots = [%s]\nexclude_slash_tmp = true\nexclude_tmpdir_env_var = true\n' \
  "$RW_CODEX_NETWORK" "$(IFS=,; echo "${roots[*]}")" > "$wt/.codex/config.toml"
"$(dirname "$0")/task-state.sh" "$n" WORKTREE="$wt" BRANCH="ai/issue-$n" >/dev/null
echo "$wt"
