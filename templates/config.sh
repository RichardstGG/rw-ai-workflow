# Per-project settings for rw-ai-workflow, sourced by its scripts. Lives outside the repo.
# Use plain assignments (no `declare`/`local`): this file is sourced inside a function.

RW_BASE=__BASE__                 # base branch for worktrees and PRs

# Codex worker sandbox (written to each worktree's .codex/config.toml)
RW_CODEX_NETWORK=false           # true if tests need a local socket or the network (e.g. flutter test)
RW_WRITABLE_ROOTS=()             # extra dirs the worker may write, e.g. ("$HOME/.pub-cache" "$HOME/sdk/flutter")

# Antigravity worker: extra dirs it may read (not write), e.g. package caches to check library APIs
RW_READ_ROOTS=()

# Codex model/effort; leave empty for Codex's own default
CODEX_MODEL=
CODEX_EFFORT=
