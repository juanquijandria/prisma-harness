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

# W1
mangle_dir="$T/native-windows-bin"
mkdir -p "$mangle_dir"
cat > "$mangle_dir/jq" <<MANGLE
#!/bin/sh
args=""
countdown=0
for a in "\$@"; do
  [ "\$countdown" = "1" ] && case "\$a" in /*) a="C:/Temp\${a}" ;; esac
  [ "\$countdown" -gt 0 ] && countdown=\$((countdown-1))
  [ "\$a" = "--arg" ] && countdown=2
  args="\$args '\$a'"
done
eval exec $(command -v jq) \$args
MANGLE
chmod +x "$mangle_dir/jq"
tx="$T/mangle.jsonl"
{ tool_use tu_m Read; tool_result tu_m false; } > "$tx"
out=$(printf '{"tool_name":"Write","transcript_path":"%s","tool_input":{"file_path":"%s/wiki/p.md"}}' "$tx" "$root" | PRISMA_DOCS_ROOT="$root" PATH="$mangle_dir:$PATH" sh "$HOOKS/gate-read-index.sh" 2>&1); rc=$?
if [ "$rc" = "0" ]; then
  pass "W1 a jq that rewrites unix paths, as Git Bash does for a native binary, does not hide that the index was read"
else
  fail "W1 path rewriting turned a read index into a block (rc=$rc) out=[$out]"
fi

printf '{}\n' > "$T/empty.jsonl"
r1=$(printf '{"tool_name":"Write","transcript_path":"%s","tool_input":{"file_path":"%s/./wiki/p.md"}}' "$T/empty.jsonl" "$root" | PRISMA_DOCS_ROOT="$root" sh "$HOOKS/gate-read-index.sh" >/dev/null 2>&1; echo $?)
r2=$(printf '{"tool_name":"Write","transcript_path":"%s","tool_input":{"file_path":"%s//wiki/p.md"}}' "$T/empty.jsonl" "$root" | PRISMA_DOCS_ROOT="$root" sh "$HOOKS/gate-read-index.sh" >/dev/null 2>&1; echo $?)
if [ "$r1" = "2" ] && [ "$r2" = "2" ]; then
  pass "X1 a dot or a double slash in the path does not walk around the index gate"
else
  fail "X1 the gate was bypassed by a normalised path (dot=$r1 doubleslash=$r2)"
fi

# X2
docs_missing=$(PRISMA_DOCS_ROOT="$T" PRISMA_DOCS_DIR=no-such-dir sh "$HOOKS/format-gate.sh" --changed 2>&1); rc=$?
if [ "$rc" = "0" ] && printf '%s' "$docs_missing" | grep -q WARN; then
  pass "X2 a docs directory that does not exist warns instead of dying in silence"
else
  fail "X2 a missing docs directory produced rc=$rc and [$docs_missing]"
fi

# X3
spaced="$T/spaced"; mkdir -p "$spaced/wiki"
printf '# a clean page\n\nNothing wrong here.\n' > "$spaced/wiki/mi pagina.md"
out=$(PRISMA_DOCS_ROOT="$spaced" PRISMA_RULE_KEBAB_CASE=0 sh "$HOOKS/format-gate.sh" --changed 2>&1); rc=$?
if [ "$rc" = "0" ] && ! printf '%s' "$out" | grep -q 'does not exist'; then
  pass "X3 a page whose name has a space is reviewed as one page and not as two that do not exist"
else
  fail "X3 a space in the name produced rc=$rc and [$out]"
fi

# X4
out=$(sh "$HOOKS/format-gate.sh" --strict --changed 2>&1 >/dev/null); rc=$?
if [ "$rc" = "0" ]; then
  pass "X4 the hook mode is recognised whatever position its flag is in"
else
  fail "X4 --strict --changed exited $rc, which blocks a session on the command line"
fi

# C1
cloned="$T/a-repo-you-cloned"
mkdir -p "$cloned/wiki"
canary="$T/the-config-ran-a-command"
printf 'EXEMPT_DIRS="raw"\nprintf x > "%s"\n' "$canary" > "$cloned/.prisma-format.conf"
printf '# a page\n\nplain text with nothing wrong.\n' > "$cloned/wiki/p.md"
PRISMA_DOCS_ROOT="$cloned" PRISMA_FORMAT_CONFIG="$cloned/.prisma-format.conf" sh "$HOOKS/format-gate.sh" --changed >/dev/null 2>&1
if [ -f "$canary" ]; then
  fail "C1 the format configuration of a repository ran a command"
else
  pass "C1 the format configuration is read as data and cannot run a command"
fi

# C2
configured="$T/a-repo-with-a-real-config"
mkdir -p "$configured/wiki"
printf 'RULE_EM_DASH=0\nNOT_A_RULE=whatever\n' > "$configured/.prisma-format.conf"
printf '# a page\n\nEsto tiene un guion largo \342\200\224 adentro.\n' > "$configured/wiki/p.md"
c2_out=$(PRISMA_DOCS_ROOT="$configured" PRISMA_FORMAT_CONFIG="$configured/.prisma-format.conf" sh "$HOOKS/format-gate.sh" --strict "$configured/wiki/p.md" 2>&1)
if printf '%s' "$c2_out" | grep -q 'em-dash'; then
  fail "C2 a known key in the configuration stopped being applied: $c2_out"
elif printf '%s' "$c2_out" | grep -q 'NOT_A_RULE'; then
  pass "C2 a known key still applies and an unknown key is named and ignored"
else
  fail "C2 an unknown key passed without a word: $c2_out"
fi

finish
