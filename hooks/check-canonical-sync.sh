#!/bin/sh
# Prisma Harness. Documented in README.md, section "check-canonical-sync".

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}"
CANONICAL="${PRISMA_CANONICAL:-$PLUGIN_ROOT/docs/es/METHOD.md}"
COPIES="${PRISMA_CANONICAL_COPIES:-}"
START='<!-- PRISMA-CANONICAL:START -->'
END='<!-- PRISMA-CANONICAL:END -->'
MODE="check"
DETAILS=""
INFRA=0

case "${1:-}" in
  --hook) MODE="hook" ;;
  --selftest) MODE="selftest" ;;
  "") ;;
  *) printf 'usage: check-canonical-sync.sh [--hook|--selftest]\n' >&2; exit 2 ;;
esac

JQ="${PRISMA_JQ-$(command -v jq)}"

fail_open() {
  msg="$1"
  if [ "$MODE" = "hook" ]; then
    if [ -n "$JQ" ]; then
      "$JQ" -n --arg c "CANONICAL SYNC NOT VERIFIED. $msg" \
        '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
    else
      printf 'CANONICAL SYNC NOT VERIFIED. %s\n' "$msg"
    fi
    exit 0
  fi
  printf 'CANONICAL SYNC WARN: %s\n' "$msg" >&2
  exit 0
}

for tool in awk cmp mktemp; do
  command -v "$tool" >/dev/null 2>&1 || fail_open "basic tool $tool is missing"
done

if [ -z "$COPIES" ]; then
  [ -r "$HOME/.claude/CLAUDE.md" ] && grep -q "$START" "$HOME/.claude/CLAUDE.md" 2>/dev/null && COPIES="$HOME/.claude/CLAUDE.md"
  proj="${CLAUDE_PROJECT_DIR:-$PWD}/CLAUDE.md"
  [ -r "$proj" ] && grep -q "$START" "$proj" 2>/dev/null && COPIES="$COPIES $proj"
fi

append_detail() {
  if [ -z "$DETAILS" ]; then DETAILS="$1"; else DETAILS="$DETAILS
$1"; fi
}

extract_block() {
  file="$1"
  out="$2"
  label="$3"

  if [ ! -r "$file" ]; then
    append_detail "$label, file missing or unreadable, $file"
    return 1
  fi

  starts=$(awk -v marker="$START" '$0==marker {n++} END {print n+0}' "$file" 2>/dev/null) || { INFRA=1; return 1; }
  ends=$(awk -v marker="$END" '$0==marker {n++} END {print n+0}' "$file" 2>/dev/null) || { INFRA=1; return 1; }

  if [ "$starts" -ne 1 ] || [ "$ends" -ne 1 ]; then
    append_detail "$label, invalid markers, START=$starts END=$ends, $file"
    return 1
  fi

  awk -v start="$START" -v end="$END" '
    $0==start {inside=1; next}
    $0==end {inside=0; found=1; exit}
    inside {print}
    END {if (!found) exit 1}
  ' "$file" > "$out" 2>/dev/null || {
    append_detail "$label, could not extract the block, $file"
    return 1
  }

  if [ ! -s "$out" ]; then
    append_detail "$label, empty canonical block, $file"
    return 1
  fi
  return 0
}

check_sync() {
  DETAILS=""
  INFRA=0
  TMP=$(mktemp -d 2>/dev/null) || { INFRA=1; return 2; }
  trap 'rm -rf "$TMP"' EXIT HUP INT TERM

  extract_block "$CANONICAL" "$TMP/canonical" "source" || {
    [ "$INFRA" -eq 1 ] && return 2
    return 1
  }

  i=0
  for path in $COPIES; do
    i=$((i+1))
    if extract_block "$path" "$TMP/copy$i" "copy $i"; then
      if ! cmp -s "$TMP/canonical" "$TMP/copy$i"; then
        append_detail "copy $i, block differs from the source, $path"
      fi
    fi
  done

  [ "$INFRA" -eq 1 ] && return 2
  [ -z "$DETAILS" ] && return 0
  return 1
}

