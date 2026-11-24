. "$(dirname "$0")/helpers.sh"

repo=$(mkrepo alice RoadScope); cd "$repo"
state=$HOME/automation/task-state/alice__RoadScope/issue-101.env
echo "Implement issue 101" > "$T/task.md"
export HC_RUN_OUT='{"first_message":{"sent":true}}'
last_run() { grep '^hc run ' "$STUB_LOG" | tail -1; }

out=$("$S/hc-spawn.sh" 101 issue "claude --model sonnet" "$T/task.md")
run=$(last_run)
check "issue: prints the terminal name" "$out" roadscope-101
check_has "issue: name" "$run" "--name roadscope-101 "
check_has "issue: outlives its parent" "$run" "--outlive-parent"
check_has "issue: runs in the main checkout" "$run" "--cwd $repo "
check_has "issue: role label" "$run" "--label rw_role=issue"
check_has "issue: repo label" "$run" "--label rw_repo=alice__RoadScope"
check_has "issue: agent label is the program" "$run" "--label rw_agent=claude"
check_has "issue: program args then task last" "$run" "claude --model sonnet Implement issue 101"
check_has "issue: state records the terminal" "$(cat "$state")" "TERM_ISSUE=roadscope-101"

code=0; "$S/hc-spawn.sh" 101 work rw-codex "$T/task.md" >/dev/null 2>"$T/err" || code=$?
check "work without a worktree: usage error" "$code" 64

mkdir -p "$T/wt"; "$S/task-state.sh" 101 WORKTREE="$T/wt" >/dev/null
out=$("$S/hc-spawn.sh" 101 work rw-codex "$T/task.md"); run=$(last_run)
check "work: prints the terminal name" "$out" roadscope-101-work
check_has "work: runs in the worktree" "$run" "--cwd $T/wt "
check_lacks "work: ends with its parent" "$run" "--outlive-parent"
check_has "work: state records the worker" "$(cat "$state")" "WORKER=rw-codex"
check_has "work: state records the terminal" "$(cat "$state")" "TERM_WORK=roadscope-101-work"

HC_RUN_OUT='{}' "$S/hc-spawn.sh" 101 verify "bash $S/verify.sh" >/dev/null; run=$(last_run)
check_has "verify: no exit note" "$run" "--no-notify"
check_lacks "verify: kept for hc read" "$run" "--rm"
check_has "verify: no task appended" "$run" "bash $S/verify.sh"

# Review Focus 1: task not delivered
rm "$state"; "$S/task-state.sh" 101 WORKTREE="$T/wt" >/dev/null
code=0
HC_RUN_OUT='{"address":"t9","first_message":{"sent":false,"reason":"not_ready"}}' \
  "$S/hc-spawn.sh" 101 work rw-codex "$T/task.md" >/dev/null 2>"$T/err" || code=$?
check "undelivered task: exit 1" "$code" 1
check_has "undelivered task: says how to inspect" "$(cat "$T/err")" "hc read roadscope-101-work"
check_lacks "undelivered task: no state" "$(cat "$state")" "TERM_WORK"

before=$(cat "$state")
for response in '{"first_message":null}' 'not json' '[]' '{"first_message":{}}' '{"first_message":{"sent":"True"}}'; do
  code=0
  HC_RUN_OUT="$response" "$S/hc-spawn.sh" 101 work rw-codex "$T/task.md" >/dev/null 2>"$T/err" || code=$?
  check "$response: exit 1" "$code" 1
  check "$response: delivery hint" "$(cat "$T/err")" "task not delivered to roadscope-101-work; run: hc read roadscope-101-work"
  check "$response: state unchanged" "$(cat "$state")" "$before"
done

# Review Focus 3: hc run fails (e.g. name taken)
before=$(cat "$state"); code=0
HC_RUN_RC=1 "$S/hc-spawn.sh" 101 work rw-codex "$T/task.md" >/dev/null 2>&1 || code=$?
check "hc run fails: exit 1" "$code" 1
check "hc run fails: state unchanged" "$(cat "$state")" "$before"

code=0; "$S/hc-spawn.sh" '#101' issue claude >/dev/null 2>&1 || code=$?
check "non-numeric issue: usage error" "$code" 64
code=0; "$S/hc-spawn.sh" 101 boss claude >/dev/null 2>&1 || code=$?
check "unknown role: usage error" "$code" 64

# only the workflow's own programs: an allowed hc-spawn.sh must not run arbitrary commands
for bad in "work|gh pr merge 5" "verify|bash -c x" "issue|bash" "review|codex" "work|rw-codex; rm -rf x" "verify|bash /other/verify.sh"; do
  : > "$STUB_LOG"; code=0; "$S/hc-spawn.sh" 101 "${bad%%|*}" "${bad#*|}" >/dev/null 2>&1 || code=$?
  check "refuses ${bad%%|*} '${bad#*|}'" "$code" 64
  check "refuses ${bad%%|*} '${bad#*|}': no hc run" "$(grep -c '^hc run' "$STUB_LOG" || true)" 0
done
out=$(HC_RUN_OUT='{"address":"t9"}' "$S/hc-spawn.sh" 101 review rw-agy-review-lite)
check "review template allowed" "$out" roadscope-101-review
check_has "missing first_message: records the terminal" "$(cat "$state")" "TERM_REVIEW=roadscope-101-review"

finish
