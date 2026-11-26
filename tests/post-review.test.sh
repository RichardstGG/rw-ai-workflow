. "$(dirname "$0")/helpers.sh"

repo=$(mkrepo alice RoadScope); cd "$repo"; mkdir -p .tmp/rw
url=https://github.com/alice/RoadScope/pull/7
sha=$(git rev-parse --short HEAD)
post() { : > "$STUB_LOG"; code=0; out=$("$S/post-review.sh" "$url" "$1" "Antigravity review（m1）" 2>&1) || code=$?; }

printf 'looks fine\nVERDICT: APPROVE\n' > .tmp/rw/review.md; post .tmp/rw/review.md
check "approve: exit 0" "$code" 0
check_has "approve: comments on the PR" "$(cat "$STUB_LOG")" "gh pr comment $url --body-file"
check_has "approve: marks ready" "$(cat "$STUB_LOG")" "gh pr ready $url"
check_has "approve: says so" "$out" "Antigravity review（m1）: APPROVE -> marked ready for review"
body=$(cat .tmp/rw/review-comment.md)
check_has "comment header names reviewer and commit" "$body" "🤖 **Antigravity review（m1）**（\`$sha\`，參考用）"
check_has "comment carries the review" "$body" "looks fine"

printf 'x.dart:3 bug\nVERDICT: APPROVE\nVERDICT: CHANGES\n' > .tmp/rw/review.md; post .tmp/rw/review.md
check_has "changes: comments" "$(cat "$STUB_LOG")" "gh pr comment"
check_lacks "changes (last verdict wins): stays draft" "$(cat "$STUB_LOG")" "gh pr ready"
check_has "changes: says draft" "$out" "left as draft"

printf 'no verdict here\n' > .tmp/rw/review.md; post .tmp/rw/review.md
check_has "no verdict: comments" "$(cat "$STUB_LOG")" "gh pr comment"
check_lacks "no verdict: stays draft" "$(cat "$STUB_LOG")" "gh pr ready"

printf ' \n\n' > .tmp/rw/review.md; post .tmp/rw/review.md
check "blank review: exit 1" "$code" 1
check_lacks "blank review: no comment" "$(cat "$STUB_LOG")" "gh pr comment"

printf 'ok\nVERDICT: APPROVE\n' > .tmp/rw/review.md; echo gemini-4-neon-medium > .tmp/rw/review.model
: > "$STUB_LOG"; out=$("$S/post-review.sh" "$url" .tmp/rw/review.md 2>&1)
check_has "no reviewer: title from review.model" "$(cat .tmp/rw/review-comment.md)" "🤖 **Antigravity review（gemini-4-neon-medium）**"
check_has "no reviewer: says so" "$out" "Antigravity review（gemini-4-neon-medium）: APPROVE"
rm .tmp/rw/review.model; out=$("$S/post-review.sh" "$url" .tmp/rw/review.md 2>&1)
check_has "no reviewer, no model file: plain title" "$(cat .tmp/rw/review-comment.md)" "🤖 **Antigravity review**（"

post .tmp/rw/missing.md
check "missing review: exit 1" "$code" 1
check_lacks "missing review: no comment" "$(cat "$STUB_LOG")" "gh pr comment"

finish
