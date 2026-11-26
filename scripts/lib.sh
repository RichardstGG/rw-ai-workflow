# Sourced by the other scripts. Everything the workflow keeps lives outside the project's git repo:
#   $RW_HOME/projects/<owner>__<repo>/config.sh   per-project settings (optional; see templates/config.sh)
#   $RW_HOME/projects/<owner>__<repo>/verify.sh   per-project verify (optional; else <repo>/scripts/ai/verify.sh)
#   $RW_HOME/task-state/<owner>__<repo>/issue-N.env   worker, job id, worktree, PR per issue
#   $RW_HOME/logs/<owner>__<repo>/issue-N/            prompts, worker output, agy logs
#   $RW_WORKTREES/<owner>__<repo>/issue-N              one git worktree per issue
RW_HOME=${RW_HOME:-$HOME/automation}
RW_WORKTREES=${RW_WORKTREES:-$HOME/worktree}

# owner/repo from the origin URL (git@host:o/r.git or https://host/o/r)
rw_slug() { git remote get-url origin | sed -E 's#\.git$##; s#^.*[:/]([^/]+/[^/]+)$#\1#'; }

# rw_load: run inside the main checkout or any of its worktrees
rw_load() {
  RW_MAIN=$(cd "$(git rev-parse --path-format=absolute --git-common-dir)/.." && pwd)
  RW_SLUG=$(rw_slug); local k=${RW_SLUG/\//__}
  RW_PROJECT=$RW_HOME/projects/$k; RW_STATE=$RW_HOME/task-state/$k; RW_LOGS=$RW_HOME/logs/$k; RW_WT=$RW_WORKTREES/$k
  RW_BASE=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || true)
  RW_BASE=${RW_BASE:-main}
  RW_CODEX_NETWORK=false; RW_WRITABLE_ROOTS=(); RW_READ_ROOTS=()
  if [ -f "$RW_PROJECT/config.sh" ]; then . "$RW_PROJECT/config.sh"; fi
}

# rw_short: the repo name as an hc terminal-name prefix (a-z 0-9 -, at most 20 chars); call after rw_load
rw_short() {
  local r; r=$(printf '%s' "${RW_SLUG#*/}" | tr A-Z a-z | sed -E 's/[^a-z0-9]+/-/g; s/^-+//')
  r=${r:0:20}; while [[ $r == *- ]]; do r=${r%-}; done
  echo "${r:-repo}"
}

# rw_verify <worktree>: path of the verify script to use
rw_verify() {
  if [ -f "$RW_PROJECT/verify.sh" ]; then echo "$RW_PROJECT/verify.sh"
  elif [ -f "$1/scripts/ai/verify.sh" ]; then echo "$1/scripts/ai/verify.sh"
  else echo "no verify script: add $RW_PROJECT/verify.sh (see ai-setup)" >&2; return 1; fi
}

# rw_log_dir N: per-issue log dir (created)
rw_log_dir() { mkdir -p "$RW_LOGS/issue-$1" && echo "$RW_LOGS/issue-$1"; }

# rw_work_model: the WORK_MODEL ai-run recorded for the issue whose worktree is $PWD (empty if none); call after rw_load
rw_work_model() {
  local n; n=$(basename "$(git rev-parse --show-toplevel)"); n=${n#issue-}
  ( WORK_MODEL=; if [ -f "$RW_STATE/issue-$n.env" ]; then . "$RW_STATE/issue-$n.env"; fi; echo "${WORK_MODEL:-}" )
}

# rw_agy_trust add|rm DIR: add DIR to (or drop it from) agy's trustedWorkspaces, keeping every other setting.
# agy's trust does not cover subfolders, so each issue worktree needs its own entry, or agy stops at a trust prompt.
rw_agy_trust() {
  python3 - "$1" "$2" "$HOME/.gemini/antigravity-cli/settings.json" <<'PY'
import json, os, sys
op, d, f = sys.argv[1:]
try:
    s = json.load(open(f))
except FileNotFoundError:
    if op == "rm": sys.exit(0)
    s = {}
t = [x for x in s.get("trustedWorkspaces", []) if x != d]
if op == "add": t.append(d)
s["trustedWorkspaces"] = t
os.makedirs(os.path.dirname(f), exist_ok=True)
with open(f + ".tmp", "w") as o: json.dump(s, o, indent=2)
os.replace(f + ".tmp", f)
PY
}
