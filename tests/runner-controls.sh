#!/bin/sh
# Prisma Harness. Controls over the selftests themselves, kept outside the runner because a runner cannot run itself.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SELF_NAME=$(basename "$0")
BASE=$(mktemp -d)
EM_DASH=$(printf '\342\200\224')
FOREIGN_PLUGIN=mattpocock-skills
RECEIPT_IN_HOME=.prisma-harness/receipts.log
ok=1
CASES=0

pass() { CASES=$((CASES+1)); printf 'PASS %s\n' "$1"; }
fail() { CASES=$((CASES+1)); printf 'FAIL %s\n' "$1"; ok=0; }
skip() { CASES=$((CASES+1)); printf 'SKIP %s\n' "$1"; }
red_lines() { printf '%s\n' "$1" | grep -cE '^ *(FAIL|SYNTAX ERROR)' | tr -d ' '; }

copy_repo() {
  mkdir -p "$1"
  for entry in "$ROOT"/* "$ROOT"/.[!.]*; do
    case "$entry" in *"/.git") continue ;; esac
    [ -e "$entry" ] && cp -R "$entry" "$1/"
  done
  rm -f "$1/tests/$SELF_NAME"
}

home_with_a_receipt() {
  mkdir -p "$1/$(dirname "$RECEIPT_IN_HOME")"
  printf '2026-01-01T00:00:00\tsize-gate\t/a/repo\tblocked\n' > "$1/$RECEIPT_IN_HOME"
}

run_suite() {
  dir="$1"; shift
  ( cd "$dir" && env "$@" sh tests/run-selftests.sh 2>&1 )
}

USER_TEMP="$BASE/a-temp-dir-the-user-chose"
mkdir -p "$USER_TEMP"

RETURN_PROBE="$BASE/top-level-return.sh"
printf 'printf started\nreturn 0\nprintf reached-the-end\n' > "$RETURN_PROBE"
ENDS_ON_TOP_LEVEL_RETURN=""
for candidate in sh dash bash; do
  found=$(command -v "$candidate" 2>/dev/null)
  [ -n "$found" ] || continue
  if [ "$("$found" "$RETURN_PROBE" 2>/dev/null)" = "started" ]; then
    ENDS_ON_TOP_LEVEL_RETURN="$found"
    break
  fi
done

if [ -n "$ENDS_ON_TOP_LEVEL_RETURN" ]; then
  printf '  a top level return ends the script under %s, so the cases that need that run there\n' "$ENDS_ON_TOP_LEVEL_RETURN"
else
  printf '  no shell here ends the script on a top level return\n'
fi

while IFS='|' read -r knob hook wanted_shell; do
  [ -n "$knob" ] || continue
  case "$wanted_shell" in
    return-ends-the-script)
      shell_for_case="$ENDS_ON_TOP_LEVEL_RETURN"
      [ -n "$shell_for_case" ] || { skip "$hook under $knob, this case needs a shell that ends the script on a top level return and no shell on this machine does that"; continue; }
      ;;
    *) shell_for_case=sh ;;
  esac
  out=$(env "$knob" "$shell_for_case" "$ROOT/hooks/$hook" --selftest 2>&1)
  if printf '%s\n' "$out" | grep -q 'SELFTEST OK:' && [ "$(red_lines "$out")" = "0" ]; then
    pass "$hook ignores $knob in the environment"
  else
    fail "$hook reads $knob from the environment, $(red_lines "$out") failing cases"
  fi
done <<KNOBS
PRISMA_RECEIPT=0|receipt.sh
PRISMA_DOCS_DIR=docs|gate-read-index.sh
PRISMA_INDEX_FILE=home.md|gate-read-index.sh
PRISMA_PYTHON=|command-invokes.sh
PRISMA_TMPDIR=/nowhere-at-all|format-gate.sh
PRISMA_VOICE=0|session-voice.sh
PRISMA_DEPS_CHECK=0|session-deps.sh
PRISMA_JQ=|check-canonical-sync.sh
PRISMA_RECEIPT_SOURCED=1|receipt.sh|return-ends-the-script
PRISMA_ESCAPE_SOURCED=1|escape-declared.sh|return-ends-the-script
TMPDIR=$USER_TEMP|format-gate.sh
HOME=$USER_TEMP|check-canonical-sync.sh
KNOBS

by_hand="$BASE/home-of-a-hook-selftest"
home_with_a_receipt "$by_hand"
cp "$by_hand/$RECEIPT_IN_HOME" "$BASE/before-the-hook.log"
env HOME="$by_hand" sh "$ROOT/hooks/gate-read-index.sh" --selftest >/dev/null 2>&1
if cmp -s "$by_hand/$RECEIPT_IN_HOME" "$BASE/before-the-hook.log"; then
  pass "a hook selftest run by hand leaves the receipt of whoever ran it untouched"
else
  fail "a hook selftest run by hand added lines to the receipt of whoever ran it"
fi

named="$BASE/receipt-named-in-the-environment.log"
printf '2026-01-01T00:00:00\tsize-gate\t/a/repo\tblocked\n' > "$named"
cp "$named" "$BASE/before-the-controls.log"
env PRISMA_RECEIPT_FILE="$named" sh "$ROOT/tests/push-gates-controls.sh" >/dev/null 2>&1
if cmp -s "$named" "$BASE/before-the-controls.log"; then
  pass "the push gate controls run by hand leave the receipt named in the environment untouched"
else
  fail "the push gate controls run by hand appended to the receipt named in the environment"
fi

poisoned="$BASE/poisoned"
copy_repo "$poisoned"
printf 'RULE_SOURCES_FOOTER=1\nEXEMPT_DIRS="raw archive inbox Clippings wiki"\n' > "$poisoned/.prisma-format.conf"
mkdir -p "$poisoned/wiki"
printf '# A page of the user\n\nUn guion largo %s vive aqui.\n' "$EM_DASH" > "$poisoned/wiki/su-pagina.md"
suite_home="$BASE/home-of-the-suite"
home_with_a_receipt "$suite_home"
printf '[commit]\n\tgpgsign = true\n[user]\n\tname = somebody else\n' > "$suite_home/.gitconfig"
mkdir -p "$suite_home/.claude"
printf '# the private global page of whoever runs this\n' > "$suite_home/.claude/CLAUDE.md"
cp "$suite_home/$RECEIPT_IN_HOME" "$BASE/before-the-suite.log"
poisoned_out=$(run_suite "$poisoned" \
  HOME="$suite_home" \
  PRISMA_RECEIPT_SOURCED=1 \
  PRISMA_ESCAPE_SOURCED=1 \
  PRISMA_DOCS_DIR=docs \
  PRISMA_INDEX_FILE=home.md \
  PRISMA_PYTHON= \
  PRISMA_JQ= \
  PRISMA_RECEIPT_FILE="$suite_home/$RECEIPT_IN_HOME" \
  PRISMA_VOICE=0 \
  PRISMA_DEPS_CHECK=0 \
  PRISMA_SIZE_BLOCK_OVER=2000 \
  PRISMA_SIZE_WARN_OVER=1999 \
  PRISMA_TMPDIR="$BASE/nowhere-at-all" \
  CLAUDE_PROJECT_DIR="$poisoned" \
  CLAUDE_PLUGIN_ROOT="$poisoned" \
  CLAUDE_PLUGIN_DATA="$BASE/plugin-data")
case "$poisoned_out" in
  *"ALL SELFTESTS OK"*) pass "a poisoned environment, a hostile home and a format config in the tree leave the whole suite green" ;;
  *) fail "an inherited environment turns the suite red, $(red_lines "$poisoned_out") failing lines" ;;
esac
if cmp -s "$suite_home/$RECEIPT_IN_HOME" "$BASE/before-the-suite.log"; then
  pass "the whole suite leaves the receipt of whoever ran it untouched"
else
  fail "the whole suite wrote into the receipt of whoever ran it"
fi

foreign="$BASE/foreign"
copy_repo "$foreign"
mkdir -p "$foreign/notes"
printf '# Reading list\n\nI tried %s today %s it reads well.\n' "$FOREIGN_PLUGIN" "$EM_DASH" > "$foreign/notes/reading-list.md"
foreign_out=$(run_suite "$foreign")
case "$foreign_out" in
  *"ALL SELFTESTS OK"*) pass "a page of the user with an em-dash and a foreign plugin name leaves the suite green" ;;
  *) fail "files the user owns turn the suite red, $(red_lines "$foreign_out") failing lines" ;;
esac

spaced="$BASE/my projects/prisma harness"
copy_repo "$spaced"
spaced_out=$(run_suite "$spaced")
case "$spaced_out" in
  *"ALL SELFTESTS OK"*) pass "the suite is green from a path that contains a space" ;;
  *) fail "a path with a space turns the suite red, $(red_lines "$spaced_out") failing lines" ;;
esac

silent="$BASE/a-selftest-that-says-nothing"
copy_repo "$silent"
printf '#!/bin/sh\nexit 0\n' > "$silent/hooks/session-voice.sh"
silent_out=$(run_suite "$silent")
case "$silent_out" in
  *"ALL SELFTESTS OK"*) fail "a hook whose selftest printed nothing was counted as green" ;;
  *) pass "a hook whose selftest prints nothing is reported, not passed over" ;;
esac

stale="$BASE/a-stale-count-in-its-own-sentence"
copy_repo "$stale"
published=$(sed -n 's/.*page-gates-receipts.sh` add \([0-9][0-9]*\) more.*/\1/p' "$stale/README.md")
if [ -n "$published" ]; then
  wrong=$((published + 1))
  sed "s/page-gates-receipts.sh\` add $published more/page-gates-receipts.sh\` add $wrong more/" "$stale/README.md" > "$stale/README.md.new" && mv "$stale/README.md.new" "$stale/README.md"
  sed "s/page-gates-receipts.sh\` suman $published más/page-gates-receipts.sh\` suman $wrong más/" "$stale/README.es.md" > "$stale/README.es.md.new" && mv "$stale/README.es.md.new" "$stale/README.es.md"
  printf '\nThis copy repeats %s on purpose.\n' "$published" >> "$stale/README.md"
  printf '\nEsta copia repite %s a propósito.\n' "$published" >> "$stale/README.es.md"
  stale_out=$(run_suite "$stale")
  case "$stale_out" in
    *"FAIL the sentence that names tests/page-gates-never-fabricate.sh does not carry"*) pass "a stale count is caught in the sentence that names its suite, even when the true number sits in another sentence" ;;
    *) fail "a stale count in the pages was not reported against its own sentence" ;;
  esac
else
  fail "the count of the never-fabricate suites could not be read from README.md, so this control measured nothing"
fi

rm -rf "$BASE"
[ "$ok" = "1" ] && printf 'SELFTEST OK: %d/%d\n' "$CASES" "$CASES" && exit 0
printf 'SELFTEST FAILED\n'; exit 1
