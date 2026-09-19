#!/bin/sh
# Prisma Harness. Documented in README.md, section "What is inside".

HOOKS_DIR="${PRISMA_HOOKS_DIR:-$(cd "$(dirname "$0")" && pwd)}"
PRISMA_RECEIPT_SOURCED=1
. "$HOOKS_DIR/receipt.sh"

NOTES_ROOT="${PRISMA_NOTES_ROOT:-}"
MARKERS="${PRISMA_MACHINERY_MARKERS:-.git node_modules package.json .venv venv}"
SKIP_DIRS="${PRISMA_MACHINERY_SKIP:-.obsidian raw Clippings archive}"
ALLOW_FILE=".prisma-allowed-machinery"

cannot_measure() {
  printf 'WARN: %s\n' "$1" >&2
  receipt_append notes-machinery "${NOTES_ROOT:-unknown}" not-measured
  exit 0
}

allowed() {
  [ -n "$ALLOW_LIST" ] || return 1
  for entry in $ALLOW_LIST; do
    case "$1" in "$entry"|"$entry"/*) return 0 ;; esac
  done
  return 1
}

scan() {
  [ -d "$NOTES_ROOT" ] || cannot_measure "$NOTES_ROOT is not a directory, so nothing was measured."

  ALLOW_LIST=""
  if [ -f "$NOTES_ROOT/$ALLOW_FILE" ]; then
    ALLOW_LIST=$(sed 's/\r$//' "$NOTES_ROOT/$ALLOW_FILE" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^#' | grep -v '^$')
  fi

  set -- "$NOTES_ROOT"
  opened=0
  for skipped in $SKIP_DIRS; do
    if [ "$opened" = "0" ]; then set -- "$@" "(" -name "$skipped"; opened=1
    else set -- "$@" -o -name "$skipped"; fi
  done
  [ "$opened" = "1" ] && set -- "$@" ")" -prune -o
  opened=0
  for marker in $MARKERS; do
    if [ "$opened" = "0" ]; then set -- "$@" "(" -name "$marker"; opened=1
    else set -- "$@" -o -name "$marker"; fi
  done
  [ "$opened" = "1" ] || cannot_measure "no marker of machinery is configured, so nothing was measured."
  set -- "$@" ")" -print

  FOUND=$(find "$@" 2>/dev/null)
  [ "$?" = "0" ] || cannot_measure "the check could not list every directory under $NOTES_ROOT, so nothing was measured."

  hits=0
  OUTER_IFS=$IFS
  IFS=$(printf '\nx'); IFS=${IFS%x}
  set -f
  for path in $FOUND; do
    relative=${path#"$NOTES_ROOT"/}
    case "$relative" in */*) ;; *) continue ;; esac
    allowed "$relative" && continue
    printf 'NOTES: %s is machinery inside a tree that holds information, where code does not live. Move it out, or name it in %s with the date and the reason.\n' "$relative" "$ALLOW_FILE" >&2
    hits=$((hits+1))
  done

  for entry in $ALLOW_LIST; do
    [ -e "$NOTES_ROOT/$entry" ] && continue
    printf 'NOTES: %s allows %s and there is nothing there any more, so the exception can go.\n' "$ALLOW_FILE" "$entry" >&2
  done
  set +f
  IFS=$OUTER_IFS

  [ "$hits" = "0" ] || receipt_append notes-machinery "$NOTES_ROOT" warned
}

