#!/usr/bin/env bash
# usage: task-state.sh N [KEY=VALUE ...]   -- records per-issue state, then prints it
#        task-state.sh list                -- one line per issue that has state
# Keys used by ai-run: WORKER WORK_MODEL WORKTREE BRANCH PR TERM_ISSUE TERM_WORK TERM_VERIFY TERM_REVIEW. Run inside the main checkout or a worktree.
set -euo pipefail
. "$(dirname "$0")/lib.sh"; rw_load
mkdir -p "$RW_STATE"
if [ "${1:-}" = list ]; then
  for f in "$RW_STATE"/issue-*.env; do [ -e "$f" ] && echo "$(basename "$f" .env): $(tr '\n' ' ' < "$f")"; done; exit 0
fi
n=${1:?issue number}; shift
f=$RW_STATE/issue-$n.env; touch "$f"
for kv in "$@"; do
  k=${kv%%=*}
  [[ $kv == *=* && $k =~ ^[A-Z_]+$ ]] || { echo "bad KEY=VALUE: $kv" >&2; exit 64; }
  grep -v "^$k=" "$f" > "$f.new" || true
  printf '%s=%q\n' "$k" "${kv#*=}" >> "$f.new"; mv "$f.new" "$f"
done
cat "$f"
