# Prisma Harness. Documented in README.md, section "What is inside". Loaded by shell-traps.sh, not run alone.

payload_for() {
  printf '{"tool_name":"Bash","cwd":"/tmp","tool_input":{"command":%s,"description":"probe","timeout":%s}}' "$(printf '%s' "$1" | jq -Rs .)" "$PROBE_TIMEOUT"
}

run_hook() {
  payload_for "$1" | SHELL="$2" PATH="${3:-$PATH}" PRISMA_REQUIRED_WRAPPERS="${4:-$DEFAULT_WRAPPERS}" sh "$SELF" 2>/dev/null
}

run_command() {
  out=$(run_hook "$@"); rc=$?
  printf '%s %s' "$rc" "$(printf '%s' "$out" | jq -c '.hookSpecificOutput.updatedInput.command // empty' 2>/dev/null | tr -d '\r')"
}

as_json() {
  printf '%s' "$1" | jq -Rs . | tr -d '\r'
}

expect_command() {
  expect "$1" "$2" "${3%% *} $(as_json "${3#* }")"
}

run_fields() {
  run_hook "$@" | jq -e --arg t "$PROBE_TIMEOUT" '.hookSpecificOutput.updatedInput | .description == "probe" and (.timeout | tostring) == $t' >/dev/null 2>&1 \
    && echo "keeps description and timeout" || echo "lost fields"
}

run_reason() {
  run_hook "$@" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null | grep -qF "'*.md'" && echo "names the pattern" || echo "no pattern in the reason"
}

payload_in() {
  printf '{"tool_name":"Bash","cwd":%s,"tool_input":{"command":%s}}' "$(printf '%s' "$2" | jq -Rs .)" "$(printf '%s' "$1" | jq -Rs .)"
}

run_payload_in() {
  payload_in "$1" "$2" | SHELL="$ZSH" sh "$SELF" >/dev/null 2>&1
  echo "$?"
}

run_payload_in_stderr() {
  payload_in "$1" "$2" | SHELL="$ZSH" sh "$SELF" 2>&1 >/dev/null
}

run_without_lsof() {
  payload_in "$1" "$2" | PRISMA_LSOF="$MISSING_TOOL" SHELL="$ZSH" sh "$SELF" >/dev/null 2>&1
  echo "$?"
}

run_without_pgrep() {
  payload_in "$1" "$2" | PRISMA_PGREP="$MISSING_TOOL" SHELL="$ZSH" sh "$SELF" >/dev/null 2>&1
  echo "$?"
}

skip_case() {
  cases=$((cases+1)); printf 'SKIP %s, %s\n' "$1" "$2"
}

expect_measured() {
  if command -v pgrep >/dev/null 2>&1; then expect "$@"; else skip_case "$1" "this system has no pgrep"; fi
}

expect_where_proc() {
  if [ -e "$PROC_PROBE" ]; then expect_measured "$@"; else skip_case "$1" "this system has no /proc"; fi
}

expect_without_proc() {
  if [ -e "$PROC_PROBE" ]; then skip_case "$1" "this system has /proc"; else expect_measured "$@"; fi
}

run_payload() {
  printf '{"tool_name":"Bash","cwd":"/tmp","tool_input":{"command":%s}}' "$(printf '%s' "$1" | jq -Rs .)" \
    | SHELL="$2" PATH="${3:-$PATH}" PRISMA_REQUIRED_WRAPPERS="${4:-$DEFAULT_WRAPPERS}" sh "$SELF" >/dev/null 2>&1
  echo "$?"
}

expect() {
  cases=$((cases+1))
  if [ "$2" = "$3" ]; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s, expected %s and got %s\n' "$1" "$3" "$2"; ok=0; fi
}

selftest_include_glob() {
  expect_command "1 an unquoted include glob under zsh is quoted and runs" "$(run_command 'grep -rn --include=*.md foo .' "$ZSH")" "0 grep -rn --include='*.md' foo ."
  expect "2 the same pattern in single quotes passes untouched" "$(run_command "grep -rn --include='*.md' foo ." "$ZSH")" "0 "
  expect "3 the whole flag in double quotes passes untouched" "$(run_command 'grep -rn "--include=*.md" foo .' "$ZSH")" "0 "
  expect "4 a search only mentioned inside quotes passes untouched" "$(run_command 'echo "grep -rn --include=*.md foo ."' "$ZSH")" "0 "
  expect "5 a real search next to a quoted mention of the glob passes untouched" "$(run_command 'grep -rn foo . && echo "next time use --include=*.md"' "$ZSH")" "0 "
  expect_command "6 an escaped quote inside double quotes stays and the glob is quoted" "$(run_command 'grep -rn "a\|href=\"#" src/ --include=*.tsx | grep -v "test"' "$ZSH")" "0 grep -rn \"a\|href=\\\"#\" src/ --include='*.tsx' | grep -v \"test\""
  expect "7 under bash the unquoted glob reaches grep and passes untouched" "$(run_command 'grep -rn --include=*.md foo .' /bin/bash)" "0 "
  expect_command "8 a brace glob becomes one quoted flag per item" "$(run_command 'cd notes && grep -rln --include=*.{md,txt} foo . | wc -l' /usr/bin/zsh)" "0 cd notes && grep -rln --include='*.md' --include='*.txt' foo . | wc -l"
  expect "9 a brace list with no glob character expands and passes untouched" "$(run_command 'grep -rn --include={a.md,b.md} foo .' "$ZSH")" "0 "
  expect "10 a search written only in a trailing comment passes untouched" "$(run_command 'ls -la # then grep -rn --include=*.md foo .' "$ZSH")" "0 "
  expect "11 the escape lets the unquoted glob through untouched" "$(run_command "$ESCAPE grep -rn --include=*.md foo ." "$ZSH")" "0 "
  expect_command "12 the pattern as a separate word is quoted too" "$(run_command 'grep -rn --include *.md foo .' "$ZSH")" "0 grep -rn --include '*.md' foo ."
  expect "13 a glob character escaped with a backslash passes untouched" "$(run_command 'grep -rn --include=\*.md foo .' "$ZSH")" "0 "
  expect_command "14 egrep counts as a search" "$(run_command 'egrep -rn --include=*.md foo .' "$ZSH")" "0 egrep -rn --include='*.md' foo ."
  expect_command "15 a SHELL named without its path still counts as zsh" "$(run_command 'grep -rn --include=*.md foo .' zsh)" "0 grep -rn --include='*.md' foo ."
  expect "23 nested braces cannot be rewritten safely and block" "$(run_payload 'grep -rn --include=*.{md,{txt,csv}} foo .' "$ZSH")" 2
  expect_command "24 every unquoted include on the line is quoted" "$(run_command 'grep -rn --include=*.md --include=*.txt foo .' "$ZSH")" "0 grep -rn --include='*.md' --include='*.txt' foo ."
  expect "25 the rewrite keeps the other fields of the call" "$(run_fields 'grep -rn --include=*.md foo .' "$ZSH")" "keeps description and timeout"
  expect "26 the reason names the quoted pattern" "$(run_reason 'grep -rn --include=*.md foo .' "$ZSH")" "names the pattern"
  expect "28 an include glob inside a heredoc body is data and passes untouched" "$(run_command "$HEREDOC_PROBE" "$ZSH")" "0 "
  expect_command "29 a real search after a heredoc is still quoted and the body is kept" "$(run_command "$HEREDOC_THEN_SEARCH" "$ZSH")" "0 $HEREDOC_THEN_SEARCH_FIXED"
  expect "30 a glob next to a quote cannot be quoted safely and blocks" "$(run_payload 'grep -rn --include=*"x".md foo .' "$ZSH")" 2
  expect "31 a glob next to a variable cannot be quoted safely and blocks" "$(run_payload 'grep -rn --include=*.$EXT foo .' "$ZSH")" 2
  expect "32 one unsafe pattern blocks the whole line, no half rewrite" "$(run_payload 'grep -rn --include=*.md --include=*"x".txt foo .' "$ZSH")" 2
  expect "33 a quoter that fails blocks as before, never opens" "$(PRISMA_QUOTE_WORDS=/usr/bin/false run_payload 'grep -rn --include=*.md foo .' "$ZSH")" 2
  expect_command "34 a herestring is not a heredoc, the search below it is quoted" "$(run_command "$HERESTRING_THEN_SEARCH" "$ZSH")" "0 $HERESTRING_THEN_SEARCH_FIXED"
  expect "35 an include next to a missing wrapper blocks" "$(run_payload "$MISSING_WRAPPER 5 grep -rn --include=*.md foo ." "$ZSH" "$PATH" "$MISSING_WRAPPER")" 2
}

selftest_kills() {
  other_dir=$(mktemp -d); own_dir=$(mktemp -d)
  ln -s "$(command -v sleep)" "$other_dir/$KILL_PROBE_NAME"
  (cd "$other_dir" && exec "./$KILL_PROBE_NAME" "$KILL_PROBE_SECONDS") &
  foreign_pid=$!
  (cd "$other_dir" && exec "$KILL_PYTHON" -c "$KILL_SLEEPER" "$KILL_PROBE_SECONDS" "$REDIRECTION") &
  redirection_pid=$!
  sleep "$PROBE_START_SECONDS"
  expect_measured "36 pkill whose pattern reaches a process in another folder blocks" "$(run_payload_in "pkill -f $KILL_PROBE_NAME" "$own_dir")" 2
  expect_measured "37 killall of a name that runs in another folder blocks" "$(run_payload_in "killall $KILL_PROBE_NAME" "$own_dir")" 2
  expect_measured "72 a killall of another long name that shares the first 15 letters passes" "$(run_payload_in "killall $KILL_PROBE_NAME-other" "$own_dir")" 0
  expect_measured "38 the same pkill from the folder that owns the process passes" "$(run_payload_in "pkill -f $KILL_PROBE_NAME" "$other_dir")" 0
  expect_measured "39 a pkill that matches nothing passes" "$(run_payload_in "pkill -f no-such-process-$KILL_PROBE_SECONDS" "$own_dir")" 0
  expect "40 a pkill only mentioned inside quotes passes" "$(run_payload_in "echo \"pkill -f $KILL_PROBE_NAME\"" "$own_dir")" 0
  expect_measured "41 the escape lets a foreign pkill through" "$(run_payload_in "$ESCAPE pkill -f $KILL_PROBE_NAME" "$own_dir")" 0
  foreign_block=$(run_payload_in_stderr "pkill -f $KILL_PROBE_NAME" "$own_dir")
  expect_measured "42 the block names the foreign folder" "$(printf '%s' "$foreign_block" | grep -c "$other_dir")" 1
  expect_measured "67 the block says the processes run in another folder, never that another session started them" "$(printf '%s' "$foreign_block" | grep -c 'another session') $(printf '%s' "$foreign_block" | grep -c 'another folder')" "0 1"
  expect_measured "43 a foreign pkill after an own pkill on the same line still blocks" "$(run_payload_in "pkill -x $KILL_OWN_NAME; pkill -f $KILL_PROBE_NAME" "$own_dir")" 2
  expect_measured "68 a pkill with a redirection still blocks a process in another folder" "$(run_payload_in "pkill -f $KILL_PROBE_NAME $REDIRECTION" "$own_dir") $(run_payload_in "pkill -f $KILL_PROBE_NAME > out.log" "$own_dir") $(run_payload_in "killall $KILL_OWN_NAME $REDIRECTION; pkill -f $KILL_PROBE_NAME 2>&1" "$own_dir")" "2 2 2"
  expect_measured "69 a redirection is not a pattern, so it never reaches a process whose command line holds it" "$(run_payload_in "pkill -f no-such-process-$KILL_PROBE_SECONDS $REDIRECTION" "$own_dir")" 0
  expect_measured "74 a redirection glued to the pattern is not part of it" "$(run_payload_in "pkill -f $KILL_PROBE_NAME>/dev/null" "$own_dir")" 2
  expect_measured "75 a quoted pattern that holds a > stays a pattern" "$(run_payload_in "pkill -f '$KILL_PROBE_SECONDS $REDIRECTION'" "$own_dir")" 2
  expect_where_proc "70 without lsof the folder is read from /proc, so a foreign pkill still blocks" "$(run_without_lsof "pkill -f $KILL_PROBE_NAME" "$own_dir")" 2
  : > "$PRISMA_RECEIPT_FILE"
  expect_without_proc "71 a process whose folder neither lsof nor /proc can read is let through and recorded as not measured" "$(run_without_lsof "pkill -f $KILL_PROBE_NAME" "$own_dir") $(grep -c "	$GATE_NAME	.*	not-measured$" "$PRISMA_RECEIPT_FILE")" "0 1"
  expect_measured "44 the flags of one pkill do not leak into the next" "$(run_payload_in "pkill -f $KILL_OWN_NAME; pkill -9 -f no-such-process-$KILL_PROBE_SECONDS" "$own_dir")" 0
  : > "$PRISMA_RECEIPT_FILE"
  expect "73 where pgrep is missing a pkill is let through and recorded as not measured" "$(run_without_pgrep "pkill -f $KILL_PROBE_NAME" "$own_dir") $(grep -c "	$GATE_NAME	.*	not-measured$" "$PRISMA_RECEIPT_FILE")" "0 1"
  receipt="$PRISMA_RECEIPT_FILE"; : > "$receipt"
  printf '{"tool_name":"Bash","tool_input":{"command":"pkill -f %s"}}' "$KILL_PROBE_NAME" | SHELL="$ZSH" sh "$SELF" >/dev/null 2>&1
  expect "45 a pkill without a session folder is let through and recorded as not measured" "$? $(grep -c "	$GATE_NAME	.*	not-measured$" "$receipt")" "0 1"
  kill "$foreign_pid" "$redirection_pid" 2>/dev/null
  wait "$foreign_pid" "$redirection_pid" 2>/dev/null
  rm -rf "$other_dir" "$own_dir"
}