selftest() {
  T=$(mktemp -d) || exit 1
  trap 'rm -rf "$T"' EXIT HUP INT TERM
  SELF=$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")
  ok=1

  make_good() {
    path="$1"; before="$2"; after="$3"
    {
      printf '# %s\n\n%s\n' "$before" "$START"
      printf '| # | Step |\n|---|---|\n| 1 | Plan |\n'
      printf '%s\n\n%s\n' "$END" "$after"
    } > "$path"
  }

  run_check() {
    PRISMA_CANONICAL="$T/canonical.md" \
    PRISMA_CANONICAL_COPIES="$T/copy-a.md $T/copy-b.md $T/copy-c.md" \
      /bin/sh "$SELF" "$@"
  }

  reset_good() {
    make_good "$T/canonical.md" "Source" "end source"
    make_good "$T/copy-a.md" "A" "end a"
    make_good "$T/copy-b.md" "B" "end b"
    make_good "$T/copy-c.md" "C" "end c"
  }

  expect_rc() {
    name="$1"; expected="$2"; shift 2
    out="$T/out"
    "$@" > "$out" 2>&1
    rc=$?
    if [ "$rc" -eq "$expected" ]; then
      printf 'PASS %s\n' "$name"
    else
      printf 'FAIL %s, expected %s and got %s\n' "$name" "$expected" "$rc"
      cat "$out"
      ok=0
    fi
  }

  reset_good
  expect_rc "four identical blocks" 0 run_check

  reset_good
  awk '{if ($0=="| 1 | Plan |") print "| 1 | Build |"; else print}' "$T/copy-b.md" > "$T/tmp"; mv "$T/tmp" "$T/copy-b.md"
  expect_rc "one divergent copy" 1 run_check
  if run_check 2>&1 | grep -q 'copy-b.md'; then
    printf 'PASS names the divergent copy\n'
  else
    printf 'FAIL does not name the divergent copy\n'; ok=0
  fi

  reset_good
  grep -v 'PRISMA-CANONICAL:END' "$T/copy-a.md" > "$T/tmp"; mv "$T/tmp" "$T/copy-a.md"
  expect_rc "missing marker" 1 run_check

  reset_good
  rm -f "$T/copy-c.md"
  expect_rc "missing file" 1 run_check

  reset_good
  printf '\ndifferent text outside the block\n' >> "$T/copy-b.md"
  expect_rc "difference outside the block is ignored" 0 run_check

  reset_good
  awk '{if ($0=="| 1 | Plan |") print "| 1 | Build |"; else print}' "$T/copy-b.md" > "$T/tmp"; mv "$T/tmp" "$T/copy-b.md"
  expect_rc "hook mode does not block on drift" 0 run_check --hook
  hook_out=$(run_check --hook 2>/dev/null)
  if [ -n "$JQ" ] && printf '%s' "$hook_out" | "$JQ" -e '.hookSpecificOutput.hookEventName=="SessionStart" and (.hookSpecificOutput.additionalContext | contains("copy-b.md"))' >/dev/null 2>&1; then
    printf 'PASS hook mode emits valid JSON and names the copy\n'
  else
    printf 'FAIL hook mode did not emit valid JSON\n'; ok=0
  fi

  plain_out=$(PRISMA_JQ="" run_check --hook 2>/dev/null)
  if printf '%s' "$plain_out" | grep -q 'copy-b.md' && ! printf '%s' "$plain_out" | grep -q 'hookSpecificOutput'; then
    printf 'PASS hook mode still reports the drift as plain text without jq\n'
  else
    printf 'FAIL hook mode without jq produced [%s]\n' "$plain_out"; ok=0
  fi

  [ "$ok" -eq 1 ] && printf 'SELFTEST OK: 9/9\n' && return 0
  printf 'SELFTEST FAILED\n'
  return 1
}

if [ "$MODE" = "selftest" ]; then
  selftest
  exit $?
fi

check_sync
rc=$?
case "$rc" in
  0)
    [ "$MODE" = "hook" ] && exit 0
    n=$(printf '%s\n' $COPIES | grep -c .)
    printf 'CANONICAL SYNC OK: the source and %s cop(y/ies) carry the same canonical block\n' "$n"
    exit 0
    ;;
  1)
    if [ "$MODE" = "hook" ]; then
      if [ -n "$JQ" ]; then
        "$JQ" -n --arg c "CANONICAL SYNC BROKEN. The source file is the single source of truth. Fix these copies before changing the method:
$DETAILS" \
          '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
      else
        printf 'CANONICAL SYNC BROKEN. The source file is the single source of truth. Fix these copies before changing the method:\n%s\n' "$DETAILS"
      fi
      exit 0
    fi
    printf 'CANONICAL SYNC FAIL:\n%s\n' "$DETAILS" >&2
    exit 1
    ;;
  2) fail_open "the comparison could not run" ;;
esac
