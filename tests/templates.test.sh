. "$(dirname "$0")/helpers.sh"

D=$(cd "$(dirname "$0")/../templates/hc" 2>/dev/null && pwd) || D=/nonexistent
field() { sed -n "s/^$2: *//p" "$1" | head -1; }
body() { awk 'n>=2; /^---$/{n++}' "$1"; }

for n in rw-codex rw-claude rw-agy-work rw-agy-review rw-agy-review-lite; do
  f=$D/$n.md
  check "$n: name matches file" "$( [ -f "$f" ] && field "$f" name)" "$n"
  check_has "$n: has description" "$( [ -f "$f" ] && field "$f" description)" " "
done
check "rw-codex command" "$(field "$D/rw-codex.md" command 2>/dev/null)" "codex --no-daemon --sandbox workspace-write --ask-for-approval never"
check "rw-claude command" "$(field "$D/rw-claude.md" command 2>/dev/null)" 'claude --model sonnet --permission-mode acceptEdits --disallowedTools "Bash(git:*)" "Bash(gh:*)" "Bash(hc:*)"'
check "rw-agy-work command" "$(field "$D/rw-agy-work.md" command 2>/dev/null)" "bash __S__/agy-launch.sh work"
check "rw-agy-review command" "$(field "$D/rw-agy-review.md" command 2>/dev/null)" "bash __S__/agy-launch.sh review"
check "rw-agy-review-lite command" "$(field "$D/rw-agy-review-lite.md" command 2>/dev/null)" "bash __S__/agy-launch.sh review gemini-4-neon-medium"

w=$(body "$D/rw-codex.md" 2>/dev/null)
check_has "worker body: writes the report file" "$w" ".tmp/rw/report.md"
check_has "worker body: verify path" "$w" "__S__/verify.sh --sandbox"
check_has "worker body: report format" "$w" "COMMIT_MESSAGE:"
check_has "worker body: no hc" "$w" "Do not run hc"
check_has "worker body: verify may be unavailable" "$w" "cannot run verify"
check_lacks "worker body: no sandbox claim about .git" "$w" "read-only in the sandbox"
check_lacks "worker body: no old placeholder" "$w" "__VERIFY__"
check "rw-claude body = rw-codex body" "$(body "$D/rw-claude.md" 2>/dev/null)" "$w"
check "rw-agy-work body = rw-codex body" "$(body "$D/rw-agy-work.md" 2>/dev/null)" "$w"
# review prompt is built by agy-launch.sh (it needs absolute paths); an empty body makes hc type nothing
check "rw-agy-review body empty" "$(body "$D/rw-agy-review.md" 2>/dev/null | tr -d '[:space:]')" ""
check "rw-agy-review-lite body empty" "$(body "$D/rw-agy-review-lite.md" 2>/dev/null | tr -d '[:space:]')" ""

finish