selftest_equals_word() {
  expect_command "46 an unquoted ==== word under zsh is quoted and the rest of the line runs" "$(run_command 'echo ==== && echo after' "$ZSH")" "0 echo '====' && echo after"
  expect_command "47 a lone == in a single bracket test is quoted" "$(run_command '[ "$a" == "$b" ] && echo same' "$ZSH")" "0 [ \"\$a\" '==' \"\$b\" ] && echo same"
  expect "48 under bash a == word passes untouched" "$(run_command 'echo ====' /bin/bash)" "0 "
  expect_command "49 a single =name is the expansion zsh means and stays, the == word next to it is quoted" "$(run_command 'ls -l =ls && echo ====' "$ZSH")" "0 ls -l =ls && echo '===='"
  expect "50 a == word with a dollar cannot be quoted safely and blocks" "$(run_payload 'echo ==$HOME' "$ZSH")" 2
  expect "62 a block for an unsafe == word names the equals trap" "$(run_payload_in_stderr 'echo ==$HOME' /tmp | grep -c '= not found')" 1
  expect "66 a == word with a quote, a glob or a brace cannot be quoted safely and blocks" "$(run_payload 'echo =="x"' "$ZSH") $(run_payload 'echo ==*' "$ZSH") $(run_payload 'echo =={a,b}' "$ZSH")" "2 2 2"
  expect "65 an unsafe include next to a == word names the include trap" "$(run_payload_in_stderr 'rsync -a --include=*.{md,{txt,csv}} src/ dst/ && echo ====' /tmp | grep -c 'no matches found')" 1
  expect_command "51 both traps on one line are quoted in one pass" "$(run_command 'grep -rn --include=*.md foo . && echo ====' "$ZSH")" "0 grep -rn --include='*.md' foo . && echo '===='"
  receipt="$PRISMA_RECEIPT_FILE"; : > "$receipt"
  equals_rc=$(run_payload 'echo ==== && echo after' "$ZSH")
  expect "52 a rewrite of a == word leaves its line in the receipt" "$equals_rc $(grep -c "	$GATE_NAME	.*	rewritten$" "$receipt")" "0 1"
}

