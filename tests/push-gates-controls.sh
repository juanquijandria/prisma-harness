#!/bin/sh
# Prisma Harness. Positive and negative controls of the three push gates against a fixture repo.

HOOKS="$(cd "$(dirname "$0")/../hooks" && pwd)"
. "$HOOKS/selftest-env.sh"
export PRISMA_COMMENTS_BLOCK=1
T=$(mktemp -d); ok=1
git -C "$T" init -q && cd "$T" || exit 1
git symbolic-ref HEAD refs/heads/main
git config user.email t@t; git config user.name t
printf 'export const A = 1;\n' > a.js; git add a.js; git commit -qm init; git checkout -qb feature
payload() { printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"%s"}}' "$T" "$1"; }
CHECKS=0
expect() { name="$1"; want="$2"; shift 2; CHECKS=$((CHECKS+1)); "$@" >/dev/null 2>&1; got=$?; if [ "$got" = "$want" ]; then printf 'PASS %s (exit %s)\n' "$name" "$got"; else printf 'FAIL %s, expected %s got %s\n' "$name" "$want" "$got"; ok=0; fi; }
run() { gate="$1"; cmd="$2"; payload "$cmd" | sh "$HOOKS/$gate"; }
receipt_lines() { [ -f "$PRISMA_RECEIPT_FILE" ] && wc -l < "$PRISMA_RECEIPT_FILE" | tr -d ' ' || echo 0; }

printf 'export const A = 1;\n// stray comment\n' > a.js; git commit -qam comment
expect "comments gate blocks a stray comment" 2 run pre-push-comments.sh "git push origin feature"
expect "comments gate passes with the escape" 0 run pre-push-comments.sh "PRISMA_COMMENTS_OK=1 git push origin feature"
out=$(payload "git push origin feature" | PRISMA_COMMENTS_BLOCK=0 sh "$HOOKS/pre-push-comments.sh" 2>&1); rc=$?
CHECKS=$((CHECKS+1)); if [ "$rc" = "0" ] && printf '%s' "$out" | grep -qi 'comment'; then printf 'PASS comments gate measures and lets the push through until the repository asks it to block\n'; else printf 'FAIL comments gate without PRISMA_COMMENTS_BLOCK (rc=%s) %s\n' "$rc" "$out"; ok=0; fi
expect "comments gate ignores a mention of git push" 0 run pre-push-comments.sh "echo git push"
expect "comments gate lets a PR read through" 0 run pre-push-comments.sh "gh pr list"
expect "comments gate lets a PR view through" 0 run pre-push-comments.sh "gh pr view 12"
expect "comments gate blocks a PR creation" 2 run pre-push-comments.sh "gh pr create --fill"
expect "comments gate ignores a PR read with a repository flag" 0 run pre-push-comments.sh "gh -R owner/name pr list"
expect "comments gate blocks a PR creation with a repository flag" 2 run pre-push-comments.sh "gh -R owner/name pr create --fill"
expect "comments gate blocks a PR marked ready" 2 run pre-push-comments.sh "gh pr ready 12"
expect "comments gate ignores a PR checks read" 0 run pre-push-comments.sh "gh pr checks 12"
expect "lint gate ignores a PR read" 0 run pre-push-lint.sh "gh pr list"
expect "the escape inside a trailing comment does not disarm the gate" 2 run pre-push-comments.sh "git push origin feature # PRISMA_COMMENTS_OK=1 because"
expect "the escape as an argument of another command does not disarm the gate" 2 run pre-push-comments.sh "echo PRISMA_COMMENTS_OK=1 reason && git push origin feature"
before=$(receipt_lines)
expect "an escape on a command that is not a push does nothing" 0 run pre-push-comments.sh "PRISMA_COMMENTS_OK=1 ls"
CHECKS=$((CHECKS+1)); if [ "$(receipt_lines)" = "$before" ]; then printf 'PASS no receipt line for an escape outside a push\n'; else printf 'FAIL an escape outside a push wrote a receipt line\n'; ok=0; fi
expect "comments gate passes a push with the escape" 0 run pre-push-comments.sh "PRISMA_COMMENTS_OK=1 git push origin feature"
CHECKS=$((CHECKS+1)); if [ "$(receipt_lines)" -gt "$before" ] && tail -1 "$PRISMA_RECEIPT_FILE" | grep -q escaped; then printf 'PASS an escape on a real push is recorded as escaped\n'; else printf 'FAIL the escaped push was not recorded\n'; ok=0; fi
printf 'export const A = 1;\n' > a.js; git commit -qam clean
expect "comments gate passes a clean diff" 0 run pre-push-comments.sh "git push origin feature"
printf 'case "$1" in\n  *stop*) exit 0 ;;\n  */dir/*) exit 1 ;;\nesac\n' > run.sh; git add run.sh; git commit -qm shellcase
expect "comments gate does not count a shell case pattern starting with * as a comment" 0 run pre-push-comments.sh "git push origin feature"
printf '/**\n * a docblock line\n */\nexport const B = 2;\n' > b.js; git add b.js; git commit -qm docblock
expect "comments gate still counts a docblock line starting with * in JavaScript" 2 run pre-push-comments.sh "git push origin feature"
git reset -q --hard HEAD~1

