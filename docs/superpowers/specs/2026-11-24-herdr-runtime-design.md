# rw-ai-workflow：從 Claude 桌面版改為以 herdr core（hc）為執行環境

日期：2026-11-24　狀態：待確認

## 目的

開發工作集中在固定的開發 VM（`dev-debian`），使用者從其他裝置透過 herdr 遙控並觀看。
目前的 plugin 依賴 Claude 桌面版（`start_session` 子對話）和背景 job（codex-companion、`agy -p`、`cursor-agent -p`），
這些 agent 都沒有終端機畫面，herdr 看不到。這次重構讓**所有 agent 都在 hc 終端機裡以互動模式執行、透過 hc 溝通**，
使用者在 herdr 能同時看到每個 agent 的即時畫面與狀態。

## 目標

- 角色不變：Claude 負責規劃、派工、在 host 驗證、commit／push、開 draft PR；Codex 負責實作；Antigravity（agy）負責 review。
- 每個 agent 都是一個 hc 終端機，用 label 標出 repo、issue、角色，可在 herdr 依 issue 查看。
- agent 之間的派工、回報、等待都透過 hc（`hc run`、`hc send`、`hc wait`、`hc read`），不再輪詢 job 檔。
- 要接新的 agent 時，只需新增一個 hc template，不用改流程。

## 非目標

- 不支援 Claude 桌面版的 `start_session` 路徑，也不保留沒有 hc 時的退路：hc 是必要條件。
- 移除 Cursor CLI 的支援（使用者決定）。Codex 額度用完時的選項改為：Antigravity（agy work）、Claude（`rw-claude` template，在 hc 裡當 worker）、等額度恢復。
- 不負責 herdr 的視窗排版（那是 `herdr-app` 的事）；使用者自己用 herdr app 或 `hc attach` 觀看。
- 使用者只觀看，不在流程中插話；需要人時（`blocked`）才 attach 處理。

## 反目標（做出來也算失敗的情況）

- 有 agent 在背景跑、herdr 上看不到。
- 主 Claude 結束或重開時，正在跑的 issue 一起被砍掉。
- 用 `hc send --force` 或其他方式繞過 agent 的權限確認。
- 從畫面文字推測成功：狀態一律看 hc 的 status，結果一律看報告檔和 verify 輸出。

## 限制（已在 VM 上確認，hc 0.1.22）

- `hc run --bg --name <n> --cwd <dir> --label k=v <cmd|template> [task]`：任務放在 launch 時一起送，送給還在啟動的 agent 可能會漏。
  launch 結果的 `first_message.sent` 為 false 時表示任務沒送出：先 `hc read` 再處理，不要盲目重送。
- 名稱在所有存活的終端機中必須唯一，格式為 1–32 個 `a-z 0-9 - _`。
- 子終端機預設會跟著父終端機一起結束；`--outlive-parent` 可以讓它繼續跑。
- 狀態來自程式送出的 OSC 7501（`idle`、`working`、`done`、`blocked`、`error`），一般程式沒有狀態，`hc wait` 會等到它結束。
- `hc wait <t>` 會在 agent 停止工作時返回；`reason: timeout`（預設 180 秒）只是定時回報，再 wait 一次即可。
- hc 會自動通知父終端機子終端機的狀況（blocked、error、exited）；回報訊息以 `<hc from="...">` 標記，視為子 agent 的報告，不是使用者指示。
- Codex 必須加 `--no-daemon`（template 也一樣），否則它的指令會跑到 hc 外面。
- template 放在 `~/.config/herdr-core/templates/<name>.md`，frontmatter 包含 `name`、`description`、`command`（含 model），內文是指示；
  hc 會把內文和 launch 的任務合併成第一則訊息。

## 做法比較

| 做法 | 內容 | 取捨 |
|---|---|---|
| A：單一 Claude 指揮 | 只有一個 Claude，替每個 issue 開 Codex 和 agy 終端機 | 終端機最少；但所有 issue 的報告和 verify 輸出都塞進同一個 context，平行 issue 一多就撐不住 |
| **B：每個 issue 一個 Claude（採用）** | 主 Claude 規劃與派工；每個 issue 由一個 Claude 跑完整流程，底下再開 Codex 和 agy | 一對一取代 `start_session` 子對話，保留 context 隔離；每個 issue 多一個 Claude，成本和現在相同 |
| C：worker 照舊在背景跑，只用 hc 顯示 log | 改動最小 | 不符合「所有 agent 進 herdr、透過 herdr 溝通」，已排除 |

