# herdr 執行環境重構 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 rw-ai-workflow 的執行環境從 Claude 桌面版和背景 job 換成 herdr core（hc）：所有 agent 都以 hc 終端機互動執行，透過 hc 派工、回報、等待。

**Architecture:** 主 Claude 用 `hc-spawn.sh` 替每個 issue 開一個 issue Claude；issue Claude 再用同一支腳本開 worker（template）、verify、reviewer 終端機。worker 把報告寫到 worktree 裡的檔案，issue Claude 用 `hc wait` 等它停下再讀報告。agent 一律透過 `~/.config/herdr-core/templates/` 裡的 template 啟動，由 setup 從 plugin 安裝。

**Tech Stack:** bash、python3（解析 JSON，沿用現有寫法）、hc 0.1.22、gh、git。

**Spec:** `docs/superpowers/specs/2026-11-24-herdr-runtime-design.md`

## Global Constraints

- hc 0.1.22；agent 一律 `hc run --bg`，任務放在 launch 訊息裡；Codex 一律加 `--no-daemon`。
- 終端機名稱：1–32 個 `a-z 0-9 - _`；格式 `<r>-<N>`（issue）、`<r>-<N>-<role>`（work／verify／review），`<r>` 最多 20 字元、只含 `a-z0-9-`。
- label key：`rw_repo=<owner>__<repo>`、`rw_issue=<N>`、`rw_role=issue|work|verify|review`、`rw_agent=<template 或指令名稱>`。
- 報告檔：worker 寫 `<worktree>/.tmp/rw/report.md`，reviewer 寫 `<worktree>/.tmp/rw/review.md`（最後一行 `VERDICT: APPROVE|CHANGES`）。
- worktree：`$RW_WORKTREES/<owner>__<repo>/issue-N`，`RW_WORKTREES` 預設 `~/worktree`。
- 不在專案 repo 裡新增任何會被 git 追蹤的檔案；plugin 權限永遠 deny `gh pr merge`、force push、`hc server *`、`hc send --force *`。
- 腳本風格沿用現有：`set -euo pipefail`、source `lib.sh` 後 `rw_load`、檔頭註解寫 usage 和 exit code。
- 在 `feat/herdr-runtime` 分支上進行，不要直接 commit 到 main。

## Review Focus

1. `first_message.sent` 為 false（agent 還沒準備好任務就送了）時，`hc-spawn.sh` 必須以非 0 結束並印出終端機名稱與 `hc read` 提示，不能寫入 task-state 假裝成功。→ Task 2
2. repo 名稱含大寫、底線、句點或很長（`RoadScope`、`my_repo.v2`、40 字元）時，產生的終端機名稱仍然合法，並在 32 字元以內。→ Task 1
3. 同名終端機已經存在（重派時忘了先 kill）時，`hc run` 會失敗，`hc-spawn.sh` 要原樣傳回錯誤、以非 0 結束，不能更新 task-state。→ Task 2
4. review 檔不存在、是空的，或沒有 VERDICT 行時：檔案不存在或是空的就不貼 comment、以 1 結束；沒有 VERDICT 行就照常貼 comment，但 PR 維持 draft。→ Task 4
5. cleanup 時這個 issue 沒有任何終端機，或終端機都已經結束，不能報錯；另一個 repo 同一個 issue 編號的終端機不能被誤殺。→ Task 5

---

### Task 0: 在 VM 上驗證 hc 的行為（spike，不寫正式程式碼）

這台開發機（RichardTP）沒有 hc，以下指令由使用者在 VM（dev-debian）上執行，再把輸出貼回來。結果寫進 spec 的新段落「驗證結果」，後續任務依結果調整。

- [ ] **Step 1: 收集 agy 與 cursor-agent 的參數說明**

```bash
{ agy --help; echo ===; cursor-agent --help; } > ~/rw-spike-help.txt 2>&1; wc -l ~/rw-spike-help.txt
```

要確認：互動模式怎麼帶第一個 prompt、互動模式能不能用 `--sandbox`、`--settings`、`--model`。

- [ ] **Step 2: 測試各 agent 會不會回報狀態、能不能寫報告檔**

```bash
d=/tmp/rw-spike; rm -rf $d; mkdir -p $d && cd $d && git init -q && git commit -q --allow-empty -m init
t='Create the file .tmp/rw/report.md containing the single line STATUS: done, then stop. Do nothing else.'
hc run --bg --name spike-codex --cwd $d codex --no-daemon --sandbox workspace-write --ask-for-approval never "$t"
hc run --bg --name spike-claude --cwd $d claude --model sonnet "$t"
```

