#!/bin/sh
# Prisma Harness. Documented in README.md, section "What is inside".

. "$(cd "$(dirname "$0")" && pwd)/controls-lib.sh"

SAID="$T/said"
receipt_tail() { tail -1 "$PRISMA_RECEIPT_FILE" 2>/dev/null | cut -f2-4 | tr '\t' ' '; }
expect_receipt() {
  added=$(( $(receipt_lines) - $3 )); said=$(cat "$SAID" 2>/dev/null)
  case "$said" in *"$4"*) heard=1 ;; *) heard=0 ;; esac
  if [ "$heard" = "1" ] && [ "$2" = "none" ] && [ "$added" = "0" ]; then pass "$1"
  elif [ "$heard" = "1" ] && [ "$2" != "none" ] && [ "$added" = "1" ] && [ "$(receipt_tail)" = "$2" ]; then pass "$1"
  else fail "$1, it added $added line(s), the last one is [$(receipt_tail)] and it said [$said]"; fi
}
run_index_gate() { PRISMA_DOCS_ROOT="$site" /bin/sh "$HOOKS/gate-read-index.sh" > "$SAID" 2>&1; echo "rc=$?" >> "$SAID"; }
index_payload() { printf '{"tool_name":"Write","transcript_path":"%s","tool_input":{"file_path":"%s"}}' "$1" "$2"; }
run_format_gate() { /bin/sh "${GATE_DIR:-$HOOKS}/format-gate.sh" "$@" > "$SAID" 2>&1; echo "rc=$?" >> "$SAID"; }

site="$T/receipt-site"
mkdir -p "$site/wiki"
no_jq="$T/bin-without-jq"
mkdir -p "$no_jq"
for tool in cat dirname basename sed tr mkdir date grep; do ln -s "$(command -v "$tool")" "$no_jq/$tool" 2>/dev/null; done
if PATH="$no_jq" /bin/sh -c 'dirname /a/b && date && mkdir -p "$1"' probe "$T/probe-dir" >/dev/null 2>&1; then
  n=$(receipt_lines); index_payload "$T/none.jsonl" "$site/wiki/p.md" | PATH="$no_jq" run_index_gate
  expect_receipt "N1 the index gate without jq leaves a not-measured line for a page under the docs" "index-gate $site not-measured" "$n" "jq is missing"
  n=$(receipt_lines); index_payload "$T/none.jsonl" "$site/src/main.go" | PATH="$no_jq" run_index_gate
  expect_receipt "N2 counterexample, without jq a write outside the docs still leaves nothing" none "$n" "rc=0"
else
  skip "N1 tools copied into another directory cannot run on this system, so a machine without jq cannot be simulated here"
  skip "N2 tools copied into another directory cannot run on this system, so a machine without jq cannot be simulated here"
fi
n=$(receipt_lines); printf '' | run_index_gate
expect_receipt "N3 an empty payload leaves a not-measured line" "index-gate $site not-measured" "$n" "empty payload"
n=$(receipt_lines); printf 'this is not json' | run_index_gate
expect_receipt "N4 a payload it cannot parse leaves a not-measured line" "index-gate $site not-measured" "$n" "could not parse the payload"
n=$(receipt_lines); printf '{"tool_input":"x"}' | run_index_gate
expect_receipt "N5 JSON of the wrong shape leaves a not-measured line" "index-gate $site not-measured" "$n" "could not read a file path"
n=$(receipt_lines); printf '{"tool_name":"Write","tool_input":{}}' | run_index_gate
expect_receipt "N6 a write without a file path leaves a not-measured line" "index-gate $site not-measured" "$n" "found no file path"
n=$(receipt_lines); index_payload "$T/no-such-transcript.jsonl" "$site/wiki/p.md" | run_index_gate
expect_receipt "N7 a transcript it cannot find leaves a not-measured line" "index-gate $site not-measured" "$n" "could not read the transcript, nothing"
printf 'this line is not json\n' > "$T/broken.jsonl"
n=$(receipt_lines); index_payload "$T/broken.jsonl" "$site/wiki/p.md" | run_index_gate
expect_receipt "N8 a transcript jq cannot parse leaves a not-measured line" "index-gate $site not-measured" "$n" "could not read the transcript, so"
n=$(receipt_lines); index_payload "$T/no-such-transcript.jsonl" "$site/notes.md" | run_index_gate
expect_receipt "N9 counterexample, a write outside the docs leaves nothing and exits 0" none "$n" "rc=0"

