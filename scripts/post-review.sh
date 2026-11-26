#!/usr/bin/env bash
# usage: post-review.sh PR_URL REVIEW_FILE [REVIEWER]   (run inside the PR's worktree)
# Posts the reviewer's file (written by the rw-agy-review terminal) as a PR comment; the reviewer itself never touches gh.
# Only when the last VERDICT line is APPROVE does it mark the draft PR ready for review; a missing verdict stays draft.
# REVIEWER is the label shown in the comment; default "Antigravity review（<model>）" from review.model beside REVIEW_FILE
#   (written by agy-launch.sh), or "Antigravity review" when that file is missing.
# exit: 0 posted (prints ready/draft) | 1 review file missing or blank (nothing posted)
set -euo pipefail
url=${1:?pr url}; review=${2:?review file}; reviewer=${3:-}
[ -f "$review" ] && grep -q '[^[:space:]]' "$review" || { echo "no review in $review; nothing posted" >&2; exit 1; }
if [ -z "$reviewer" ]; then
  m=$(cat "$(dirname "$review")/review.model" 2>/dev/null || true)
  reviewer="Antigravity review${m:+（$m）}"
fi
body=$(dirname "$review")/review-comment.md
printf '🤖 **%s**（`%s`，參考用）\n\n%s\n' "$reviewer" "$(git rev-parse --short HEAD)" "$(cat "$review")" > "$body"
gh pr comment "$url" --body-file "$body"
if [[ $(grep -oE 'VERDICT: *(APPROVE|CHANGES)' "$review" | tail -1) == *APPROVE ]]; then
  gh pr ready "$url" && echo "$reviewer: APPROVE -> marked ready for review"
else
  echo "$reviewer: not approved -> left as draft"
fi