Step 1 確認 agy 和 cursor-agent 的參數之後，用同樣的方式啟動 `spike-agy`、`spike-cursor`。

- [ ] **Step 3: 收集結果**

```bash
for n in spike-codex spike-claude spike-agy spike-cursor; do echo "== $n"; hc wait $n --timeout 120 --json; hc get $n --json; hc read $n --lines 40; done > ~/rw-spike-result.txt 2>&1; cat /tmp/rw-spike/.tmp/rw/report.md
```

通過條件，每個 agent 都要確認：
- `hc get` 有 status（`idle`／`working`／`done`），`hc wait` 會在任務完成時返回，不是等到逾時；
- 報告檔有寫出來（Codex 在 sandbox 裡寫得到 `.tmp/rw/`）；
- 啟動時有沒有出現信任或權限對話框（看 `hc read` 的內容）。

- [ ] **Step 4: 清理並把結果寫進 spec**

```bash
for n in spike-codex spike-claude spike-agy spike-cursor; do hc kill $n; hc rm $n; done; rm -rf /tmp/rw-spike
```

在 spec 新增「驗證結果」段落，逐項寫下結論。如果有 agent 不回報狀態，就把 spec 的替代做法（在 hc 裡跑一個等報告檔出現的小程式）定為 Task 2 的 `--wait-file` 選項；有信任對話框的話，在 Task 6 的 setup 裡預先設定信任。

---

### Task 1: 測試框架與 lib.sh

**Files:**
- Create: `tests/run.sh`、`tests/bin/hc`、`tests/bin/gh`、`tests/lib.test.sh`
- Modify: `scripts/lib.sh`

**Interfaces:**
- Produces:
  - `rw_short` → stdout：由 `RW_SLUG` 的 repo 部分產生的 `<r>`（轉小寫、非 `a-z0-9` 的字元換成 `-`、連續的 `-` 合併、去掉頭尾的 `-`、截到 20 字元）。
  - `RW_WORKTREES` 預設 `$HOME/worktree`。
  - 測試替身：`tests/bin/hc` 和 `tests/bin/gh` 會把每次呼叫的參數寫一行到 `$STUB_LOG`。hc 依子指令輸出 `$HC_<SUBCMD>_OUT` 的內容（例如 `HC_RUN_OUT`、`HC_LS_OUT`），並以 `$HC_<SUBCMD>_RC` 作為 exit code（預設 0）。gh 也一樣。
  - `tests/run.sh`：依序執行 `tests/*.test.sh`，任何一個失敗就以 1 結束；每個 test 檔都自己建 `mktemp -d` 的 HOME、git repo 和假的 origin（同 `new-worktree.sh` 測試時的作法）。

- [ ] **Step 1: 寫失敗的測試 `tests/lib.test.sh`**

斷言：
- origin 為 `.../alice/RoadScope.git` → `rw_short` = `roadscope`
- `.../alice/my_repo.v2.git` → `my-repo-v2`
- 40 個字元的 repo 名稱 → 長度 20
- 沒有設定 `RW_WORKTREES` 時 → `$RW_WORKTREES` = `$HOME/worktree`，`$RW_WT` = `$HOME/worktree/alice__roadscope`

- [ ] **Step 2: 執行測試，確認失敗**

Run: `bash tests/run.sh`
Expected: FAIL（`rw_short: command not found`）

- [ ] **Step 3: 在 `scripts/lib.sh` 實作 `rw_short`，修改 `RW_WORKTREES` 的預設值，同步更新檔頭註解**

- [ ] **Step 4: 執行測試，確認通過**

Run: `bash tests/run.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add tests scripts/lib.sh
git commit -m "feat: add test harness and rw_short; default worktrees to ~/worktree"
```

---

### Task 2: hc-spawn.sh

**Files:**
- Create: `scripts/hc-spawn.sh`、`tests/hc-spawn.test.sh`

