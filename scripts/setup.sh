#!/usr/bin/env bash
# usage: setup.sh   (run inside the project's main checkout) -- idempotent; writes nothing that git tracks:
#   $RW_HOME/{logs,task-state,projects}/<owner>__<repo>, $RW_WORKTREES, a config.sh template,
#   .git/info/exclude entries, Claude permissions in .claude/settings.local.json, Codex trust for the repo,
#   and the rw-* hc templates in ~/.config/herdr-core/templates (rerun after a plugin update: they hold its scripts path).
# exit: 0 ok | 1 hc server not running
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd); T=$here/../templates
. "$here/lib.sh"; rw_load
hc server status >/dev/null 2>&1 || { echo "hc server is not running; start it with: hc server start" >&2; exit 1; }
cd "$RW_MAIN"
mkdir -p "$RW_PROJECT" "$RW_STATE" "$RW_LOGS" "$RW_WORKTREES"
if [ ! -f "$RW_PROJECT/config.sh" ]; then
  sed "s|__BASE__|$RW_BASE|" "$T/config.sh" > "$RW_PROJECT/config.sh"; echo "created $RW_PROJECT/config.sh"
fi

excl=$(git rev-parse --git-path info/exclude); mkdir -p "$(dirname "$excl")"
for p in .tmp/ .codex/ .claude/settings.local.json; do
  grep -qxF "$p" "$excl" 2>/dev/null || { echo "$p" >> "$excl"; echo "excluded $p"; }
done

# Claude permissions: merge (never remove the user's own rules)
mkdir -p .claude
python3 - "$T/settings.local.json" "$RW_SLUG" .claude/settings.local.json <<'P'
import json, os, sys
tpl, slug, p = sys.argv[1:]
new = json.loads(open(tpl).read().replace("__REPO__", slug))
old = json.load(open(p)) if os.path.exists(p) else {}
perm = old.setdefault("permissions", {})
for k in ("allow", "deny"):
    perm[k] = list(dict.fromkeys(perm.get(k, []) + new["permissions"][k]))
json.dump(old, open(p, "w"), indent=2, ensure_ascii=False); open(p, "a").write("\n")
P
python3 -m json.tool .claude/settings.local.json >/dev/null

# Codex resolves trust for a git worktree from its main repository, so trusting the main checkout covers $RW_WORKTREES.
cfg=~/.codex/config.toml
if [ -f "$cfg" ] && ! grep -qF "[projects.\"$RW_MAIN\"]" "$cfg"; then
  cp "$cfg" "$cfg.bak.rw-ai-workflow"
  printf '\n[projects."%s"]\ntrust_level = "trusted"\n' "$RW_MAIN" >> "$cfg"
  echo "codex trust added (backup: $cfg.bak.rw-ai-workflow)"
fi
# hc templates: __S__ -> this plugin's scripts dir; a locally changed copy is backed up before it is replaced
dst=$HOME/.config/herdr-core/templates; mkdir -p "$dst"
for f in "$T"/hc/*.md; do
  n=$(basename "$f"); new=$(sed "s|__S__|$here|g" "$f")
  if [ -f "$dst/$n" ] && [ "$(cat "$dst/$n")" == "$new" ]; then continue; fi
  if [ -f "$dst/$n" ]; then cp "$dst/$n" "$dst/$n.bak.rw-ai-workflow"; echo "backed up $dst/$n.bak.rw-ai-workflow"; fi
  printf '%s\n' "$new" > "$dst/$n"; echo "installed template ${n%.md}"
done
echo "setup OK: $RW_SLUG (base $RW_BASE); project dir $RW_PROJECT"