if [ "${1:-}" = "--selftest" ]; then
  . "$HOOKS_DIR/selftest-env.sh"
  SELF="$HOOKS_DIR/notes-machinery.sh"
  T=$(mktemp -d)
  ok=1
  CASES=0
  pass() { CASES=$((CASES+1)); printf 'PASS %s\n' "$1"; }
  fail() { CASES=$((CASES+1)); printf 'FAIL %s\n' "$1"; ok=0; }
  skip() { CASES=$((CASES+1)); printf 'SKIP %s\n' "$1"; }

  export PRISMA_RECEIPT_FILE="$T/receipts.log"
  receipt_lines() { [ -f "$PRISMA_RECEIPT_FILE" ] && wc -l < "$PRISMA_RECEIPT_FILE" | tr -d ' ' || echo 0; }
  receipt_tail() { tail -1 "$PRISMA_RECEIPT_FILE" 2>/dev/null | cut -f2-4 | tr '\t' ' '; }

  run() {
    before=$(receipt_lines)
    said=$(env PRISMA_NOTES_ROOT="$1" /bin/sh "$SELF" 2>&1)
    code=$?
    added=$(( $(receipt_lines) - before ))
  }

  expect_silent() {
    if [ -z "$said" ] && [ "$added" = "0" ] && [ "$code" = "0" ]; then pass "$1"
    else fail "$1, it said [$said], added $added receipt line(s) and exited $code"; fi
  }

  expect_reports() {
    case "$said" in
      *"$2"*)
        if [ "$added" = "1" ] && [ "$(receipt_tail)" = "notes-machinery $NOTES_UNDER_TEST warned" ] && [ "$code" = "0" ]; then pass "$1"
        else fail "$1, it added $added receipt line(s), the last is [$(receipt_tail)] and it exited $code"; fi ;;
      *) fail "$1, it said [$said] and that does not name $2" ;;
    esac
  }

  expect_not_measured() {
    case "$said" in
      *"$2"*)
        if [ "$added" = "1" ] && [ "$(receipt_tail)" = "notes-machinery $NOTES_UNDER_TEST not-measured" ]; then pass "$1"
        else fail "$1, it added $added receipt line(s) and the last is [$(receipt_tail)]"; fi ;;
      *) fail "$1, it said [$said] and that does not name $2" ;;
    esac
  }

  tree() {
    NOTES_UNDER_TEST="$T/$1"
    mkdir -p "$NOTES_UNDER_TEST/wiki/deep/inside"
    printf 'a page\n' > "$NOTES_UNDER_TEST/wiki/page.md"
  }

  tree clean
  run "$NOTES_UNDER_TEST"
  expect_silent "a tree with nothing but pages says nothing and writes no receipt line"

  before=$(receipt_lines)
  said=$(env -u PRISMA_NOTES_ROOT /bin/sh "$SELF" 2>&1); code=$?
  added=$(( $(receipt_lines) - before ))
  expect_silent "without a declared tree the check does not apply, so it says nothing"

  tree nested-git
  mkdir -p "$NOTES_UNDER_TEST/wiki/deep/inside/.git"
  run "$NOTES_UNDER_TEST"
  expect_reports "a git repository nested inside the tree is reported" "wiki/deep/inside/.git"

  tree spaced
  mkdir -p "$NOTES_UNDER_TEST/wiki/qa de referidos/.git"
  run "$NOTES_UNDER_TEST"
  expect_reports "a path with a space in it is reported whole and not split in two" "wiki/qa de referidos/.git"

  tree spaced-allowed
  mkdir -p "$NOTES_UNDER_TEST/wiki/qa de referidos/.git"
  printf 'wiki/qa de referidos\n' > "$NOTES_UNDER_TEST/$ALLOW_FILE"
  run "$NOTES_UNDER_TEST"
  expect_silent "an exception with a space in it covers the path it names"

  tree own-git
  mkdir -p "$NOTES_UNDER_TEST/.git"
  run "$NOTES_UNDER_TEST"
  expect_silent "the tree's own repository at its root is its own business"

  tree modules
  mkdir -p "$NOTES_UNDER_TEST/wiki/deep/node_modules"
  run "$NOTES_UNDER_TEST"
  expect_reports "a node_modules nested inside the tree is reported" "node_modules"

  tree manifest
  printf '{}\n' > "$NOTES_UNDER_TEST/wiki/deep/package.json"
  run "$NOTES_UNDER_TEST"
  expect_reports "a package manifest nested inside the tree is reported" "package.json"

  tree env
  mkdir -p "$NOTES_UNDER_TEST/wiki/deep/.venv"
  run "$NOTES_UNDER_TEST"
  expect_reports "a virtual environment nested inside the tree is reported" ".venv"

  tree notes-app
  mkdir -p "$NOTES_UNDER_TEST/.obsidian/plugins/one"
  printf '{}\n' > "$NOTES_UNDER_TEST/.obsidian/plugins/one/package.json"
  mkdir -p "$NOTES_UNDER_TEST/.obsidian/plugins/one/.git"
  run "$NOTES_UNDER_TEST"
  expect_silent "the machinery a notes application keeps for itself is not reported"

  tree ingest
  mkdir -p "$NOTES_UNDER_TEST/raw/one/.git" "$NOTES_UNDER_TEST/Clippings/two/node_modules"
  run "$NOTES_UNDER_TEST"
  expect_silent "what an ingestion dropped under the directories the format gate already exempts is not reported"

  tree outside
  mkdir -p "$T/outside-sibling/.git"
  run "$NOTES_UNDER_TEST"
  expect_silent "machinery outside the declared tree is not reported"

  tree allowed
  mkdir -p "$NOTES_UNDER_TEST/wiki/deep/tool/.git"
  printf '# the tool below is on purpose, 2026-09-18\nwiki/deep/tool\n' > "$NOTES_UNDER_TEST/$ALLOW_FILE"
  run "$NOTES_UNDER_TEST"
  expect_silent "a path listed in the exceptions file is not reported"

  tree allowed-comments
  mkdir -p "$NOTES_UNDER_TEST/wiki/deep/tool/.git"
  printf '\n# a comment\n\nwiki/deep/tool\n' > "$NOTES_UNDER_TEST/$ALLOW_FILE"
  run "$NOTES_UNDER_TEST"
  expect_silent "comments and blank lines in the exceptions file are ignored"

  tree allowed-stale
  printf 'wiki/deep/gone\n' > "$NOTES_UNDER_TEST/$ALLOW_FILE"
  run "$NOTES_UNDER_TEST"
  case "$said" in
    *"wiki/deep/gone"*) pass "an exception that no longer matches anything is named, so the list cannot rot" ;;
    *) fail "a stale exception was not named, it said [$said]" ;;
  esac

  tree partial
  mkdir -p "$NOTES_UNDER_TEST/wiki/deep/one/.git" "$NOTES_UNDER_TEST/wiki/deep/two/.git"
  printf 'wiki/deep/one\n' > "$NOTES_UNDER_TEST/$ALLOW_FILE"
  run "$NOTES_UNDER_TEST"
  case "$said" in
    *"wiki/deep/two/.git"*)
      case "$said" in
        *"wiki/deep/one/.git"*) fail "an allowed path was reported anyway" ;;
        *) pass "with one path allowed and one not, only the one that is not gets reported" ;;
      esac ;;
    *) fail "the path that is not allowed was not reported, it said [$said]" ;;
  esac

  NOTES_UNDER_TEST="$T/does-not-exist"
  run "$NOTES_UNDER_TEST"
  expect_not_measured "a declared tree that is not there cannot be measured, and it says so" "is not a directory"

  NOTES_UNDER_TEST="$T/a-file"
  printf 'x\n' > "$NOTES_UNDER_TEST"
  run "$NOTES_UNDER_TEST"
  expect_not_measured "a declared tree that is a file cannot be measured, and it says so" "is not a directory"

  tree unreadable
  mkdir -p "$NOTES_UNDER_TEST/wiki/locked/inside"
  chmod 000 "$NOTES_UNDER_TEST/wiki/locked" 2>/dev/null
  if [ "$(id -u)" = "0" ] || find "$NOTES_UNDER_TEST/wiki/locked" >/dev/null 2>&1; then
    skip "a directory that cannot be listed is not enforced on this machine"
  else
    run "$NOTES_UNDER_TEST"
    expect_not_measured "a directory it cannot list means it could not measure, never a clean tree" "could not list"
  fi
  chmod 755 "$NOTES_UNDER_TEST/wiki/locked" 2>/dev/null

  tree no-receipt
  mkdir -p "$NOTES_UNDER_TEST/wiki/deep/inside/.git"
  before=$(receipt_lines)
  said=$(env PRISMA_NOTES_ROOT="$NOTES_UNDER_TEST" PRISMA_RECEIPT=0 /bin/sh "$SELF" 2>&1); code=$?
  added=$(( $(receipt_lines) - before ))
  case "$said" in
    *".git"*) if [ "$added" = "0" ] && [ "$code" = "0" ]; then pass "with the receipt switched off it still reports and writes no line"
              else fail "receipt off added $added line(s) and exited $code"; fi ;;
    *) fail "receipt off stopped it from reporting, it said [$said]" ;;
  esac

  rm -rf "$T"
  [ "$ok" = "1" ] && printf 'SELFTEST OK: %d/%d\n' "$CASES" "$CASES" && exit 0
  printf 'SELFTEST FAILED\n'
  exit 1
fi

[ -n "$NOTES_ROOT" ] || exit 0
scan

exit 0
