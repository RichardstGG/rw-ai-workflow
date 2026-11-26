#!/usr/bin/env bash
# usage: codex-launch.sh   (the command of the rw-codex hc template; runs inside the issue's worktree)
# Execs Codex as the worker. Model: the issue's WORK_MODEL in task state (ai-run sets it), else Codex's own default.
# The task is typed in by hc after Codex is ready. exit: execs codex | 3 codex not installed
set -euo pipefail
command -v codex >/dev/null || { echo "codex not found" >&2; exit 3; }
. "$(dirname "$0")/lib.sh"; rw_load
m=$(rw_work_model)
exec codex --no-daemon --sandbox workspace-write --ask-for-approval never ${m:+--model "$m"}