selftest_unexpanded_regions() {
  expect_command "53 a == inside [[ ]] is an operator and stays, the word after the test is quoted" "$(run_command '[[ $a == b ]] && echo ====' "$ZSH")" "0 [[ \$a == b ]] && echo '===='"
  expect "54 an include pattern inside [[ ]] keeps its meaning" "$(run_command '[[ $f == --include=*.md ]] && grep -rn foo .' "$ZSH")" "0 "
  expect_command "55 arithmetic in (( )) and \$(( )) stays as written" "$(run_command 'echo $(( 1 == 1 )) && (( 2 == 2 )) && echo ====' "$ZSH")" "0 echo \$(( 1 == 1 )) && (( 2 == 2 )) && echo '===='"
  expect_command "63 case and in written as plain arguments do not stop the rewrite" "$(run_command 'grep -rn -e case -e in --include=*.md . && echo ====' "$ZSH")" "0 grep -rn -e case -e in --include='*.md' . && echo '===='"
  expect "56 an include pattern of a case keeps its meaning" "$(run_command 'case $f in --include=*.md) grep -rn foo . ;; esac' "$ZSH")" "0 "
  expect_command "57 a == pattern of a case stays and its body is still quoted" "$(run_command 'case $x in ==*) echo ==== ;; esac' "$ZSH")" "0 case \$x in ==*) echo '====' ;; esac"
}

