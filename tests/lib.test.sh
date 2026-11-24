. "$(dirname "$0")/helpers.sh"

# short_for OWNER NAME: rw_short, RW_WORKTREES and RW_WT as seen from a clone of OWNER/NAME
short_for() { (cd "$(mkrepo "$1" "$2")" && . "$S/lib.sh" && rw_load && echo "$(rw_short)|$RW_WORKTREES|$RW_WT"); }

IFS='|' read -r short wts wt <<<"$(short_for alice RoadScope)"
check "rw_short lowercases" "$short" roadscope
check "RW_WORKTREES defaults to ~/worktree" "$wts" "$HOME/worktree"
check "RW_WT is per repo" "$wt" "$HOME/worktree/alice__RoadScope"

IFS='|' read -r short _ <<<"$(short_for alice my_repo.v2)"
check "rw_short maps other chars to -" "$short" my-repo-v2

IFS='|' read -r short _ <<<"$(short_for alice --A__b--)"
check "rw_short squeezes and trims -" "$short" a-b

long=abcdefghijklmnopqrstuvwxyz0123456789abcd
IFS='|' read -r short _ <<<"$(short_for alice $long)"
check "rw_short caps at 20 chars" "$short" "${long:0:20}"

finish