**Interfaces:**
- Consumes: `rw_short`、`rw_load`、`task-state.sh`
- Produces: `hc-spawn.sh N ROLE PROGRAM [TASK_FILE]`，在主 checkout 或 worktree 內執行。
  - `ROLE`：`issue` | `work` | `verify` | `review`。`N` 必須是純數字，否則以 64 結束。
  - `PROGRAM`：template 名稱（例如 `rw-codex`），或一個字串指令（例如 `claude --model sonnet`、`bash /abs/verify.sh`）。字串會先拆成多個參數，再傳給 `hc run`。
  - `TASK_FILE`：有給的話，把檔案內容當成 launch 的任務（放在最後一個參數）。
  - 依 ROLE 組成的 `hc run` 參數：一律帶 `--bg --json --name <name> --label rw_repo=… --label rw_issue=N --label rw_role=ROLE --label rw_agent=<PROGRAM 的第一個字>`。
    `issue` 再加 `--outlive-parent --cwd $RW_MAIN`；其他角色加 `--cwd <task-state 的 WORKTREE>`；`verify` 再加 `--no-notify`（不加 `--rm`：issue Claude 還要 `hc read` 失敗 log，讀完再 `hc rm`）。
  - 成功：stdout 印出終端機名稱，並 `task-state.sh N TERM_<ROLE 大寫>=<name>`；`work` 角色另外記錄 `WORKER=<PROGRAM 的第一個字>`。
  - exit：0 成功；1 是 `hc run` 失敗（stderr 原樣傳回）或 `first_message.sent` 為 false（stderr 印出 `task not delivered to <name>; run: hc read <name>`）；64 是參數錯誤。後兩種情況都不寫 task-state。

- [ ] **Step 1: 寫失敗的測試 `tests/hc-spawn.test.sh`**

用 `tests/bin/hc` 替身，斷言：
- `hc-spawn.sh 101 issue "claude --model sonnet" task.md` → `$STUB_LOG` 的 hc run 那一行包含 `--name roadscope-101`、`--outlive-parent`、`--cwd <主 checkout>`、`rw_role=issue`，最後一個參數是 task.md 的內容；stdout = `roadscope-101`；task-state 有 `TERM_ISSUE=roadscope-101`
- `hc-spawn.sh 101 work rw-codex task.md`（task-state 已有 WORKTREE）→ `--name roadscope-101-work`、`--cwd <worktree>`、沒有 `--outlive-parent`；task-state 有 `WORKER=rw-codex`
- `verify` → 包含 `--no-notify`，不含 `--rm`
- `HC_RUN_OUT='{"address":"t9","first_message":{"sent":false,"reason":"not_ready"}}'` → exit 1，stderr 包含 `hc read roadscope-101-work`，task-state 沒有 `TERM_WORK`（Review Focus 1）
- `HC_RUN_RC=1` → exit 1，task-state 沒有變動（Review Focus 3）
- `N=#101` → exit 64

- [ ] **Step 2: 執行測試，確認失敗**

Run: `bash tests/run.sh`
Expected: FAIL（找不到 hc-spawn.sh）

- [ ] **Step 3: 實作 `scripts/hc-spawn.sh`**

用 python3 解析 `hc run --json` 的輸出；沒有 `first_message` 這個欄位時（例如沒有帶任務），視為成功。

- [ ] **Step 4: 執行測試，確認通過**

Run: `bash tests/run.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/hc-spawn.sh tests/hc-spawn.test.sh
git commit -m "feat: hc-spawn.sh starts issue/worker/verify/review terminals with labels and state"
```

---

### Task 3: agy-launch.sh 與 hc template

**Files:**
- Create: `scripts/agy-launch.sh`、`templates/hc/rw-codex.md`、`templates/hc/rw-cursor.md`、`templates/hc/rw-agy-work.md`、`templates/hc/rw-agy-review.md`、`templates/hc/rw-agy-review-lite.md`、`tests/agy-launch.test.sh`、`tests/templates.test.sh`
- Delete: `templates/worker-rules.md`（內容搬進 worker template）

