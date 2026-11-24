# rw-ai-workflow

A Claude Code plugin for a three-agent workflow on GitHub issues:

- **Claude** plans issues, verifies on the host, commits, pushes and opens draft PRs.
- **Codex** implements each issue in its own git worktree (via the openai-codex Claude Code plugin).
- **Antigravity (agy)** reviews every PR and posts a comment (APPROVE → ready for review, otherwise draft); it can also implement on request. **Cursor CLI** is an optional implementer.

Nothing is added to the project's git history. Everything the workflow keeps lives outside the repo:

```
~/projects/<Repo>/                  # main checkout (any path works)
~/worktrees/<owner>__<repo>/issue-N/  # one worktree per issue, branch ai/issue-N
~/automation/
├── projects/<owner>__<repo>/       # config.sh, optional verify.sh
├── task-state/<owner>__<repo>/     # issue-N.env: worker, job id, worktree, PR
└── logs/<owner>__<repo>/issue-N/   # prompts, worker output, agy logs
```

Override the roots with `RW_HOME` (default `~/automation`) and `RW_WORKTREES` (default `~/worktrees`).
Inside the repo it only touches files git does not track: `.git/info/exclude` and `.claude/settings.local.json`.

## Requirements

`git`, `gh` (logged in), `node`, `python3`, `codex` (logged in) and OpenAI's Codex plugin for Claude Code (`codex@openai-codex`; its `codex-companion.mjs` runs the jobs).
Optional: `agy` (reviews, agy work), `cursor-agent` (Cursor implementer).

## Install

```
/plugin marketplace add RichardstGG/rw-ai-workflow
/plugin install rw-ai-workflow@rw-ai-workflow
```

Then, inside a repo: ask Claude to run **ai-setup**. It checks the tools, writes `~/automation/projects/<owner>__<repo>/config.sh`,
finds or drafts a verify script, and (with your OK) creates the `ai:*` labels.

## Use

| You say | What happens |
|---|---|
| `開跑 #N` | Codex implements issue N in `~/worktrees/<owner>__<repo>/issue-N`, Claude runs verify on the host, pushes `ai/issue-N`, opens a draft PR, agy reviews |
| `開跑 #N cursor` | Same, with Cursor CLI as the implementer |
| `派工 #N #M` | From a planning conversation: one child session per issue (desktop app), or sequential dispatch (CLI) |
| `PR #X 有 comment` | Claude turns your review comments into a fix brief for the same implementer |
| `agy work` | Antigravity implements instead (edits only; Claude verifies and commits) |

If Codex hits its usage limit, Claude stops and asks: Cursor, Antigravity, a Claude subagent, or wait.
You merge PRs yourself; the plugin's permissions deny `gh pr merge` and force pushes.

## Per-project verify

`scripts/verify.sh` runs, from the repo root, `~/automation/projects/<owner>__<repo>/verify.sh` or else the repo's own `scripts/ai/verify.sh`.
It should mirror the Linux-runnable part of CI and accept `--sandbox`, where steps needing sockets, D-Bus or the network print `ENV_LIMITED: skipped <step>` instead of running.

Example `config.sh` for a Flutter project whose tests need a local socket:

```bash
RW_BASE=main
RW_CODEX_NETWORK=true
RW_WRITABLE_ROOTS=("$HOME/.pub-cache" "$HOME/.dart-tool" "$HOME/.config/flutter" "$HOME/sdk/flutter")
RW_READ_ROOTS=("$HOME/.pub-cache" "$HOME/sdk/flutter")
CODEX_MODEL=
CODEX_EFFORT=high
```