selftest_heredoc_delimiters() {
  dashed=$(printf 'cat <<END-DATA\nuse --include=*.md\nEND-DATA\ngrep -rn --include=*.txt foo .')
  expect_command "58 a delimiter with a dash keeps its body and the search below it is quoted" "$(run_command "$dashed" "$ZSH")" "0 $(printf 'cat <<END-DATA\nuse --include=*.md\nEND-DATA\ngrep -rn --include='"'*.txt'"' foo .')"
  dotted=$(printf "cat <<'end.txt'\necho ====\nend.txt\necho ====")
  expect_command "59 a quoted delimiter with a dot keeps its body and the word below it is quoted" "$(run_command "$dotted" "$ZSH")" "0 $(printf "cat <<'end.txt'\necho ====\nend.txt\necho '===='")"
  spaced=$(printf 'cat <<EOF\n EOF\necho ====\nEOF\necho done')
  expect "60 a body line with a space before the delimiter does not close the body" "$(run_command "$spaced" "$ZSH")" "0 "
  mixed=$(printf 'cat <<E"O"F\necho ====\nEOF\necho ====')
  expect_command "64 a delimiter written with mixed quotes keeps its body" "$(run_command "$mixed" "$ZSH")" "0 $(printf 'cat <<E"O"F\necho ====\nEOF\necho '"'===='"'')"
  tabbed=$(printf 'cat <<-EOF\n\techo ====\n\tEOF\necho ====')
  expect_command "61 under <<- a delimiter after tabs closes the body" "$(run_command "$tabbed" "$ZSH")" "0 $(printf 'cat <<-EOF\n\techo ====\n\tEOF\necho '"'===='"'')"
}

