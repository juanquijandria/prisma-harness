# Prisma Harness. Documented in README.md, section "What is inside". Loaded by secret-reads.sh, not run alone.

PROBE_TIMEOUT=7000
PROBE_DIR="/tmp/probe"
NAMES_HINT="cut -d= -f1"
SEARCH_EXCLUSION="--exclude='.env*' --exclude='*.env'"
RG_EXCLUSION="-g '!.env*' -g '!*.env'"
PATHSPEC_EXCLUSION="':(exclude,glob)**/.env*' ':(exclude,glob)**/*.env'"

payload_for() {
  printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":%s,"description":"probe","timeout":%s}}' \
    "$PROBE_DIR" "$(printf '%s' "$1" | jq -Rs .)" "$PROBE_TIMEOUT"
}

run_gate() {
  : > "$PRISMA_RECEIPT_FILE"
  out=$(payload_for "$1" | sh "$SELF" 2>/dev/null); rc=$?
  rewritten=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedInput.command // empty' 2>/dev/null | tr -d '\r')
  [ -n "$rewritten" ] && printf '%s %s' "$rc" "$rewritten" || printf '%s' "$rc"
}

last_outcome() {
  tail -n 1 "$PRISMA_RECEIPT_FILE" 2>/dev/null | awk -F'\t' -v gate="$GATE_NAME" '$2 == gate { print $4 }'
}

expect() {
  cases=$((cases+1))
  if [ "$2" = "$3" ]; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s, expected [%s] and got [%s]\n' "$1" "$3" "$2"; ok=0; fi
}

skip() {
  cases=$((cases+1))
  printf 'SKIP %s\n' "$1"
}

selftest_direct_reads() {
  expect "1 cat of a .env blocks" "$(run_gate 'cat .env')" "2"
  expect "2 cat of a .env.example passes" "$(run_gate 'cat .env.example')" "0"
  expect "3 sed on a .env.stg under a folder blocks" "$(run_gate 'sed -n 1,5p config/.env.stg')" "2"
  expect "4 head of a name that ends in .env blocks" "$(run_gate 'head -3 deploy/prod.env')" "2"
  expect "5 a file inside .venv is not a secrets file" "$(run_gate 'cat .venv/bin/activate')" "0"
  expect "6 diff that names a .env blocks" "$(run_gate 'diff .env.dev .env.example')" "2"
  expect "7 a .env named inside quotes of another command passes" "$(run_gate 'echo "no leas .env"')" "0"
  expect "8 cut of the names passes" "$(run_gate 'cut -d= -f1 .env')" "0"
  expect "9 a cat inside a substitution still blocks" "$(run_gate 'echo $(cat .env.testing)')" "2"
  hint=$(payload_for 'tail .env' | sh "$SELF" 2>&1 >/dev/null)
  case "$hint" in *"$NAMES_HINT"*) got="names the way out" ;; *) got="no way out" ;; esac
  expect "10 the block says how to see only the names" "$got" "names the way out"
}

selftest_named_searches() {
  expect "11 grep on a .env.dev blocks" "$(run_gate 'grep TOKEN .env.dev')" "2"
  expect "12 grep -l on a .env.dev passes" "$(run_gate 'grep -l TOKEN .env.dev')" "0"
  expect "13 a quiet grep inside a cluster passes" "$(run_gate 'grep -qs TOKEN .env')" "0"
  expect "14 a .env as the pattern is not a path" "$(run_gate 'grep -n ".env" app.py')" "0"
  expect "15 a .env as the -e pattern is not a path" "$(run_gate 'grep -e .env -A 2 app.py')" "0"
  expect "16 rg on a .env blocks" "$(run_gate 'rg -n TOKEN deploy/.env')" "2"
  expect "17 git grep on a .env after the dashes blocks" "$(run_gate 'git grep -n TOKEN -- .env.dev')" "2"
  expect "18 git grep -c on a .env counts and passes" "$(run_gate 'git -C repo grep -c TOKEN -- .env.dev')" "0"
  expect "19 a recursive grep that names a .env blocks" "$(run_gate 'grep -rn TOKEN config/.env.stg')" "2"
  expect "20 rg -L follows links and lists nothing, so it blocks" "$(run_gate 'rg -L TOKEN .env')" "2"
  expect "21 an include that reaches a .env would beat the exclusion, so it blocks" "$(run_gate "grep -rn --include='.env*' TOKEN .")" "2"
  expect "22 an rg glob that reaches every file would beat it too" "$(run_gate "rg -g '*' --hidden TOKEN")" "2"
  expect "23 an include of another kind of file still gets the exclusion" "$(run_gate "grep -rn --include '*.py' TOKEN .")" "0 grep $SEARCH_EXCLUSION -rn --include '*.py' TOKEN ."
}

