#!/bin/sh
# Prisma Harness. Documented in README.md, section "What is inside".
# PRISMA_RECEIPT_ENTRYPOINT_MARKER, how this file knows it is the script being run and not a library.

receipt_file() {
  printf '%s' "${PRISMA_RECEIPT_FILE:-$HOME/.prisma-harness/receipts.log}"
}

receipt_append() {
  [ "${PRISMA_RECEIPT:-1}" = "1" ] || return 0
  gate="$1"; repo="${2:-unknown}"; outcome="${3:-blocked}"
  RECEIPT_FILE=$(receipt_file)
  mkdir -p "$(dirname "$RECEIPT_FILE")" 2>/dev/null || return 0
  printf '%s\t%s\t%s\t%s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$gate" "$repo" "$outcome" >> "$RECEIPT_FILE" 2>/dev/null || return 0
}

receipt_summary() {
  RECEIPT_FILE=$(receipt_file)
  if [ ! -s "$RECEIPT_FILE" ]; then
    printf 'PRISMA receipt: no gate has blocked anything yet. File: %s\n' "$RECEIPT_FILE"
    return 0
  fi
  printf 'PRISMA receipt, %s\n\n' "$(date +%Y-%m-%d)"
  printf '%-22s %8s %8s  %-10s %-10s\n' gate blocked escaped first last
  awk -F'\t' '
    { g=$2; n[g]++; if ($4=="escaped") e[g]++; else b[g]++
      d=substr($1,1,10); if (!(g in f) || d<f[g]) f[g]=d; if (d>l[g]) l[g]=d }
    END { for (g in n) printf "%-22s %8d %8d  %-10s %-10s\n", g, b[g]+0, e[g]+0, f[g], l[g] }
  ' "$RECEIPT_FILE" | sort
  total=$(wc -l < "$RECEIPT_FILE" | tr -d ' ')
  printf '\n%s lines. It counts blocks, not whether each block was right, and it cannot see what no gate caught. Nothing here leaves this machine unless you paste it.\n' "$total"
}

receipt_selftest() {
  SELF_PATH=$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")
  ok=1; T=$(mktemp -d); export PRISMA_RECEIPT_FILE="$T/r.log"
  receipt_append size-gate /repo/a blocked
  receipt_append size-gate /repo/a escaped
  receipt_append comments-gate /repo/b blocked
  n=$(wc -l < "$PRISMA_RECEIPT_FILE" | tr -d ' ')
  [ "$n" = "3" ] && printf 'PASS one line per event, 3 events give 3 lines\n' || { printf 'FAIL %s lines\n' "$n"; ok=0; }
  awk -F'\t' 'NF!=4{bad=1} END{exit bad}' "$PRISMA_RECEIPT_FILE" && printf 'PASS every line has four tab-separated fields\n' || { printf 'FAIL field count\n'; ok=0; }
  s=$(receipt_summary)
  printf '%s' "$s" | grep -qE 'size-gate +1 +1' && printf 'PASS the summary counts blocked and escaped apart\n' || { printf 'FAIL summary: %s\n' "$s"; ok=0; }
  printf '%s' "$s" | grep -qE 'comments-gate +1 +0' && printf 'PASS a gate with no escape shows zero\n' || { printf 'FAIL comments row\n'; ok=0; }
  PRISMA_RECEIPT=0 receipt_append other-gate /repo/c blocked
  n=$(wc -l < "$PRISMA_RECEIPT_FILE" | tr -d ' ')
  [ "$n" = "3" ] && printf 'PASS PRISMA_RECEIPT=0 writes nothing\n' || { printf 'FAIL switch wrote a line\n'; ok=0; }
  PRISMA_RECEIPT_FILE="$T/nodir/deeper/r.log" receipt_append x /r blocked && printf 'PASS a missing directory is created, the gate never fails on the receipt\n' || { printf 'FAIL missing dir\n'; ok=0; }
  ro="$T/ro"; mkdir -p "$ro"; chmod 500 "$ro"
  PRISMA_RECEIPT_FILE="$ro/sub/r.log" receipt_append x /r blocked && printf 'PASS an unwritable location fails open, exit 0\n' || { printf 'FAIL unwritable location broke the caller\n'; ok=0; }
  chmod 700 "$ro"
  PRISMA_RECEIPT_FILE="$T/empty.log" receipt_summary | grep -q "no gate has blocked" && printf 'PASS an empty receipt says so\n' || { printf 'FAIL empty summary\n'; ok=0; }
  printf '#!/bin/sh\nselftest() { printf "the caller keeps its own selftest\\n"; }\n. "%s"\nprintf "the caller still owns its arguments: [%%s]\\n" "$1"\nselftest\n' "$SELF_PATH" > "$T/caller.sh"
  ln -s "$SELF_PATH" "$T/prisma-receipt" 2>/dev/null
  if [ -L "$T/prisma-receipt" ]; then
    if [ "$(sh "$T/prisma-receipt" --path)" = "$PRISMA_RECEIPT_FILE" ]; then printf 'PASS it still answers under another name\n'; else printf 'FAIL renamed copy answered nothing\n'; ok=0; fi
  else printf 'SKIP no symlink on this filesystem\n'; fi
  out=$(sh "$T/caller.sh" --selftest)
  if printf '%s' "$out" | grep -q 'the caller still owns its arguments: \[--selftest\]' && printf '%s' "$out" | grep -q 'the caller keeps its own selftest' && ! printf '%s' "$out" | grep -q 'one line per event'; then printf 'PASS sourcing it takes neither the arguments nor the selftest of the caller\n'; else printf 'FAIL sourcing hijacked the caller: %s\n' "$out"; ok=0; fi
  rm -rf "$T"
  [ "$ok" = "1" ] && printf 'SELFTEST OK: 10/10\n' && exit 0
  printf 'SELFTEST FAILED\n'; exit 1
}

[ "${PRISMA_RECEIPT_SOURCED:-0}" = "1" ] && { PRISMA_RECEIPT_SOURCED=0; return 0; }
grep -q PRISMA_RECEIPT_ENTRYPOINT_MARKER "$0" 2>/dev/null || { return 0 2>/dev/null || exit 0; }

case "${1:-}" in
  --summary) receipt_summary; exit 0 ;;
  --path) receipt_file; printf '\n'; exit 0 ;;
  --reset)
    RECEIPT_FILE=$(receipt_file)
    [ -f "$RECEIPT_FILE" ] || { printf 'nothing to reset\n'; exit 0; }
    printf 'This empties %s. Type yes to continue: ' "$RECEIPT_FILE"; read -r answer
    [ "$answer" = "yes" ] && : > "$RECEIPT_FILE" && printf 'receipt emptied\n'; exit 0 ;;
  --selftest) receipt_selftest ;;
esac
