#!/usr/bin/env bash
# usage: post-review.sh PR_URL REVIEW_FILE REVIEWER   (run inside the PR's worktree)
# Posts the reviewer's file (written by the rw-agy-review terminal) as a PR comment; the reviewer itself never touches gh.
# Only when the last VERDICT line is APPROVE does it mark the draft PR ready for review; a missing verdict stays draft.
# REVIEWER is the label shown in the comment, e.g. "Antigravity review（gemini-4-hydrogen-high）".
# exit: 0 posted (prints ready/draft) | 1 review file missing or blank (nothing posted)
set -euo pipefail
url=${1:?pr url}; review=${2:?review file}; reviewer=${3:?reviewer}
[ -f "$review" ] && grep -q '[^[:space:]]' "$review" || { echo "no review in $review; nothing posted" >&2; exit 1; }
body=$(dirname "$review")/review-comment.md
printf '🤖 **%s**（`%s`，參考用）\n\n%s\n' "$reviewer" "$(git rev-parse --short HEAD)" "$(cat "$review")" > "$body"
gh pr comment "$url" --body-file "$body"
if [[ $(grep -oE 'VERDICT: *(APPROVE|CHANGES)' "$review" | tail -1) == *APPROVE ]]; then
  gh pr ready "$url" && echo "$reviewer: APPROVE -> marked ready for review"
else
  echo "$reviewer: not approved -> left as draft"
fi
