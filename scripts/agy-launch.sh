#!/usr/bin/env bash
# usage: agy-launch.sh work|review [MODEL]   (the command of the rw-agy-* hc templates; runs inside the issue's worktree)
# Builds agy's per-session settings from $PWD, then execs agy interactively under --sandbox:
#   work   -> worktree read/write plus RW_READ_ROOTS read-only; the task is typed in by hc after agy is ready.
#   review -> writes origin/<base>...HEAD to $RW_LOGS/issue-N/review.diff, worktree read-only, and passes the review
#             prompt with -i; agy writes $RW_LOGS/issue-N/review.md. Both files sit outside the worktree because an agy
#             deny on the worktree also beats any allow under it, and agy's sandbox cannot reach a worktree's gitdir.
# Always denied: gh, git and hc (hc's messages invite an `hc send`, which would only stop at a permission prompt).
# models: work $AGY_WORK_MODEL (default gemini-4-argon-high), review $AGY_MODEL (default gemini-4-hydrogen-high).
# exit: execs agy | 1 empty diff (review) | 3 agy not installed | 64 usage
set -euo pipefail
mode=${1:-}; model=${2:-}
command -v agy >/dev/null || { echo "agy not found" >&2; exit 3; }
. "$(dirname "$0")/lib.sh"; rw_load
wt=$(git rev-parse --show-toplevel)
settings() { python3 -c 'import json,sys; a,d=json.loads(sys.argv[1]),json.loads(sys.argv[2]); print(json.dumps({"permissions": {"allow": a, "deny": d + ["command(gh)", "command(git)", "command(hc)"]}}))' "$1" "$2"; }
case "$mode" in
  work)
    allow=$(python3 -c 'import json,os,sys; w,*ro=sys.argv[1:]; print(json.dumps([f"read_file({w})", f"write_file({w})"] + [f"read_file({d})" for d in ro if d and os.path.isdir(d)]))' "$wt" "${RW_READ_ROOTS[@]}")
    exec agy --model "${model:-${AGY_WORK_MODEL:-gemini-4-argon-high}}" --sandbox --settings "$(settings "$allow" '[]')" ;;
  review)
    n=$(basename "$wt"); n=${n#issue-}; log=$(rw_log_dir "$n")
    git fetch -q origin "$RW_BASE"
    git diff "origin/$RW_BASE...HEAD" > "$log/review.diff"
    [ -s "$log/review.diff" ] || { echo "empty diff against origin/$RW_BASE" >&2; exit 1; }
    rm -f "$log/review.md"   # a stale review must not be posted for this run
    allow=$(python3 -c 'import json,sys; w,l=sys.argv[1:]; print(json.dumps([f"read_file({w})", f"read_file({l})", f"write_file({l})"]))' "$wt" "$log")
    prompt="You are reviewing a pull request. The full diff (origin/$RW_BASE...HEAD) is in $log/review.diff (absolute path); read it with your file-reading tool, then read surrounding code in $wt as needed.
Do not modify files in $wt and do not run commands (no git, gh or hc). Stay focused: read only the files the diff touches and their direct callers. Look for correctness bugs, security issues and missing tests; skip style nits.
Write your review to $log/review.md in Traditional Chinese (Taiwan) markdown: one-line verdict, then at most 8 findings as \`- path:line — issue\` (plain path, no links).
If there is nothing worth fixing, say so in one line.
End the file with exactly one last line: VERDICT: APPROVE if nothing must be fixed before merge, otherwise VERDICT: CHANGES. Then stop."
    exec agy --model "${model:-${AGY_MODEL:-gemini-4-hydrogen-high}}" --sandbox --add-dir "$log" \
      --settings "$(settings "$allow" "$(python3 -c 'import json,sys; print(json.dumps([f"write_file({sys.argv[1]})"]))' "$wt")")" -i "$prompt" ;;
  *) echo "usage: agy-launch.sh work|review [MODEL]" >&2; exit 64 ;;
esac
