#!/bin/sh
# Prisma Harness. Controls proving the format gate and the index gate never fabricate a verdict.

. "$(cd "$(dirname "$0")" && pwd)/controls-lib.sh"

page="$T/wiki/a-page.md"
mkdir -p "$T/wiki"
printf '# a page\n\nEsto tiene un guion largo \342\200\224 roto.\n' > "$page"
err=$(PRISMA_DOCS_ROOT="$T" PRISMA_TMPDIR="$T/nonexistent-dir" sh "$HOOKS/format-gate.sh" --strict "$page" 2>&1 >"$T/a3.out"); rc=$?
if printf '%s' "$err" | grep -q WARN && ! grep -q '^PASS:' "$T/a3.out"; then
  pass "A3 a tally it cannot create warns and never certifies PASS"
else
  fail "A3 (rc=$rc) stderr=[$err] stdout=[$(cat "$T/a3.out")]"
fi

err=$(sh "$HOOKS/format-gate.sh" --bogus-option 2>&1 >/dev/null); rc=$?
if [ "$rc" = "1" ]; then
  pass "R10a a usage error exits 1, which no hook reads as a block"
else
  fail "R10a a usage error exited $rc"
fi

err=$(PRISMA_DOCS_ROOT="$T" PRISMA_TMPDIR="$T/nonexistent-dir" sh "$HOOKS/format-gate.sh" --changed 2>&1 >/dev/null); rc=$?
if [ "$rc" = "0" ] && printf '%s' "$err" | grep -q WARN; then
  pass "R10b in hook mode a gate that cannot measure warns and exits 0"
else
  fail "R10b in hook mode exited $rc with [$err]"
fi

out=$(printf 'this is not json' | sh "$HOOKS/gate-read-index.sh" 2>&1); rc=$?
if printf '%s' "$out" | grep -q WARN; then
  pass "B5 a payload it cannot parse warns"
else
  fail "B5 an unparseable payload produced no output at all"
fi

out=$(printf '' | sh "$HOOKS/gate-read-index.sh" 2>&1); rc=$?
if printf '%s' "$out" | grep -q WARN; then
  pass "R8 an empty payload warns instead of exiting in silence"
else
  fail "R8 an empty payload produced no output at all (rc=$rc)"
fi

root="$T/index-root"
mkdir -p "$root/wiki"
index_gate() { printf '{"tool_name":"Write","transcript_path":"%s","tool_input":{"file_path":"%s/wiki/p.md"}}' "$1" "$root" | PRISMA_DOCS_ROOT="$root" sh "$HOOKS/gate-read-index.sh" 2>&1; }
tool_use() { printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"%s","name":"%s","input":{"file_path":"%s/index.md"}}]}}\n' "$1" "$2" "$root"; }
tool_result() { printf '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"%s","is_error":%s,"content":"x"}]}}\n' "$1" "$2"; }
tx="$T/write-ok.jsonl"
{ tool_use tu_w Write; tool_result tu_w false; } > "$tx"
out=$(index_gate "$tx"); rc=$?
if [ "$rc" = "0" ]; then
  pass "F4a a Write of the index that succeeded counts as knowing it"
else
  fail "F4a a successful Write of the index was refused as evidence (rc=$rc)"
fi

tx="$T/write-err.jsonl"
{ tool_use tu_w Write; tool_result tu_w true; } > "$tx"
out=$(index_gate "$tx"); rc=$?
if [ "$rc" = "2" ]; then
  pass "F4c a Write of the index that errored does not count"
else
  fail "F4c a failed Write was accepted as evidence (rc=$rc)"
fi

tx="$T/read-noid.jsonl"
{ printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"%s/index.md"}}]}}\n' "$root"; tool_result tu_x true; } > "$tx"
out=$(index_gate "$tx"); rc=$?
if [ "$rc" = "2" ]; then
  pass "F4d a tool call without an id is not evidence"
else
  fail "F4d a Read without an id was accepted as evidence (rc=$rc)"
fi

tx="$T/read-spaceid.jsonl"
{ tool_use "tu 1" Read; tool_result "tu 1" true; } > "$tx"
out=$(index_gate "$tx"); rc=$?
if [ "$rc" = "2" ]; then
  pass "F4e an id with a space is matched whole, not word-split"
else
  fail "F4e an id with a space slipped through (rc=$rc)"
fi

tx2="$T/failed-read-tx.jsonl"
{ tool_use tu_1 Read; tool_result tu_1 true; } > "$tx2"
out=$(index_gate "$tx2"); rc=$?
if [ "$rc" = "2" ]; then
  pass "F4b a read that errored does not count as having read it"
else
  fail "F4b a failed Read was accepted as evidence (rc=$rc)"
fi

finish
