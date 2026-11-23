#!/usr/bin/env bash
# Guard around codex-companion (from the openai-codex Claude Code plugin): only task/status/result;
# `task` must name its workspace and mode (companion treats unknown args such as --help as a prompt and runs a real job).
# Model/effort: --model/--effort args, else CODEX_MODEL/CODEX_EFFORT from env or the project's config.sh, else Codex's default.
set -euo pipefail
C="$(ls -d ~/.claude/plugins/cache/openai-codex/codex/*/ 2>/dev/null | sort -V | tail -1 || true)scripts/codex-companion.mjs"
[ -f "$C" ] || { echo "codex-companion not found: install the openai-codex plugin" >&2; exit 64; }
cmd=${1:-}; shift || true
case "$cmd" in
  task)
    case " $* " in *" --cwd "*|*" -C "*) ;; *) echo "task requires --cwd <worktree>" >&2; exit 64;; esac
    case " $* " in *" --write "*) ;; *) echo "task requires --write (otherwise sandbox is read-only)" >&2; exit 64;; esac
    cwd=; prev=; for a in "$@"; do case "$prev" in --cwd|-C) cwd=$a;; esac; prev=$a; done
    . "$(dirname "$0")/lib.sh"
    cfg=$(cd "$cwd" && rw_load && echo "${CODEX_MODEL:-}|${CODEX_EFFORT:-}")
    model=${cfg%|*}; effort=${cfg#*|}
    case " $* " in *" --model "*|*" -m "*) ;; *) if [ -n "$model" ]; then set -- --model "$model" "$@"; fi;; esac
    case " $* " in *" --effort "*) ;; *) if [ -n "$effort" ]; then set -- --effort "$effort" "$@"; fi;; esac ;;
  status|result) ;;
  *) echo "usage: companion.sh task|status|result ..." >&2; exit 64;;
esac
exec node "$C" "$cmd" "$@"