selftest_folder_searches() {
  expect "24 grep -rn over a folder gets the exclusion" "$(run_gate 'grep -rn TOKEN .')" "0 grep $SEARCH_EXCLUSION -rn TOKEN ."
  expect "25 the pipe after the search is untouched" "$(run_gate 'grep -R TOKEN src | head -5')" "0 grep $SEARCH_EXCLUSION -R TOKEN src | head -5"
  expect "26 rg gets its glob" "$(run_gate 'rg TOKEN')" "0 rg $RG_EXCLUSION TOKEN"
  expect "27 git grep gets the pathspec at its end" "$(run_gate 'git grep META_')" "0 git grep META_ $PATHSPEC_EXCLUSION"
  expect "28 the pathspec goes after the paths already given" "$(run_gate 'git -C repo grep -n X -- src && ls')" "0 git -C repo grep -n X -- src $PATHSPEC_EXCLUSION && ls"
  expect "29 grep -rl only lists names and is untouched" "$(run_gate 'grep -rl TOKEN .')" "0"
  expect "30 a grep that is not recursive is untouched" "$(run_gate 'grep -n TOKEN app.py')" "0"
  expect "31 two searches on one line both get it" "$(run_gate 'grep -r A . && rg B')" "0 grep $SEARCH_EXCLUSION -r A . && rg $RG_EXCLUSION B"
  expect "32 a quoted search is not a command" "$(run_gate 'grep -rn "grep -r" docs')" "0 grep $SEARCH_EXCLUSION -rn \"grep -r\" docs"
  fields=$(payload_for 'rg TOKEN' | sh "$SELF" 2>/dev/null | jq -r --arg t "$PROBE_TIMEOUT" '.hookSpecificOutput.updatedInput | (.description == "probe") and ((.timeout | tostring) == $t)' 2>/dev/null)
  expect "33 the rewrite keeps the description and the timeout" "$fields" "true"
  run_gate 'grep -rn TOKEN .' >/dev/null
  expect "34 a rewrite leaves its line in the receipt" "$(last_outcome)" "rewritten"
  told=$(payload_for 'rg TOKEN' | sh "$SELF" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
  case "$told" in *"$RG_EXCLUSION"*) got="the model is told what ran" ;; *) got="the model is not told" ;; esac
  expect "35 the model is told the search skipped the secrets files" "$got" "the model is told what ran"
}

selftest_git_patches() {
  expect "36 git diff gets the pathspec" "$(run_gate 'git diff')" "0 git diff $PATHSPEC_EXCLUSION"
  expect "37 git diff with dashes gets it after its paths" "$(run_gate 'git diff HEAD -- src')" "0 git diff HEAD -- src $PATHSPEC_EXCLUSION"
  expect "38 git show gets the pathspec" "$(run_gate 'git show HEAD~1 | head -40')" "0 git show HEAD~1 $PATHSPEC_EXCLUSION | head -40"
  expect "39 git log with a patch gets the pathspec" "$(run_gate 'git log -n 3 -p')" "0 git log -n 3 -p $PATHSPEC_EXCLUSION"
  expect "40 git log without a patch is untouched" "$(run_gate 'git log --oneline -5')" "0"
  expect "41 git diff --stat only lists names and is untouched" "$(run_gate 'git diff --stat HEAD~1')" "0"
  expect "42 git show of a .env inside a revision blocks" "$(run_gate 'git show HEAD:config/.env.dev')" "2"
  expect "43 git diff that names a .env blocks" "$(run_gate 'git diff -- .env.testing')" "2"
  expect "44 git log -p that names a .env blocks" "$(run_gate 'git log -p .env')" "2"
}

