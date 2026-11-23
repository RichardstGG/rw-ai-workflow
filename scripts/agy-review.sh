#!/usr/bin/env bash
# usage: agy-review.sh <pr-url> <base-branch>   (run inside the PR's worktree; up to ~20 min, run it in the background)
# Antigravity reviews origin/<base>...HEAD headless and sandboxed: it may only read files in this worktree
# (anything else is auto-denied in print mode); this script, not agy, posts the PR comment and,
# only when the review ends with VERDICT: APPROVE, marks the draft PR ready for review.
# If the primary model fails, times out or returns nothing (e.g. quota used up), the fallback model reviews instead.
# The diff is precomputed because agy's sandbox cannot reach a worktree's gitdir.
# models: $AGY_MODEL (default gemini-4-hydrogen-high), then $AGY_FALLBACK_MODEL (default gemini-3.8-flash-high)
# exit: 0 posted (prints ready/draft), 1 both reviews failed/empty, 3 agy not installed
set -euo pipefail
url=${1:?pr url}; base=${2:?base branch}
command -v agy >/dev/null || { echo "agy not found; skipping review" >&2; exit 3; }
wt=$(git rev-parse --show-toplevel); cd "$wt"
git fetch -q origin "$base"
mkdir -p .tmp; diff=.tmp/agy-review.diff; trap 'rm -f "$diff"' EXIT
git diff "origin/$base...HEAD" > "$diff"
[ -s "$diff" ] || { echo "empty diff against origin/$base" >&2; exit 1; }
# deny overrides the user's global agy grants (e.g. command(gh), command(git push))
settings=$(python3 -c 'import json,sys; print(json.dumps({"permissions": {"allow": [f"read_file({sys.argv[1]})"], "deny": [f"write_file({sys.argv[1]})", "command(gh)", "command(git)"]}}))' "$wt")
prompt="You are reviewing a pull request. The full diff (origin/$base...HEAD) is in $wt/$diff (absolute path); read it with your file-reading tool, then read surrounding code in this directory as needed.
Do not modify files or run commands. Stay focused: read only the files the diff touches and their direct callers. Look for correctness bugs, security issues and missing tests; skip style nits.
Reply in Traditional Chinese (Taiwan) markdown: one-line verdict, then at most 8 findings as \`- path:line — issue\` (plain path, no links).
If there is nothing worth fixing, say so in one line.
End with exactly one last line: VERDICT: APPROVE if nothing must be fixed before merge, otherwise VERDICT: CHANGES."
valid() { [ -n "${1//[[:space:]]/}" ] && [[ $1 != jetski:* ]]; }
out=; reviewer=
# Cursor is never used automatically; a Cursor review only runs when the user asks for it.
for model in "${AGY_MODEL:-gemini-4-hydrogen-high}" "${AGY_FALLBACK_MODEL:-gemini-3.8-flash-high}"; do
  out=$(agy -p "$prompt" --model "$model" --sandbox --settings "$settings" --print-timeout 600s) || out=
  if valid "$out"; then reviewer="Antigravity review（$model）"; break; fi
  echo "agy ($model) failed or empty" >&2
done
[ -n "$reviewer" ] || { echo "no review produced: $out" >&2; exit 1; }
printf '🤖 **%s**（`%s`，參考用）\n\n%s\n' "$reviewer" "$(git rev-parse --short HEAD)" "$out" | gh pr comment "$url" --body-file -
# missing or unclear verdict counts as not approved
if [[ $(grep -oE 'VERDICT: *(APPROVE|CHANGES)' <<<"$out" | tail -1) == *APPROVE ]]; then
  gh pr ready "$url" && echo "$reviewer: APPROVE -> marked ready for review"
else
  echo "$reviewer: not approved -> left as draft"
fi
