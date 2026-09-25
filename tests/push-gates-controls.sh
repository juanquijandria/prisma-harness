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
run_from_root() { ( cd / && payload "$1" | sh "$HOOKS/pre-push-comments.sh" ); }
receipt_lines() { [ -f "$PRISMA_RECEIPT_FILE" ] && wc -l < "$PRISMA_RECEIPT_FILE" | tr -d ' ' || echo 0; }
warns_unmeasured() {
  name="$1"; shift; before=$(receipt_lines); out=$("$@" 2>&1); rc=$?; CHECKS=$((CHECKS+1))
  if [ "$rc" = "0" ] && printf '%s' "$out" | grep -q WARN && [ "$(receipt_lines)" = "$((before+1))" ] && tail -1 "$PRISMA_RECEIPT_FILE" | grep -q not-measured; then printf 'PASS %s\n' "$name"; else printf 'FAIL %s (rc=%s) %s\n' "$name" "$rc" "$out"; ok=0; fi
}

printf 'export const A = 1;\n// stray comment\n' > a.js; git commit -qam comment
expect "comments gate blocks a stray comment" 2 run pre-push-comments.sh "git push origin feature"
for diff_setting in diff.external=true color.ui=always diff.noprefix=true; do
  git config "${diff_setting%%=*}" "${diff_setting#*=}"
  expect "comments gate reads the same diff with $diff_setting" 2 run pre-push-comments.sh "git push origin feature"
  git config --unset "${diff_setting%%=*}"
done
mkdir -p "$T/sub"; git config diff.relative true
out=$(printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"%s"}}' "$T/sub" "git push origin feature" | sh "$HOOKS/pre-push-comments.sh" 2>&1); rc=$?; CHECKS=$((CHECKS+1))
if [ "$rc" = "2" ]; then printf 'PASS comments gate reads the whole diff from a subdirectory with diff.relative\n'; else printf 'FAIL comments gate from a subdirectory with diff.relative (rc=%s) %s\n' "$rc" "$out"; ok=0; fi
git config --unset diff.relative; rmdir "$T/sub"
expect "comments gate blocks a push that follows an arithmetic expansion" 2 run pre-push-comments.sh 'n=$((n+1)); git push origin feature'
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
printf '// only on disk\n' >> a.js
expect "comments gate passes a push whose comment is only on disk" 0 run pre-push-comments.sh "git push origin feature"
warns_unmeasured "comments gate says it measured nothing when the same command commits before it pushes" run pre-push-comments.sh "git commit -qam more && git push origin feature"
git checkout -q -- a.js
printf 'export const D = 4;\n// stray comment\n' > d.js; git add d.js; git commit -qm "comment committed"
printf 'export const D = 4;\n' > d.js
expect "comments gate blocks a committed comment deleted only on disk" 2 run pre-push-comments.sh "git push origin feature"
warns_unmeasured "comments gate says it measured nothing when a commit follows the push" run pre-push-comments.sh "git push origin feature && git commit --allow-empty -m marker"
warns_unmeasured "comments gate says it measured nothing when a commit sits between two pushes" run pre-push-comments.sh "git push origin feature; git commit --allow-empty -m marker; git push origin feature"
warns_unmeasured "comments gate says it measured nothing when a loop pushes and then commits" run pre-push-comments.sh "for i in 1 2; do git push origin feature; git commit --allow-empty -m marker; done"
warns_unmeasured "comments gate says it measured nothing when a function pushes after a commit" run pre-push-comments.sh "p() { git push origin feature; }; git commit --allow-empty -m marker && p"
git reset -q --hard HEAD~1
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
  elif [ "$verdict" = "skips" ]; then
    if [ "$rc" = "0" ] && [ -z "$out" ]; then printf 'PASS size gate stays silent on [%s], which sends no branch\n' "$shape"; else printf 'FAIL size gate spoke about [%s], which sends no branch, rc=%s %s\n' "$shape" "$rc" "$out"; ok=0; fi
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
git -C /tmp push origin feature|refuses
git --git-dir=/tmp/elsewhere/.git push origin feature|refuses
git --work-tree=/tmp/elsewhere push origin feature|refuses
GIT_DIR=/tmp/elsewhere/.git git push origin feature|refuses
git -c user.name=somebody push origin feature|measures
git -c push.default=matching push origin|refuses
git -c remote.origin.push=refs/heads/main:refs/heads/main push origin|refuses
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=push.default GIT_CONFIG_VALUE_0=matching git push origin|refuses
git push --tags origin feature|measures
git push origin feature --tags|measures
git push origin feature refs/tags/v1|measures
git push origin feature && git push --tags|measures
git push --tags|skips
git push --tags origin|skips
git push origin refs/tags/v1|skips
git push origin +refs/tags/v1|skips
git push origin HEAD:refs/tags/v1|skips
git push origin --delete old|skips
git --no-pager push origin feature|measures
SHAPES
for odd_branch in fix--delete-modal chore--tags; do
  git checkout -qb "$odd_branch"
  expect "size gate measures a branch named $odd_branch" 2 run pre-push-size.sh "git push origin $odd_branch"
  git checkout -q feature; git branch -qD "$odd_branch"