使用者選 B。

## 設計

### 終端機結構

```
main                 claude（使用者自己啟動並 attach）            cwd: ~/projects/<Repo>
└─ <r>-<N>           claude --model sonnet「開跑 #N」 --outlive-parent  cwd: ~/projects/<Repo>
   ├─ <r>-<N>-work   實作者 template（預設 rw-codex）               cwd: worktree
   ├─ <r>-<N>-verify verify.sh（一般程式，讀完輸出後移除）               cwd: worktree
   └─ <r>-<N>-review rw-agy-review template                         cwd: worktree
```

- issue Claude 直接以 `claude --model sonnet "<任務>"` 啟動（和現在子對話用 Sonnet 一致），任務內容包含「開跑 #N」、版本目標，以及這個 issue 和其他 issue 的關係。
- verify 可能跑很久，照 hc 的建議在獨立終端機跑：`hc run --bg --no-notify --name <r>-<N>-verify ...`，再 `hc wait`；失敗時 `hc read` 取 log，讀完 `hc rm`。issue Claude 在等待期間仍收得到訊息，使用者也看得到 verify 的進度。

- `<r>` 是 repo 名稱轉小寫，只保留 `a-z0-9-`，最多 20 字元；`<N>` 是 issue 編號。名稱長度不會超過 32 字元。
- 每個終端機都加 label：`rw_repo=<owner>__<repo>`、`rw_issue=<N>`、`rw_role=main|issue|work|review`、`rw_agent=<template 名稱>`。
  使用者可以用 `hc ls --label rw_issue=101` 篩選。
- issue Claude 加 `--outlive-parent`：主 Claude 重開不會影響進行中的 issue。
  worker 和 reviewer 不加：issue Claude 結束時它們跟著結束，不會留下孤兒程式。
- 啟動主 Claude 的方式寫進 README：`hc run --bg --name main --cwd ~/projects/<Repo> claude`，然後 `hc attach main`。

### 溝通方式

- **往下派工**：任務一律放在 `hc run` 的 launch 訊息裡；之後的追加指示（例如重派、套用 review 意見）用 `hc send`。
- **worker 回報**：worker 把報告寫到 `<worktree>/.tmp/rw/report.md`，格式沿用現在的 STATUS／SUMMARY／FILES／TESTS／ENV_LIMITED／COMMIT_MESSAGE／QUESTIONS。
  issue Claude 用 `hc wait <r>-<N>-work` 等它停下，再讀報告檔。
  不依賴 worker 主動 `hc send`，因為 Codex 的 sandbox 不一定連得到 hc 的 socket；用檔案回報對任何 agent 都適用。
  wait 返回後如果沒有報告檔，就用 `hc read --lines 200` 看畫面判斷原因（額度用完、出錯、卡在對話框）。
- **reviewer 回報**：agy 把 review 寫到 `$RW_LOGS/issue-N/review.md`（在 worktree 外，見驗證結果第 4 項；格式沿用現在的 prompt，最後一行是 `VERDICT: APPROVE|CHANGES`）。
  由 issue Claude 呼叫 `scripts/post-review.sh <PR> <review 檔>` 貼 PR comment，結論是 APPROVE 時把 PR 轉為 ready。agy 本身不碰 gh 和 git。
- **issue Claude 回報主 Claude**：issue Claude 跑在 host 上，可以直接 `hc send <parent> "<一行結論>"`，內容是 PR 連結、ready／draft、待人工驗證的項目，blocked 時附 QUESTIONS。
  主 Claude 用 `hc wait --children any` 接收；hc 也會在 issue Claude blocked、error 或結束時自動通知主 Claude。
