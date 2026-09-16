#!/bin/sh
# Prisma Harness. Runs every hook selftest and exits non-zero if any fails.

HOOKS="$(cd "$(dirname "$0")/../hooks" && pwd)"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$HOOKS/selftest-env.sh"
. "$ROOT/tests/shipped.sh"
failed=0
OUT=$(mktemp)
for hook in gate-read-index format-gate check-canonical-sync blind-replica session-voice session-deps command-invokes escape-declared receipt; do
  printf '\n##### %s\n' "$hook"
  if sh "$HOOKS/$hook.sh" --selftest > "$OUT" 2>&1; then :; else failed=$((failed+1)); fi
  cat "$OUT"
  declared=$(sed -n 's/.*SELFTEST OK: \([0-9][0-9]*\)\/[0-9][0-9]*.*/\1/p' "$OUT" | tail -1)
  ran=$(grep -cE '^ *(PASS|SKIP)' "$OUT")
  [ "$hook" = "format-gate" ] && format_gate_cases="$ran"
  skipped=$(grep -cE '^ *SKIP' "$OUT")
  [ "$skipped" -gt 0 ] && printf '  %s case(s) skipped on this machine\n' "$skipped"
  if [ -z "$declared" ] && ! grep -q 'SELFTEST FAILED' "$OUT"; then
    printf 'FAIL %s printed no count line and no failure either, so its cases cannot be accounted for\n' "$hook"
    failed=$((failed+1))
  elif [ "$declared" != "$ran" ]; then
    printf 'FAIL %s says %s cases and printed %s PASS or SKIP lines\n' "$hook" "$declared" "$ran"
    failed=$((failed+1))
  fi
done
rm -f "$OUT"
printf '\n##### the pages of this repo under its own gate\n'
set --
while IFS= read -r page; do
  [ -n "$page" ] && set -- "$@" "$page"
done <<PAGES
$(shipped_pages "$ROOT")
PAGES
GATE_OUT=$(PRISMA_DOCS_ROOT="$ROOT" PRISMA_FORMAT_CONFIG="$ROOT/there-is-no-format-config-here" PRISMA_EXEMPT_NAMES="none.md" PRISMA_RULE_KEBAB_CASE=0 PRISMA_RULE_H1_FIRST_LINE=0 PRISMA_RULE_LINE_CEILING=0 sh "$HOOKS/format-gate.sh" --strict "$@" 2>&1)
printf '%s\n' "$GATE_OUT" | tail -1
printf '%s' "$GATE_OUT" | grep -q 'PASS: 0 blocking, 0 warnings' || { printf 'FAIL the repo pages do not pass the rules this repo ships\n'; failed=$((failed+1)); }
printf '  %s pages, the ones this repo publishes and not every file under it\n' "$#"
printf '  three rules are off for this check, file names and the H1 because the repo root uses uppercase names and an HTML title, and the line ceiling because both READMEs are longer than the 150 lines this repo proposes\n'

printf '\n##### push gate controls\n'
PUSH=$(mktemp)
if /bin/sh "$(dirname "$0")/push-gates-controls.sh" > "$PUSH" 2>&1; then :; else failed=$((failed+1)); fi
cat "$PUSH"
push_gate_cases=$(grep -cE '^ *(PASS|SKIP)' "$PUSH")
rm -f "$PUSH"

for controls in push-gates-never-fabricate page-gates-never-fabricate; do
  printf '\n##### %s\n' "$controls"
  FAB=$(mktemp)
  if /bin/sh "$(dirname "$0")/$controls.sh" > "$FAB" 2>&1; then :; else failed=$((failed+1)); fi
  cat "$FAB"
  fab_declared=$(sed -n 's/.*SELFTEST OK: \([0-9][0-9]*\)\/[0-9][0-9]*.*/\1/p' "$FAB" | tail -1)
  fab_ran=$(grep -cE '^ *(PASS|SKIP)' "$FAB")
  never_fabricate_cases=$((${never_fabricate_cases:-0} + fab_ran))
  if [ -n "$fab_declared" ] && [ "$fab_declared" != "$fab_ran" ]; then
    printf 'FAIL %s says %s cases and printed %s PASS or SKIP lines\n' "$controls" "$fab_declared" "$fab_ran"
    failed=$((failed+1))
  fi
  rm -f "$FAB"
done
printf '\n##### skills controls\n'
SK=$(mktemp)
if /bin/sh "$(dirname "$0")/skills-controls.sh" > "$SK" 2>&1; then :; else failed=$((failed+1)); fi
cat "$SK"
sk_declared=$(sed -n 's/.*SELFTEST OK: \([0-9][0-9]*\)\/[0-9][0-9]*.*/\1/p' "$SK" | tail -1)
sk_ran=$(grep -cE '^ *(PASS|SKIP)' "$SK")
if [ -n "$sk_declared" ] && [ "$sk_declared" != "$sk_ran" ]; then
  printf 'FAIL skills-controls says %s cases and printed %s PASS or SKIP lines\n' "$sk_declared" "$sk_ran"
  failed=$((failed+1))
fi
rm -f "$SK"
printf '\n##### the counts these pages publish\n'
readme_carries() {
  grep -q "[^0-9]$1[^0-9]" "$ROOT/README.md" && grep -q "[^0-9]$1[^0-9]" "$ROOT/README.es.md"
}
while IFS='|' read -r label number; do
  [ -n "$label" ] || continue
  if readme_carries "$number"; then
    printf '  both pages carry %s for %s\n' "$number" "$label"
  else
    printf 'FAIL neither page carries %s for %s, a count in prose that the suite can disprove\n' "$number" "$label"
    failed=$((failed+1))
  fi
done <<COUNTS
the push gate controls|$push_gate_cases
the two never-fabricate suites|$never_fabricate_cases
the skills controls|$sk_ran
the format gate suite|$format_gate_cases
COUNTS

printf '\n##### syntax of every hook and every test\n'
for f in "$HOOKS"/*.sh "$ROOT"/tests/*.sh; do
  case "$f" in *measure-comments.sh) bash -n "$f" ;; *) sh -n "$f" ;; esac || { printf 'SYNTAX ERROR %s\n' "$f"; failed=$((failed+1)); }
done
printf '\n'
[ "$failed" -eq 0 ] && printf 'ALL SELFTESTS OK\n' && exit 0
printf '%s SELFTEST(S) FAILED\n' "$failed"; exit 1
