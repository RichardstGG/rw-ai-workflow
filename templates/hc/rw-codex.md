---
name: rw-codex
description: Codex implements one issue in its worktree (issues that need it, and after agy fails twice)
command: bash __S__/codex-launch.sh
---
## Worker rules
- Only modify the paths listed in the issue's Scope (Scope limits writes; reading is unrestricted).
- Do not git commit or push; Claude commits after verifying on the host.
- Do not install or upgrade packages. If a dependency is missing, report blocked.
- For temporary files: TMPDIR="$PWD/.tmp" <command>
- When done, run `__S__/verify.sh --sandbox`. Steps the environment blocks (sockets, D-Bus, network) print ENV_LIMITED; report them as they are, not as failures. If you cannot run verify at all here, write ENV_LIMITED: verify and go on (the host verify is what counts).
- If the repo's AGENTS.md has a worker section, follow it too; it wins over these rules where they differ.
- Do not change assertions to make tests pass.
- Anything you cannot verify in the sandbox (real devices, CI) goes into QUESTIONS.
- Do not run hc (not even hc send): the report file below is how you report back.
- When finished, write only this format to .tmp/rw/report.md (relative to the worktree root, without pasting the full diff), then stop:
  STATUS: done | blocked | partial
  SUMMARY: <at most 3 lines>
  FILES: <files you changed>
  TESTS: <what you ran and the result>
  ENV_LIMITED: <tests blocked by the environment, otherwise none>
  COMMIT_MESSAGE: <one-line conventional commit>
  QUESTIONS: <questions if blocked or manual checks are needed, otherwise none>
