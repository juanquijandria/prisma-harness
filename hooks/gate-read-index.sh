#!/bin/sh
# Prisma Harness. Documented in README.md, section "gate-read-index".

SELF=$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")

DOCS_ROOT="${PRISMA_DOCS_ROOT:-${CLAUDE_PROJECT_DIR:-$PWD}}"
DOCS_DIR="${PRISMA_DOCS_DIR:-wiki}"
INDEX_FILE="${PRISMA_INDEX_FILE:-index.md}"
INDEX_PATH="$DOCS_ROOT/$INDEX_FILE"

if [ "$1" = "--selftest" ]; then
  root=$(mktemp -d)
  export PRISMA_DOCS_ROOT="$root"
  read_tx=$(mktemp)
  echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"'"$root"'/index.md"}}]}}' > "$read_tx"
  empty_tx=$(mktemp)
  echo '{}' > "$empty_tx"
  mention_tx=$(mktemp)
  echo '{"type":"user","message":{"content":"take a look at '"$root"'/index.md later"}}' > "$mention_tx"
  alarm_tx=$(mktemp)
  echo '{"type":"user","message":{"content":"INDEX GATE: you are about to write a page under wiki/ without opening the index"}}' > "$alarm_tx"
  r1=$(printf '{"tool_name":"Write","transcript_path":"%s","tool_input":{"file_path":"%s/wiki/a/b.md"}}' "$empty_tx" "$root" | "$SELF"; echo "exit=$?")
  r2=$(printf '{"tool_name":"Write","transcript_path":"%s","tool_input":{"file_path":"%s/wiki/a/b.md"}}' "$read_tx" "$root" | "$SELF"; echo "exit=$?")
  r3=$(printf '{"tool_name":"Write","transcript_path":"%s","tool_input":{"file_path":"%s/notes.md"}}' "$empty_tx" "$root" | "$SELF"; echo "exit=$?")
  r4=$(printf '{"tool_name":"Write","transcript_path":"%s","tool_input":{"file_path":"%s/wiki/a/b.md"}}' "$mention_tx" "$root" | "$SELF"; echo "exit=$?")
  r5=$(printf '{"tool_name":"Write","transcript_path":"%s","tool_input":{"file_path":"%s/wiki/a/b.md"}}' "$alarm_tx" "$root" | "$SELF"; echo "exit=$?")
  rm -rf "$read_tx" "$empty_tx" "$mention_tx" "$alarm_tx" "$root"
  ok=1
  case "$r1" in *"exit=2"*) echo "PASS case 1 (blocks when the index was not read)";; *) echo "FAIL case 1: $r1"; ok=0;; esac
  case "$r2" in *"exit=0"*) echo "PASS case 2 (passes when the index was actually read)";; *) echo "FAIL case 2: $r2"; ok=0;; esac
  case "$r3" in *"exit=0"*) echo "PASS case 3 (outside the docs dir it does not apply)";; *) echo "FAIL case 3: $r3"; ok=0;; esac
  case "$r4" in *"exit=2"*) echo "PASS case 4 (mentioning the path is not reading it)";; *) echo "FAIL case 4: $r4"; ok=0;; esac
  case "$r5" in *"exit=2"*) echo "PASS case 5 (its own alarm text does not disarm it)";; *) echo "FAIL case 5: $r5"; ok=0;; esac
  [ "$ok" = "1" ] && echo "SELFTEST OK: 5/5" && exit 0
  echo "SELFTEST FAILED"
  exit 1
fi

command -v jq >/dev/null 2>&1 || { echo "WARN: the index gate did not run, jq is missing." >&2; exit 0; }

payload=$(cat)
file_path=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null)

case "$file_path" in
  "$DOCS_ROOT/$DOCS_DIR"/*) ;;
  *) exit 0 ;;
esac

[ -n "$transcript" ] && [ -f "$transcript" ] || { echo "WARN: the index gate could not read the transcript, nothing was verified." >&2; exit 0; }

if jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") | select(.name=="Read" or .name=="Edit" or .name=="Write") | .input.file_path // empty' "$transcript" 2>/dev/null | grep -qx "$INDEX_PATH"; then
  exit 0
fi

echo "INDEX GATE: you are about to write a page under $DOCS_DIR/ without having opened $INDEX_FILE in this session. Read $INDEX_PATH first so you do not create a duplicate page or leave the index stale, then retry." >&2
exit 2
