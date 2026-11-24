#!/usr/bin/env bash
# usage: hc-tell.sh N MESSAGE        (main Claude -> this repo's live issue Claude for issue N)
#        hc-tell.sh parent MESSAGE   (issue Claude -> the terminal that started it, i.e. the main Claude)
# The only way ai-run sends text into another terminal: raw `hc send` is not allowed, because it could type a
# command into any terminal and so get around the permission deny list.
# exit: 0 sent | 1 no such live terminal (start a new issue Claude) | 64 usage
set -euo pipefail
. "$(dirname "$0")/lib.sh"; rw_load
to=${1:-}; msg=${2:-}
[ -n "$msg" ] || { echo "usage: hc-tell.sh N|parent MESSAGE" >&2; exit 64; }
if [ "$to" = parent ]; then
  addr=$(hc get "${HC_TERMINAL_ID:?not inside an hc terminal}" --json | python3 -c 'import json,sys; print(json.load(sys.stdin).get("parent") or "")')
elif [[ $to =~ ^[0-9]+$ ]]; then
  addr=$(hc ls --json --label "rw_repo=${RW_SLUG/\//__}" --label "rw_issue=$to" --label rw_role=issue |
    python3 -c 'import json,sys; print(next((t["address"] for t in json.load(sys.stdin).get("terminals", []) if t.get("state") == "live"), ""))')
else
  echo "usage: hc-tell.sh N|parent MESSAGE" >&2; exit 64
fi
[ -n "$addr" ] || { echo "no live terminal for $to" >&2; exit 1; }
hc send "$addr" "$msg"
