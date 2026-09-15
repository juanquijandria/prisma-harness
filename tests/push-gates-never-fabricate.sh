#!/bin/sh
# Prisma Harness. Controls proving the push gates and their helpers never fabricate a verdict.

. "$(cd "$(dirname "$0")" && pwd)/controls-lib.sh"

permissions_bite() {
  probe="$T/probe-dir"
  mkdir -p "$probe" 2>/dev/null || return 1
  chmod 000 "$probe" 2>/dev/null || return 1
  ( cd "$probe" ) 2>/dev/null && { chmod 755 "$probe"; return 1; }
  chmod 755 "$probe"
  return 0
}

cat > "$T/crashing-python" <<'STUB'
#!/bin/sh
cat >/dev/null 2>&1
echo "Traceback (most recent call last):" >&2
echo "AttributeError: reconfigure" >&2
exit 1
STUB
chmod +x "$T/crashing-python"

out=$(printf 'git commit -m "x; PRISMA_SIZE_OK=1 y" && git push' | PRISMA_PYTHON= sh "$HOOKS/strip-quotes.sh" 2>&1); rc=$?
if [ "$rc" = "3" ] && printf '%s' "$out" | grep -q WARN; then
  pass "A1a strip-quotes without python warns and exits 3"
else
  fail "A1a strip-quotes without python returned rc=$rc out=[$out]"
fi

