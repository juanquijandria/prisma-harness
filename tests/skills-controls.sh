#!/bin/sh
# Prisma Harness. Controls over the text of the step skills, and positive controls on mutated copies.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T=$(mktemp -d)
ok=1
CASES=0
STEP_SKILLS="prisma-plan prisma-build prisma-fidelity-review prisma-diagnose"

pass() { CASES=$((CASES+1)); printf 'PASS %s\n' "$1"; }
fail() { CASES=$((CASES+1)); printf 'FAIL %s\n' "$1"; ok=0; }

line_of() { grep -n -m1 -- "$2" "$1" | cut -d: -f1; }

check_frontmatter() {
  for name in prisma $STEP_SKILLS; do
    f="$1/$name/SKILL.md"
    [ -f "$f" ] || return 1
    grep -qx "name: $name" "$f" || return 1
    grep -q '^description: .' "$f" || return 1
  done
  for name in $STEP_SKILLS; do
    grep -q 'disable-model-invocation' "$1/$name/SKILL.md" && return 1
  done
  return 0
}

check_no_em_dash() {
  for name in prisma $STEP_SKILLS; do
    grep -q "$(printf '\342\200\224')" "$1/$name/SKILL.md" && return 1
  done
  return 0
}

check_plan_closes() {
  f="$1/prisma-plan/SKILL.md"
  grep -q 'step 1' "$f" || return 1
  a=$(line_of "$f" '^## Closing the interview'); b=$(line_of "$f" '^## The record'); c=$(line_of "$f" '140k')
  [ -n "$a" ] && [ -n "$b" ] && [ -n "$c" ] || return 1
  [ "$a" -lt "$c" ] && [ "$c" -lt "$b" ] || return 1
  sed -n "${a},${b}p" "$f" | grep -qi 'lane'
}

check_build_order() {
  f="$1/prisma-build/SKILL.md"
  grep -q 'step 2' "$f" || return 1
  a=$(line_of "$f" 'Red is seen'); b=$(line_of "$f" 'prisma-fidelity-review'); c=$(line_of "$f" '^## The commit')
  [ -n "$a" ] && [ -n "$b" ] && [ -n "$c" ] || return 1
  [ "$a" -lt "$b" ] && [ "$b" -lt "$c" ]
}

check_review_axes() {
  f="$1/prisma-fidelity-review/SKILL.md"
  grep -q 'no more and no less' "$f" && grep -q '<fixed point>\.\.\.HEAD' "$f" && grep -q 'rev-parse' "$f" && grep -q '## Fidelity' "$f" && grep -q '## Standards' "$f"
}

check_diagnose_escape() {
  f="$1/prisma-diagnose/SKILL.md"
  grep -q 'step 2b' "$f" || return 1
  a=$(line_of "$f" '^## Close'); [ -n "$a" ] || return 1
  grep -q 'Escaped from' "$f" || return 1
  tail=$(sed -n "${a},\$p" "$f")
  for step in 'Step 1' 'Step 2' 'Step 3' 'Step 4' 'Step 5' 'The route'; do
    printf '%s' "$tail" | grep -q "$step" || return 1
  done
  return 0
}

if check_frontmatter "$ROOT/skills"; then pass "every skill has its name, a description, and the step skills stay model-invocable"; else fail "frontmatter of the skills"; fi
if check_no_em_dash "$ROOT/skills"; then pass "no em-dash in any skill, frontmatter and fences included"; else fail "an em-dash in a skill"; fi
hits=$(grep -rniE 'mattpocock|pocock|/to-spec|/to-tickets|/implement\b|grill-with-docs' "$ROOT" --exclude-dir=.git | grep -vE '^[^:]*(README(\.es)?\.md|skills-controls\.sh):' | wc -l | tr -d ' ')
credit=$(grep -ciE 'pocock' "$ROOT/README.md"); credit_es=$(grep -ciE 'pocock' "$ROOT/README.es.md")
if [ "$hits" = "0" ] && [ "$credit" = "1" ] && [ "$credit_es" = "1" ]; then pass "the external plugin is named once per README as credit and nowhere else"; else fail "external plugin references: $hits outside the READMEs and this file, $credit and $credit_es in them"; fi
if check_plan_closes "$ROOT/skills"; then pass "prisma-plan names step 1 and closes with the lane and the session ceiling"; else fail "prisma-plan closing section"; fi
if check_build_order "$ROOT/skills"; then pass "prisma-build sees red before the review and the review before the commit"; else fail "prisma-build order"; fi
if check_review_axes "$ROOT/skills"; then pass "prisma-fidelity-review pins the fixed point and keeps the two axes apart"; else fail "prisma-fidelity-review anchors"; fi
if check_diagnose_escape "$ROOT/skills"; then pass "prisma-diagnose names step 2b and closes by naming the step the defect escaped from"; else fail "prisma-diagnose closing"; fi
orphan=0
for name in $STEP_SKILLS; do
  for page in skills/prisma/SKILL.md METHOD.md docs/es/METHOD.md; do
    grep -q "$name" "$ROOT/$page" || orphan=1
  done
done
if [ "$orphan" = "0" ]; then pass "every step skill is named by prisma, by METHOD.md and by the canonical block"; else fail "a step skill is an orphan in the method pages"; fi

mutate() { rm -rf "$T/skills"; cp -R "$ROOT/skills" "$T/skills"; }
mutate; printf '\nA line with an em-dash \342\200\224 inside.\n' >> "$T/skills/prisma-build/SKILL.md"
if check_no_em_dash "$T/skills"; then fail "control: an injected em-dash was not caught"; else pass "control: an injected em-dash turns the em-dash case red"; fi
mutate; grep -v '140k' "$T/skills/prisma-plan/SKILL.md" > "$T/p.md"; mv "$T/p.md" "$T/skills/prisma-plan/SKILL.md"
if check_plan_closes "$T/skills"; then fail "control: removing the session ceiling was not caught"; else pass "control: removing the session ceiling turns the plan case red"; fi
mutate; f="$T/skills/prisma-build/SKILL.md"; { printf '## The commit\n\nMoved up.\n\n'; grep -v '^## The commit' "$f"; } > "$T/b.md"; mv "$T/b.md" "$f"
if check_build_order "$T/skills"; then fail "control: the commit moved above the red run was not caught"; else pass "control: the commit above the red run turns the order case red"; fi
mutate; grep -v 'Escaped from' "$T/skills/prisma-diagnose/SKILL.md" > "$T/d.md"; mv "$T/d.md" "$T/skills/prisma-diagnose/SKILL.md"
if check_diagnose_escape "$T/skills"; then fail "control: removing the escape line was not caught"; else pass "control: removing the escape line turns the diagnose case red"; fi
mutate; printf 'disable-model-invocation: true\n' >> "$T/skills/prisma-plan/SKILL.md"
if check_frontmatter "$T/skills"; then fail "control: a user-only plan skill was not caught"; else pass "control: a user-only plan skill turns the frontmatter case red"; fi

rm -rf "$T"
if [ "$ok" = "1" ]; then printf 'SELFTEST OK: %d/%d\n' "$CASES" "$CASES"; exit 0; fi
printf 'SELFTEST FAILED\n'; exit 1
