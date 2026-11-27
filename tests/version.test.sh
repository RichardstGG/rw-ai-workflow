. "$(dirname "$0")/helpers.sh"

# README must open with the plugin.json version, so a bump that skips the README fails here
want=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$S/../.claude-plugin/plugin.json")
check "README version matches plugin.json" "$(sed -n '3p' "$S/../README.md")" "**Version:** $want"

finish
