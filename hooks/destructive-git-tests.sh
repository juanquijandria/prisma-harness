#!/bin/sh
# Prisma Harness. Documented in README.md, section "What is inside". Loaded by destructive-git.sh, not run alone.

skip_case() { cases=$((cases+1)); printf 'SKIP %s, %s\n' "$1" "$2"; }

expect() {
  cases=$((cases+1))
  if [ "$2" = "$3" ]; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s, expected [%s] and got [%s]\n' "$1" "$3" "$2"; ok=0; fi
}

new_repo() {
  repo=$(mktemp -d)
  git -C "$repo" init -q
  printf 'one\n' > "$repo/tracked.txt"
  git -C "$repo" add tracked.txt
  git -C "$repo" -c user.name=selftest -c user.email=selftest@example.invalid commit -q -m "first"
}

pre_tool_use() {
  "$JQ" -nc --arg tool "${TOOL_FOR_TEST:-Bash}" --arg command "$1" --arg cwd "${CWD_FOR_TEST-$repo}" \
    '{hook_event_name: "PreToolUse", tool_name: $tool, tool_input: {command: $command}, cwd: $cwd}' \
    | PRISMA_JQ="${JQ_FOR_TEST-$JQ}" PRISMA_PARSER_FAULT="${PARSER_FAULT_FOR_TEST-}" sh "$GATE" 2>"$stderr_file"
}

verdict() {
  : > "$PRISMA_RECEIPT_FILE"
  out=$(pre_tool_use "$1"); rc=$?
  decision=$(printf '%s' "$out" | "$JQ" -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  outcome=$(cut -f4 "$PRISMA_RECEIPT_FILE" | tr '\n' ' ' | sed 's/ $//')
  printf '%s %s %s' "$rc" "${decision:-none}" "${outcome:-silent}"
}

ASKS="0 ask asked"
PASSES="0 none silent"
BLOCKS="2 none blocked"
ESCAPES="0 none escaped"

selftest_forced_pushes() {
  expect "1 the real case, a push with a lease and the escape of another gate, asks the person" "$(verdict "cd $repo && PRISMA_SIZE_OK=1 git push --force-with-lease origin feat/delivery 2>&1 | tail -2")" "$ASKS"
  expect "2 a push with --force asks" "$(verdict "git push --force origin main")" "$ASKS"
  expect "3 a push with -f asks" "$(verdict "git push -f")" "$ASKS"
  expect "4 a refspec that starts with a plus asks" "$(verdict "git push origin +main:main")" "$ASKS"
  expect "5 a lease with a value asks" "$(verdict "git push --force-with-lease=main:0a1b2c origin main")" "$ASKS"
  expect "6 --force-if-includes asks" "$(verdict "git push --force-if-includes origin main")" "$ASKS"
  expect "7 -f inside a cluster of short flags asks" "$(verdict "git push -uf origin work")" "$ASKS"
  expect "8 the escape never turns a forced push into a pass" "$(verdict "$ESCAPE git push --force origin main")" "$ASKS"
  expect "9 an ordinary push passes without a receipt line" "$(verdict "git push origin main")" "$PASSES"
  expect "10 a branch whose name carries the word force passes" "$(verdict "git push -u origin fix/force-push-f")" "$PASSES"
  expect "11 a forced push written inside a commit message passes" "$(verdict "git commit -m \"never git push --force here\" && git push origin main")" "$PASSES"
  expect "12 a forced push that is only printed passes" "$(verdict "echo 'git push --force origin main'")" "$PASSES"
  expect "39 a forced push run under timeout asks" "$(verdict "timeout 30 git push --force origin main")" "$ASKS"
  expect "40 an ordinary push run under timeout passes" "$(verdict "timeout -k 5 30s git push origin main")" "$PASSES"
  pre_tool_use "git push --force origin main" | "$JQ" -r '.hookSpecificOutput.permissionDecisionReason' > "$scratch/reason.txt" 2>/dev/null
  expect "44 the reason of a forced push says nothing of a hard reset" "$(grep -c "hard reset" "$scratch/reason.txt")" "0"
  expect "45 the first line of the reason says that Enter accepts" "$(head -1 "$scratch/reason.txt" | grep -c "Enter accepts")" "1"
  expect "13 the reason shown to the person quotes the command" "$(grep -c -- "git push --force origin main" "$scratch/reason.txt")" "1"
}

