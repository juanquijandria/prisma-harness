#!/bin/sh
# Prisma Harness. Positive and negative controls of the three push gates against a fixture repo.

HOOKS="$(cd "$(dirname "$0")/../hooks" && pwd)"
export PRISMA_RECEIPT_FILE="${PRISMA_RECEIPT_FILE:-$(mktemp -d)/receipts.log}"
T=$(mktemp -d); ok=1
git -C "$T" init -q && cd "$T" || exit 1
git symbolic-ref HEAD refs/heads/main
git config user.email t@t; git config user.name t
printf 'export const A = 1;\n' > a.js; git add a.js; git commit -qm init; git checkout -qb feature
payload() { printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"%s"}}' "$T" "$1"; }
expect() { name="$1"; want="$2"; shift 2; "$@" >/dev/null 2>&1; got=$?; if [ "$got" = "$want" ]; then printf 'PASS %s (exit %s)\n' "$name" "$got"; else printf 'FAIL %s, expected %s got %s\n' "$name" "$want" "$got"; ok=0; fi; }
run() { gate="$1"; cmd="$2"; payload "$cmd" | sh "$HOOKS/$gate"; }

printf 'export const A = 1;\n// stray comment\n' > a.js; git commit -qam comment
expect "comments gate blocks a stray comment" 2 run pre-push-comments.sh "git push origin feature"
expect "comments gate passes with the escape" 0 run pre-push-comments.sh "PRISMA_COMMENTS_OK=1 git push origin feature"
expect "comments gate ignores a mention of git push" 0 run pre-push-comments.sh "echo git push"
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
git init -q --bare "$T.remote"; git remote add origin "$T.remote"; git push -q origin main feature; git branch -q --set-upstream-to=origin/main main
git checkout -q main
out=$(run pre-push-size.sh "git push origin feature" 2>&1); rc=$?
if [ "$rc" = "0" ] && printf '%s' "$out" | grep -q WARN; then printf 'PASS size gate from main warns that it measured nothing\n'; else printf 'FAIL size gate from main (rc=%s) %s\n' "$rc" "$out"; ok=0; fi
git checkout -q feature

expect "lint gate passes a repo with no linter" 0 run pre-push-lint.sh "git push origin feature"
expect "lint gate ignores a non-push command" 0 run pre-push-lint.sh "git status"

cd / && rm -rf "$T" "$T.remote"
[ "$ok" = "1" ] && printf 'PUSH GATE CONTROLS OK: 11/11\n' && exit 0
printf 'PUSH GATE CONTROLS FAILED\n'; exit 1
