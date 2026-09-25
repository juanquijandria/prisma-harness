#!/bin/sh
# Prisma Harness. Documented in README.md, section "What is inside".

HOOKS_DIR="${PRISMA_HOOKS_DIR:-$(cd "$(dirname "$0")" 2>/dev/null && pwd)}"
INVOKES="$HOOKS_DIR/command-invokes.sh"
STRIP_QUOTES="$HOOKS_DIR/strip-quotes.sh"
GATE="$HOOKS_DIR/measure-comments.sh"
ESCAPE="PRISMA_COMMENTS_OK=1"
PRISMA_RECEIPT_SOURCED=1
. "$HOOKS_DIR/receipt.sh"
PRISMA_ESCAPE_SOURCED=1
. "$HOOKS_DIR/escape-declared.sh"
. "$HOOKS_DIR/push-names-head.sh"

command -v jq >/dev/null 2>&1 || { echo "WARN: the comments gate did not run, jq is missing." >&2; exit 0; }
[ -x "$GATE" ] || { echo "WARN: the comments gate did not run, measure-comments.sh is missing." >&2; exit 0; }

payload=$(cat)
[ -n "$payload" ] || exit 0

tool=$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$tool" = "Bash" ] || exit 0

command_text=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$command_text" ] || exit 0

if [ -x "$STRIP_QUOTES" ]; then
  bare_command=$(printf '%s' "$command_text" | "$STRIP_QUOTES"); strip_rc=$?
else
  echo "WARN: strip-quotes.sh is missing, so a declared escape will not be honored here." >&2
  strip_rc=3
fi
[ "$strip_rc" = "0" ] || bare_command=""
if [ -x "$INVOKES" ]; then
  segments=$(printf '%s' "$command_text" | "$INVOKES" git push); rc=$?
  [ "$rc" = "3" ] && { echo "WARN: the comments gate did not run, the command parser could not read the command." >&2; exit 0; }
  pr_raw=$(printf '%s' "$command_text" | "$INVOKES" gh pr); pr_rc=$?
  [ "$pr_rc" = "3" ] && { echo "WARN: the gate did not run, the command parser failed." >&2; exit 0; }
  pr_segments=$(printf '%s' "$pr_raw" | grep -E '(^| )pr +(create|ready)( |$)' || true)
  [ -n "$segments" ] || [ -n "$pr_segments" ] || exit 0
else
  echo "WARN: without command-invokes.sh the trigger is approximate." >&2
  case "$command_text" in *"git push"*|*"pr create"*) ;; *) exit 0 ;; esac
  segments="$command_text"; pr_segments=""
fi

if [ -n "$segments" ]; then
  real_pushes=$(pushes_that_send_a_branch "$segments")
else
  real_pushes="$pr_segments"
fi
[ -n "$real_pushes" ] || exit 0

dir=$(printf '%s' "$command_text" | sed -n 's|^[[:space:]]*cd[[:space:]]\{1,\}\([^&;|]*\).*|\1|p' | sed 's/[[:space:]]*$//' | tr -d "'\"")
if [ -z "$dir" ]; then
  dir=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)
fi
case "$dir" in
  "~") dir="$HOME" ;;
  "~/"*) dir="$HOME/${dir#\~/}" ;;
esac

if [ -z "$dir" ] || [ ! -d "$dir" ]; then
  echo "WARN: the comments gate could not locate the repo, nothing was measured." >&2
  exit 0
fi

real_dir=$(cd "$dir" 2>/dev/null && pwd -P)

for skip in ${PRISMA_SKIP_REPOS:-}; do
  case "$dir" in "$skip"|"$skip"/*) exit 0 ;; esac
  case "$real_dir" in "$skip"|"$skip"/*) exit 0 ;; esac
done

if escape_declared "$ESCAPE" "$bare_command"; then receipt_append comments-gate "$real_dir" escaped; exit 0; fi

cd "$dir" 2>/dev/null || { echo "WARN: the comments gate could not enter $dir, so nothing was measured." >&2; receipt_append comments-gate "$real_dir" not-measured; exit 0; }

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
    echo "WARN: the comments gate measures the branch HEAD is on, and it cannot prove this push sends that branch, so nothing was measured." >&2
    receipt_append comments-gate "$real_dir" not-measured
    exit 0
  fi
fi

if git_may_change_what_is_pushed "$INVOKES" "$command_text"; then
  unmeasured_because_git_may_change "the comments gate" comments-gate "$real_dir"
  exit 0
fi

output=$("$GATE" 2>&1)
status=$?

if [ "$status" = "0" ]; then
  exit 0
fi

if [ "$status" != "1" ]; then
  echo "WARN: the comments gate could not measure in $dir, so nothing is blocked. $(printf '%s' "$output" | tail -1)" >&2
  receipt_append comments-gate "$real_dir" not-measured
  exit 0
fi

if [ "${PRISMA_COMMENTS_BLOCK:-0}" != "1" ]; then
  echo "COMMENTS GATE, measured and not blocking. This repository has not asked it to block, so set PRISMA_COMMENTS_BLOCK=1 to turn the ceiling into a block." >&2
  printf '%s\n' "$output" >&2
  receipt_append comments-gate "$real_dir" warned
  exit 0
fi

cat >&2 <<MSG
COMMENTS GATE: this diff is over the ceiling, and the push is blocked.

$output

The ceiling is ZERO comment lines. Code explains itself. If a line needs a
comment, the name is wrong or a function with a proper name is missing. The
only exceptions are the shebang, a linter directive with its reason, a license
header, and a public API docblock where the repo already uses them.

What to do, in this order.

1. The why of a decision goes in the change description and in the module docs,
   not above the line. There it gets reviewed and there it ages in plain sight.
2. A MUTABLE figure does not live in a comment. It has no source, no date and no
   one to refute it, and it expires silently. It goes to the docs with its label.
   A protocol constant, a provider limit or a value a test pins IS legitimate,
   and is declared with the escape.
3. A file:line reference breaks silently at the first foreign edit. Name the
   symbol, which survives a rename. A permalink pinned to a commit is the
   exception and is declared.
4. If a better name deletes the comment, it was a bad name, not a needed comment.
5. The one exception is a non-obvious invariant that already bit in production,
   in ONE line.

If the violation is deliberate, declare it by prefixing the command with
$ESCAPE, and write the reason in the change description.
MSG
receipt_append comments-gate "$real_dir" blocked
exit 2
