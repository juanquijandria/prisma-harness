#!/bin/sh
# Prisma Harness. Documented in README.md, section "What is inside", and in METHOD.md, "Single-model mode".
if [ "${1:-}" = "--selftest" ]; then . "$(cd "$(dirname "$0")" && pwd)/selftest-env.sh"; fi

SELF=$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")
MIN_WORDS=50

usage() {
  cat >&2 <<USAGE
usage: blind-replica.sh <brief.txt>        print the blind brief, or run PRISMA_AUDITOR_CMD on it
       blind-replica.sh --selftest

The brief carries ONLY the claim and the sources. Never the calculation, the
query or the reasoning behind the claim.

With PRISMA_AUDITOR_CMD set, the brief is piped into it and the exit code is the
verdict. 0 the auditor confirmed, 5 it refuted, 4 no verdict, which covers an
auditor that exited non-zero, an undetermined answer, a missing VERDICT line, or
fewer than $MIN_WORDS words. The auditor's stderr passes through and is never
read as part of the answer. Without it, the brief is printed for you to hand to a fresh-context
subagent, labeled as single-model, and the exit code is 6, nobody audited.
USAGE
  exit 2
}

verdict_kind() {
  text="$1"
  words=$(printf '%s' "$text" | wc -w | tr -d ' ')
  first=$(printf '%s' "$text" | tr -d '\r' | grep -m1 . | sed 's/^[[:space:]*`_]*//; s/[[:space:]*`_]*$//')
  [ "$words" -ge "$MIN_WORDS" ] || { echo none; return; }
  case "$first" in
    "VERDICT: CONFIRMS"|"VERDICT:CONFIRMS") echo confirms ;;
    "VERDICT: REFUTES"|"VERDICT:REFUTES") echo refutes ;;
    *) echo none ;;
  esac
}

build_brief() {
  brief="$1"
  cat <<BRIEF
You are the blind replica of a PRISMA check. You receive a claim and its sources
and nothing else. Do not ask for the author's calculation or reasoning and do not
try to infer it. Produce your own figure or verdict, your method, your premises,
and your limits, in that order. If something requires executing code you cannot
run, mark it "not verified" instead of inferring it. Silence is not approval.
Your first line is exactly one of VERDICT: CONFIRMS, VERDICT: REFUTES or
VERDICT: UNDETERMINED, and everything else follows it.

--- CLAIM AND SOURCES ---
$(cat "$brief")
--- END ---
BRIEF
}

