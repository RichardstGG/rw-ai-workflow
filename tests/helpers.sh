# Sourced by tests/*.test.sh: a scratch HOME, hc/gh test doubles on PATH, repo fixtures and assertions.
set -euo pipefail
S=$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export HOME=$T/home STUB_LOG=$T/stub.log PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/bin" && pwd):$PATH"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset RW_HOME RW_WORKTREES
mkdir -p "$HOME"; : > "$STUB_LOG"
fails=0

# mkrepo OWNER NAME: a clone of a local bare origin (main, one commit); prints the clone's path
mkrepo() {
  local o=$T/remotes/$1/$2.git c=$T/$1-$2
  git init -q --bare -b main "$o"
  git clone -q "$o" "$c" 2>/dev/null
  git -C "$c" commit -q --allow-empty -m init
  git -C "$c" push -q origin main
  git -C "$c" remote set-head origin main
  echo "$c"
}

# check DESC ACTUAL EXPECTED
check() {
  if [ "$2" == "$3" ]; then echo "ok - $1"; else echo "not ok - $1: got '$2', want '$3'"; fails=$((fails + 1)); fi
}
# check_has DESC HAYSTACK NEEDLE / check_lacks DESC HAYSTACK NEEDLE
check_has() { if [[ $2 == *"$3"* ]]; then echo "ok - $1"; else echo "not ok - $1: '$3' not in '$2'"; fails=$((fails + 1)); fi; }
check_lacks() { if [[ $2 != *"$3"* ]]; then echo "ok - $1"; else echo "not ok - $1: '$3' found in '$2'"; fails=$((fails + 1)); fi; }

finish() { exit $((fails > 0)); }
