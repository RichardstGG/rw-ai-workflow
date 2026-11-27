. "$(dirname "$0")/helpers.sh"

repo=$(mkrepo alice RoadScope); cd "$repo"
dst=$HOME/.config/herdr-core/templates
run() { code=0; out=$("$S/setup.sh" 2>&1) || code=$?; }

HC_SERVER_RC=1 run
check "hc server down: exit 1" "$code" 1
check_has "hc server down: says so" "$out" "hc server start"
check "hc server down: no templates" "$(ls "$dst" 2>/dev/null)" ""

run
check "setup: exit 0" "$code" 0
check_has "hc server status checked" "$(cat "$STUB_LOG")" "hc server status"
for n in rw-codex rw-claude rw-claude-opus rw-agy-work rw-agy-review rw-agy-review-lite; do
  check "installed $n" "$( [ -f "$dst/$n.md" ] && echo yes)" yes
done
check_lacks "placeholder replaced" "$(cat "$dst"/*.md)" "__S__"
check_has "scripts path filled in" "$(cat "$dst/rw-agy-review.md")" "command: bash $S/agy-launch.sh review"
check_has "verify path filled in" "$(cat "$dst/rw-codex.md")" "$S/verify.sh --sandbox"
check_has "reports install" "$out" "installed template rw-codex"

run
check "rerun: no backups" "$(ls "$dst" | grep -c bak || true)" 0
check_lacks "rerun: nothing reinstalled" "$out" "installed template"

echo mine >> "$dst/rw-codex.md"; run
check_has "changed template: says backed up" "$out" "backed up"
check "changed template: backed up" "$(grep -c mine "$dst/rw-codex.md.bak.rw-ai-workflow")" 1
check_lacks "changed template: overwritten" "$(cat "$dst/rw-codex.md")" "mine"

p=.claude/settings.local.json
check "settings valid json" "$(python3 -m json.tool "$p" >/dev/null && echo ok)" ok
deny=$(python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))["permissions"]["deny"]))' "$p")
allow=$(python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))["permissions"]["allow"]))' "$p")
check_has "deny hc server" "$deny" "Bash(hc server *)"
check_has "deny hc send --force" "$deny" "Bash(hc send --force *)"
check_has "allow hc wait" "$allow" "Bash(hc wait *)"
check_lacks "no raw hc run (bypasses deny)" "$allow" "Bash(hc run"
check_lacks "no raw hc send (bypasses deny)" "$allow" "Bash(hc send"
check "exclude entries" "$(grep -v '^#' .git/info/exclude)" "$(printf '.tmp/\n.codex/\n.claude/settings.local.json')"
check_lacks "config template: no CODEX_MODEL" "$(cat "$HOME/automation/projects/alice__RoadScope/config.sh")" "CODEX_MODEL"

finish
