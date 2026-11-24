. "$(dirname "$0")/helpers.sh"

repo=$(mkrepo alice RoadScope); cd "$repo"
tell() { : > "$STUB_LOG"; code=0; out=$("$S/hc-tell.sh" "$@" 2>&1) || code=$?; log=$(cat "$STUB_LOG"); }

HC_LS_OUT='{"terminals":[{"address":"t7","state":"live"}]}' tell 101 "PR #5 有 comment"
check "issue: exit 0" "$code" 0
check_has "issue: filters this repo" "$log" "--label rw_repo=alice__RoadScope"
check_has "issue: filters the issue" "$log" "--label rw_issue=101"
check_has "issue: filters the role" "$log" "--label rw_role=issue"
check_has "issue: sends to it" "$log" "hc send t7 PR #5 有 comment"

HC_LS_OUT='{"terminals":[{"address":"t7","state":"finished"}]}' tell 101 hi
check "issue gone: exit 1" "$code" 1
check_lacks "issue gone: nothing sent" "$log" "hc send"

HC_TERMINAL_ID=t9 HC_GET_OUT='{"address":"t9","parent":"t2"}' tell parent "#101 done"
check "parent: exit 0" "$code" 0
check_has "parent: looks itself up" "$log" "hc get t9"
check_has "parent: sends to parent" "$log" "hc send t2 #101 done"

HC_TERMINAL_ID=t9 HC_GET_OUT='{"address":"t9","parent":null}' tell parent x
check "no parent: exit 1" "$code" 1
check_lacks "no parent: nothing sent" "$log" "hc send"

tell bogus x; check "bad target: exit 64" "$code" 64
tell 101; check "no message: exit 64" "$code" 64

finish
