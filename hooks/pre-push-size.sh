#!/bin/sh
# Prisma Harness. Documented in README.md, section "What is inside".

HOOKS_DIR="${PRISMA_HOOKS_DIR:-$(cd "$(dirname "$0")" 2>/dev/null && pwd)}"
JQ=$(command -v jq)
MEASURE="$HOOKS_DIR/measure-diff-size.sh"
COMPARE_BASE="$HOOKS_DIR/compare-base.sh"
INVOKES="$HOOKS_DIR/command-invokes.sh"
STRIP_QUOTES="$HOOKS_DIR/strip-quotes.sh"
WARN_OVER="${PRISMA_SIZE_WARN_OVER:-200}"
BLOCK_OVER="${PRISMA_SIZE_BLOCK_OVER:-400}"
ESCAPE="PRISMA_SIZE_OK=1"
PRISMA_RECEIPT_SOURCED=1
. "$HOOKS_DIR/receipt.sh"
PRISMA_ESCAPE_SOURCED=1
. "$HOOKS_DIR/escape-declared.sh"
. "$HOOKS_DIR/push-names-head.sh"

[ -n "$JQ" ] || { echo "WARN: the size gate did not run, jq is missing." >&2; exit 0; }
[ -x "$MEASURE" ] || { echo "WARN: the size gate did not run, measure-diff-size.sh is missing." >&2; exit 0; }
[ -x "$COMPARE_BASE" ] || { echo "WARN: the size gate did not run, compare-base.sh is missing." >&2; exit 0; }
[ -x "$INVOKES" ] || { echo "WARN: the size gate did not run, command-invokes.sh is missing." >&2; exit 0; }
[ -x "$STRIP_QUOTES" ] || echo "WARN: strip-quotes.sh is missing, so a declared escape will not be honored here." >&2

payload=$(cat)
[ -n "$payload" ] || exit 0

tool=$(printf '%s' "$payload" | "$JQ" -r '.tool_name // empty' 2>/dev/null)
[ "$tool" = "Bash" ] || exit 0

command_text=$(printf '%s' "$payload" | "$JQ" -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$command_text" ] || exit 0

if [ -x "$STRIP_QUOTES" ]; then
  bare_command=$(printf '%s' "$command_text" | "$STRIP_QUOTES"); strip_rc=$?
else
  strip_rc=3
fi
[ "$strip_rc" = "0" ] || bare_command=""

segments=$(printf '%s' "$command_text" | "$INVOKES" git push); rc=$?
[ "$rc" = "3" ] && { echo "WARN: the size gate did not run, the command parser could not read the command." >&2; exit 0; }
pr_raw=$(printf '%s' "$command_text" | "$INVOKES" gh pr); pr_rc=$?
[ "$pr_rc" = "3" ] && { echo "WARN: the size gate did not run, the command parser failed." >&2; exit 0; }
pr_segments=$(printf '%s' "$pr_raw" | grep -E '(^| )pr +(create|ready)( |$)' || true)
[ -n "$segments" ] || [ -n "$pr_segments" ] || exit 0

if [ -n "$segments" ]; then
  real_pushes=$(printf '%s\n' "$segments" | grep -vE -- '--delete|--tags|refs/tags' || true)
else
  real_pushes="$pr_segments"
fi
[ -n "$real_pushes" ] || exit 0

dir=$(printf '%s' "$command_text" | sed -n 's|^[[:space:]]*cd[[:space:]]\{1,\}\([^&;|]*\).*|\1|p' | sed 's/[[:space:]]*$//' | tr -d "'\"")
case "$dir" in
  "~") dir="$HOME" ;;
  "~/"*) dir="$HOME/${dir#\~/}" ;;
esac
if [ -z "$dir" ] || [ ! -d "$dir" ]; then
  dir=$(printf '%s' "$payload" | "$JQ" -r '.cwd // empty' 2>/dev/null)
fi
[ -n "$dir" ] && [ -d "$dir" ] || { echo "WARN: the size gate could not locate the repo, nothing was measured." >&2; exit 0; }
real_dir=$(cd "$dir" 2>/dev/null && pwd -P)
for skip in ${PRISMA_SKIP_REPOS:-}; do
  case "$dir" in "$skip"|"$skip"/*) exit 0 ;; esac
  case "$real_dir" in "$skip"|"$skip"/*) exit 0 ;; esac
done

if escape_declared "$ESCAPE" "$bare_command"; then receipt_append size-gate "$real_dir" escaped; exit 0; fi

cd "$dir" 2>/dev/null || { echo "WARN: the size gate could not enter $dir, so nothing was measured." >&2; receipt_append size-gate "$real_dir" not-measured; exit 0; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "WARN: the size gate did not measure, $dir is not a git repository." >&2; receipt_append size-gate "$real_dir" not-measured; exit 0; }

if [ -n "$segments" ]; then
  head_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  proven=1
  while IFS= read -r one_push; do
    [ -n "$one_push" ] || continue
    push_names_head "$head_branch" "$one_push" "$command_text" || { proven=0; break; }
  done <<PUSHES
$real_pushes
PUSHES
  if [ "$proven" = "0" ]; then
    echo "WARN: the size gate measures the branch HEAD is on, and it cannot prove this push sends that branch, so nothing was measured." >&2
    receipt_append size-gate "$real_dir" not-measured
    exit 0
  fi
fi

merge_base=$("$COMPARE_BASE"); rc=$?
if [ "$rc" = "2" ]; then echo "WARN: the size gate measures HEAD and HEAD has nothing over its base, so nothing was measured. If you are pushing another branch from here, check it out first." >&2; receipt_append size-gate "$real_dir" not-measured; exit 0; fi
[ "$rc" = "0" ] && [ -n "$merge_base" ] || { echo "WARN: the size gate could not find a base to compare against, nothing was measured." >&2; receipt_append size-gate "$real_dir" not-measured; exit 0; }

lines=$("$MEASURE" "$(pwd)" "$merge_base" HEAD) || { echo "WARN: the size gate could not read the diff, nothing was measured." >&2; receipt_append size-gate "$real_dir" not-measured; exit 0; }
case "$lines" in
  ''|*[!0-9]*) echo "WARN: the size gate could not measure, nothing is blocked." >&2; receipt_append size-gate "$real_dir" not-measured; exit 0 ;;
esac

STALE_BEHIND=10
behind=$(git rev-list --count "HEAD..@{upstream}" 2>/dev/null)
case "$behind" in ''|*[!0-9]*) behind=0 ;; esac

if [ "$lines" -gt "$BLOCK_OVER" ]; then
  {
    echo "SIZE GATE: $lines lines changed, the push is blocked."
    echo
    echo "This repository blocks a push over $BLOCK_OVER changed lines and warns"
    echo "over $WARN_OVER. Reviewers stop finding things long before they finish reading."
    echo
    if [ "$behind" -ge "$STALE_BEHIND" ]; then
      echo "NOTE: this branch is $behind commits BEHIND its upstream. Much of those"
      echo "lines may be work already merged elsewhere. Rebase and measure again"
      echo "BEFORE thinking about splitting the change."
    else
      echo "See whether it splits into two pushes that stand on their own."
    fi
    echo
    echo "If it truly cannot be split and is up to date, declare $ESCAPE and"
    echo "write in the PR body why it could not be split."
  } >&2
  receipt_append size-gate "$(pwd)" blocked
  exit 2
fi

if [ "$lines" -gt "$WARN_OVER" ]; then
  echo "WARN from the size gate: $lines lines changed, over the $WARN_OVER this repository warns at. Not blocking." >&2
  receipt_append size-gate "$real_dir" warned
fi

exit 0
