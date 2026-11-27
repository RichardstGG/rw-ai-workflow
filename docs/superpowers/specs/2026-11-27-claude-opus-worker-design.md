# Claude Opus worker — design (small change)

## Intent
One more implementer choice: Claude Opus, used only when the user names it. No routing change.

## Goals / non-goals
- Goal: "claude work" / "開跑 #N opus" runs the issue on Claude Opus at effort high, with the same worker rules and sandboxing as `rw-claude`.
- Non-goal: automatic routing to Opus; changing Sonnet's behaviour; per-issue model/effort override for Claude workers.
- Anti-goal: an Opus worker that can run git/gh/hc (it must stay as isolated as `rw-claude`).

## Approaches
- **A (picked):** new hc template `templates/hc/rw-claude-opus.md`, a copy of `rw-claude.md` with `claude --model opus --effort high ...`. `setup.sh` already installs every `templates/hc/*.md`.
- B: `claude-launch.sh` reading `WORK_MODEL` for `rw-claude`. More code for one extra option.
- Agent-tool subagent inside the issue Claude: inherits git/gh, runs outside the worker sandbox. Dropped.

## Decided
- `claude` / `sonnet` → Sonnet (`rw-claude`, unchanged). `claude work` / `opus` → Opus (`rw-claude-opus`).
- Opus is never picked without the user naming it. It is listed as an option when an implementer runs out of quota.
- Commit trailer `Implemented by Claude Opus via rw-ai-workflow`; PR body `Worker: Claude Opus`.

## Changes
- `templates/hc/rw-claude-opus.md` (new).
- `tests/templates.test.sh`, `tests/setup.test.sh`: add it to the template lists; assert its command; assert its body equals `rw-claude`'s so the two can't drift.
- `skills/ai-run/SKILL.md`: implementer list, routing triggers, quota menu, Implemented-by line, PR Worker line, description triggers.
- `skills/ai-setup/SKILL.md`, `README.md`: mention the template.
- Version bump `.claude-plugin/plugin.json` + README line 3 → 0.2.8.

## Left to the builder
Exact wording in the skill and README.
