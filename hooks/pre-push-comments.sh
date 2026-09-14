#!/bin/sh
# Prisma Harness. Documented in README.md, section "pre-push-comments".

HOOKS_DIR="${PRISMA_HOOKS_DIR:-$(cd "$(dirname "$0")" 2>/dev/null && pwd)}"
INVOKES="$HOOKS_DIR/command-invokes.sh"
STRIP_QUOTES="$HOOKS_DIR/strip-quotes.sh"
GATE="$HOOKS_DIR/measure-comments.sh"
ESCAPE="PRISMA_COMMENTS_OK=1"

command -v jq >/dev/null 2>&1 || { echo "WARN: the comments gate did not run, jq is missing." >&2; exit 0; }
[ -x "$GATE" ] || { echo "WARN: the comments gate did not run, measure-comments.sh is missing." >&2; exit 0; }

payload=$(cat)
[ -n "$payload" ] || exit 0

tool=$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$tool" = "Bash" ] || exit 0

comando=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$comando" ] || exit 0

if [ -x "$STRIP_QUOTES" ]; then desnudo=$(printf '%s' "$comando" | "$STRIP_QUOTES"); else desnudo="$comando"; fi
case "$desnudo" in
  *"$ESCAPE"*) exit 0 ;;
esac

if [ -x "$INVOKES" ]; then
  segmentos=$(printf '%s' "$comando" | "$INVOKES" git push)
  segmentos_pr=$(printf '%s' "$comando" | "$INVOKES" gh pr)
  [ -n "$segmentos" ] || [ -n "$segmentos_pr" ] || exit 0
else
  echo "WARN: without command-invokes.sh the trigger is approximate." >&2
  case "$comando" in *"git push"*|*"pr create"*) ;; *) exit 0 ;; esac
  segmentos="$comando"; segmentos_pr=""
fi

if [ -n "$segmentos" ]; then
  reales=$(printf '%s\n' "$segmentos" | grep -vE -- '--delete|--tags|refs/tags' || true)
else
  reales="$segmentos_pr"
fi
[ -n "$reales" ] || exit 0

dir=$(printf '%s' "$comando" | sed -n 's|^[[:space:]]*cd[[:space:]]\{1,\}\([^&;|]*\).*|\1|p' | sed 's/[[:space:]]*$//' | tr -d "'\"")
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

real=$(cd "$dir" 2>/dev/null && pwd -P)

for skip in ${PRISMA_SKIP_REPOS:-}; do
  case "$real" in "$skip"|"$skip"/*) exit 0 ;; esac
done

salida=$(cd "$dir" 2>/dev/null && "$GATE" 2>&1)
estado=$?

if [ "$estado" = "0" ]; then
  exit 0
fi

if [ "$estado" != "1" ]; then
  echo "WARN: the comments gate could not measure in $dir, so nothing is blocked. $(printf '%s' "$salida" | tail -1)" >&2
  exit 0
fi

cat >&2 <<MSG
COMMENTS GATE: this diff is over the ceiling, and the push is blocked.

$salida

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
exit 2
