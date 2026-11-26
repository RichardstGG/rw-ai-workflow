# rw-ai-workflow

A Claude Code plugin for a three-agent workflow on GitHub issues, with every agent running as a herdr core (`hc`) terminal:

- **Claude** plans issues, verifies on the host, commits, pushes and opens draft PRs.
- **Antigravity** implements ordinary issues and **Codex** the ones that need it, each in its own git worktree; the dispatching Claude picks the worker and model per issue, and an issue moves to Codex after agy fails twice in a row.
- **Antigravity (agy)** reviews every PR and posts a comment (APPROVE → ready for review, otherwise draft); it can also implement on request. **Claude Sonnet** is the other fallback implementer.

Nothing is added to the project's git history. Everything the workflow keeps lives outside the repo:

```
~/projects/<Repo>/                   # main checkout (any path works)
~/worktree/<owner>__<repo>/issue-N/  # one worktree per issue, branch ai/issue-N
~/automation/
├── projects/<owner>__<repo>/        # config.sh, optional verify.sh
├── task-state/<owner>__<repo>/      # issue-N.env: worker, hc terminal names, worktree, PR
└── logs/<owner>__<repo>/issue-N/    # task files, review.diff, review.md
~/.config/herdr-core/templates/rw-*.md   # hc templates installed by setup
```

Override the roots with `RW_HOME` (default `~/automation`) and `RW_WORKTREES` (default `~/worktree`).
Inside the repo it only touches files git does not track: `.git/info/exclude` and `.claude/settings.local.json`.

## Requirements

`git`, `gh` (logged in), `python3`, `hc` (herdr core, server running), `codex` (logged in).
Optional: `agy` (reviews, agy work).

## Install

```
/plugin marketplace add RichardstGG/rw-ai-workflow
/plugin install rw-ai-workflow@rw-ai-workflow
```

Then, inside a repo: ask Claude to run **ai-setup**. It checks the tools, writes `~/automation/projects/<owner>__<repo>/config.sh`,
installs the `rw-*` hc templates, finds or drafts a verify script, and (with your OK) creates the `ai:*` labels.
Rerun ai-setup after a plugin update: the templates hold the plugin's scripts path.
Model and effort live in each template's `command` line; edit `~/.config/herdr-core/templates/rw-*.md` to change them.

## Start and watch

```
hc run --bg --name main --cwd ~/projects/<Repo> claude
hc attach main            # ctrl+\ detaches
```

`main` starts one issue Claude per dispatched issue (`<r>-N`), which starts its worker (`<r>-N-work`), verify (`<r>-N-verify`) and reviewer (`<r>-N-review`).
`<r>` is the repo name in lower case. Every terminal carries the labels `rw_repo`, `rw_issue`, `rw_role` and `rw_agent`:

```
hc ls --label rw_issue=101          # one issue's terminals
hc attach <r>-101-work              # watch or take over the worker
```

A terminal that waits for a person (a trust-this-folder prompt, a permission request) shows as `blocked`; Claude tells you which one to attach to.
claude asks once per new folder whether to trust it; trusting `~/worktree` once covers every worktree.
agy's trust does not cover subfolders, so `agy-launch.sh` adds each issue worktree to `trustedWorkspaces` in `~/.gemini/antigravity-cli/settings.json` (only paths under `~/worktree/<owner>__<repo>/issue-*`), and `cleanup.sh` removes the entry.

## Use

| You say | What happens |
|---|---|
| `開跑 #N` | agy or Codex (routed by complexity) implements issue N in `~/worktree/<owner>__<repo>/issue-N`, Claude runs verify on the host, pushes `ai/issue-N`, opens a draft PR, agy reviews |
| `開跑 #N agy` / `開跑 #N codex` / `開跑 #N claude` | Same, with that implementer (optionally `開跑 #N agy gemini-4-neon-xhigh` to pick the model) |
| `派工 #N #M` | From the main conversation: one issue Claude terminal per issue, each reporting back with one line |
| `PR #X 有 comment` | Claude turns your review comments into a fix brief for the same implementer |

If the implementer (agy or Codex) hits its usage limit, Claude stops and asks: the other implementer, Claude Sonnet, or wait.
You merge PRs yourself; the plugin's permissions deny `gh pr merge`, force pushes, `hc server *` and `hc send --force`.
Claude starts terminals only through `hc-spawn.sh` (which accepts only the workflow's own programs) and talks to them only through `hc-tell.sh`; raw `hc run` and `hc send` are not allowed, since they could run any command.

## Per-project verify

`scripts/verify.sh` runs, from the repo root, `~/automation/projects/<owner>__<repo>/verify.sh` or else the repo's own `scripts/ai/verify.sh`.
It should mirror the Linux-runnable part of CI and accept `--sandbox`, where steps needing sockets, D-Bus or the network print `ENV_LIMITED: skipped <step>` instead of running.

Example `config.sh` for a Flutter project whose tests need a local socket:

```bash
RW_BASE=main
RW_CODEX_NETWORK=true
RW_WRITABLE_ROOTS=("$HOME/.pub-cache" "$HOME/.dart-tool" "$HOME/.config/flutter" "$HOME/sdk/flutter")
RW_READ_ROOTS=("$HOME/.pub-cache" "$HOME/sdk/flutter")
```
