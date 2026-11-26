#!/usr/bin/env bash
# usage: codex-launch.sh   (the command of the rw-codex hc template; runs inside the issue's worktree)
# Execs Codex as the worker. Model: the issue's WORK_MODEL in task state (ai-run sets it), else ~/.codex/config.toml.
# Takes no arguments, so the allowed scripts/*.sh rule never lets Claude pass flags to codex (effort etc. go in
# ~/.codex/config.toml); Claude's settings also deny running it directly.
# The task is typed in by hc after Codex is ready. exit: execs codex | 3 codex not installed | 64 any argument
set -euo pipefail
[ $# -eq 0 ] || { echo "usage: codex-launch.sh (no arguments)" >&2; exit 64; }
command -v codex >/dev/null || { echo "codex not found" >&2; exit 3; }
. "$(dirname "$0")/lib.sh"; rw_load
m=$(rw_work_model)
exec codex --no-daemon --sandbox workspace-write --ask-for-approval never ${m:+--model "$m"}