selftest() {
  T=$(mktemp -d); ok=1
  printf 'Claim: the file has 3 lines.\nSource: %s/three.txt\n' "$T" > "$T/brief.txt"
  printf 'a\nb\nc\n' > "$T/three.txt"

  out=$(PRISMA_AUDITOR_CMD= /bin/sh "$SELF" "$T/brief.txt"); rc=$?
  if [ "$rc" -eq 6 ] && printf '%s' "$out" | grep -q '^\[SINGLE-MODEL' && printf '%s' "$out" | grep -q 'CLAIM AND SOURCES'; then
    printf 'PASS without auditor: prints the brief with the single-model label and exits 6, nobody audited\n'
  else printf 'FAIL without auditor (rc=%s)\n%s\n' "$rc" "$out"; ok=0; fi

  if printf '%s' "$out" | grep -qi 'calculation:'; then
    printf 'FAIL the brief leaked something that looks like a calculation\n'; ok=0
  else printf 'PASS the brief carries only what the file carries\n'; fi

  if printf '%s' "$out" | grep -q 'VERDICT: CONFIRMS'; then
    printf 'PASS the brief asks for the verdict line\n'
  else printf 'FAIL the brief does not ask for the verdict line\n'; ok=0; fi

  auditor() { printf '#!/bin/sh\ncat >/dev/null\nprintf "%%s\\n" "%s"\ni=0; while [ $i -lt 60 ]; do printf "word "; i=$((i+1)); done; printf "\\nMethod: counted lines.\\n"\n' "$2" > "$T/$1"; chmod +x "$T/$1"; }
  auditor confirms.sh "VERDICT: CONFIRMS"
  auditor refutes.sh "VERDICT: REFUTES"
  auditor undetermined.sh "VERDICT: UNDETERMINED"
  auditor noverdict.sh "Looks fine to me."

  out=$(PRISMA_AUDITOR_CMD="$T/confirms.sh" /bin/sh "$SELF" "$T/brief.txt"); rc=$?
  if [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -q '^\[SINGLE-MODEL'; then
    printf 'PASS an auditor that confirms exits 0 without the single-model label\n'
  else printf 'FAIL confirming auditor (rc=%s)\n%s\n' "$rc" "$out"; ok=0; fi

  out=$(PRISMA_AUDITOR_CMD="$T/refutes.sh" /bin/sh "$SELF" "$T/brief.txt"); rc=$?
  if [ "$rc" -eq 5 ] && printf '%s' "$out" | grep -q 'VERDICT: REFUTES'; then
    printf 'PASS an auditor that refutes exits 5 and its answer is delivered\n'
  else printf 'FAIL refuting auditor (rc=%s)\n%s\n' "$rc" "$out"; ok=0; fi

  out=$(PRISMA_AUDITOR_CMD="$T/undetermined.sh" /bin/sh "$SELF" "$T/brief.txt" 2>&1); rc=$?
  if [ "$rc" -eq 4 ]; then printf 'PASS an undetermined answer is exit 4, no verdict\n'
  else printf 'FAIL undetermined answer (rc=%s)\n' "$rc"; ok=0; fi

  out=$(PRISMA_AUDITOR_CMD="$T/noverdict.sh" /bin/sh "$SELF" "$T/brief.txt" 2>&1); rc=$?
  if [ "$rc" -eq 4 ]; then printf 'PASS an answer without a verdict line is exit 4, never a confirmation\n'
  else printf 'FAIL answer without verdict line (rc=%s)\n' "$rc"; ok=0; fi

  printf '#!/bin/sh\ncat >/dev/null; echo "warning: model deprecated" >&2; echo "VERDICT: REFUTES"; i=0; while [ $i -lt 60 ]; do printf "w "; i=$((i+1)); done; echo\n' > "$T/noisy.sh"; chmod +x "$T/noisy.sh"
  PRISMA_AUDITOR_CMD="$T/noisy.sh" /bin/sh "$SELF" "$T/brief.txt" >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 5 ]; then printf 'PASS noise on the auditor stderr does not hide a refutation\n'
  else printf 'FAIL stderr noise turned a refutation into rc=%s\n' "$rc"; ok=0; fi

  printf '#!/bin/sh\ncat >/dev/null; echo; echo "**VERDICT: REFUTES**  "; i=0; while [ $i -lt 60 ]; do printf "w "; i=$((i+1)); done; echo\n' > "$T/bold.sh"; chmod +x "$T/bold.sh"
  PRISMA_AUDITOR_CMD="$T/bold.sh" /bin/sh "$SELF" "$T/brief.txt" >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 5 ]; then printf 'PASS a blank line, bold marks and trailing spaces around the verdict do not hide it\n'
  else printf 'FAIL cosmetic noise around the verdict gave rc=%s\n' "$rc"; ok=0; fi

  printf '#!/bin/sh\ncat >/dev/null; echo "VERDICT: CONFIRMS"; echo "looks fine"\n' > "$T/short-auditor.sh"; chmod +x "$T/short-auditor.sh"
  PRISMA_AUDITOR_CMD="$T/short-auditor.sh" /bin/sh "$SELF" "$T/brief.txt" >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 4 ]; then printf 'PASS a verdict line with no method behind it is not delivered (exit 4)\n'
  else printf 'FAIL short answer accepted (rc=%s)\n' "$rc"; ok=0; fi

  printf '#!/bin/sh\ncat >/dev/null; echo "VERDICT: CONFIRMS"; i=0; while [ $i -lt 60 ]; do printf "w "; i=$((i+1)); done; exit 42\n' > "$T/crash-auditor.sh"; chmod +x "$T/crash-auditor.sh"
  PRISMA_AUDITOR_CMD="$T/crash-auditor.sh" /bin/sh "$SELF" "$T/brief.txt" >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 4 ]; then printf 'PASS a non-zero auditor exit is not delivered as a verdict (exit 4)\n'
  else printf 'FAIL crashed auditor accepted (rc=%s)\n' "$rc"; ok=0; fi

  /bin/sh "$SELF" "$T/missing.txt" >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 2 ]; then printf 'PASS a missing brief exits 2\n'
  else printf 'FAIL missing brief (rc=%s)\n' "$rc"; ok=0; fi

  rm -rf "$T"
  [ "$ok" -eq 1 ] && printf 'SELFTEST OK: 12/12\n' && return 0
  printf 'SELFTEST FAILED\n'; return 1
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  ""|-h|--help) usage ;;
esac

BRIEF_FILE="$1"
[ -r "$BRIEF_FILE" ] || { printf 'blind-replica: cannot read %s\n' "$BRIEF_FILE" >&2; exit 2; }

if [ -n "${PRISMA_AUDITOR_CMD:-}" ]; then
  raw=$(mktemp); err=$(mktemp)
  build_brief "$BRIEF_FILE" | $PRISMA_AUDITOR_CMD > "$raw" 2>"$err"
  rc=$?
  verdict=$(cat "$raw"); [ -s "$err" ] && cat "$err" >&2; rm -f "$raw" "$err"
  if [ "$rc" -ne 0 ]; then
    printf 'blind-replica: the auditor exited %s, no verdict delivered.\n%s\n' "$rc" "$verdict" >&2
    exit 4
  fi
  case "$(verdict_kind "$verdict")" in
    confirms) printf '%s\n' "$verdict"; exit 0 ;;
    refutes) printf '%s\n' "$verdict"; exit 5 ;;
  esac
  printf 'blind-replica: no verdict delivered. The answer is an error, undetermined, missing the VERDICT line, or too short to carry a method.\n%s\n' "$verdict" >&2
  exit 4
fi

printf '[SINGLE-MODEL MODE. No second engine is configured. Hand this brief to a subagent with a FRESH context, never to the session that produced the claim. This gives independence of derivation, not of engine. Set PRISMA_AUDITOR_CMD to use another engine.]\n\n'
build_brief "$BRIEF_FILE"
exit 6