- **重派與套用 review**：verify 失敗要重派時，或套用 review 意見時，先 `hc kill`／`hc rm` 舊的 worker，再用新的 launch 任務啟動一個新的
  （附 issue 全文、`git diff`、失敗 log 或 fix brief），對應現在的 `--fresh`。
  使用者在主對話說「PR #X 有 comment」時，主 Claude 用 `hc send <r>-<N>` 轉給對應的 issue Claude；issue Claude 已經結束的話，就重新啟動一個並帶上這個任務。
- **review 失敗的替代方案**：`review.md` 沒有產生，或 reviewer 進入 error 狀態時，用 `$AGY_FALLBACK_MODEL` 重開一次 reviewer。兩次都失敗就告訴使用者，不影響 PR。
- **需要人的時候**：任何終端機變成 `blocked`，都由它的父 agent 讀畫面後在主對話告訴使用者，使用者 attach 處理。不使用 `--force`。

### 實作者與 template（接其他 agent 的方式）

plugin 新增 `templates/hc/`，`setup.sh` 會把裡面的檔案複製到 `~/.config/herdr-core/templates/`（已存在且內容不同時，先備份再覆蓋）。

| template | command | 用途 |
|---|---|---|
| `rw-codex` | `codex --no-daemon --sandbox workspace-write --ask-for-approval never` | 預設實作者 |
| `rw-claude` | `claude --model sonnet`（互動模式） | Codex 額度用完時改派 |
| `rw-agy-work` | `bash <S>/agy-launch.sh work`（互動模式） | `agy work` |
| `rw-agy-review` | `bash <S>/agy-launch.sh review`（互動模式） | 每個 PR 的 review |
| `rw-agy-review-lite` | `bash <S>/agy-launch.sh review gemini-4-neon-medium` | 主要模型 review 失敗時的替代方案 |

> 2026-11-26 起 agy 全部改用 Neon：work／review 預設 `gemini-4-neon-high`，`rw-agy-review-lite` 改為 `gemini-4-neon-medium`；review 標題的模型由 `agy-launch.sh` 寫入的 `review.model` 決定。

- template 是全域的，但 agy 的 `--settings` 要用到 worktree 的路徑，所以 agy template 改成呼叫 `scripts/agy-launch.sh`。
  它從 `$PWD` 算出 settings（work：worktree 可讀寫，再加上 `RW_READ_ROOTS` 可讀；review：worktree 唯讀），
  review 模式會先把 `git diff origin/<base>...HEAD` 寫到 `$RW_LOGS/issue-N/review.diff`（agy 的 sandbox 讀不到 worktree 的 gitdir），最後 `exec agy ... -i "<prompt>"`；work 模式不帶 `-i`，任務由 hc 打進去（見驗證結果第 5 項）。
  `<S>` 由 setup 在安裝 template 時換成 plugin `scripts/` 的絕對路徑。

- worker template 的內文就是現在的 `templates/worker-rules.md`，只把「最後回覆」改成「把報告寫到 `.tmp/rw/report.md`」。
- 任何 agent 只要符合以下約定，就能當實作者：在 hc 裡以互動模式執行、會送出 OSC 7501 狀態、完成時寫報告檔。
  `開跑 #N <名稱>` 會使用 `rw-<名稱>` 這個 template；換實作者、額度用完時的詢問流程都和現在一樣，只是換成另一個 template。
- model 與 effort：寫在 template 的 `command` 裡，要換就改 `~/.config/herdr-core/templates/` 裡的檔案。
  hc 沒有提供在 template 指令後面附加參數的方式，所以 `config.sh` 的 `CODEX_MODEL`／`CODEX_EFFORT` 刪除。
- Codex 的 sandbox 設定照舊：`new-worktree.sh` 寫入 worktree 的 `.codex/config.toml`。

### 狀態檔

`task-state/<owner>__<repo>/issue-N.env` 的 `JOB_ID` 改成 `TERM_ISSUE`、`TERM_WORK`、`TERM_REVIEW`（hc 的終端機名稱），`WORKER` 改記 template 名稱。
換對話或 context 被壓縮時，用 `task-state.sh list` 加上 `hc ls --label rw_repo=...` 就能找回所有終端機。

### worktree 路徑

`RW_WORKTREES` 的預設值改為 `~/worktree`，實際路徑是 `~/worktree/<owner>__<repo>/issue-N`。
保留 owner/repo 這層目錄，兩個 repo 才能同時跑同一個 issue 編號。
舊路徑的 worktree 由 `cleanup.sh` 依 task-state 記錄的路徑清除（已支援）。