selftest_hard_resets() {
  printf 'two\n' >> "$repo/tracked.txt"
  expect "14 the real case, a hard reset over uncommitted work, asks the person" "$(verdict "git reset --hard HEAD")" "$ASKS"
  pre_tool_use "git reset --hard HEAD" | "$JQ" -r '.hookSpecificOutput.permissionDecisionReason' > "$scratch/reset-reason.txt" 2>/dev/null
  expect "46 the reason of a hard reset says when a hard reset asks" "$(grep -c "A hard reset asks" "$scratch/reset-reason.txt")" "1"
  expect "15 the escape never turns it into a pass" "$(verdict "$ESCAPE git reset --hard HEAD")" "$ASKS"
  git -C "$repo" add tracked.txt
  expect "16 work that is staged and not committed asks too" "$(verdict "git reset --hard")" "$ASKS"
  elsewhere=$(mktemp -d)
  expect "17 the tree is the one git -C names, not the one the session works in" "$(CWD_FOR_TEST="$elsewhere" verdict "git -C $repo reset --hard")" "$ASKS"
  expect "18 the tree is the one a leading cd names" "$(CWD_FOR_TEST="$elsewhere" verdict "cd $repo && git reset -q --hard origin/main")" "$ASKS"
  clean=$(mktemp -d); git -C "$clean" init -q
  expect "42 a cd written after the reset does not move the tree that is measured" "$(verdict "$ESCAPE git reset --hard HEAD && cd $clean")" "$ASKS"
  expect "43 two folder changes cannot be followed, so it asks" "$(CWD_FOR_TEST="$elsewhere" verdict "cd $clean && cd $repo && git reset --hard")" "$ASKS"
  rm -rf "$clean"
  git -C "$repo" -c user.name=selftest -c user.email=selftest@example.invalid commit -q -m "second"
  expect "19 the other side, a hard reset over a clean tree, blocks until the escape is declared" "$(verdict "git reset --hard HEAD~1")" "$BLOCKS"
  expect "20 the block names the escape" "$(grep -c -- "$ESCAPE" "$stderr_file")" "1"
  expect "21 the same reset with the escape declared passes, and the receipt says escaped" "$(verdict "$ESCAPE git reset --hard HEAD~1")" "$ESCAPES"
  printf 'new\n' > "$repo/untracked.txt"
  expect "22 a file git does not track is not lost by a hard reset, so the tree counts as clean" "$(verdict "git reset --hard")" "$BLOCKS"
  expect "23 a folder that is not a repository cannot be measured, so it asks" "$(CWD_FOR_TEST="$elsewhere" verdict "git reset --hard")" "$ASKS"
  expect "24 a folder written with a variable cannot be measured, so it asks" "$(verdict "cd \$WORK/copy && git reset --hard")" "$ASKS"
  expect "25 a soft reset passes" "$(verdict "git reset --soft HEAD~1")" "$PASSES"
  expect "26 a mixed reset of one file passes" "$(verdict "git reset HEAD tracked.txt")" "$PASSES"
  expect "27 a hard reset written inside a commit message passes" "$(verdict "git commit -m 'undo with git reset --hard'")" "$PASSES"
  rm -rf "$elsewhere"
}

selftest_branch_deletions() {
  expect "28 the real case, a forced branch deletion at the end of a cleanup, blocks until the escape is declared" "$(verdict "git worktree remove ../review-36 && git branch -D review-pr36 && git worktree list")" "$BLOCKS"
  expect "29 the same deletion with the escape declared passes" "$(verdict "git worktree remove ../review-36 && $ESCAPE git branch -D review-pr36")" "$ESCAPES"
  expect "30 --delete with --force blocks" "$(verdict "git branch --delete --force old")" "$BLOCKS"
  expect "31 -d with -f blocks" "$(verdict "git branch -d -f old")" "$BLOCKS"
  expect "41 -d and -f in one cluster block, in either order" "$(verdict "git branch -df old")|$(verdict "git branch -fd old")" "$BLOCKS|$BLOCKS"
  expect "32 a deletion git itself refuses when unmerged passes" "$(verdict "git branch -d merged")" "$PASSES"
  expect "33 listing branches passes" "$(verdict "git branch -a")" "$PASSES"
  expect "34 a deletion next to a forced push asks, escape or not" "$(verdict "$ESCAPE git branch -D old && git push --force origin main")" "$ASKS"
}