seq 1 1200 > big.txt; git add big.txt; git commit -qm big
expect "size gate blocks 1200 lines" 2 run pre-push-size.sh "git push origin feature"
expect "size gate passes with the escape" 0 run pre-push-size.sh "PRISMA_SIZE_OK=1 git push origin feature"
expect "size gate lets a PR read through while the diff is over the ceiling" 0 run pre-push-size.sh "gh pr list"
expect "size gate blocks a PR creation over the ceiling" 2 run pre-push-size.sh "gh pr create --fill"
git init -q --bare "$T.remote"; git remote add origin "$T.remote"; git push -q origin main feature; git branch -q --set-upstream-to=origin/main main
git checkout -q main
before=$(receipt_lines)
out=$(run pre-push-size.sh "git push origin feature" 2>&1); rc=$?
CHECKS=$((CHECKS+1)); if [ "$rc" = "0" ] && printf '%s' "$out" | grep -q WARN; then printf 'PASS size gate from main warns that it measured nothing\n'; else printf 'FAIL size gate from main (rc=%s) %s\n' "$rc" "$out"; ok=0; fi
after_one=$(receipt_lines)
CHECKS=$((CHECKS+1)); if [ "$after_one" = "$((before+1))" ] && tail -1 "$PRISMA_RECEIPT_FILE" | grep -q 'not-measured'; then printf 'PASS one run that could not measure leaves exactly one line saying so\n'; else printf 'FAIL one run that could not measure left %s lines\n' "$((after_one-before))"; ok=0; fi
run pre-push-size.sh "git push origin feature" >/dev/null 2>&1
run pre-push-size.sh "git push origin feature" >/dev/null 2>&1
CHECKS=$((CHECKS+1)); if [ "$(receipt_lines)" = "$((before+3))" ]; then printf 'PASS three runs that could not measure leave three lines, one each\n'; else printf 'FAIL three runs left %s lines\n' "$(($(receipt_lines)-before))"; ok=0; fi
summary=$(sh "$HOOKS/receipt.sh" --summary)
unmeasured=$(printf '%s\n' "$summary" | awk '$1=="size-gate"{print $4}')
CHECKS=$((CHECKS+1)); if [ "$unmeasured" = "3" ] 2>/dev/null; then printf 'PASS the summary counts what a gate could not measure apart from what it blocked\n'; else printf 'FAIL the summary column for unmeasured events reads [%s]\n' "$unmeasured"; ok=0; fi
git checkout -q feature

seq 1 1500 > bigger.txt; printf 'export const C = 3;\n// a stray comment\n' > c.js; git add bigger.txt c.js; git commit -qm "over the base"
while IFS='|' read -r shape verdict; do
  [ -n "$shape" ] || continue
  out=$(run pre-push-size.sh "$shape" 2>&1); rc=$?
  CHECKS=$((CHECKS+1))
  if [ "$verdict" = "measures" ]; then
    if [ "$rc" = "2" ]; then printf 'PASS size gate measures [%s], which it can prove is HEAD\n' "$shape"; else printf 'FAIL size gate refused a push it could prove is HEAD, [%s] rc=%s %s\n' "$shape" "$rc" "$out"; ok=0; fi
  else
    if [ "$rc" = "0" ] && printf '%s' "$out" | grep -q WARN; then printf 'PASS size gate says nothing about [%s], which it cannot prove is HEAD\n' "$shape"; else printf 'FAIL size gate answered for [%s] it could not prove is HEAD, rc=%s %s\n' "$shape" "$rc" "$out"; ok=0; fi
  fi
done <<SHAPES
git push|measures
git push origin|measures
git push origin feature|measures
git push origin HEAD|measures
git push -u origin feature|measures
git push origin feature:main|measures
git push origin main|refuses
git push origin main:main|refuses
git push origin main feature|refuses
git push --all origin|refuses
git push --a-flag-nobody-taught-it origin feature|refuses
SHAPES
out=$(run pre-push-comments.sh "git push origin main" 2>&1); rc=$?
CHECKS=$((CHECKS+1)); if [ "$rc" = "0" ]; then printf 'PASS comments gate says nothing about a push it cannot prove is HEAD\n'; else printf 'FAIL comments gate answered for a push of another branch (rc=%s) %s\n' "$rc" "$out"; ok=0; fi
git reset -q --hard HEAD~1

expect "lint gate passes a repo with no linter" 0 run pre-push-lint.sh "git push origin feature"
expect "lint gate ignores a non-push command" 0 run pre-push-lint.sh "git status"

out=$(cd / && payload "git push origin feature" | sh "$HOOKS/pre-push-size.sh" 2>&1); rc=$?
CHECKS=$((CHECKS+1)); if [ "$rc" = "0" ] && printf '%s' "$out" | grep -q WARN; then printf 'PASS size gate warns when the directory is not a git repository\n'; else printf 'FAIL size gate silent outside a repo (rc=%s) %s\n' "$rc" "$out"; ok=0; fi
out=$(payload "cd /nonexistent-dir-xyz && git push origin feature" | sh "$HOOKS/pre-push-lint.sh" 2>&1); rc=$?
CHECKS=$((CHECKS+1)); if [ "$rc" = "0" ] && printf '%s' "$out" | grep -q WARN; then printf 'PASS lint gate warns when it cannot locate the repo\n'; else printf 'FAIL lint gate silent on a missing repo (rc=%s) %s\n' "$rc" "$out"; ok=0; fi

CHECKS=$((CHECKS+1))
if sh "$HOOKS/receipt.sh" --summary | grep -qE 'gate +[0-9]'; then printf 'PASS a separate process reads back the receipt these gates wrote\n'; else printf 'FAIL the receipt summary shows no gate row\n'; ok=0; fi

cd / && rm -rf "$T" "$T.remote"
[ "$ok" = "1" ] && printf 'PUSH GATE CONTROLS OK: %s of %s\n' "$CHECKS" "$CHECKS" && exit 0
printf 'PUSH GATE CONTROLS FAILED\n'; exit 1
