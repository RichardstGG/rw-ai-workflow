#!/usr/bin/env bash
# usage: cleanup.sh N   (run inside the main checkout, after the PR is merged)
# Once ai/issue-N is in origin/<base>: ends and removes the issue's hc terminals (labels rw_repo + rw_issue),
# removes the worktree (and its agy trust entry) and the local branch, closes the issue (drops ai:review), and deletes the task state. Logs are kept.
# Not merged yet (or squash-merged): touches nothing and exits 1.
set -euo pipefail
. "$(dirname "$0")/lib.sh"; rw_load
n=${1:?issue number}; cd "$RW_MAIN"
git fetch -q --prune
git merge-base --is-ancestor "ai/issue-$n" "origin/$RW_BASE" || {
  echo "ai/issue-$n is not in origin/$RW_BASE (squash merge, or not merged yet): nothing cleaned; delete with git branch -D if sure" >&2; exit 1; }
hc ls --all --json --label "rw_repo=${RW_SLUG/\//__}" --label "rw_issue=$n" |
  python3 -c 'import json,sys; [print(t["address"], t["state"]) for t in json.load(sys.stdin).get("terminals", [])]' |
  while read -r addr st; do
    if [ "$st" = live ]; then hc kill "$addr" >/dev/null; fi
    hc rm "$addr" >/dev/null
  done
# the recorded path wins, so worktrees made before the per-repo layout still get removed
wt=$(if [ -f "$RW_STATE/issue-$n.env" ]; then . "$RW_STATE/issue-$n.env"; fi; echo "${WORKTREE:-$RW_WT/issue-$n}")
if [ -d "$wt" ]; then git worktree remove "$wt"; fi
rw_agy_trust rm "$wt"
git branch -D "ai/issue-$n"
# a PR into a non-default base does not auto-close its issue; closing an already-closed one is harmless
{ gh issue close "$n" --repo "$RW_SLUG" --comment "Merged into $RW_BASE." >/dev/null &&
  gh issue edit "$n" --repo "$RW_SLUG" --remove-label ai:review >/dev/null; } ||
  echo "could not close issue #$n or drop ai:review; do it by hand" >&2
rm -f "$RW_STATE/issue-$n.env"
echo "cleaned issue-$n (logs kept in $RW_LOGS/issue-$n)"