selftest_outcomes() {
  heredoc_then_search=$(printf "cat > notes.md <<'EOF'\nx\nEOF\ngrep -rn TOKEN .")
  heredoc_then_read=$(printf "cat > notes.md <<'EOF'\nx\nEOF\ncat .env")
  expect "45 a command the parser cannot read passes" "$(export PRISMA_PARSER_FAULT=1; run_gate 'cat .env')" "0"
  expect "46 and it is written down as not measured" "$(last_outcome)" "not-measured"
  expect "47 a search the rewrite cannot place passes" "$(run_gate "$heredoc_then_search")" "0"
  expect "48 and it is written down as not measured" "$(last_outcome)" "not-measured"
  expect "49 a read after a heredoc still blocks" "$(run_gate "$heredoc_then_read")" "2"
  expect "50 a block leaves its line in the receipt" "$(last_outcome)" "blocked"
  expect "51 the declared escape passes" "$(run_gate 'PRISMA_SECRET_READS_OK=1 cat .env')" "0"
  expect "52 and it is written down as escaped" "$(last_outcome)" "escaped"
  expect "53 the escape as an argument of echo does not count" "$(run_gate 'echo PRISMA_SECRET_READS_OK=1 && cat .env')" "2"
  without_jq=$(mktemp -d)
  for tool in dirname mkdir date tr cat sed grep; do ln -s "$(command -v "$tool")" "$without_jq/$tool"; done
  if PATH="$without_jq" /bin/sh -c 'dirname /a/b && date && mkdir -p "$1"' probe "$without_jq/probe-dir" >/dev/null 2>&1; then
    : > "$PRISMA_RECEIPT_FILE"
    rc=$(payload_for 'cat .env' | PATH="$without_jq" /bin/sh "$SELF" >/dev/null 2>&1; echo "$?")
    expect "54 without jq the gate passes and writes it down as not measured" "$rc $(last_outcome)" "0 not-measured"
    : > "$PRISMA_RECEIPT_FILE"
    rc=$(payload_for 'ls -la' | PATH="$without_jq" /bin/sh "$SELF" >/dev/null 2>&1; echo "$?")
    expect "80 without jq a command that names no secrets file passes and leaves no line" "$rc $(last_outcome)" "0 "
  else
    skip "54 tools copied into another directory cannot run on this system, so a machine without jq cannot be simulated here"
    skip "80 tools copied into another directory cannot run on this system, so a machine without jq cannot be simulated here"
  fi
  rm -rf "$without_jq"
  expect "55 an unquoted include is quoted in the same rewrite" "$(SHELL=/bin/zsh; export SHELL; run_gate 'grep -rn --include=*.py TOKEN .')" "0 grep $SEARCH_EXCLUSION -rn --include='*.py' TOKEN ."
  expect "81 under bash the include keeps its own form, because only zsh aborts on it" "$(SHELL=/bin/bash; export SHELL; run_gate 'grep -rn --include=*.py TOKEN .')" "0 grep $SEARCH_EXCLUSION -rn --include=*.py TOKEN ."
  expect "82 the declared escape of the shell traps keeps the include as written" "$(SHELL=/bin/zsh; export SHELL; run_gate 'PRISMA_SHELL_TRAPS_OK=1 grep -rn --include=*.py TOKEN .')" "0 PRISMA_SHELL_TRAPS_OK=1 grep $SEARCH_EXCLUSION -rn --include=*.py TOKEN ."
  expect "83 cut of the values blocks, only the first field passes" "$(run_gate 'cut -d= -f2 .env') $(run_gate 'cut -d= -f1,2 .env')" "2 2"
  expect "84 sort, uniq and tac print the lines and block" "$(run_gate 'sort .env') $(run_gate 'uniq .env.dev') $(run_gate 'tac .env')" "2 2 2"
  expect "85 an encoder prints the lines too and blocks" "$(run_gate 'base64 .env') $(run_gate 'od -c .env')" "2 2"
}