### 檔案異動

| 檔案 | 異動 |
|---|---|
| `scripts/companion.sh`、`codex-wait.sh`、`codex-result.sh` | 刪除（不再依賴 openai-codex plugin 的 codex-companion） |
| `scripts/cursor-task.sh` | 刪除（不再支援 Cursor） |
| `scripts/agy-work.sh` | 刪除，改由 template 呼叫 `agy-launch.sh` 啟動 |
| `scripts/agy-launch.sh`（新增） | 依模式產生 agy settings、review 前先算 diff，再 `exec agy` |
| `scripts/agy-review.sh` | 改為 `post-review.sh`：只負責貼 comment、判斷 VERDICT、`gh pr ready` |
| `scripts/hc-spawn.sh`（新增） | 統一處理名稱、label、cwd、`--outlive-parent`、model 參數，並檢查 `first_message.sent`；印出終端機名稱 |
| `scripts/cleanup.sh` | 再加上 `hc kill` 和 `hc rm` 這個 issue 的終端機（只處理有 `rw_issue=N` label 的） |
| `scripts/setup.sh` | 安裝 hc template；檢查 `hc server status`；Codex 信任設定照舊 |
| `scripts/lib.sh` | `RW_WORKTREES` 的預設值改為 `~/worktree`；新增產生 `<r>` 的函式 |
| `templates/hc/*.md`（新增） | 五個 template |
| `templates/config.sh` | 刪除 `CODEX_MODEL`、`CODEX_EFFORT` |
| `templates/worker-rules.md` | 併入 worker template 後刪除 |
| `templates/settings.local.json` | allow 加入 `hc run/send/wait/read/get/ls/label/kill/rm`；deny 加入 `hc server *`、`hc send --force *`；移除 companion 相關規則 |
| `skills/ai-run/SKILL.md` | 改寫「主對話」「Dispatch」「Finalize」「Apply review」「Cleanup」，換成 hc 的流程 |
| `skills/ai-setup/SKILL.md` | 前置檢查改成 `hc`、`codex`、`agy`；移除 openai-codex plugin 的檢查 |
| `README.md` | 改寫需求、安裝、啟動主 Claude 與觀看方式 |

## 交給實作者的部分

- 下面的驗證項目要**先在 VM 上用一次性的小實驗確認**，再寫正式程式碼；確認結果寫回這份文件：
  1. `hc ls` 時 codex、claude、agy 有沒有送出狀態（`get` 的 status 不為空）。
     沒有狀態的 agent，`hc wait` 會一直等到它結束：這種情況改成在 hc 裡跑一個等報告檔出現的小程式，再 `hc wait` 那個程式。
  2. agy 的互動模式是否支援目前 `-p` 模式用的 `--sandbox`、`--settings` 等參數。
  3. Codex 在 `workspace-write` sandbox 下能不能寫 `.tmp/rw/`（應該可以，`.tmp/` 在 worktree 內）。
  4. 第一次在 worktree 啟動 Codex 時會不會跳出信任對話框（skill 提到可能要 `hc keys <t> down enter`）；跳出的話，由 hc-spawn.sh 處理，或在 setup 時就設定信任。
- `hc-spawn.sh` 的參數設計、名稱和 label 的細節、template 的確切內文。
- SKILL.md 的寫法照現有風格（台灣繁中、條列、指令寫成絕對路徑）。

## 驗證結果（Task 0，2026-11-24，dev-debian，hc 0.1.22、agy 1.5.16、Claude Code 2.1.331）

1. **狀態回報**：codex、claude、agy 都會送出狀態，`hc wait` 在工作完成時以 `status: done`、`turn: 1` 返回，不需要 `--wait-file`。
   - 例外：程式剛啟動、還沒開始第一個 turn 時是 `idle`、`turn: 0`，`hc wait` 會立刻返回（`agy -i` 啟動後會先 idle 十幾秒）。
     所以 wait 返回時如果 `turn` 是 0 而且 status 是 `idle`，代表還沒開始，要再 wait 一次。
   - codex 停在信任對話框時 status 是空的；claude 和 agy 會回報 `blocked`（`kind: permission`, `msg: trust this folder`）。
