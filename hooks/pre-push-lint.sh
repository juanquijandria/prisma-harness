#!/bin/sh
# Prisma Harness. Documented in README.md, section "What is inside".

HOOKS_DIR="${PRISMA_HOOKS_DIR:-$(cd "$(dirname "$0")" 2>/dev/null && pwd)}"
JQ=$(command -v jq)
INVOKES="$HOOKS_DIR/command-invokes.sh"
STRIP_QUOTES="$HOOKS_DIR/strip-quotes.sh"
COMPARE_BASE="$HOOKS_DIR/compare-base.sh"
ESCAPE="PRISMA_LINT_OK=1"
PRISMA_RECEIPT_SOURCED=1
. "$HOOKS_DIR/receipt.sh"
PRISMA_ESCAPE_SOURCED=1
. "$HOOKS_DIR/escape-declared.sh"
[ -n "$JQ" ] || { echo "WARN: the lint gate did not run, jq is missing." >&2; exit 0; }

payload=$(cat)
[ -n "$payload" ] || exit 0

tool=$(printf '%s' "$payload" | "$JQ" -r '.tool_name // empty' 2>/dev/null)
[ "$tool" = "Bash" ] || exit 0

command_text=$(printf '%s' "$payload" | "$JQ" -r '.tool_input.command // empty' 2>/dev/null)
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
  [ "$rc" = "3" ] && { echo "WARN: the lint gate did not run, the command parser has no python." >&2; exit 0; }
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
  real_pushes=$(printf '%s\n' "$segments" | grep -vE -- '--delete|--tags|refs/tags' || true)
else
  real_pushes="$pr_segments"
fi
[ -n "$real_pushes" ] || exit 0

dir=$(printf '%s' "$command_text" | sed -n 's|^[[:space:]]*cd[[:space:]]\{1,\}\([^&;|]*\).*|\1|p' | sed 's/[[:space:]]*$//' | tr -d "'\"")
if [ -z "$dir" ]; then
  dir=$(printf '%s' "$payload" | "$JQ" -r '.cwd // empty' 2>/dev/null)
fi
case "$dir" in
  "~") dir="$HOME" ;;
  "~/"*) dir="$HOME/${dir#\~/}" ;;
esac
[ -n "$dir" ] && [ -d "$dir" ] || { echo "WARN: the lint gate could not locate the repo, nothing was measured." >&2; exit 0; }

real_dir=$(cd "$dir" 2>/dev/null && pwd -P)
for skip in ${PRISMA_SKIP_REPOS:-}; do
  case "$dir" in "$skip"|"$skip"/*) exit 0 ;; esac
  case "$real_dir" in "$skip"|"$skip"/*) exit 0 ;; esac
done

if escape_declared "$ESCAPE" "$bare_command"; then receipt_append lint-gate "$real_dir" escaped; exit 0; fi

cd "$dir" 2>/dev/null || { echo "WARN: the lint gate could not enter $dir, so nothing was measured." >&2; exit 0; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "WARN: the lint gate did not measure, $dir is not a git repository." >&2; exit 0; }

merge_base=$("$COMPARE_BASE") || { echo "WARN: the lint gate could not find a base to compare against, nothing was measured." >&2; exit 0; }
[ -n "$merge_base" ] || { echo "WARN: the lint gate could not find a base to compare against, nothing was measured." >&2; exit 0; }

if [ -x vendor/bin/php-cs-fixer ] && [ -f .php-cs-fixer.php ]; then
  files=$(git diff --name-only --diff-filter=ACMR "$merge_base" -- '*.php') || {
    echo "WARN: the lint gate could not list the changed php files, so nothing was measured." >&2
    files=""
  }
  if [ -n "$files" ]; then
    set --
    while IFS= read -r changed; do [ -n "$changed" ] && set -- "$@" "$changed"; done <<FILES
$files
FILES
    runner=$(mktemp "${TMPDIR:-/tmp}/csfix-XXXXXX.php") || {
      echo "WARN: the lint gate could not create a temporary file, so nothing was measured." >&2
      exit 0
    }
    cat > "$runner" <<'PHP'
<?php
set_error_handler(static function (int $no, string $msg): bool {
    return str_contains($msg, 'opentelemetry');
}, E_USER_WARNING);
require getcwd() . '/vendor/autoload.php';
restore_error_handler();
require getcwd() . '/vendor/friendsofphp/php-cs-fixer/php-cs-fixer';
PHP
    output=$(PHP_CS_FIXER_IGNORE_ENV=1 php "$runner" fix --config=.php-cs-fixer.php --dry-run --using-cache=no --sequential --show-progress=none "$@" 2>&1)
    status=$?
    rm -f "$runner"
    if [ "$status" != "0" ]; then
      how_many=$(printf '%s' "$output" | sed -n 's/^Found \([0-9]*\) of.*/\1/p')
      if [ -n "$how_many" ] && [ "$how_many" != "0" ]; then
        echo "LINT GATE: php-cs-fixer has $how_many file(s) to fix, and this repo CI will go red for it. The push is blocked." >&2
        printf '%s\n' "$output" | grep -E "^ +[0-9]+\)" >&2
        echo "" >&2
        echo "Fix with: ./vendor/bin/php-cs-fixer fix --config=.php-cs-fixer.php <files>" >&2
        echo "If deliberate, prefix the command with $ESCAPE." >&2
        receipt_append lint-gate "$(pwd)" blocked
        exit 2
      fi
      echo "WARN: php-cs-fixer could not run here, nothing was measured. $(printf '%s' "$output" | tail -1)" >&2
    fi
  fi
fi

if [ -f package.json ] && [ -x node_modules/.bin/eslint ]; then
  files=$(git diff --name-only --diff-filter=ACMR "$merge_base" -- '*.js' '*.mjs' '*.ts' '*.tsx' '*.vue') || {
    echo "WARN: the lint gate could not list the changed javascript files, so nothing was measured." >&2
    files=""
  }
  if [ -n "$files" ]; then
    set --
    while IFS= read -r changed; do [ -n "$changed" ] && set -- "$@" "$changed"; done <<FILES
$files
FILES
    output=$(node_modules/.bin/eslint "$@" 2>&1)
    status=$?
    if [ "$status" != "0" ]; then
      if printf '%s' "$output" | grep -qE "[0-9]+ error"; then
        echo "LINT GATE: eslint reports errors in files of this diff, and the push is blocked." >&2
        printf '%s\n' "$output" | grep -E "error" | head -12 >&2
        echo "If deliberate, prefix the command with $ESCAPE." >&2
        receipt_append lint-gate "$(pwd)" blocked
        exit 2
      fi
      echo "WARN: eslint could not run here, so nothing was measured. $(printf '%s' "$output" | tail -1)" >&2
    fi
  fi
fi

exit 0