printf '# p\n\ntext\n' > "$site/wiki/p.md"
no_reader="$T/hooks-without-the-reader"
cp -R "$HOOKS" "$no_reader" && rm -f "$no_reader/read-format-config.sh"
n=$(receipt_lines); ( GATE_DIR="$no_reader" PRISMA_HOOKS_DIR="$no_reader" PRISMA_DOCS_ROOT="$site" run_format_gate --changed )
expect_receipt "N10 the format gate without its config reader leaves a not-measured line" "format-gate $site not-measured" "$n" "read-format-config.sh is missing"
n=$(receipt_lines); ( GATE_DIR="$no_reader" PRISMA_HOOKS_DIR="$no_reader" PRISMA_DOCS_ROOT="$site" run_format_gate --strict "$site/wiki/p.md" )
expect_receipt "N11 by hand, a missing config reader exits 1 and writes no receipt" none "$n" "rc=1"
n=$(receipt_lines); ( PRISMA_DOCS_ROOT="$site" PRISMA_TMPDIR="$T/nonexistent-dir" run_format_gate --changed )
expect_receipt "N12 a tally it cannot create leaves a not-measured line" "format-gate $site not-measured" "$n" "could not create its tally file"
shims="$T/shims"
mkdir -p "$shims" "$T/tally-dir"
printf '#!/bin/sh\nprintf "%%s\\n" "$PRISMA_TMPDIR/prisma-tally-never-created"\n' > "$shims/mktemp"
printf '#!/bin/sh\nrm -f "$PRISMA_TMPDIR"/prisma-tally-*\nexec "$REAL_HEAD" "$@"\n' > "$shims/head"
chmod +x "$shims/mktemp" "$shims/head"
n=$(receipt_lines); ( PATH="$shims:$PATH" PRISMA_DOCS_ROOT="$site" PRISMA_TMPDIR="$T/tally-dir" run_format_gate --changed )
expect_receipt "N13 a tally path that never became a file leaves a not-measured line" "format-gate $site not-measured" "$n" "could not create its tally file"
rm -f "$shims/mktemp"
n=$(receipt_lines); ( REAL_HEAD=$(command -v head); export REAL_HEAD; PATH="$shims:$PATH" PRISMA_DOCS_ROOT="$site" PRISMA_TMPDIR="$T/tally-dir" run_format_gate --changed )
expect_receipt "N14 a tally lost during the review leaves a not-measured line" "format-gate $site not-measured" "$n" "lost its tally file"
mkdir -p "$site/wiki/locked" && chmod 000 "$site/wiki/locked"
if ls "$site/wiki/locked" >/dev/null 2>&1; then
  skip "N15 this filesystem does not enforce directory permissions, so find cannot be made to fail here"
else
  n=$(receipt_lines); ( PRISMA_DOCS_ROOT="$site" run_format_gate --changed )
  expect_receipt "N15 a docs directory find cannot list leaves a not-measured line" "format-gate $site not-measured" "$n" "could not list today's pages"
fi
chmod 700 "$site/wiki/locked"
mkdir -p "$T/no-wiki-here"
n=$(receipt_lines); ( PRISMA_DOCS_ROOT="$T/no-wiki-here" PRISMA_TMPDIR="$T/nonexistent-dir" run_format_gate --changed )
expect_receipt "N16 counterexample, a project without a docs directory leaves nothing even with a broken tally" none "$n" "found no directory"
mkdir -p "$T/old-site/wiki" && printf '# old\n' > "$T/old-site/wiki/old.md" && touch -t 202001010000 "$T/old-site/wiki/old.md"
n=$(receipt_lines); ( PRISMA_DOCS_ROOT="$T/old-site" PRISMA_TMPDIR="$T/nonexistent-dir" run_format_gate --changed )
expect_receipt "N17 counterexample, no page touched today leaves nothing even with a broken tally" none "$n" "touched today"
n=$(receipt_lines); ( GATE_DIR="$no_reader" PRISMA_HOOKS_DIR="$no_reader" PRISMA_DOCS_ROOT="$T/old-site" run_format_gate --changed )
expect_receipt "N18 counterexample, no page touched today leaves nothing even without the config reader" none "$n" "touched today"
mkdir -p "$T/exempt-site/wiki/raw" && printf '# raw\n' > "$T/exempt-site/wiki/raw/r.md"
n=$(receipt_lines); ( PRISMA_DOCS_ROOT="$T/exempt-site" PRISMA_TMPDIR="$T/nonexistent-dir" run_format_gate --changed )
expect_receipt "N19 counterexample, only exempt pages touched today leave nothing even with a broken tally" none "$n" "touched today"

no_rate_rule="$T/hooks-without-the-rate-rule"
cp -R "$HOOKS" "$no_rate_rule" && rm -f "$no_rate_rule/rate-rule.sh"
n=$(receipt_lines); ( GATE_DIR="$no_rate_rule" PRISMA_HOOKS_DIR="$no_rate_rule" PRISMA_DOCS_ROOT="$site" run_format_gate --changed )
expect_receipt "N20 the format gate without its rate rule leaves a not-measured line" "format-gate $site not-measured" "$n" "rate-rule.sh is missing"
n=$(receipt_lines); ( GATE_DIR="$no_rate_rule" PRISMA_HOOKS_DIR="$no_rate_rule" PRISMA_DOCS_ROOT="$site" run_format_gate --strict "$site/wiki/p.md" )
expect_receipt "N21 by hand, a missing rate rule exits 1 and writes no receipt" none "$n" "rc=1"

finish