done
expect "comments gate measures a branch pushed together with every tag" 2 run pre-push-comments.sh "git push --tags origin feature"
git config remote.origin.push refs/heads/main:refs/heads/main
warns_unmeasured "size gate says it measured nothing when a configured push refspec decides what a bare push sends" run pre-push-size.sh "git push"
git config --unset remote.origin.push
git config push.default matching
warns_unmeasured "comments gate says it measured nothing when push.default matching decides what a bare push sends" run pre-push-comments.sh "git push"
warns_unmeasured "comments gate reads the push configuration of the repository even when it runs from elsewhere" run_from_root "git push"
git config --unset push.default
git config push.default nothing
warns_unmeasured "size gate says it measured nothing when push.default nothing decides what a bare push sends" run pre-push-size.sh "git push"
git config --unset push.default
git config remote.origin.mirror true
warns_unmeasured "size gate says it measured nothing when the remote is a mirror" run pre-push-size.sh "git push origin"
git config --unset remote.origin.mirror
out=$(run pre-push-comments.sh "git push origin main" 2>&1); rc=$?
CHECKS=$((CHECKS+1)); if [ "$rc" = "0" ]; then printf 'PASS comments gate says nothing about a push it cannot prove is HEAD\n'; else printf 'FAIL comments gate answered for a push of another branch (rc=%s) %s\n' "$rc" "$out"; ok=0; fi
git reset -q --hard HEAD~1

expect "lint gate passes a repo with no linter" 0 run pre-push-lint.sh "git push origin feature"
expect "lint gate ignores a non-push command" 0 run pre-push-lint.sh "git status"

L=$(mktemp -d)
git -C "$L" init -q; git -C "$L" symbolic-ref HEAD refs/heads/main
git -C "$L" config user.email t@t; git -C "$L" config user.name t
mkdir -p "$L/node_modules/.bin"; printf '{"private":true}\n' > "$L/package.json"
printf '#!/bin/sh\nif grep -q BAD "$@"; then echo "1 error"; exit 1; fi\nexit 0\n' > "$L/node_modules/.bin/eslint"; chmod +x "$L/node_modules/.bin/eslint"
printf 'node_modules/\n' > "$L/.gitignore"
printf 'export const BASE = 1;\n' > "$L/base.js"; printf 'export const A = 1;\n' > "$L/a.js"
git -C "$L" add -A; git -C "$L" commit -qm base; git -C "$L" checkout -qb feature
lint_at() { printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"%s"}}' "$L" "$1" | sh "$HOOKS/pre-push-lint.sh"; }
printf 'export const A = BAD;\n' > "$L/a.js"; git -C "$L" commit -qam "lint error committed"
expect "lint gate blocks a lint error that is committed" 2 lint_at "git push origin feature"
expect "lint gate blocks a lint error when the branch goes out with every tag" 2 lint_at "git push --tags origin feature"
warns_unmeasured "lint gate says it measured nothing when a commit follows the push" lint_at "git push origin feature && git commit --allow-empty -m marker"
warns_unmeasured "lint gate says it measured nothing when the command moves a branch with update-ref" lint_at "git update-ref refs/heads/feature HEAD && git push origin feature"
warns_unmeasured "lint gate says it measured nothing when a git call in the command cannot be read" lint_at "git -C . status && git push origin feature"
printf '{"private":true,"eslintConfig":{}}\n' > "$L/package.json"
warns_unmeasured "lint gate says it measured nothing when only the linter configuration changed on disk" lint_at "git push origin feature"
git -C "$L" checkout -q -- package.json
expect "lint gate blocks a committed lint error when the words git commit are only quoted text" 2 lint_at "echo 'git commit' && git push origin feature"
expect "lint gate blocks a committed lint error after a git call that leaves commits alone" 2 lint_at "git status && git fetch && git push origin feature"
warns_unmeasured "lint gate says it measured nothing for a git subcommand it does not know to leave commits alone" lint_at "git stash branch sb && git push origin feature"
warns_unmeasured "lint gate says it measured nothing when the command sets git configuration" lint_at "git config push.default matching && git push origin"
warns_unmeasured "lint gate says it measured nothing when git grep could run a program" lint_at "git grep -O true x && git push origin feature"
printf 'scratch\n' > "$L/notes.txt"
warns_unmeasured "lint gate says it measured nothing when an untracked file sits in the working tree" lint_at "git push origin feature"
rm -f "$L/notes.txt"
warns_unmeasured "lint gate says it measured nothing when an empty commit comes before the push" lint_at "git commit --allow-empty -m marker && git push origin feature"
warns_unmeasured "lint gate says it measured nothing when the command switches branch before the push" lint_at "git switch feature && git push origin feature"
printf 'export const A = 2;\n' > "$L/a.js"
warns_unmeasured "lint gate says it measured nothing when a committed lint error is fixed only on disk" lint_at "git push origin feature"
warns_unmeasured "lint gate says it measured nothing when the fix is only on disk and a commit follows the push" lint_at "git push origin feature && git commit --allow-empty -m marker"
git -C "$L" commit -qam "fixed"
printf 'export const A = BAD;\n' > "$L/a.js"
warns_unmeasured "lint gate says it measured nothing when a pushed file has an uncommitted lint error" lint_at "git push origin feature"
warns_unmeasured "lint gate says it measured nothing when the same command commits before it pushes" lint_at "git commit -qam more && git push origin feature"
git -C "$L" checkout -q -- a.js
printf 'export const BASE = BAD;\n' > "$L/base.js"
warns_unmeasured "lint gate says it measured nothing when the uncommitted change is in a file the push does not send" lint_at "git push origin feature"
git -C "$L" checkout -q -- base.js
expect "lint gate measures and passes a clean tree whose commits are clean" 0 lint_at "git push origin feature"
rm -rf "$L"