2. **第一次執行的對話框**（上一輪 120 秒沒寫出報告的原因）：codex 停在「Trust this folder?」，claude 停在首次啟動的主題選擇（這台機器當時還沒完成 Claude Code 的初始設定）。按掉之後三者都在 10 秒內寫出 `.tmp/rw/report.md`。
   - codex：`setup.sh` 已經把主 repo 設為信任，worktree 會沿用（維持現狀）。
   - claude：信任父目錄就涵蓋子目錄。README 請使用者第一次使用 `rw-claude` 前，在 `~/worktree` 啟動一次 claude 並選擇信任。
   - agy：信任記在 `~/.gemini/antigravity-cli/settings.json` 的 `trustedWorkspaces`，**不會**涵蓋子目錄，每個新 worktree 都會跳一次。
     使用者後來決定自動信任：`agy-launch.sh` 只把 `$RW_WT/issue-*` 加進 `trustedWorkspaces`（agy 一律在 `--sandbox` 下跑，且禁止 git、gh、hc），`cleanup.sh` 移除 worktree 時一併拿掉這一筆。
3. **Codex 的 sandbox**：`workspace-write` 下可以寫 `.tmp/rw/`。
4. **agy 互動模式**：`agy -i "<task>"` 可以和 `--sandbox`、`--settings`、`--model`、`--add-dir` 一起用。位置參數當 prompt 會以 exit 2 結束。
   - 互動模式預設是 auto mode（編輯和安全的指令自動核准），所以 settings 沒有 deny 的地方都寫得進去。
   - **deny 優先於更細的 allow**：`deny write_file(<wt>)` 加上 `allow write_file(<wt>/.tmp/rw)`，`.tmp/rw/` 也寫不進去。
     deny 是比對路徑，不是字串前綴（deny `/tmp/rw-spike` 不會擋到 `/tmp/rw-spike-out`）。
   - 因此 **review 的 diff 和結果改放在 worktree 外**：`$RW_LOGS/issue-N/review.diff`、`review.md`。
     settings 是 worktree 可讀、log 目錄可讀寫，deny `write_file(<wt>)`。
   - hc 的訊息會附上 `reach="hc send <parent> when done or stuck"`，agy 看到後會嘗試 `hc send`，然後停在權限詢問。所以 agy 的 settings 一律 deny `command(hc)`，worker template 也寫明不要執行 hc。
5. **template 的任務怎麼傳**：hc **不是**把任務當成 command 的參數（argc 是 0），而是等程式回報 ready 之後，把「template 內文 + 任務」包成 `<hc from=... reach=...>…</hc>` 打進終端機。
   程式沒有回報 ready 就結束的話，`first_message.sent` 是 false。內文是空的而且沒有任務時，hc 不會打任何東西。
   - `agy-launch.sh work`：最後 `exec agy --sandbox --settings ...`，不加 `-i`，任務由 hc 打進去。
   - `agy-launch.sh review`：review 的 prompt 需要 log 目錄的絕對路徑，所以由腳本組好，用 `exec agy ... -i "<prompt>"` 傳；`rw-agy-review` template 的內文留空，issue Claude 啟動時也不帶任務。
6. **hc 的子終端機通知是直接打進父終端機的輸入**：父終端機是 bash 時會被當成指令執行。父終端機是 Claude 時會變成一則訊息，這正是設計要的。在 bash 裡做實驗時，子終端機一律加 `--no-notify`。

## 由 Claude 決定、需要使用者確認的事項

- 不保留 Claude 桌面版和沒有 hc 時的退路。
- issue Claude 加 `--outlive-parent`；worker 和 reviewer 不加。
- worker 以報告檔回報，不依賴 `hc send`。
- 貼 PR comment 由 issue Claude 透過腳本處理，agy 只寫檔案。
- worktree 預設路徑改為 `~/worktree/<owner>__<repo>/issue-N`（你貼的目錄結構是 `~/worktrees/issue-N`）。
- template 由 setup 複製到 `~/.config/herdr-core/templates/`，不使用 symlink（plugin 更新後路徑會變），plugin 更新後要重跑 setup。