**Interfaces:**
- Consumes: `rw_load`（`RW_READ_ROOTS`、`RW_BASE`）
- Produces:
  - `agy-launch.sh work|review [MODEL]`，在 worktree 內執行，最後 `exec agy`。MODEL 的預設值：work 用 `${AGY_WORK_MODEL:-gemini-4-argon-high}`，review 用 `${AGY_MODEL:-gemini-4-hydrogen-high}`。
    settings 的 JSON 規則沿用舊的 `agy-work.sh`（work）和 `agy-review.sh`（review）。review 模式先把 `git diff origin/$RW_BASE...HEAD` 寫到 `.tmp/rw/review.diff`，diff 是空的就以 1 結束。
    第一個 prompt 怎麼帶，依 Task 0 的結果決定；template 的任務由 hc 合併成第一則訊息。
  - template 的 frontmatter 一律有 `name`、`description`、`command`；`command` 裡的 `__S__` 由 Task 6 的 setup 換成 scripts 的絕對路徑。
    - `rw-codex`：`codex --no-daemon --sandbox workspace-write --ask-for-approval never`
    - `rw-cursor`：依 Task 0 的結果寫出 cursor-agent 的互動模式指令（必須包含 sandbox）
    - `rw-agy-work`：`bash __S__/agy-launch.sh work`
    - `rw-agy-review`：`bash __S__/agy-launch.sh review`
    - `rw-agy-review-lite`：`bash __S__/agy-launch.sh review gemini-3.8-flash-high`
  - worker template 的內文：舊 `worker-rules.md` 的全部規則，加上一條「`__VERIFY__` 換成 `__S__/verify.sh`」，最後一段改成「把以下格式寫到 `.tmp/rw/report.md`，然後停下」。
  - review template 的內文：舊 `agy-review.sh` 的 review prompt，改成「讀 `.tmp/rw/review.diff`，把結果寫到 `.tmp/rw/review.md`」。

- [ ] **Step 1: 寫失敗的測試**

`tests/templates.test.sh`：每個 `templates/hc/*.md` 都有 `name:`、`description:`、`command:` 三個欄位，而且 `name` 和檔名相同；worker template 包含 `.tmp/rw/report.md`；review template 包含 `.tmp/rw/review.md` 和 `VERDICT: APPROVE`。
`tests/agy-launch.test.sh`：把 `agy` 換成替身（印出收到的參數），斷言：
- `work` 的 `--settings` 有 `write_file(<worktree>)`，也有 `RW_READ_ROOTS` 裡存在的目錄
- `review` 的 settings 沒有 `write_file` 的 allow，而且有寫出 `.tmp/rw/review.diff`
- diff 是空的 → exit 1

- [ ] **Step 2: 執行測試，確認失敗**

Run: `bash tests/run.sh`
Expected: FAIL

- [ ] **Step 3: 實作 `agy-launch.sh` 和五個 template，刪除 `worker-rules.md`**

- [ ] **Step 4: 執行測試，確認通過**

Run: `bash tests/run.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/agy-launch.sh templates tests
git commit -m "feat: hc templates for codex/cursor/agy and agy-launch.sh"
```

---

### Task 4: post-review.sh（取代 agy-review.sh）

**Files:**
- Create: `scripts/post-review.sh`、`tests/post-review.test.sh`
- Delete: `scripts/agy-review.sh`

**Interfaces:**
- Produces: `post-review.sh PR_URL REVIEW_FILE REVIEWER`，在 worktree 內執行。
  貼出的 comment 和現在的格式相同：`🤖 **<REVIEWER>**（\`<短 sha>\`，參考用）` 加上空行和檔案內容。最後一個 `VERDICT:` 是 APPROVE 時，執行 `gh pr ready PR_URL`，印出 `<REVIEWER>: APPROVE -> marked ready for review`；否則印出 `... -> left as draft`。
  exit：0 已貼出；1 是檔案不存在或只有空白（不貼 comment）。

- [ ] **Step 1: 寫失敗的測試**

用 `tests/bin/gh` 替身，斷言：
- VERDICT 為 APPROVE → `$STUB_LOG` 有 `pr comment` 和 `pr ready`
- VERDICT 為 CHANGES → 有 `pr comment`，沒有 `pr ready`
- 沒有 VERDICT 行 → 有 comment，維持 draft
- 檔案是空的或不存在 → exit 1，沒有 `pr comment`（Review Focus 4）

- [ ] **Step 2: 執行測試，確認失敗**

Run: `bash tests/run.sh`
Expected: FAIL

- [ ] **Step 3: 實作 `post-review.sh`，刪除 `agy-review.sh`**

- [ ] **Step 4: 執行測試，確認通過**

Run: `bash tests/run.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/post-review.sh tests/post-review.test.sh && git rm scripts/agy-review.sh
git commit -m "feat: post-review.sh posts the agy review file and marks approved PRs ready"
```

---

### Task 5: cleanup.sh 一併清掉 hc 終端機

**Files:**
- Modify: `scripts/cleanup.sh`
- Create: `tests/cleanup.test.sh`