selftest_trees_that_cannot_be_told() {
  dirty=$(mktemp -d); git -C "$dirty" init -q; printf 'one\n' > "$dirty/kept.txt"; git -C "$dirty" add kept.txt
  git -C "$dirty" -c user.name=selftest -c user.email=selftest@example.invalid commit -q -m "first"; printf 'two\n' >> "$dirty/kept.txt"
  spare=$(mktemp -d); git -C "$spare" init -q
  expect "47 the real case, a pushd into a tree with uncommitted work and the escape declared, asks" "$(verdict "$ESCAPE pushd $dirty && git reset --hard")" "$ASKS"
  expect "48 two folders named with -C cannot be told apart, so it asks" "$(verdict "$ESCAPE git -C $spare -C $dirty reset --hard")" "$ASKS"
  expect "49 a tree named with --git-dir and --work-tree asks" "$(verdict "$ESCAPE git --git-dir=$dirty/.git --work-tree=$dirty reset --hard")" "$ASKS"
  expect "50 a tree named through the environment of git asks" "$(verdict "GIT_DIR=$dirty/.git GIT_WORK_TREE=$dirty $ESCAPE git reset --hard")" "$ASKS"
  expect "51 a tree named with env -C asks" "$(verdict "$ESCAPE env -C $dirty git reset --hard")" "$ASKS"
  rm -rf "$dirty" "$spare"
}

