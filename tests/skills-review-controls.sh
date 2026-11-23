#!/bin/sh
# Prisma Harness. Controls over what the skills say about the standards sources of a review, and that the gate reads the line the build skill tells the builder to write.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/hooks/selftest-env.sh"
T=$(mktemp -d)
ok=1
CASES=0
JQ=$(command -v jq)
SOURCES_HEADING="^## Find the standards sources"
NEXT_HEADING="^## The smells baseline"
SOURCES_CLAUSES="Do not stop at the list the caller passed|Search the repository for every file that documents how code is written|open each one|hooks/review-reads-standards.sh|list of the sources you read"
SOURCES_SEARCH_RULE="Search the repository for every file that documents how code is written"
STANDARDS_LINE_RULE="on one line that starts with"
LABEL_IN_BACKTICKS='s/.*on one line that starts with `\([^`]*\)`.*/\1/p'
MUTANT_LABEL="Rules:"
HELD=2

pass() { CASES=$((CASES+1)); printf 'PASS %s\n' "$1"; }
skip() { CASES=$((CASES+1)); printf 'SKIP %s\n' "$1"; }
fail() { CASES=$((CASES+1)); printf 'FAIL %s\n' "$1"; ok=0; }

carries_every_clause() {
  text="$1"; old_ifs=$IFS; IFS='|'
  for clause in $2; do
    case "$text" in *"$clause"*) ;; *) IFS=$old_ifs; return 1 ;; esac
  done
  IFS=$old_ifs
}

check_review_searches() {
  carries_every_clause "$(sed -n "/$SOURCES_HEADING/,/$NEXT_HEADING/p" "$1/prisma-fidelity-review/SKILL.md")" "$SOURCES_CLAUSES"
}

label_the_builder_writes() { sed -n "$LABEL_IN_BACKTICKS" "$1/prisma-build/SKILL.md" | head -1; }

check_gate_reads_the_label() {
  label=$(label_the_builder_writes "$1"); [ -n "$label" ] || return 1
  printf '# Code rules\n' > "$T/code-rules.md"
  "$JQ" -nc --arg text "Invoke prisma-harness:prisma-fidelity-review. $label $T/code-rules.md" '{type: "user", message: {content: $text}}' > "$T/agent.jsonl"
  "$JQ" -nc --arg transcript "$T/agent.jsonl" --arg cwd "$T" '{agent_type: "general-purpose", agent_transcript_path: $transcript, cwd: $cwd, stop_hook_active: false}' \
    | sh "$ROOT/hooks/review-reads-standards.sh" >/dev/null 2>&1
  [ "$?" = "$HELD" ]
}

mutate() { rm -rf "$T/skills"; cp -R "$ROOT/skills" "$T/skills"; }

if check_review_searches "$ROOT/skills"; then pass "prisma-fidelity-review searches the repository for its standards sources, opens each one and lists what it read"; else fail "prisma-fidelity-review standards sources"; fi
if carries_every_clause "$(cat "$ROOT/skills/prisma-build/SKILL.md")" "$STANDARDS_LINE_RULE"; then pass "prisma-build puts the standards files on one labelled line"; else fail "prisma-build standards line"; fi
mutate; grep -vF "$SOURCES_SEARCH_RULE" "$T/skills/prisma-fidelity-review/SKILL.md" > "$T/r.md"; mv "$T/r.md" "$T/skills/prisma-fidelity-review/SKILL.md"
if check_review_searches "$T/skills"; then fail "control: removing the search of the repository was not caught"; else pass "control: removing the search of the repository turns the standards sources case red"; fi
if [ -z "$JQ" ]; then
  skip "the gate reads the label the build skill gives, this case needs jq"
  skip "control: a label the gate does not read, this case needs jq"
else
  if check_gate_reads_the_label "$ROOT/skills"; then pass "the review reads gate holds a review whose prompt carries the line prisma-build tells the builder to write"; else fail "the gate does not read the label prisma-build gives"; fi
  mutate; sed "s/\`$(label_the_builder_writes "$ROOT/skills")\`/\`$MUTANT_LABEL\`/" "$T/skills/prisma-build/SKILL.md" > "$T/b.md"; mv "$T/b.md" "$T/skills/prisma-build/SKILL.md"
  if check_gate_reads_the_label "$T/skills"; then fail "control: a label the gate does not read was not caught"; else pass "control: a label the gate does not read turns the label case red"; fi
fi

rm -rf "$T"
if [ "$ok" = "1" ]; then printf 'SELFTEST OK: %d/%d\n' "$CASES" "$CASES"; exit 0; fi
printf 'SELFTEST FAILED\n'; exit 1
