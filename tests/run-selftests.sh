#!/bin/sh
# Prisma Harness. Runs every hook selftest and exits non-zero if any fails.

HOOKS="$(cd "$(dirname "$0")/../hooks" && pwd)"
failed=0
for hook in gate-read-index format-gate check-canonical-sync blind-replica session-voice session-deps command-invokes; do
  printf '\n##### %s\n' "$hook"
  if /bin/sh "$HOOKS/$hook.sh" --selftest; then :; else failed=$((failed+1)); fi
done
printf '\n##### diagram gate and layout\n'
if command -v node >/dev/null 2>&1; then
  D="$(cd "$(dirname "$0")/../diagram" && pwd)"
  node "$D/verify.mjs" && node "$D/verify.mjs" --selftest | tail -1 && node "$D/test-layout.mjs" | tail -1 || failed=$((failed+1))
else
  printf 'SKIP node is not installed, the diagram checks did not run\n'
fi
printf '\n##### push gate controls\n'
if /bin/sh "$(dirname "$0")/push-gates-controls.sh"; then :; else failed=$((failed+1)); fi
printf '\n##### syntax of every hook\n'
for f in "$HOOKS"/*.sh; do
  case "$f" in *measure-comments.sh) bash -n "$f" ;; *) sh -n "$f" ;; esac || { printf 'SYNTAX ERROR %s\n' "$f"; failed=$((failed+1)); }
done
printf '\n'
[ "$failed" -eq 0 ] && printf 'ALL SELFTESTS OK\n' && exit 0
printf '%s SELFTEST(S) FAILED\n' "$failed"; exit 1