selftest_commands_inside_other_commands() {
  expect "52 a forced push handed to a shell as text asks" "$(verdict "sh -c \"git push -f origin main\"")" "$ASKS"
  expect "53 a hard reset handed to a login shell as text asks" "$(verdict "bash -lc 'git reset --hard'")" "$ASKS"
  expect "54 a forced push inside eval asks" "$(verdict "eval \"git push --force origin main\"")" "$ASKS"
  expect "55 a forced push inside backquotes asks" "$(verdict "echo \`git push -f origin main\`")" "$ASKS"
  expect "56 a forced push built by xargs asks" "$(verdict "echo origin | xargs git push -f")" "$ASKS"
  expect "57 a forced branch deletion handed to a shell as text asks, escape or not" "$(verdict "$ESCAPE sh -c 'git branch -D old'")" "$ASKS"
  expect "58 a push that mirrors rewrites the remote, so it asks" "$(verdict "git push --mirror origin")" "$ASKS"
  expect "59 a shell handed a harmless text passes" "$(verdict "sh -c 'git status' && bash -lc \"npm test\"")" "$PASSES"
  expect "60 xargs with a harmless git command passes" "$(verdict "git ls-files | xargs git add")" "$PASSES"
  expect "61 the real case, a page written from a heredoc that names a hard reset, passes" "$(verdict "cat > notes.md <<'PAGE'
git reset --hard
git push --force origin main
PAGE")" "$PASSES"
  expect "62 a forced push on the line after a heredoc still asks" "$(verdict "cat > notes.md <<'PAGE'
some text
PAGE
git push --force origin main")" "$ASKS"
}

selftest_commands_across_lines_and_short_flags() {
  expect "63 the real case, a hard reset written across two lines, is seen" "$(verdict "git reset \\
  --hard origin/main")" "$BLOCKS"
  expect "64 a forced branch deletion across two lines is seen" "$(verdict "git branch \\
  -D old")" "$BLOCKS"
  expect "65 a forced push across two lines asks" "$(verdict "git push origin main \\
  --force")" "$ASKS"
  expect "66 a lease across two lines asks" "$(verdict "git push \\
  --force-with-lease origin main")" "$ASKS"
  expect "67 an ordinary push across two lines passes" "$(verdict "git push \\
  origin main")" "$PASSES"
  expect "68 a hard reset with its flag cut short, which git accepts, is seen" "$(verdict "git reset --har")|$(verdict "git reset --h HEAD~1")" "$BLOCKS|$BLOCKS"
  expect "69 a lease and a mirror cut short ask" "$(verdict "git push --force-w origin main")|$(verdict "git push --mir origin")" "$ASKS|$ASKS"
  expect "70 a deletion and its force cut short block" "$(verdict "git branch --del --forc old")" "$BLOCKS"
  expect "71 a flag that only starts like one of them passes" "$(verdict "git reset --help")|$(verdict "git push --follow-tags origin main")" "$PASSES|$PASSES"
}

selftest_branches_moved_by_force() {
  git -C "$repo" branch settled 2>/dev/null
  expect "72 the real case, a branch that exists moved with branch -f, asks" "$(verdict "git branch -f settled HEAD~1")" "$ASKS"
  expect "73 checkout -B over a branch that exists asks" "$(verdict "git checkout -B settled HEAD")" "$ASKS"
  expect "74 switch -C over a branch that exists asks, escape or not" "$(verdict "$ESCAPE git switch -C settled HEAD")" "$ASKS"
  expect "75 switch --force-create over a branch that exists asks" "$(verdict "git switch --force-create settled")" "$ASKS"
  expect "76 the other side, the same flags over a branch that does not exist pass" "$(verdict "git switch -C brand-new HEAD")|$(verdict "git checkout -B brand-new-two")|$(verdict "git branch -f brand-new-three HEAD")" "$PASSES|$PASSES|$PASSES"
  expect "77 a tree named before the subcommand is the folder, and -C after it is the flag" "$(CWD_FOR_TEST="$scratch" verdict "git -C $repo switch -C settled")" "$ASKS"
  expect "78 a branch that cannot be looked up asks" "$(CWD_FOR_TEST="$scratch" verdict "git switch -C settled")" "$ASKS"
  expect "82 a branch whose folder is written with a variable cannot be looked up, so it asks" "$(verdict "cd \$WORK/copy && git switch -C settled")" "$ASKS"
  expect "79 switch and checkout without the flag pass" "$(verdict "git switch settled")|$(verdict "git checkout -b fresh")|$(verdict "git switch -c fresh-two")" "$PASSES|$PASSES|$PASSES"
}

selftest_drive_letter_paths() {
  case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*)
    skip_case "80 a folder written with a drive letter is not read as relative" "this system cannot hold a folder named C:"
    skip_case "81 a folder written with a drive letter and backslashes is not read as relative" "this system cannot hold a folder named C:"
    return ;;
  esac
  mkdir -p "$repo/C:/sub"; git -C "$repo/C:/sub" init -q
  expect "80 a folder written with a drive letter is not read as relative, so it cannot be measured and asks" "$(verdict "git -C C:/sub reset --hard")" "$ASKS"
  mkdir -p "$repo/C:\\sub"; git -C "$repo/C:\\sub" init -q
  expect "81 a folder written with a drive letter and backslashes is not read as relative" "$(verdict "git -C 'C:\\sub' reset --hard")" "$ASKS"
  rm -rf "$repo/C:" "$repo/C:\\sub"
}

selftest_what_is_not_measured() {
  expect "35 a tool that is not the shell passes" "$(TOOL_FOR_TEST=Write verdict "git push --force")" "$PASSES"
  expect "36 without jq the gate lets the command go and says it did not measure" "$(JQ_FOR_TEST= verdict "git push --force origin main")" "0 none not-measured"
  expect "37 a parser that fails on a git command is not measured" "$(PARSER_FAULT_FOR_TEST=1 verdict "git push --force origin main")" "0 none not-measured"
  expect "38 a parser that fails on a command without git leaves no receipt line" "$(PARSER_FAULT_FOR_TEST=1 verdict "ls -la")" "$PASSES"
}

selftest() {
  ok=1; cases=0
  [ -n "$JQ" ] || { printf 'SKIP the destructive git gate needs jq to build its fixtures\n'; printf 'SELFTEST OK: 1/1\n'; return 0; }
  new_repo; scratch=$(mktemp -d); stderr_file="$scratch/stderr.txt"
  selftest_forced_pushes
  selftest_hard_resets
  selftest_branch_deletions
  selftest_trees_that_cannot_be_told
  selftest_commands_inside_other_commands
  selftest_commands_across_lines_and_short_flags
  selftest_branches_moved_by_force
  selftest_drive_letter_paths
  selftest_what_is_not_measured
  rm -rf "$repo" "$scratch"
  [ "$ok" = "1" ] && [ "$cases" = "$SELFTEST_CASES" ] && { printf 'SELFTEST OK: %s/%s\n' "$cases" "$SELFTEST_CASES"; return 0; }
  printf 'SELFTEST FAILED, %s cases ran and %s were declared\n' "$cases" "$SELFTEST_CASES"; return 1
}
