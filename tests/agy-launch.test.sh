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
check_has "work: default model" "$log" "--model gemini-4-neon-high"
check_has "work: sandboxed" "$log" "--sandbox"
check_lacks "work: task comes from hc, not -i" "$log" " -i "

(cd "$wt" && "$S/task-state.sh" 7 WORK_MODEL=gemini-4-neon-medium >/dev/null)
launch work
check_has "work: WORK_MODEL from task state" "$log" "--model gemini-4-neon-medium"
launch work gemini-4-neon-xhigh
check_has "work: WORK_MODEL beats the template's model argument" "$log" "--model gemini-4-neon-medium"
(cd "$wt" && "$S/task-state.sh" 7 WORK_MODEL= >/dev/null)
launch work gemini-4-neon-xhigh
check_has "work: cleared WORK_MODEL falls back to the argument" "$log" "--model gemini-4-neon-xhigh"
WORK_MODEL=from-env launch work
check_has "work: exported WORK_MODEL ignored" "$log" "--model gemini-4-neon-high"
rm "$HOME/automation/task-state/alice__RoadScope/issue-7.env"

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
check_has "review: denies every command" "$log" "command(*)"
check_has "review: prompt names the review file" "$log" "-i You are reviewing"
check_has "review: prompt says where to write" "$log" "$logs/review.md"
check_has "review: default model" "$log" "--model gemini-4-neon-high"
check "review: records the model" "$(cat "$logs/review.model")" gemini-4-neon-high
check "review: stale review removed" "$( [ -e "$logs/review.md" ] && echo kept || echo removed)" removed

launch review gemini-4-neon-medium
check_has "review: model argument" "$log" "--model gemini-4-neon-medium"
check "review: records the argument model" "$(cat "$logs/review.model")" gemini-4-neon-medium
AGY_MODEL=m-env AGY_WORK_MODEL=w-env launch review
check_has "review: AGY_MODEL overrides" "$log" "--model m-env"
AGY_WORK_MODEL=w-env launch work
check_has "work: AGY_WORK_MODEL overrides" "$log" "--model w-env"

# trust: only worktrees under RW_WT/<owner>__<repo>/issue-N, once each, other settings kept
agyset=$HOME/.gemini/antigravity-cli/settings.json
check_lacks "trust: folder outside the worktree root not trusted" "$(cat "$agyset" 2>/dev/null)" "$wt"
mkdir -p "$(dirname "$agyset")"; echo '{"trustedWorkspaces":["/keep"],"theme":"x"}' > "$agyset"
wt2=$HOME/worktree/alice__RoadScope/issue-8; git worktree add -q -b issue-8 "$wt2"
(cd "$wt2" && "$S/agy-launch.sh" work >/dev/null 2>&1); (cd "$wt2" && "$S/agy-launch.sh" work >/dev/null 2>&1)
check "trust: worktree added once" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["trustedWorkspaces"])' "$agyset")" "['/keep', '$wt2']"
check_has "trust: other settings kept" "$(cat "$agyset")" '"theme": "x"'

launch bogus
check "unknown mode: exit 64" "$code" 64

finish
