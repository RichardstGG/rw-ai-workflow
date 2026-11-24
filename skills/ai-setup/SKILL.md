---
name: ai-setup
description: Prepare a repo (or a new machine) for the rw-ai-workflow ai-run flow without adding any file to the repo's git history - per-project config and verify script under ~/automation, worktrees under ~/worktree, .git/info/exclude, local Claude permissions, Codex trust, the rw-* herdr core (hc) templates, GitHub labels. Use before the first "開跑 #N" in a repo, or when moving the workflow to another machine.
---

目標：讓 `ai-run` 能在這個 repo 跑，但不新增任何會被 git 追蹤的檔案。`S` 的定義同 `ai-run`。

## 0. 前置檢查（只讀）
- `git rev-parse --show-toplevel`、`git remote get-url origin`
- `hc server status`（herdr core 要在跑；所有 agent 都是 hc 的終端機）、`codex --version`、`codex login status`、`gh auth status`
- 可選：`agy --version`（review 與 agy work 需要）
- `gh repo view --repo <repo> --json defaultBranchRef,hasIssuesEnabled`
必要項目不符就停下來說明；Issues 未啟用要請使用者去 Settings 打開。可選工具沒裝只要告知會少哪個功能。

## 1. 盤點 repo 內的舊流程（只讀，不刪）
列出 repo 裡舊的分工檔案與段落：`.claude/skills/ai-run`、`scripts/ai/`、AGENTS.md／CLAUDE.md 的 Claude–Codex 分工段落、舊的 codex wrapper。
每項附路徑與建議：
- `scripts/ai/verify.sh` 這類專案自己的驗證腳本：可以留在 repo（plugin 會找到它），或搬到 `~/automation/projects/<owner>__<repo>/verify.sh`。
- 其他流程腳本與 ai-run skill：plugin 已取代，建議刪除（用另一個 PR，不在這一步做）。
- AGENTS.md 的 worker 段落：專案專屬的規則（例如特定工具鏈的測試指令）可以留著，worker 會一併遵守。
等使用者確認，這一步不修改任何檔案。

## 2. 安裝（只寫 repo 外的東西）
`$S/setup.sh`（冪等），它會：
- 建 `~/automation/{projects,task-state,logs}/<owner>__<repo>/` 與 `~/worktree/`（可用 `RW_HOME`、`RW_WORKTREES` 改位置）
- 從範本建立 `config.sh`（已存在就不動）
- 把 `.tmp/ .codex/ .claude/settings.local.json` 寫進 `.git/info/exclude`（只在本機，主 checkout 與所有 worktree 共用）
- 合併 Claude 權限到 `.claude/settings.local.json`（只新增，不刪使用者原有規則）
- 在 `~/.codex/config.toml` 信任主 checkout（先備份；Codex 對 worktree 的信任以主 repo 為準）
- 把 hc template（`rw-codex`、`rw-claude`、`rw-agy-work`、`rw-agy-review`、`rw-agy-review-lite`）裝到 `~/.config/herdr-core/templates/`，填入本 plugin `scripts/` 的絕對路徑；被改過的舊檔先備份成 `.bak.rw-ai-workflow`。plugin 更新後路徑會變，要重跑 setup。
hc server 沒在跑時 setup 會以 1 結束：請使用者 `hc server start`。跑完把輸出告訴使用者。
另外提醒使用者：claude 第一次在新的 worktree 啟動時會問要不要信任資料夾，終端機會停在 blocked，要 attach 進去選擇。claude 信任上層資料夾就涵蓋子資料夾，所以可以先在 `~/worktree` 跑一次 `claude` 並選信任。agy 不用處理：`agy-launch.sh` 會自動把該 issue 的 worktree 加進 agy 的 `trustedWorkspaces`，cleanup 時再移除。

## 3. 專案專屬設定
- 編輯 `~/automation/projects/<owner>__<repo>/config.sh`：base branch、Codex sandbox 要不要網路、要額外寫入的目錄（SDK、套件快取）、agy 要額外讀取的目錄。model 和 effort 寫在 `~/.config/herdr-core/templates/rw-*.md` 的 `command` 裡（重跑 setup 會覆蓋，覆蓋前會備份）。依專案工具鏈判斷，把設定與理由告訴使用者。
- verify 腳本：repo 已有 `scripts/ai/verify.sh` 就沿用；沒有就參考 CI 設定寫一份 `~/automation/projects/<owner>__<repo>/verify.sh`：
  - 鏡像 CI 中 Linux 能跑的子集，不比 CI 嚴；從 repo 根目錄執行（`$S/verify.sh` 會先 cd 過去）。
  - 支援 `--sandbox`：需要 socket／D-Bus／網路的步驟在 sandbox 模式下跳過，印出 `ENV_LIMITED: skipped <step>`。
  - 最後印 `verify OK`。
  寫完在 host 跑一次 `$S/verify.sh`，把結果告訴使用者。
- 建置輸出目錄（build/、target/ 等）若沒被 .gitignore 涵蓋，加進 `.git/info/exclude`，不要改 .gitignore。

## 4. 需使用者同意後才做
建立 labels：`ai:proposed` `ai:ready` `ai:in-progress` `ai:review` `ai:changes` `ai:blocked`（`gh label create ... --repo <repo>`，已存在就略過）。

## 5. 回報
用表格列出每步結果、建立或修改的檔案（全部在 repo 外，或在 git 不追蹤的檔案裡）、備份檔、待使用者決定的事。
