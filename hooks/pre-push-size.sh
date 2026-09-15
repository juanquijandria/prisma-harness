#!/bin/sh
# Prisma Harness. Documented in README.md, section "pre-push-size".

HOOKS_DIR="${PRISMA_HOOKS_DIR:-$(cd "$(dirname "$0")" 2>/dev/null && pwd)}"
JQ=$(command -v jq)
MEDIDOR="$HOOKS_DIR/measure-diff-size.sh"
BASE_DE_COMPARACION="$HOOKS_DIR/compare-base.sh"
INVOCA="$HOOKS_DIR/command-invokes.sh"
SIN_COMILLAS="$HOOKS_DIR/strip-quotes.sh"
AVISO_SOBRE="${PRISMA_SIZE_WARN_OVER:-400}"
FRENO_SOBRE="${PRISMA_SIZE_BLOCK_OVER:-1000}"
ESCAPE="PRISMA_SIZE_OK=1"
. "$HOOKS_DIR/receipt.sh"

[ -n "$JQ" ] || { echo "WARN: the size gate did not run, jq is missing." >&2; exit 0; }
[ -x "$MEDIDOR" ] || { echo "WARN: the size gate did not run, measure-diff-size.sh is missing." >&2; exit 0; }
[ -x "$BASE_DE_COMPARACION" ] || { echo "WARN: the size gate did not run, compare-base.sh is missing." >&2; exit 0; }
[ -x "$INVOCA" ] || { echo "WARN: the size gate did not run, command-invokes.sh is missing." >&2; exit 0; }
[ -x "$SIN_COMILLAS" ] || { echo "WARN: the size gate did not run, strip-quotes.sh is missing." >&2; exit 0; }

payload=$(cat)
[ -n "$payload" ] || exit 0

tool=$(printf '%s' "$payload" | "$JQ" -r '.tool_name // empty' 2>/dev/null)
[ "$tool" = "Bash" ] || exit 0

comando=$(printf '%s' "$payload" | "$JQ" -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$comando" ] || exit 0

desnudo=$(printf '%s' "$comando" | "$SIN_COMILLAS")
case "$desnudo" in
  *"$ESCAPE"*) receipt_append size-gate "$(printf '%s' "$payload" | "$JQ" -r '.cwd // empty' 2>/dev/null)" escaped; exit 0 ;;
esac

segmentos=$(printf '%s' "$comando" | "$INVOCA" git push); rc=$?
[ "$rc" = "3" ] && { echo "WARN: the size gate did not run, the command parser has no python." >&2; exit 0; }
segmentos_pr=$(printf '%s' "$comando" | "$INVOCA" gh pr)
[ -n "$segmentos" ] || [ -n "$segmentos_pr" ] || exit 0

if [ -n "$segmentos" ]; then
  reales=$(printf '%s\n' "$segmentos" | grep -vE -- '--delete|--tags|refs/tags' || true)
else
  reales="$segmentos_pr"
fi
[ -n "$reales" ] || exit 0

dir=$(printf '%s' "$desnudo" | sed -n 's|^[[:space:]]*cd[[:space:]]\{1,\}\([^&;|]*\).*|\1|p' | sed 's/[[:space:]]*$//' | tr -d "'\"")
case "$dir" in
  "~") dir="$HOME" ;;
  "~/"*) dir="$HOME/${dir#\~/}" ;;
esac
if [ -z "$dir" ] || [ ! -d "$dir" ]; then
  dir=$(printf '%s' "$payload" | "$JQ" -r '.cwd // empty' 2>/dev/null)
fi
[ -n "$dir" ] && [ -d "$dir" ] || exit 0
for skip in ${PRISMA_SKIP_REPOS:-}; do
  case "$dir" in "$skip"|"$skip"/*) exit 0 ;; esac
done

cd "$dir" 2>/dev/null || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

mb=$("$BASE_DE_COMPARACION"); rc=$?
if [ "$rc" = "2" ]; then echo "WARN: the size gate measures HEAD and HEAD has nothing over its base, so nothing was measured. If you are pushing another branch from here, check it out first." >&2; exit 0; fi
[ "$rc" = "0" ] && [ -n "$mb" ] || { echo "WARN: the size gate could not find a base to compare against, nothing was measured." >&2; exit 0; }

lineas=$("$MEDIDOR" "$(pwd)" "$mb" HEAD)
case "$lineas" in
  ''|*[!0-9]*) echo "WARN: the size gate could not measure, nothing is blocked." >&2; exit 0 ;;
esac

ATRASO_SOSPECHOSO=10
atras=$(git rev-list --count "HEAD..@{upstream}" 2>/dev/null)
case "$atras" in ''|*[!0-9]*) atras=0 ;; esac

if [ "$lineas" -gt "$FRENO_SOBRE" ]; then
  {
    echo "SIZE GATE: $lineas lines changed, the push is blocked."
    echo
    echo "Over $FRENO_SOBRE lines, defect detection in review drops below half."
    echo "Reviewers stop finding things long before they finish reading."
    echo
    if [ "$atras" -ge "$ATRASO_SOSPECHOSO" ]; then
      echo "NOTE: this branch is $atras commits BEHIND its upstream. Much of those"
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

if [ "$lineas" -gt "$AVISO_SOBRE" ]; then
  echo "WARN from the size gate: $lineas lines changed, over the $AVISO_SOBRE where review starts missing defects. Not blocking." >&2
fi

exit 0