selftest_wrappers_and_input() {
  expect "16 a wrapper that is not installed blocks" "$(run_payload "$MISSING_WRAPPER 10 curl -s https://example.com" "$ZSH" "$PATH" "$MISSING_WRAPPER")" 2
  expect "17 an installed timeout passes" "$(run_payload "$DEFAULT_WRAPPERS 10 curl -s https://example.com" "$ZSH" "$fake_bin:$PATH")" 0
  expect "18 a missing wrapper only mentioned passes" "$(run_payload "echo $MISSING_WRAPPER is missing" "$ZSH" "$PATH" "$MISSING_WRAPPER")" 0
  expect "19 input that is not JSON passes" "$(printf 'this is not json' | sh "$SELF" >/dev/null 2>&1; echo "$?")" 0
  expect "20 a tool other than Bash passes" "$(printf '{"tool_name":"Write","tool_input":{"command":"grep --include=*.md x"}}' | SHELL="$ZSH" sh "$SELF" >/dev/null 2>&1; echo "$?")" 0
}

selftest_receipt() {
  receipt="$PRISMA_RECEIPT_FILE"; : > "$receipt"
  blocked_rc=$(run_payload 'grep -rn --include=*.{md,{txt,csv}} foo .' "$ZSH")
  expect "21 a block leaves its line in the receipt" "$blocked_rc $(grep -c "	$GATE_NAME	.*	blocked$" "$receipt")" "2 1"
  rewritten_rc=$(run_payload 'grep -rn --include=*.md foo .' "$ZSH")
  expect "27 a rewrite leaves its own line in the receipt" "$rewritten_rc $(grep -c "	$GATE_NAME	.*	rewritten$" "$receipt")" "0 1"
  fault_rc=$(PRISMA_PARSER_FAULT=1 run_payload 'grep -rn --include=*.md foo .' "$ZSH")
  expect "22 a parser that fails lets the command through and says so in the receipt" "$fault_rc $(grep -c "	$GATE_NAME	.*	not-measured$" "$receipt")" "0 1"
}

