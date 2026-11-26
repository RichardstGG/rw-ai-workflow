. "$(dirname "$0")/helpers.sh"

repo=$(mkrepo alice RoadScope); cd "$repo"
wt=$T/wt/issue-7; git worktree add -q -b issue-7 "$wt"
launch() { : > "$STUB_LOG"; code=0; (cd "$wt" && "$S/codex-launch.sh" >/dev/null 2>&1) || code=$?; log=$(cat "$STUB_LOG"); }

launch
check "no WORK_MODEL: exit 0" "$code" 0
check "no WORK_MODEL: Codex's own default" "$log" "codex --no-daemon --sandbox workspace-write --ask-for-approval never"

(cd "$wt" && "$S/task-state.sh" 7 WORK_MODEL=gpt-6.2-sol >/dev/null)
launch
check "WORK_MODEL: passed to codex" "$log" "codex --no-daemon --sandbox workspace-write --ask-for-approval never --model gpt-6.2-sol"

finish