P=$(mktemp -d)
git -C "$P" init -q; git -C "$P" symbolic-ref HEAD refs/heads/main
git -C "$P" config user.email t@t; git -C "$P" config user.name t
mkdir -p "$P/vendor/bin" "$P/fake-bin"; printf '#!/bin/sh\nexit 0\n' > "$P/vendor/bin/php-cs-fixer"; chmod +x "$P/vendor/bin/php-cs-fixer"; : > "$P/.php-cs-fixer.php"
printf '#!/bin/sh\nfor arg in "$@"; do case "$arg" in *.php) grep -q BAD "$arg" && bad=1 ;; esac; done\n[ -z "$bad" ] && exit 0\necho "   1) a.php"; echo "Found 1 of 1 files that can be fixed"; exit 8\n' > "$P/fake-bin/php"; chmod +x "$P/fake-bin/php"
printf 'vendor/\nfake-bin/\n' > "$P/.gitignore"
printf '<?php $base = 1;\n' > "$P/base.php"; printf '<?php $a = 1;\n' > "$P/a.php"
git -C "$P" add -A; git -C "$P" commit -qm base; git -C "$P" checkout -qb feature
php_at() { printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"%s"}}' "$P" "$1" | PATH="$P/fake-bin:$PATH" sh "$HOOKS/pre-push-lint.sh"; }
printf '<?php $a = BAD;\n' > "$P/a.php"; git -C "$P" commit -qam "php error committed"
expect "lint gate blocks a php-cs-fixer finding that is committed" 2 php_at "git push origin feature"
printf '<?php $a = 2;\n' > "$P/a.php"
before=$(receipt_lines); out=$(php_at "git push origin feature" 2>&1); rc=$?; CHECKS=$((CHECKS+1))
if [ "$rc" = "0" ] && printf '%s' "$out" | grep -q WARN && [ "$(receipt_lines)" = "$((before+1))" ]; then printf 'PASS lint gate says it measured nothing when a committed php finding is fixed only on disk\n'; else printf 'FAIL lint gate on a php finding fixed only on disk (rc=%s) %s\n' "$rc" "$out"; ok=0; fi
git -C "$P" commit -qam "php fixed"; printf '<?php $base = BAD;\n' > "$P/base.php"
warns_unmeasured "lint gate says it measured nothing when the uncommitted php change is in a file the push does not send" php_at "git push origin feature"
rm -rf "$P"

out=$(cd / && payload "git push origin feature" | sh "$HOOKS/pre-push-size.sh" 2>&1); rc=$?
CHECKS=$((CHECKS+1)); if [ "$rc" = "0" ] && printf '%s' "$out" | grep -q WARN; then printf 'PASS size gate warns when the directory is not a git repository\n'; else printf 'FAIL size gate silent outside a repo (rc=%s) %s\n' "$rc" "$out"; ok=0; fi
out=$(payload "cd /nonexistent-dir-xyz && git push origin feature" | sh "$HOOKS/pre-push-lint.sh" 2>&1); rc=$?
CHECKS=$((CHECKS+1)); if [ "$rc" = "0" ] && printf '%s' "$out" | grep -q WARN; then printf 'PASS lint gate warns when it cannot locate the repo\n'; else printf 'FAIL lint gate silent on a missing repo (rc=%s) %s\n' "$rc" "$out"; ok=0; fi

CHECKS=$((CHECKS+1))
if sh "$HOOKS/receipt.sh" --summary | grep -qE 'gate +[0-9]'; then printf 'PASS a separate process reads back the receipt these gates wrote\n'; else printf 'FAIL the receipt summary shows no gate row\n'; ok=0; fi

cd / && rm -rf "$T" "$T.remote"
[ "$ok" = "1" ] && printf 'PUSH GATE CONTROLS OK: %s of %s\n' "$CHECKS" "$CHECKS" && exit 0
printf 'PUSH GATE CONTROLS FAILED\n'; exit 1
