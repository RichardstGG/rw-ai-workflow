. "$(dirname "$0")/helpers.sh"

repo=$(mkrepo alice RoadScope); cd "$repo"
wt=$T/wt/issue-7; git worktree add -q -b issue-7 "$wt"
ro=$T/sdk; mkdir -p "$ro"; mkdir -p "$HOME/automation/projects/alice__RoadScope"
echo "RW_READ_ROOTS=(\"$ro\" \"$T/missing\")" > "$HOME/automation/projects/alice__RoadScope/config.sh"
logs=$HOME/automation/logs/alice__RoadScope/issue-7
launch() { : > "$STUB_LOG"; code=0; out=$(cd "$wt" && "$S/agy-launch.sh" "$@" 2>&1) || code=$?; log=$(cat "$STUB_LOG"); }

launch work
check "work: exit 0" "$code" 0
check_has "work: writes worktree" "$log" "write_file($wt)"
check_has "work: reads RW_READ_ROOTS" "$log" "read_file($ro)"
check_lacks "work: skips missing roots" "$log" "$T/missing"
check_has "work: denies hc" "$log" "command(hc)"
check_has "work: default model" "$log" "--model gemini-4-argon-high"
check_has "work: sandboxed" "$log" "--sandbox"
check_lacks "work: task comes from hc, not -i" "$log" " -i "

launch review
check "review: empty diff exits 1" "$code" 1
check "review: empty diff does not start agy" "$log" ""

echo x > "$wt/a.txt"; git -C "$wt" add a.txt; git -C "$wt" commit -q -m a
echo stale > "$logs/review.md"
launch review
check "review: exit 0" "$code" 0
check_has "review: diff written outside the worktree" "$(cat "$logs/review.diff")" "a.txt"
check_has "review: worktree is read-only" "$log" "\"deny\": [\"write_file($wt)\""
check_has "review: log dir writable" "$log" "write_file($logs)"
check_has "review: denies hc" "$log" "command(hc)"
check_has "review: prompt names the review file" "$log" "-i You are reviewing"
check_has "review: prompt says where to write" "$log" "$logs/review.md"
check_has "review: default model" "$log" "--model gemini-4-hydrogen-high"
check "review: stale review removed" "$( [ -e "$logs/review.md" ] && echo kept || echo removed)" removed

launch review gemini-3.8-flash-high
check_has "review: model argument" "$log" "--model gemini-3.8-flash-high"

launch bogus
check "unknown mode: exit 64" "$code" 64

finish
