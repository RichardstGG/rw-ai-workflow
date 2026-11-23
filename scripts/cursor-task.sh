#!/usr/bin/env bash
# usage: cursor-task.sh <worktree> <prompt-file> [timeout_s=3600]   -- Cursor CLI as the worker
# Runs in the foreground until Cursor exits (Claude launches it in the background), then prints the worker's final report.
# Never add --force: it runs commands outside the sandbox. With --sandbox enabled, shell commands auto-run with
# writes limited to the worktree and no network; the sandbox still allows git commit, so .cursor/cli.json denies it
# (written here if the repo has none; .cursor/ is excluded via .git/info/exclude by ai-setup).
# Model: account default, or $CURSOR_MODEL. Raw output goes to the issue's log dir.
# exit: 0 report printed | 1 Cursor failed/empty | 3 cursor-agent not installed | 124 timeout
set -euo pipefail
wt=$(cd "${1:?worktree}" && pwd); pf=${2:?prompt file}
bin=$(command -v cursor-agent) || { echo "cursor-agent not found" >&2; exit 3; }
. "$(dirname "$0")/lib.sh"; cd "$wt"; rw_load
n=$(basename "$wt"); n=${n#issue-}; out=$(rw_log_dir "$n")/cursor-out.json
if [ ! -f "$wt/.cursor/cli.json" ]; then
  mkdir -p "$wt/.cursor"
  printf '{\n  "permissions": {\n    "allow": [],\n    "deny": ["Shell(gh)", "Shell(git:commit*)", "Shell(git:push*)"]\n  }\n}\n' > "$wt/.cursor/cli.json"
fi
timeout "${3:-3600}" "$bin" -p --trust --sandbox enabled --workspace "$wt" --output-format json \
  ${CURSOR_MODEL:+--model "$CURSOR_MODEL"} "$(cat "$pf")" > "$out"
python3 - "$out" "${CURSOR_MODEL:-default}" <<'P'
import json, sys
j = json.load(open(sys.argv[1])); r = (j.get("result") or "").strip()
print("model:", sys.argv[2], "| session:", j.get("session_id"), "| error:", j.get("is_error"))
print(r)
sys.exit(1 if j.get("is_error") or not r else 0)
P
