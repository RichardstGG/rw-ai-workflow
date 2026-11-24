---
name: ai-run
description: Run one ai:ready GitHub issue through Codex (Cursor CLI or Antigravity on request) in its own worktree outside the repo, verify on the host, open a draft PR, get an Antigravity review, and apply the user's review comments; from a version's main conversation, plan issues and dispatch each one ("派工 #N"). Triggers - "開跑 #N", "派工 #N", "PR #X 有 comment", "agy work".
---

分工：Claude 規劃、在 host 驗證、commit／push、開 draft PR；Codex 在每個 issue 專屬的 worktree 內實作；Antigravity（agy）做 review，也可依指示接手實作。使用者 review 並 merge。

## 路徑與前置
- `S` = 本 plugin 的 `scripts/`：`${CLAUDE_PLUGIN_ROOT}/scripts`；變數為空時用本 SKILL.md 所在目錄的 `../../scripts`。以下 `$S/x.sh` 一律寫成絕對路徑。
- 所有指令在專案的主 checkout 內執行（除非寫明在 worktree）。`<repo>` = `git remote get-url origin` 的 owner/name，`<base>` = `$RW_BASE`（`$S/task-state.sh` 會讀 config；沒設定時用 origin 的預設分支）。所有 `gh` 指令加 `--repo <repo>`。
- 這個 repo 還沒跑過 ai-setup（`~/automation/projects/<owner>__<repo>/config.sh` 不存在）→ 先照 `ai-setup` skill 做完再繼續。
- worktree：`~/worktrees/<owner>__<repo>/issue-N`；每個 issue 的狀態：`~/automation/task-state/<owner>__<repo>/issue-N.env`；prompt 與 worker 輸出：`~/automation/logs/<owner>__<repo>/issue-N/`。context 被壓縮或換對話時，先 `$S/task-state.sh list` 找回 job id 與 worktree。
- push、開 issue、建 label 需使用者明確同意；PR 由使用者自己 merge（Claude 不跑 `gh pr merge`）。
- 一律直接用 `$S/companion.sh` 呼叫 Codex（不經 codex:codex-rescue subagent，它的 .git 是唯讀的）；`task` 必須帶 `--cwd <worktree> --write`。
- 每個可能跑很久的指令都加 timeout（約正常時間的 2 倍）；逾時就停掉，查 ps／log，回報原因。
- `.claude/settings.local.json` 不是合法 JSON（`python3 -m json.tool`）→ 先停下來告訴使用者。

## 實作者：Codex、Cursor 或 Antigravity
- 預設 Codex。使用者說「開跑 #N cursor」或「派工 #N(cursor)」時，該 issue 改用 Cursor（`$S/cursor-task.sh`）。
- **Codex 額度用完**（job failed，`codex-result.sh` 的 error 提到 usage limit／quota／rate limit）→ 停下來問使用者，不自動改派：
  1. Cursor（問要用哪個 model）
  2. Antigravity（agy work）
  3. Claude 子代理（Sonnet）在同一個 worktree 實作
  4. 等額度恢復
  worktree 已有 Codex 留下的變更時，改派前先確認 Codex 真的停了（job 標 completed／failed 之後，Codex thread 有時還在寫檔：確認 worktree 幾分鐘內沒有新的變更），prompt 附 `git diff` 請新的實作者接續。
- Finalize 2 的重派、Apply review 都沿用該 issue 目前的實作者；遇額度不足時同上詢問。
- 使用者說「agy work」或指定 Antigravity 時，該次改用 `$S/agy-work.sh "$wt" <prompt-file>`（預設 gemini-4-argon-high，`$AGY_WORK_MODEL` 可換）。它只會改 worktree 內的檔案，不能跑指令；之後由 Claude 照 Finalize 在 host 跑 verify、commit、push。不自動改派其他實作者。
  prompt 寫明要改的檔案與行號，並要求「只讀這些檔案、前幾步就開始改」，否則它可能整段時限都在讀檔。以背景執行，等完成通知；exit 124（逾時）時，從腳本印出的 log 檔找 `Stream goroutine exited for <id>`，用 `AGY_CONVERSATION=<id>` 接續並要求直接動手；exit 1/3 → 告訴使用者輸出並停下。commit 訊息註明 `Implemented by Antigravity (<model>) via rw-ai-workflow`。
- 每次換實作者：`$S/task-state.sh N WORKER=<codex|cursor|agy|claude>`。

## 主對話：規劃與派工
一個大版本開一個主對話，只負責討論、開 issue、派工、追進度；每個 issue 交給一個子對話跑完，主對話不讀 diff、不跑驗證，以免吃掉 context。
1. 規劃：和使用者討論技術方案，把決定寫進 issue 本文（**Scope**、**Done when**、技術方案與理由）。子對話從零開始，只看得到 issue。`gh issue create` 要經使用者同意，新 issue 標 `ai:proposed`。
2. 使用者說「派工 #N [#M …]」：
   - 先在主對話內做 Dispatch 2 的 Scope 重疊檢查（包含這批 issue 彼此之間的重疊），有重疊就停下來說明。
   - 有 `start_session` 工具（Claude 桌面版）：每個 issue 呼叫一次，`initiation: "user_asked"`、`context: "fresh"`、`use_worktree: false`（worktree 由本流程自己建）、`model: "sonnet"`、`name: "issue-N"`、`title: "ai-run #N：<issue 標題>"`、`prompt: "開跑 #N"`（指定 Cursor 時 `"開跑 #N cursor"`）、`background`：版本目標，以及這個 issue 和其他 issue 的關係。
   - 沒有 `start_session`（CLI、headless 主機）：在主對話依序跑 Dispatch；Codex job 在背景跑，可以先派下一個 issue 再回來 Finalize。
