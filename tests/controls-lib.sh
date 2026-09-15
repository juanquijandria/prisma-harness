#!/bin/sh
# Prisma Harness. Shared helpers for the controls that prove no gate fabricates a verdict.

HOOKS="$(cd "$(dirname "$0")/../hooks" && pwd)"
T=$(mktemp -d)
export PRISMA_RECEIPT_FILE="$T/receipts.log"
ok=1
CASES=0

pass() { CASES=$((CASES+1)); printf 'PASS %s\n' "$1"; }
skip() { CASES=$((CASES+1)); printf 'SKIP %s\n' "$1"; }
fail() { CASES=$((CASES+1)); printf 'FAIL %s\n' "$1"; ok=0; }

payload() { printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"%s"}}' "$1" "$2"; }
receipt_lines() { [ -f "$PRISMA_RECEIPT_FILE" ] && wc -l < "$PRISMA_RECEIPT_FILE" | tr -d ' ' || echo 0; }

fixture_repo() {
  dir="$1"
  mkdir -p "$dir" && git -C "$dir" init -q && git -C "$dir" symbolic-ref HEAD refs/heads/main
  git -C "$dir" config user.email t@t; git -C "$dir" config user.name t
}

finish() {
  rm -rf "$T"
  if [ "$ok" = "1" ]; then
    printf 'SELFTEST OK: %d/%d\n' "$CASES" "$CASES"
    exit 0
  fi
  printf 'SELFTEST FAILED\n'
  exit 1
}