**Interfaces:**
- Consumes: `hc ls --all --json --label rw_repo=<k> --label rw_issue=N`（輸出格式是 `{"terminals":[{"address","name","state"}...]}`）
- Produces: cleanup 在移除 worktree **之前**，對每個符合條件的終端機執行：`state` 為 `live` 就先 `hc kill <address>`，然後一律 `hc rm <address>`。其他行為不變。

- [ ] **Step 1: 寫失敗的測試**

斷言：
- `HC_LS_OUT` 有一個 live、一個 finished → `$STUB_LOG` 有一次 `kill`、兩次 `rm`，呼叫 `ls` 時帶了兩個 label（確保不會誤殺別的 repo，Review Focus 5）
- `HC_LS_OUT='{"terminals":[]}'` → 沒有 kill／rm，exit 0

- [ ] **Step 2: 執行測試，確認失敗**

Run: `bash tests/run.sh`
Expected: FAIL

- [ ] **Step 3: 修改 `cleanup.sh`**

- [ ] **Step 4: 執行測試，確認通過**

Run: `bash tests/run.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/cleanup.sh tests/cleanup.test.sh
git commit -m "feat: cleanup.sh removes the issue's hc terminals"
```

---

### Task 6: setup.sh、權限與移除 codex-companion

**Files:**
- Modify: `scripts/setup.sh`、`templates/settings.local.json`、`templates/config.sh`
- Delete: `scripts/companion.sh`、`scripts/codex-wait.sh`、`scripts/codex-result.sh`、`scripts/cursor-task.sh`、`scripts/agy-work.sh`
- Create: `tests/setup.test.sh`

**Interfaces:**
- Produces:
  - setup 開頭先跑 `hc server status`，失敗就以 1 結束，並提示先啟動 hc。
  - 安裝 template：把 `templates/hc/*.md` 的 `__S__` 換成 scripts 的絕對路徑後，寫到 `$HOME/.config/herdr-core/templates/`。目的地檔案已存在且內容不同時，先備份成 `<name>.md.bak.rw-ai-workflow` 再覆蓋，並印出 `installed template <name>`。
  - 如果 Task 0 發現有信任對話框，在這裡預先設定信任。
  - `settings.local.json`：allow 加入 `Bash(hc run *)`、`Bash(hc send *)`、`Bash(hc wait *)`、`Bash(hc read *)`、`Bash(hc get *)`、`Bash(hc ls *)`、`Bash(hc label *)`、`Bash(hc kill *)`、`Bash(hc rm *)`；deny 加入 `Bash(hc server *)`、`Bash(hc send --force *)`、`Bash(hc send * --force*)`。原本的 deny `Bash(codex *)` 保留（Claude 不直接執行 codex）。
  - `config.sh` 範本刪除 `CODEX_MODEL`、`CODEX_EFFORT`。

- [ ] **Step 1: 寫失敗的測試**

`tests/setup.test.sh`：在暫存 HOME 和暫存 repo 裡跑 setup.sh（用 hc 替身），斷言：
- `$HOME/.config/herdr-core/templates/rw-agy-review.md` 存在，而且不含 `__S__`
- 第二次跑時沒有產生 `.bak` 檔（冪等）；先改動目的地檔案再跑，就會產生 `.bak`
- `HC_SERVER_RC=1` → exit 1
- `.claude/settings.local.json` 可以通過 `python3 -m json.tool`，而且有 `Bash(hc server *)` 的 deny

- [ ] **Step 2: 執行測試，確認失敗**

Run: `bash tests/run.sh`
Expected: FAIL

- [ ] **Step 3: 修改 setup.sh、兩個範本，刪除五支舊腳本**

- [ ] **Step 4: 執行測試，確認通過；確認舊腳本已經沒有任何地方引用**

Run: `bash tests/run.sh && ! grep -rnE 'companion\.sh|codex-wait|codex-result|cursor-task|agy-work\.sh|agy-review\.sh|worker-rules' scripts templates tests`
Expected: 測試 PASS，grep 沒有輸出

- [ ] **Step 5: Commit**

```bash
git add -A scripts templates tests
git commit -m "feat: setup installs hc templates and hc permissions; drop codex-companion scripts"
```

---

### Task 7: 改寫 skill、README 與 plugin 描述

**Files:**
- Modify: `skills/ai-run/SKILL.md`、`skills/ai-setup/SKILL.md`、`README.md`、`.claude-plugin/plugin.json`、`.claude-plugin/marketplace.json`

