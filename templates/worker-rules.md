## Worker rules (Codex or Cursor CLI)
- Only modify the paths listed in the issue's Scope (Scope limits writes; reading is unrestricted).
- Do not git commit or push (.git is read-only in the sandbox).
- Do not install or upgrade packages. If a dependency is missing, report blocked.
- For temporary files: TMPDIR="$PWD/.tmp" <command>
- When done, run `__VERIFY__ --sandbox`. Steps the environment blocks (sockets, D-Bus, network) print ENV_LIMITED; report them as they are, not as failures.
- If the repo's AGENTS.md has a worker section, follow it too; it wins over these rules where they differ.
- Do not change assertions to make tests pass.
- Anything you cannot verify in the sandbox (real devices, CI) goes into QUESTIONS.
- Your final reply uses only this format, without pasting the full diff:
  STATUS: done | blocked | partial
  SUMMARY: <at most 3 lines>
  FILES: <files you changed>
  TESTS: <what you ran and the result>
  ENV_LIMITED: <tests blocked by the environment, otherwise none>
  COMMIT_MESSAGE: <one-line conventional commit>
  QUESTIONS: <questions if blocked or manual checks are needed, otherwise none>
