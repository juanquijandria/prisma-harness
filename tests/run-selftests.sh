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
  ran=$(grep -c '^ *PASS' "$OUT")
  if [ -n "$declared" ] && [ "$declared" != "$ran" ]; then
    printf 'FAIL %s says %s cases and printed %s PASS lines\n' "$hook" "$declared" "$ran"
    failed=$((failed+1))
  fi
done
rm -f "$OUT"
printf '\n##### push gate controls\n'
if /bin/sh "$(dirname "$0")/push-gates-controls.sh"; then :; else failed=$((failed+1)); fi
printf '\n##### receipt written by the push gate controls\n'
sh "$HOOKS/receipt.sh" --summary | grep -E 'gate +[0-9]' || { printf 'FAIL no gate wrote a receipt line during the controls\n'; failed=$((failed+1)); }
printf '\n##### syntax of every hook\n'
for f in "$HOOKS"/*.sh; do
  case "$f" in *measure-comments.sh) bash -n "$f" ;; *) sh -n "$f" ;; esac || { printf 'SYNTAX ERROR %s\n' "$f"; failed=$((failed+1)); }
done
printf '\n'
[ "$failed" -eq 0 ] && printf 'ALL SELFTESTS OK\n' && exit 0
printf '%s SELFTEST(S) FAILED\n' "$failed"; exit 1