selftest_indirect_reads() {
  heredoc_naming=$(printf "cat > notes.md <<'EOF'\nrun sort < .env\nEOF")
  expect "56 an input redirection from a .env blocks" "$(run_gate 'cat < .env')" "2"
  expect "57 a read loop fed from a .env blocks" "$(run_gate 'while read l; do echo $l; done < config/.env.dev')" "2"
  expect "58 a redirection from a .env.example passes" "$(run_gate 'wc -l < .env.example')" "0"
  expect "59 a redirection written inside a heredoc body passes" "$(run_gate "$heredoc_naming")" "0"
  expect "60 a here-string that says .env passes" "$(run_gate 'cat <<< .env')" "0"
  expect "61 find that selects .env files and runs cat blocks" "$(run_gate "find . -name '.env*' -exec cat {} \\;")" "2"
  expect "62 find that runs cat on other files passes" "$(run_gate "find . -name '*.py' -exec cat {} \\;")" "0"
  expect "63 find that only lists matches inside .env files passes" "$(run_gate "find . -name '.env*' -exec grep -l TOKEN {} +")" "0"
  expect "64 a .env fed through a pipe to xargs cat blocks" "$(run_gate 'ls .env.dev | xargs cat')" "2"
  expect "65 xargs running a grep that names a .env blocks" "$(run_gate 'xargs -n1 grep TOKEN .env.dev < hosts.txt')" "2"
  expect "66 xargs that only lists matches passes" "$(run_gate 'ls src | xargs grep -l TOKEN')" "0"
  expect "67 find with a glob that reaches .env files and runs cat blocks" "$(run_gate "find . -name '*.env*' -exec cat {} \\;")" "2"
  expect "68 a glob that names no .env fed to xargs cat passes" "$(run_gate 'ls src/* | xargs cat')" "0"
  expect "69 cat of a glob that reaches .env files blocks" "$(run_gate 'cat config/*.env*')" "2"
  expect "70 the replace option of the BSD xargs takes its value" "$(run_gate 'ls .env.dev | xargs -J % cat %')" "2"
  expect "71 a second -exec of find is read too" "$(run_gate "find . -name '.env*' -exec echo {} \\; -exec cat {} \\;")" "2"
  expect "72 a redirection inside backticks blocks" "$(run_gate 'x=`cat < .env`')" "2"
  expect "73 a redirection inside a quoted substitution blocks" "$(run_gate 'echo "$(< .env)"')" "2"
  expect "74 a redirection written as quoted text passes" "$(run_gate 'echo "use cat < .env to see it"')" "0"
  expect "75 find -execdir that runs cat on .env files blocks" "$(run_gate "find . -name '.env*' -execdir cat {} \\;")" "2"
  expect "76 a process substitution is not a file" "$(run_gate 'diff <(sort a) <(sort b)')" "0"
  expect "77 a redirection written in a comment passes" "$(run_gate 'ls # then cat < .env')" "0"
  expect "79 an escaped less-than sign is not a redirection" "$(run_gate 'echo \< .env')" "0"
  lonely=$(mktemp -d)
  cp "$HOOKS_DIR"/*.sh "$lonely/" && rm -f "$lonely/secret-names.sh"
  : > "$PRISMA_RECEIPT_FILE"
  rc=$(payload_for 'cat .env' | sh "$lonely/secret-reads.sh" >/dev/null 2>&1; echo "$?")
  expect "78 without secret-names.sh the gate passes and writes it down as not measured" "$rc $(last_outcome)" "0 not-measured"
  rm -rf "$lonely"
}

selftest() {
  ok=1; cases=0
  selftest_direct_reads
  selftest_named_searches
  selftest_folder_searches
  selftest_git_patches
  selftest_outcomes
  selftest_indirect_reads
  [ "$cases" = "$SELFTEST_CASES" ] || { printf 'FAIL %s cases ran and %s were expected\n' "$cases" "$SELFTEST_CASES"; ok=0; }
  [ "$ok" = "1" ] && printf 'SELFTEST OK: %s/%s\n' "$SELFTEST_CASES" "$SELFTEST_CASES" && exit 0
  printf 'SELFTEST FAILED\n'; exit 1
}
