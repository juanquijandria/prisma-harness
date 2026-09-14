#!/bin/sh
# Prisma Harness. Documented in README.md, section "blind-replica", and in METHOD.md, "Single-model mode".

SELF=$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")
MIN_WORDS=50

usage() {
  cat >&2 <<USAGE
usage: blind-replica.sh <brief.txt>        print the blind brief, or run PRISMA_AUDITOR_CMD on it
       blind-replica.sh --selftest

The brief carries ONLY the claim and the sources. Never the calculation, the
query or the reasoning behind the claim. If PRISMA_AUDITOR_CMD is set, the brief
is piped into it and its answer is validated (exit 4 if it is an error or shorter
than $MIN_WORDS words). If it is not set, the brief is printed for you to hand to a
fresh-context subagent, and the output is labeled as single-model.
USAGE
  exit 2
}

validate_verdict() {
  text="$1"
  words=$(printf '%s' "$text" | wc -w | tr -d ' ')
  first=$(printf '%s' "$text" | sed -n '1p' | tr '[:upper:]' '[:lower:]')
  case "$first" in
    error*|failed*|"command not found"*) return 1 ;;
  esac
  [ "$words" -ge "$MIN_WORDS" ]
}

build_brief() {
  brief="$1"
  cat <<BRIEF
You are the blind replica of a PRISMA check. You receive a claim and its sources
and nothing else. Do not ask for the author's calculation or reasoning and do not
try to infer it. Produce your own figure or verdict, your method, your premises,
and your limits, in that order. If something requires executing code you cannot
run, mark it "not verified" instead of inferring it. Silence is not approval.

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
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '^\[SINGLE-MODEL' && printf '%s' "$out" | grep -q 'CLAIM AND SOURCES'; then
    printf 'PASS without auditor: prints the brief with the single-model label\n'
  else printf 'FAIL without auditor (rc=%s)\n%s\n' "$rc" "$out"; ok=0; fi

  if printf '%s' "$out" | grep -qi 'calculation:'; then
    printf 'FAIL the brief leaked something that looks like a calculation\n'; ok=0
  else printf 'PASS the brief carries only what the file carries\n'; fi

  cat > "$T/good-auditor.sh" <<'A'
#!/bin/sh
cat >/dev/null
i=0; while [ $i -lt 60 ]; do printf 'word '; i=$((i+1)); done; printf '\nMethod: counted lines.\n'
A
  chmod +x "$T/good-auditor.sh"
  out=$(PRISMA_AUDITOR_CMD="$T/good-auditor.sh" /bin/sh "$SELF" "$T/brief.txt"); rc=$?
  if [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -q '^\[SINGLE-MODEL'; then
    printf 'PASS with auditor: returns its verdict without the single-model label\n'
  else printf 'FAIL with auditor (rc=%s)\n%s\n' "$rc" "$out"; ok=0; fi

  printf '#!/bin/sh\ncat >/dev/null; echo "Error: model does not exist"\n' > "$T/error-auditor.sh"; chmod +x "$T/error-auditor.sh"
  PRISMA_AUDITOR_CMD="$T/error-auditor.sh" /bin/sh "$SELF" "$T/brief.txt" >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 4 ]; then printf 'PASS an error text is not delivered as a verdict (exit 4)\n'
  else printf 'FAIL error text accepted (rc=%s)\n' "$rc"; ok=0; fi

  printf '#!/bin/sh\ncat >/dev/null; echo "looks fine"\n' > "$T/short-auditor.sh"; chmod +x "$T/short-auditor.sh"
  PRISMA_AUDITOR_CMD="$T/short-auditor.sh" /bin/sh "$SELF" "$T/brief.txt" >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 4 ]; then printf 'PASS a %s-word answer is not delivered as a verdict (exit 4)\n' 2
  else printf 'FAIL short answer accepted (rc=%s)\n' "$rc"; ok=0; fi

  printf '#!/bin/sh\ncat >/dev/null; i=0; while [ $i -lt 60 ]; do printf "w "; i=$((i+1)); done; exit 42\n' > "$T/crash-auditor.sh"; chmod +x "$T/crash-auditor.sh"
  PRISMA_AUDITOR_CMD="$T/crash-auditor.sh" /bin/sh "$SELF" "$T/brief.txt" >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 4 ]; then printf 'PASS a non-zero auditor exit is not delivered as a verdict (exit 4)\n'
  else printf 'FAIL crashed auditor accepted (rc=%s)\n' "$rc"; ok=0; fi

  /bin/sh "$SELF" "$T/missing.txt" >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 2 ]; then printf 'PASS a missing brief exits 2\n'
  else printf 'FAIL missing brief (rc=%s)\n' "$rc"; ok=0; fi

  rm -rf "$T"
  [ "$ok" -eq 1 ] && printf 'SELFTEST OK: 7/7\n' && return 0
  printf 'SELFTEST FAILED\n'; return 1
}

case "${1:-}" in
  --selftest) selftest; exit $? ;;
  ""|-h|--help) usage ;;
esac

BRIEF_FILE="$1"
[ -r "$BRIEF_FILE" ] || { printf 'blind-replica: cannot read %s\n' "$BRIEF_FILE" >&2; exit 2; }

if [ -n "${PRISMA_AUDITOR_CMD:-}" ]; then
  raw=$(mktemp)
  build_brief "$BRIEF_FILE" | $PRISMA_AUDITOR_CMD > "$raw" 2>&1
  rc=$?
  verdict=$(cat "$raw"); rm -f "$raw"
  if [ "$rc" -ne 0 ]; then
    printf 'blind-replica: the auditor exited %s, no verdict delivered.\n%s\n' "$rc" "$verdict" >&2
    exit 4
  fi
  if ! validate_verdict "$verdict"; then
    printf 'blind-replica: the auditor answer is an error or too short to be a verdict, not delivered.\n%s\n' "$verdict" >&2
    exit 4
  fi
  printf '%s\n' "$verdict"
  exit 0
fi

printf '[SINGLE-MODEL MODE. No second engine is configured. Hand this brief to a subagent with a FRESH context, never to the session that produced the claim. This gives independence of derivation, not of engine. Set PRISMA_AUDITOR_CMD to use another engine.]\n\n'
build_brief "$BRIEF_FILE"
exit 0
