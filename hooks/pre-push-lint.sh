#!/bin/sh
# Prisma Harness. Documented in README.md, section "pre-push-lint".

HOOKS_DIR="${PRISMA_HOOKS_DIR:-$(cd "$(dirname "$0")" 2>/dev/null && pwd)}"
JQ=$(command -v jq)
INVOCA="$HOOKS_DIR/command-invokes.sh"
SIN_COMILLAS="$HOOKS_DIR/strip-quotes.sh"
BASE_DE_COMPARACION="$HOOKS_DIR/compare-base.sh"
ESCAPE="PRISMA_LINT_OK=1"
[ -n "$JQ" ] || { echo "WARN: the lint gate did not run, jq is missing." >&2; exit 0; }

payload=$(cat)
[ -n "$payload" ] || exit 0

tool=$(printf '%s' "$payload" | "$JQ" -r '.tool_name // empty' 2>/dev/null)
[ "$tool" = "Bash" ] || exit 0

comando=$(printf '%s' "$payload" | "$JQ" -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$comando" ] || exit 0

if [ -x "$SIN_COMILLAS" ]; then desnudo=$(printf '%s' "$comando" | "$SIN_COMILLAS"); else desnudo="$comando"; fi
case "$desnudo" in
  *"$ESCAPE"*) exit 0 ;;
esac

if [ -x "$INVOCA" ]; then
  segmentos=$(printf '%s' "$comando" | "$INVOCA" git push)
  segmentos_pr=$(printf '%s' "$comando" | "$INVOCA" gh pr)
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
  dir=$(printf '%s' "$payload" | "$JQ" -r '.cwd // empty' 2>/dev/null)
fi
case "$dir" in
  "~") dir="$HOME" ;;
  "~/"*) dir="$HOME/${dir#\~/}" ;;
esac
[ -n "$dir" ] && [ -d "$dir" ] || exit 0

real=$(cd "$dir" 2>/dev/null && pwd -P)
for skip in ${PRISMA_SKIP_REPOS:-}; do
  case "$real" in "$skip"|"$skip"/*) exit 0 ;; esac
done

cd "$dir" 2>/dev/null || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

mb=$("$BASE_DE_COMPARACION") || exit 0
[ -n "$mb" ] || exit 0

if [ -x vendor/bin/php-cs-fixer ] && [ -f .php-cs-fixer.php ]; then
  archivos=$(git diff --name-only --diff-filter=ACMR "$mb" -- '*.php' | tr '\n' ' ')
  if [ -n "$archivos" ]; then
    runner=$(mktemp /tmp/csfix-XXXXXX.php) || exit 0
    cat > "$runner" <<'PHP'
<?php
set_error_handler(static function (int $no, string $msg): bool {
    return str_contains($msg, 'opentelemetry');
}, E_USER_WARNING);
require getcwd() . '/vendor/autoload.php';
restore_error_handler();
require getcwd() . '/vendor/friendsofphp/php-cs-fixer/php-cs-fixer';
PHP
    salida=$(PHP_CS_FIXER_IGNORE_ENV=1 php "$runner" fix --config=.php-cs-fixer.php --dry-run --using-cache=no --sequential --show-progress=none $archivos 2>&1)
    estado=$?
    rm -f "$runner"
    if [ "$estado" != "0" ]; then
      cuantos=$(printf '%s' "$salida" | sed -n 's/^Found \([0-9]*\) of.*/\1/p')
      if [ -n "$cuantos" ] && [ "$cuantos" != "0" ]; then
        echo "LINT GATE: php-cs-fixer has $cuantos file(s) to fix, and this repo CI will go red for it. The push is blocked." >&2
        printf '%s\n' "$salida" | grep -E "^ +[0-9]+\)" >&2
        echo "" >&2
        echo "Fix with: ./vendor/bin/php-cs-fixer fix --config=.php-cs-fixer.php <files>" >&2
        echo "If deliberate, prefix the command with $ESCAPE." >&2
        exit 2
      fi
      echo "WARN: php-cs-fixer could not run here, nothing was measured. $(printf '%s' "$salida" | tail -1)" >&2
    fi
  fi
fi

if [ -f package.json ] && [ -x node_modules/.bin/eslint ]; then
  archivos=$(git diff --name-only --diff-filter=ACMR "$mb" -- '*.js' '*.mjs' '*.ts' '*.tsx' '*.vue' | tr '\n' ' ')
  if [ -n "$archivos" ]; then
    salida=$(node_modules/.bin/eslint $archivos 2>&1)
    if [ $? != 0 ] && printf '%s' "$salida" | grep -qE "[0-9]+ error"; then
      echo "LINT GATE: eslint reports errors in files of this diff, and the push is blocked." >&2
      printf '%s\n' "$salida" | grep -E "error" | head -12 >&2
      echo "If deliberate, prefix the command with $ESCAPE." >&2
      exit 2
    fi
  fi
fi

exit 0
