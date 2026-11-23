#!/usr/bin/env bash
# usage: agy-work.sh <worktree> <prompt-file> [timeout_s=1800]   -- Antigravity as the worker (edits only)
# Runs in the foreground until agy exits (Claude launches it in the background), then prints the worker's final report.
# agy runs headless and sandboxed: it may only read and write files inside <worktree>; every command is
# auto-denied in print mode (git and gh are denied explicitly, overriding the user's global agy grants).
# So agy never commits, pushes or runs tests: Claude runs verify.sh, commits and pushes afterwards.
# It may also read (not write) RW_READ_ROOTS from config.sh (e.g. SDKs, package caches) to check library APIs.
# resume: AGY_CONVERSATION=<id from the log's "Stream goroutine exited for <id>"> continues a timed-out run.
# model: $AGY_WORK_MODEL (default gemini-4-argon-high). No automatic fallback: on failure, ask the user.
# exit: 0 report printed | 1 agy failed/empty | 3 agy not installed | 124 timeout
set -euo pipefail
wt=$(cd "${1:?worktree}" && pwd); pf=${2:?prompt file}
command -v agy >/dev/null || { echo "agy not found" >&2; exit 3; }
. "$(dirname "$0")/lib.sh"; cd "$wt"; rw_load
n=$(basename "$wt"); n=${n#issue-}; log=$(rw_log_dir "$n")/agy-work.log
settings=$(python3 -c 'import json,os,sys; w,*ro=sys.argv[1:]; print(json.dumps({"permissions": {"allow": [f"read_file({w})", f"write_file({w})"] + [f"read_file({d})" for d in ro if d and os.path.isdir(d)], "deny": ["command(gh)", "command(git)"]}}))' "$wt" "${RW_READ_ROOTS[@]}")
model=${AGY_WORK_MODEL:-gemini-4-argon-high}
prompt="You are working in the repository at $wt (absolute path). Edit files only inside it.
You cannot run commands (no git, tests or builds); the caller verifies, commits and pushes.
Make the smallest change that fully fixes the task, keep the surrounding code style, and update or add tests for it.
End with a short report in Traditional Chinese (Taiwan): changed files, what you changed and why, anything left undone.

Task:
$(cat "$pf")"
out=$(timeout "${3:-1800}" agy -p "$prompt" --model "$model" ${AGY_CONVERSATION:+--conversation "$AGY_CONVERSATION"} --sandbox --settings "$settings" --print-timeout 0s --log-file "$log") || { rc=$?; echo "agy ($model) failed: rc=$rc (log: $log)" >&2; exit $(( rc == 124 ? 124 : 1 )); }
[[ -n ${out//[[:space:]]/} && $out != jetski:* ]] || { echo "agy ($model) returned nothing: $out (log: $log)" >&2; exit 1; }
echo "model: $model | log: $log"
printf '%s\n' "$out"
