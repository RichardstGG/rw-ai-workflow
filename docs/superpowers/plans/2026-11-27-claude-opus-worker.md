# Claude Opus Worker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `rw-claude-opus`, a user-named-only implementer running Claude Opus at effort high.

**Architecture:** One new hc template beside `rw-claude`; `setup.sh` already installs every `templates/hc/*.md`. The rest is skill/README text.

**Tech Stack:** bash tests (`tests/run.sh`), hc templates, Markdown skills.

**Spec:** `docs/superpowers/specs/2026-11-27-claude-opus-worker-design.md`

## Global Constraints
- Command: `claude --model opus --effort high --permission-mode acceptEdits --disallowedTools "Bash(git:*)" "Bash(gh:*)" "Bash(hc:*)"`
- Triggers: `claude work` / `opus` → Opus; `claude` / `sonnet` → Sonnet (unchanged). Never routed to automatically.
- Trailer `Implemented by Claude Opus via rw-ai-workflow`; PR `Worker: Claude Opus`.
- Version 0.2.8 in `.claude-plugin/plugin.json` and README line 3.

## Review Focus
- Opus body drifting from the other worker bodies → pinned by `rw-claude-opus body = rw-codex body`.
- setup not installing the new file → pinned in `tests/setup.test.sh` list.
- "開跑 #N claude" silently switching to Opus → skill text keeps `claude` = Sonnet.

---

### Task 1: Template + tests
**Files:** Create `templates/hc/rw-claude-opus.md`; Modify `tests/templates.test.sh`, `tests/setup.test.sh`
- [ ] Add `rw-claude-opus` to both template loops; add `check "rw-claude-opus command"` with the exact command above and `check "rw-claude-opus body = rw-codex body"`.
- [ ] Run `bash tests/run.sh` → FAIL on rw-claude-opus checks.
- [ ] Create the template (name, description, command above, body copied from `rw-claude.md`).
- [ ] Run `bash tests/run.sh` → no `not ok`.

### Task 2: Docs + version
**Files:** Modify `skills/ai-run/SKILL.md`, `skills/ai-setup/SKILL.md`, `README.md`, `.claude-plugin/plugin.json`
- [ ] ai-run: implementer list, routing triggers, quota menu, Implemented-by line, PR Worker line, description triggers.
- [ ] ai-setup template list; README implementer line, trigger table, quota sentence.
- [ ] Bump to 0.2.8 in plugin.json and README line 3; `bash tests/run.sh` → no `not ok`.
- [ ] Commit, push, open PR.