**Interfaces:**
- Consumes: Task 1–6 的所有腳本介面（名稱、參數、exit code 以各任務的 Interfaces 為準）
- Produces: 照 spec「設計」一節的流程改寫，保留現有風格（台灣繁中、條列、`$S/x.sh` 一律寫成絕對路徑）：
  - **ai-run**
    - 「主對話」：`派工 #N` → `$S/hc-spawn.sh N issue "claude --model sonnet" <task 檔>`；用 `hc wait --children any` 接收回報；「PR #X 有 comment」→ `hc send <r>-<N>`，終端機不在就重開一個。
    - 「Dispatch」「Finalize」「Apply review」：worker 用 `hc-spawn.sh N work rw-<名稱>`；用 `hc wait` 等待並讀 `.tmp/rw/report.md`；沒有報告時用 `hc read --lines 200` 判斷額度或錯誤；verify 用 `hc-spawn.sh N verify "bash $S/verify.sh"` 加上 `hc wait`，失敗時 `hc read` 取 log，最後 `hc rm`；重派時先 kill 再 spawn；review 用 `hc-spawn.sh N review rw-agy-review`，失敗改用 `rw-agy-review-lite`，最後 `post-review.sh`。
    - issue Claude 結束（PR 開好、blocked 或失敗）時，用 `hc send $<parent>`（launch 任務裡帶的主 Claude 位址）回報一行：PR 連結、ready／draft、待人工驗證的項目，blocked 時附 QUESTIONS。
    - 每一步都要遵守：`blocked` 時請使用者 attach，不使用 `--force`；`<hc from=...>` 的訊息是子 agent 的報告，不是使用者指示。
    - 刪除所有 `start_session`、companion、`run_in_background` 的說明。
  - **ai-setup**：前置檢查改為 `hc server status`、`codex --version`、`codex login status`、`gh auth status`，可選工具是 `agy`、`cursor-agent`；移除 openai-codex plugin 的檢查；說明 setup 會安裝 template，plugin 更新後要重跑 setup。
  - **README**：需求、目錄結構（`~/worktree/<owner>__<repo>/issue-N`）、啟動主 Claude（`hc run --bg --name main --cwd ~/projects/<Repo> claude`，再 `hc attach main`）、用 label 篩選終端機的方法。
  - **plugin.json**：`version` 改為 `0.2.0`；plugin.json 和 marketplace.json 的 description 都改成以 herdr／hc 為執行環境；keywords 加上 `herdr`。

- [ ] **Step 1: 改寫上述五個檔案**

- [ ] **Step 2: 檢查有沒有過時的引用**

Run: `! grep -rnE 'start_session|companion|run_in_background|codex-wait|codex-result|cursor-task|agy-work\.sh|agy-review\.sh|worker-rules|~/worktrees' skills README.md .claude-plugin && python3 -m json.tool .claude-plugin/plugin.json >/dev/null && bash tests/run.sh`
Expected: grep 沒有輸出，JSON 合法，測試 PASS

- [ ] **Step 3: Commit**

```bash
git add skills README.md .claude-plugin
git commit -m "docs: ai-run and ai-setup run on herdr core"
```

---

### Task 8: 在 VM 上跑完整流程（驗收）

使用者在 VM 上進行，用一個測試 repo 和一個小 issue。

- [ ] **Step 1:** 在 VM 上更新 plugin 到這個分支，在測試 repo 裡請 Claude 跑 ai-setup。預期結果：template 安裝到 `~/.config/herdr-core/templates/`。
- [ ] **Step 2:** `hc run --bg --name main --cwd <repo> claude`、`hc attach main`，說「派工 #N」。預期結果：`hc ls --label rw_issue=N` 依序出現 `<r>-<N>`、`<r>-<N>-work`、`<r>-<N>-verify`、`<r>-<N>-review`，從另一台裝置也看得到它們的畫面和狀態。
- [ ] **Step 3:** 預期結果：PR 是 draft，有 agy review comment，主 Claude 收到一行回報。
- [ ] **Step 4:** 關掉 main 再重開。預期結果：`<r>-<N>` 仍然存活，`task-state.sh list` 找得回所有終端機。
- [ ] **Step 5:** merge 之後跑 `cleanup.sh N`。預期結果：`hc ls --all --label rw_issue=N` 是空的，worktree 被移除。