selftest() {
  SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
  ZSH=/bin/zsh
  PROBE_TIMEOUT=60000
  KILL_PROBE_NAME=prisma-kill-probe-$$
  KILL_PROBE_SECONDS=300
  KILL_OWN_NAME=prisma-own-probe-$$
  KILL_PYTHON=$(command -v python3 || command -v python)
  KILL_SLEEPER='import sys, time; time.sleep(int(sys.argv[1]))'
  REDIRECTION='2>/dev/null'
  MISSING_TOOL=no-such-tool-$$
  PROC_PROBE=/proc/$$/cwd
  PROBE_START_SECONDS=1
  HEREDOC_PROBE=$(printf "python3 - <<'EOF'\nprint('grep -rn --include=*.md foo .')\nEOF")
  HEREDOC_THEN_SEARCH=$(printf "cat > notes.txt <<'EOF'\nuse --include=*.md\nEOF\ngrep -rn --include=*.txt foo .")
  HERESTRING_THEN_SEARCH=$(printf "cat <<<'x'\ngrep -rn --include=*.md foo .")
  HERESTRING_THEN_SEARCH_FIXED=$(printf "cat <<<'x'\ngrep -rn --include='*.md' foo .")
  HEREDOC_THEN_SEARCH_FIXED=$(printf "cat > notes.txt <<'EOF'\nuse --include=*.md\nEOF\ngrep -rn --include='*.txt' foo .")
  MISSING_WRAPPER=no-such-wrapper-alpha
  fake_bin=$(mktemp -d)
  printf '#!/bin/sh\nexit 0\n' > "$fake_bin/$DEFAULT_WRAPPERS"; chmod +x "$fake_bin/$DEFAULT_WRAPPERS"
  ok=1; cases=0
  selftest_include_glob
  selftest_equals_word
  selftest_unexpanded_regions
  selftest_heredoc_delimiters
  selftest_wrappers_and_input
  selftest_kills
  selftest_receipt
  rm -rf "$fake_bin"
  [ "$cases" = "$SELFTEST_CASES" ] || { printf 'FAIL %s cases ran and %s were expected\n' "$cases" "$SELFTEST_CASES"; ok=0; }
  [ "$ok" = "1" ] && printf 'SELFTEST OK: %s/%s\n' "$SELFTEST_CASES" "$SELFTEST_CASES" && exit 0
  printf 'SELFTEST FAILED\n'; exit 1
}
