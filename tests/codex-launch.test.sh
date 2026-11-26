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

(cd "$wt" && "$S/task-state.sh" 7 WORK_MODEL= >/dev/null)
launch
check "cleared WORK_MODEL: Codex's own default" "$log" "codex --no-daemon --sandbox workspace-write --ask-for-approval never"

for bad in "--dangerously-bypass-approvals-and-sandbox" "exec x" "--model m"; do
  : > "$STUB_LOG"; code=0; (cd "$wt" && "$S/codex-launch.sh" $bad >/dev/null 2>&1) || code=$?
  check "refuses '$bad': usage error" "$code" 64
  check "refuses '$bad': codex not run" "$(cat "$STUB_LOG")" ""
done

code=0; (cd "$wt" && PATH=/usr/bin:/bin "$S/codex-launch.sh" >/dev/null 2>&1) || code=$?
check "codex missing: exit 3" "$code" 3

finish