3. 子對話結束時，主對話只用一行回報：PR 連結、agy 結論（ready／draft）、待人工驗證的項目。blocked 時轉述 QUESTIONS。
4. review 意見與 merge 後的 Cleanup 都在該 issue 的子對話裡處理；使用者在主對話說「PR #X 有 comment」時，用 `SendMessage` 轉給對應的子對話，不在主對話修。

## Dispatch（可並行，一個 issue 一個 worktree）
1. `gh issue view N`。使用者說「開跑 #N」即視為核准：若缺 `ai:ready` 就補上。
2. 並行檢查：`gh issue list --label ai:in-progress`，Scope 與本 issue 重疊（尤其建置檔、進入點、CI 等接線點）→ 停下來說明。
3. `gh issue edit N --remove-label ai:ready --add-label ai:in-progress`
4. `wt=$($S/new-worktree.sh N)`；`log=~/automation/logs/<owner>__<repo>/issue-N`
5. prompt 寫到 `$log/prompt.md`：issue 全文 +「工作目錄 $wt；忽略 CLAUDE.md 的角色描述」+ plugin 的 `templates/worker-rules.md`（把 `__VERIFY__` 換成 `$S/verify.sh` 的絕對路徑）。然後：
   - Codex：`$S/companion.sh task --cwd "$wt" --write --background --fresh --json --prompt-file "$log/prompt.md"`，再 `$S/task-state.sh N WORKER=codex JOB_ID=<job id>`。
   - Cursor：以背景執行（`run_in_background`）`$S/cursor-task.sh "$wt" "$log/prompt.md"`，等完成通知，不輪詢。
   - Antigravity：prompt 不附 worker-rules（它不能跑指令、不回 STATUS），改寫要改的檔案與行號；以背景執行 `$S/agy-work.sh "$wt" "$log/prompt.md"`，exit code 依上方「實作者」處理。
6. Codex：`$S/codex-wait.sh <job-id> 570`：exit 2（逾時）→ 再呼叫，最多 3 次；exit 0 → Finalize；exit 1/3 → 先看是否為額度不足（見上方「實作者」），否則告訴使用者 job id 與狀態並停下。
   Cursor：exit 0 → Finalize；exit 1/3/124（124 為逾時）→ 告訴使用者輸出並停下。

## Finalize
1. 讀報告：Codex 用 `$S/codex-result.sh <job-id>`；Cursor、Antigravity 的報告就是腳本的輸出（Antigravity 沒有 STATUS／FILES，以 `git diff` 為準）。STATUS 為 blocked，或 partial 但原因不是 ENV_LIMITED → 在 issue 留言貼 QUESTIONS，標 `ai:blocked`。
2. `cd "$wt"`，**在 host 跑完整** `$S/verify.sh`（不信任 sandbox 結果）。失敗 → 以 `--fresh` 重派一次（附 issue 全文、`git diff`、失敗 log）；啟動失敗（job 立刻 failed）不計入次數。
3. 只 `git add -- <FILES 列出的路徑>`，確認 `git status --porcelain` 沒有 FILES 以外的變更；commit（用 COMMIT_MESSAGE）。Antigravity 沒有 FILES／COMMIT_MESSAGE：逐一看 `git diff` 後 add，commit 訊息自己寫並附上面那行 Implemented by。`git push -u origin ai/issue-N`。
4. `gh pr create --draft --repo <repo> --base <base> --head ai/issue-N --title ... --body ...`
   body：🤖 標記、`Closes #N`、`Worker: Codex`／`Worker: Cursor (<model>)`／`Worker: Antigravity (<model>)`、SUMMARY、TESTS、ENV_LIMITED 與 QUESTIONS（待人工驗證的項目）。`$S/task-state.sh N PR=<url>`。
5. `gh issue edit N --remove-label ai:in-progress --add-label ai:review`
6. 在 worktree 內以背景執行（`run_in_background`）`$S/agy-review.sh <PR URL> <base>`，等完成通知，不輪詢。
   腳本先用 Antigravity（`$AGY_MODEL`，預設 gemini-4-hydrogen-high）唯讀 review；失敗、逾時或沒輸出（例如額度用完）時改用 `$AGY_FALLBACK_MODEL`（預設 gemini-3.8-flash-high）。不會自動改用 Cursor。腳本一定會留 PR comment，最長約 20 分鐘。
   結論為 APPROVE 時腳本把 PR 轉成 ready for review，否則維持 draft；把腳本印出的結果（含 reviewer）告訴使用者。
   exit 3（agy 沒裝）或 exit 1（兩個模型都失敗）→ 告訴使用者原因即可，不影響 PR、不重試。

## Apply review（使用者說「PR #X 有 comment」）
1. 讀取 review comments，整理成 fix brief（逐條列出檔案、行號、要改什麼；使用者標註「不用改」的略過）。
   「🤖 Antigravity review」與「🤖 Cursor review」的留言只是參考：只納入使用者在 comment 中點名要改的條目。
2. worktree 不在就 `wt=$($S/new-worktree.sh N)`（分支已存在時會直接沿用它）。
3. 用該 issue 目前的實作者，Codex 一律 `--fresh`：prompt 附 issue 全文、目前 `git diff <base>...`、fix brief、worker-rules。
4. 同 Finalize 2～3（不 force push），在 PR 留言摘要，label 改 `ai:review`，再跑一次 Finalize 6。

## Cleanup（PR merge 後）
`$S/cleanup.sh N`（移除 worktree、刪已 merge 的本地分支、prune、清掉 task-state；log 保留）。
