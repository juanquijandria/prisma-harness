#!/bin/sh
# Prisma Harness. Runs every hook selftest and exits non-zero if any fails.

HOOKS="$(cd "$(dirname "$0")/../hooks" && pwd)"
export PRISMA_RECEIPT_FILE="$(mktemp -d)/receipts.log"
failed=0
OUT=$(mktemp)
for hook in gate-read-index format-gate check-canonical-sync blind-replica session-voice session-deps command-invokes receipt; do
  printf '\n##### %s\n' "$hook"
  if sh "$HOOKS/$hook.sh" --selftest > "$OUT" 2>&1; then :; else failed=$((failed+1)); fi
  cat "$OUT"
  declared=$(sed -n 's/.*SELFTEST OK: \([0-9][0-9]*\)\/[0-9][0-9]*.*/\1/p' "$OUT" | tail -1)
  ran=$(grep -cE '^ *(PASS|SKIP)' "$OUT")
  skipped=$(grep -cE '^ *SKIP' "$OUT")
  [ "$skipped" -gt 0 ] && printf '  %s case(s) skipped on this machine\n' "$skipped"
  if [ -n "$declared" ] && [ "$declared" != "$ran" ]; then
    printf 'FAIL %s says %s cases and printed %s PASS or SKIP lines\n' "$hook" "$declared" "$ran"
    failed=$((failed+1))
  fi
done
rm -f "$OUT"
printf '\n##### the pages of this repo under its own gate\n'
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PAGES=$(find "$ROOT" -name '*.md' -not -path '*/.git/*')
GATE_OUT=$(PRISMA_DOCS_ROOT="$ROOT" PRISMA_EXEMPT_NAMES="none.md" PRISMA_RULE_KEBAB_CASE=0 PRISMA_RULE_H1_FIRST_LINE=0 PRISMA_RULE_LINE_CEILING=0 sh "$HOOKS/format-gate.sh" --strict $PAGES 2>&1)
printf '%s\n' "$GATE_OUT" | tail -1
printf '%s' "$GATE_OUT" | grep -q 'PASS: 0 blocking, 0 warnings' || { printf 'FAIL the repo pages do not pass the rules this repo ships\n'; failed=$((failed+1)); }
printf '  file names and the H1 are off here, the repo root uses uppercase names and an HTML title\n'

printf '\n##### push gate controls\n'
if /bin/sh "$(dirname "$0")/push-gates-controls.sh"; then :; else failed=$((failed+1)); fi

for controls in push-gates-never-fabricate page-gates-never-fabricate; do
  printf '\n##### %s\n' "$controls"
  FAB=$(mktemp)
  if /bin/sh "$(dirname "$0")/$controls.sh" > "$FAB" 2>&1; then :; else failed=$((failed+1)); fi
  cat "$FAB"
  fab_declared=$(sed -n 's/.*SELFTEST OK: \([0-9][0-9]*\)\/[0-9][0-9]*.*/\1/p' "$FAB" | tail -1)
  fab_ran=$(grep -cE '^ *(PASS|SKIP)' "$FAB")
  if [ -n "$fab_declared" ] && [ "$fab_declared" != "$fab_ran" ]; then
    printf 'FAIL %s says %s cases and printed %s PASS or SKIP lines\n' "$controls" "$fab_declared" "$fab_ran"
    failed=$((failed+1))
  fi
  rm -f "$FAB"
done
printf '\n##### receipt written by the push gate controls\n'
sh "$HOOKS/receipt.sh" --summary | grep -E 'gate +[0-9]' || { printf 'FAIL no gate wrote a receipt line during the controls\n'; failed=$((failed+1)); }
printf '\n##### syntax of every hook\n'
for f in "$HOOKS"/*.sh; do
  case "$f" in *measure-comments.sh) bash -n "$f" ;; *) sh -n "$f" ;; esac || { printf 'SYNTAX ERROR %s\n' "$f"; failed=$((failed+1)); }
done
printf '\n'
[ "$failed" -eq 0 ] && printf 'ALL SELFTESTS OK\n' && exit 0
printf '%s SELFTEST(S) FAILED\n' "$failed"; exit 1
