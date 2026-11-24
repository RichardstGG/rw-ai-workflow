. "$(dirname "$0")/helpers.sh"

repo=$(mkrepo alice RoadScope); cd "$repo"
git branch ai/issue-101   # at origin/main, so it counts as merged
"$S/task-state.sh" 101 TERM_ISSUE=roadscope-101 >/dev/null
state=$HOME/automation/task-state/alice__RoadScope/issue-101.env

export HC_LS_OUT='{"terminals":[{"address":"t4","name":"roadscope-101","state":"live"},{"address":"t5","name":"roadscope-101-verify","state":"finished"}]}'
code=0; "$S/cleanup.sh" 101 >/dev/null 2>&1 || code=$?
log=$(cat "$STUB_LOG")
check "merged: exit 0" "$code" 0
check_has "lists only this repo's issue" "$log" "hc ls --all --json --label rw_repo=alice__RoadScope --label rw_issue=101"
check "kills only live terminals" "$(grep -c '^hc kill' <<<"$log")" 1
check_has "kills the live one" "$log" "hc kill t4"
check "removes every terminal" "$(grep -c '^hc rm' <<<"$log")" 2
check "state removed" "$([ -e "$state" ] && echo yes || echo no)" no

# Review Focus 5: nothing to clean in hc
git branch ai/issue-102; : > "$STUB_LOG"
code=0; HC_LS_OUT='{"terminals":[]}' "$S/cleanup.sh" 102 >/dev/null 2>&1 || code=$?
check "no terminals: exit 0" "$code" 0
check_lacks "no terminals: nothing killed or removed" "$(cat "$STUB_LOG")" "hc kill"

# not merged yet: leave its terminals and worktree alone
git switch -q -c ai/issue-103 && git commit -q --allow-empty -m wip && git switch -q main
mkdir -p "$T/wt103"; "$S/task-state.sh" 103 WORKTREE="$T/wt103" >/dev/null; : > "$STUB_LOG"
code=0; "$S/cleanup.sh" 103 >/dev/null 2>&1 || code=$?
check "unmerged: exit 1" "$code" 1
check_lacks "unmerged: terminals untouched" "$(cat "$STUB_LOG")" "hc kill"
check "unmerged: worktree kept" "$([ -d "$T/wt103" ] && echo yes || echo no)" yes

finish