repo="$T/escape-repo"
fixture_repo "$repo"
printf 'export const A = 1;\n' > "$repo/a.js"
git -C "$repo" add a.js >/dev/null 2>&1; git -C "$repo" commit -qm init
git -C "$repo" checkout -qb feature
printf 'export const A = 1;\n// stray comment\n' > "$repo/a.js"; git -C "$repo" commit -qam comment
blind="$T/hooks-without-strip"
mkdir -p "$blind" && cp "$HOOKS"/*.sh "$blind"/ && rm -f "$blind/strip-quotes.sh"
hidden='git commit -m \"x; PRISMA_COMMENTS_OK=1 y\" && git push origin feature'
before=$(receipt_lines)
out=$(payload "$repo" "$hidden" | PRISMA_HOOKS_DIR="$blind" sh "$blind/pre-push-comments.sh" 2>&1); rc=$?
after=$(receipt_lines)
if [ "$rc" != "0" ] && ! { tail -1 "$PRISMA_RECEIPT_FILE" 2>/dev/null | grep -q escaped; }; then
  pass "B7 an escape hidden in quotes does not open the gate when quotes cannot be stripped"
else
  fail "B7 the hidden escape opened the gate (rc=$rc receipts $before->$after)"
fi

if permissions_bite; then
  locked="$T/locked"
  mkdir -p "$locked"; chmod 000 "$locked"
  before=$(receipt_lines)
  out=$(payload "$locked" "git push origin feature" | sh "$HOOKS/pre-push-comments.sh" 2>&1); rc=$?
  after=$(receipt_lines)
  chmod 755 "$locked"
  if [ "$rc" = "0" ] && printf '%s' "$out" | grep -q WARN && [ "$after" = "$before" ]; then
    pass "A2 a directory it cannot enter warns instead of fabricating a block"
  else
    fail "A2 fabricated a verdict (rc=$rc receipts $before->$after) out=[$out]"
  fi
else
  skip "A2 this filesystem does not enforce directory permissions"
fi

out=$("$HOOKS/measure-comments.sh" --diff "$T" 2>&1); rc=$?
if [ "$rc" = "2" ] && printf '%s' "$out" | grep -q 'could not read the diff'; then
  pass "A4 an unreadable diff is named as unreadable and exits 2"
else
  fail "A4 an unreadable diff gave rc=$rc and [$out]"
fi

base_repo="$T/no-base"
fixture_repo "$base_repo"
printf 'x\n' > "$base_repo/f.txt"; git -C "$base_repo" add f.txt >/dev/null 2>&1; git -C "$base_repo" commit -qm init
err=$(cd "$base_repo" && sh "$HOOKS/compare-base.sh" 2>&1 >/dev/null)
if printf '%s' "$err" | grep -q WARN; then
  pass "A5 a fabricated base is announced"
else
  fail "A5 returned a fabricated base in silence"
fi

out=$(printf 'git push origin main' | PRISMA_PYTHON="$T/crashing-python" sh "$HOOKS/command-invokes.sh" git push 2>&1); rc=$?
if [ "$rc" = "3" ]; then
  pass "A6 a parser that crashes is not read as no push found"
else
  fail "A6 a crashing parser exited $rc, which the gates read as no push found"
fi

cat > "$T/chatty-python" <<CH
#!/bin/sh
echo "pyenv: shim version 3.12.1" >&2
exec "$(command -v python3 || command -v python)" "\$@"
CH
chmod +x "$T/chatty-python"
out=$(printf 'git push origin main' | PRISMA_PYTHON="$T/chatty-python" sh "$HOOKS/command-invokes.sh" git push 2>"$T/r4a.err"); rc=$?
if [ "$rc" = "0" ] && printf '%s' "$out" | grep -q 'git push' && ! grep -q WARN "$T/r4a.err"; then
  pass "R4a an interpreter that talks on stderr and answers correctly is not read as a failure"
else
  fail "R4a chatty interpreter rc=$rc out=[$out] err=[$(cat "$T/r4a.err")]"
fi

out=$(printf 'git push origin main' | PRISMA_PARSER_FAULT=1 sh "$HOOKS/command-invokes.sh" git push 2>&1); rc=$?
if [ "$rc" = "3" ] && printf '%s' "$out" | grep -q WARN; then
  pass "R4b an exception inside the parser is reported as a parser failure"
else
  fail "R4b an exception inside the parser exited $rc out=[$out]"
fi

out=$(printf 'ls -la' | sh "$HOOKS/command-invokes.sh" git push 2>&1); rc=$?
if [ "$rc" = "0" ] && [ -z "$out" ]; then
  pass "R4c no push found is exit 0 with empty output, never a failure code"
else
  fail "R4c no push found exited $rc out=[$out]"
fi

out=$(printf 'git status\ngit push origin main' | sh "$HOOKS/command-invokes.sh" git push 2>&1); rc=$?
if [ "$rc" = "0" ] && printf '%s' "$out" | grep -q 'git push origin main'; then
  pass "R1a a push on the second line of a command is found"
else
  fail "R1a a push on the second line was missed (rc=$rc out=[$out])"
fi

before=$(receipt_lines)
out=$(payload "$repo" 'git status\ngit push origin feature' | sh "$HOOKS/pre-push-comments.sh" 2>&1); rc=$?
if [ "$rc" = "2" ]; then
  pass "R1b the comments gate blocks a push written on the second line"
else
  fail "R1b a push on the second line went through the comments gate (rc=$rc)"
fi

out=$(printf 'echo "a \\" ; PRISMA_SIZE_OK=1 b" && git push origin main' | sh "$HOOKS/strip-quotes.sh" 2>&1); rc=$?
if [ "$rc" = "0" ] && ! printf '%s' "$out" | grep -q PRISMA_SIZE_OK; then
  pass "R2a an escaped quote does not leak the quoted text past the stripper"
else
  fail "R2a the stripper leaked [$out]"
fi

before=$(receipt_lines)
out=$(payload "$repo" 'echo \"a \\\" ; PRISMA_COMMENTS_OK=1 b\" && git push origin feature' | sh "$HOOKS/pre-push-comments.sh" 2>&1); rc=$?
if [ "$rc" = "2" ] && ! { tail -1 "$PRISMA_RECEIPT_FILE" 2>/dev/null | grep -q escaped; }; then
  pass "R2b an escape hidden behind an escaped quote does not open the gate"
else
  fail "R2b the hidden escape opened the gate (rc=$rc) out=[$out]"
fi

bigrepo="$T/big-repo"
fixture_repo "$bigrepo"
printf 'x\n' > "$bigrepo/f.txt"; git -C "$bigrepo" add f.txt >/dev/null 2>&1; git -C "$bigrepo" commit -qm init
git -C "$bigrepo" checkout -qb feature
seq 1 1200 > "$bigrepo/big.txt"; git -C "$bigrepo" add big.txt >/dev/null 2>&1; git -C "$bigrepo" commit -qm big
hidden='git commit -m \"x; PRISMA_SIZE_OK=1 y\" && git push origin feature'
before=$(receipt_lines)
out=$(payload "$bigrepo" "$hidden" | PRISMA_HOOKS_DIR="$blind" sh "$blind/pre-push-size.sh" 2>&1); rc=$?
if [ "$rc" = "2" ] && ! { tail -1 "$PRISMA_RECEIPT_FILE" 2>/dev/null | grep -q escaped; }; then
  pass "R6 the size gate still blocks when quotes cannot be stripped and the escape hides in them"
else
  fail "R6 the size gate opened (rc=$rc) out=[$out]"
fi

lintrepo="$T/lint-repo"
fixture_repo "$lintrepo"; mkdir -p "$lintrepo/node_modules/.bin"
printf '{"name":"x"}\n' > "$lintrepo/package.json"
printf 'export const A = 1;\n' > "$lintrepo/a.js"
git -C "$lintrepo" add . >/dev/null 2>&1; git -C "$lintrepo" commit -qm init
git -C "$lintrepo" checkout -qb feature
printf 'export const A = 2;\n' > "$lintrepo/a.js"; git -C "$lintrepo" commit -qam change
cat > "$lintrepo/node_modules/.bin/eslint" <<'EL'
#!/bin/sh
echo "Oops! Something went wrong! :(" >&2
echo "ESLint could not find the config file." >&2
exit 2
EL
chmod +x "$lintrepo/node_modules/.bin/eslint"
out=$(payload "$lintrepo" "git push origin feature" | sh "$HOOKS/pre-push-lint.sh" 2>&1); rc=$?
if [ "$rc" = "0" ] && printf '%s' "$out" | grep -q WARN; then
  pass "B1 a linter that fails for a reason that is not lint warns"
else
  fail "B1 the lint gate passed in silence (rc=$rc) out=[$out]"
fi

bigrepo2="$T/size-policy-repo"
fixture_repo "$bigrepo2"
printf 'x\n' > "$bigrepo2/f.txt"; git -C "$bigrepo2" add f.txt >/dev/null 2>&1; git -C "$bigrepo2" commit -qm init
git -C "$bigrepo2" checkout -qb feature
seq 1 3200 > "$bigrepo2/big.txt"; git -C "$bigrepo2" add big.txt >/dev/null 2>&1; git -C "$bigrepo2" commit -qm big
out=$(payload "$bigrepo2" "git push origin feature" | PRISMA_SIZE_BLOCK_OVER=3000 sh "$HOOKS/pre-push-size.sh" 2>&1); rc=$?
if [ "$rc" = "2" ] && printf '%s' "$out" | grep -q '3000' && ! printf '%s' "$out" | grep -qi 'drops below half\|defect detection'; then
  pass "F2a with a custom ceiling the block message states the policy and no empirical claim"
else
  fail "F2a rc=$rc out=[$out]"
fi

seq 1 500 > "$bigrepo2/big.txt"; git -C "$bigrepo2" commit -qam smaller
out=$(payload "$bigrepo2" "git push origin feature" | sh "$HOOKS/pre-push-size.sh" 2>&1); rc=$?
if [ "$rc" = "2" ]; then
  pass "F2b the default ceiling blocks a 500-line push"
else
  fail "F2b a 500-line push passed the default ceiling (rc=$rc)"
fi

seq 1 250 > "$bigrepo2/big.txt"; git -C "$bigrepo2" commit -qam smaller-still
out=$(payload "$bigrepo2" "git push origin feature" | sh "$HOOKS/pre-push-size.sh" 2>&1); rc=$?
if [ "$rc" = "0" ] && printf '%s' "$out" | grep -qE 'WARN from the size gate: [0-9]+ lines changed'; then
  pass "F2c the default warning fires on a 250-line push without blocking"
else
  fail "F2c a 250-line push (rc=$rc) out=[$out]"
fi

# X5
out=$(payload "$repo" "git push origin feature" | PRISMA_PARSER_FAULT=1 sh "$HOOKS/pre-push-comments.sh" 2>&1); rc=$?
if [ "$rc" = "0" ] && printf '%s' "$out" | grep -q WARN && ! printf '%s' "$out" | grep -q 'has no python'; then
  pass "X5 a parser that failed for another reason is not reported as a missing python"
else
  fail "X5 the gate stated a cause it did not measure (rc=$rc)"
fi

finish
