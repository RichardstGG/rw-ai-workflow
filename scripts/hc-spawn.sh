#!/usr/bin/env bash
# usage: hc-spawn.sh N ROLE PROGRAM [TASK_FILE]   (run inside the main checkout or a worktree) -> prints the terminal name
# Starts one hc terminal for issue N, child of the caller's terminal:
#   ROLE issue  -> <r>-N         in the main checkout, --outlive-parent (survives the main Claude restarting)
#   ROLE work   -> <r>-N-work    in the issue's worktree
#   ROLE verify -> <r>-N-verify  in the issue's worktree, --no-notify (kept until read; remove with hc rm)
#   ROLE review -> <r>-N-review  in the issue's worktree
# PROGRAM is limited to the workflow's own programs, so allowing this script never allows arbitrary commands:
#   issue "claude --model sonnet" | work, review: an rw-* hc template | verify "bash <this dir>/verify.sh"
# TASK_FILE's content becomes the launch task (the agent's first message).
# Labels: rw_repo, rw_issue, rw_role, rw_agent. Task state gets TERM_<ROLE>=<name> (and WORKER for work).
# exit: 0 started | 1 hc run failed or the task was not delivered (state untouched) | 64 usage
set -euo pipefail
. "$(dirname "$0")/lib.sh"; rw_load
usage() { echo "usage: hc-spawn.sh N issue|work|verify|review PROGRAM [TASK_FILE]${1:+ ($1)}" >&2; exit 64; }
[ $# -ge 3 ] || usage
n=$1 role=$2 prog=$3 task=${4:-}
[[ $n =~ ^[0-9]+$ ]] || usage "N must be a number"
case "$role:$prog" in
  "issue:claude --model sonnet" | "verify:bash $(cd "$(dirname "$0")" && pwd)/verify.sh") ;;
  work:rw-* | review:rw-*) [[ $prog =~ ^rw-[a-z0-9-]+$ ]] || usage "not an rw-* template: $prog" ;;
  issue:* | work:* | verify:* | review:*) usage "program not allowed for $role: $prog" ;;
esac
read -ra argv <<<"$prog"
name=$(rw_short)-$n
args=(--bg --json --label "rw_repo=${RW_SLUG/\//__}" --label "rw_issue=$n" --label "rw_role=$role" --label "rw_agent=${argv[0]}")
case "$role" in
  issue) args+=(--outlive-parent --cwd "$RW_MAIN") ;;
  work|verify|review)
    name+=-$role
    wt=$(if [ -f "$RW_STATE/issue-$n.env" ]; then . "$RW_STATE/issue-$n.env"; fi; echo "${WORKTREE:-}")
    [ -n "$wt" ] && [ -d "$wt" ] || usage "no worktree recorded for issue $n; run new-worktree.sh $n"
    args+=(--cwd "$wt")
    if [ "$role" = verify ]; then args+=(--no-notify); fi ;;
  *) usage "unknown role $role" ;;
esac
if [ -n "$task" ]; then argv+=("$(cat "$task")"); fi
out=$(hc run --name "$name" "${args[@]}" "${argv[@]}") || exit 1
# A launch with a task must confirm delivery before we record it in task state.
if ! python3 -c '
import json
import sys

try:
    result = json.loads(sys.argv[1])
except ValueError:
    sys.exit(1)

if not isinstance(result, dict):
    sys.exit(1)
if not sys.argv[2] and "first_message" not in result:
    sys.exit(0)
message = result.get("first_message")
sys.exit(0 if isinstance(message, dict) and message.get("sent") is True else 1)
' "$out" "$task"; then
  echo "task not delivered to $name; run: hc read $name" >&2
  exit 1
fi
kv=(TERM_${role^^}="$name"); if [ "$role" = work ]; then kv+=(WORKER="${argv[0]}"); fi
"$(dirname "$0")/task-state.sh" "$n" "${kv[@]}" >/dev/null
echo "$name"
