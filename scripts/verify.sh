#!/usr/bin/env bash
# usage: verify.sh [--sandbox]   (run inside a worktree) -- runs the project's verify script from its repo root.
# Lookup: $RW_HOME/projects/<owner>__<repo>/verify.sh, else <worktree>/scripts/ai/verify.sh.
# --sandbox: worker mode; the project script must skip socket/D-Bus/network steps and print ENV_LIMITED for them.
set -euo pipefail
. "$(dirname "$0")/lib.sh"; rw_load
root=$(git rev-parse --show-toplevel); v=$(rw_verify "$root")
cd "$root"; exec bash "$v" "$@"
