#!/bin/sh
# Prisma Harness. Documented in README.md, section "What is inside".
if [ "${1:-}" = "--selftest" ]; then . "$(cd "$(dirname "$0")" && pwd)/selftest-env.sh"; fi

HOOKS_DIR="${PRISMA_HOOKS_DIR:-$(cd "$(dirname "$0")" 2>/dev/null && pwd)}"
INVOKES="$HOOKS_DIR/command-invokes.sh"
STRIP_QUOTES="$HOOKS_DIR/strip-quotes.sh"
QUOTE_INCLUDES="${PRISMA_QUOTE_INCLUDES:-$HOOKS_DIR/quote-include-globs.sh}"
ESCAPE="PRISMA_SHELL_TRAPS_OK=1"
GATE_NAME="shell-traps-gate"
UNQUOTED_INCLUDE_GLOB='(^|[[:space:]])--include(=|[[:space:]]+)([^'"'"'"[:space:]\\]|\\.)*[*?[]'
SEARCH_PROGRAMS="grep egrep fgrep ugrep"
DEFAULT_WRAPPERS="timeout"
REQUIRED_WRAPPERS="${PRISMA_REQUIRED_WRAPPERS:-$DEFAULT_WRAPPERS}"
PARSER_FAILED=3
SELFTEST_CASES=35
PRISMA_RECEIPT_SOURCED=1
. "$HOOKS_DIR/receipt.sh"
PRISMA_ESCAPE_SOURCED=1
. "$HOOKS_DIR/escape-declared.sh"

not_measured() {
  echo "WARN: the shell traps gate did not run, $1." >&2
  receipt_append "$GATE_NAME" "$working_dir" not-measured
  exit 0
}

block() {
  {
    printf 'SHELL TRAP: %s\n\n%s\n\nFix: %s\n' "$1" "$2" "$3"
    printf 'If you really mean what you wrote, declare %s at the start of the command.\n' "$ESCAPE"
  } >&2
  receipt_append "$GATE_NAME" "$working_dir" blocked
  exit 2
}

invokes() {
  found=$(printf '%s' "$2" | "$INVOKES" "$1" 2>/dev/null); rc=$?
  [ "$rc" = "$PARSER_FAILED" ] && not_measured "the command parser could not read the command"
  [ -n "$found" ]
}

invokes_a_search() {
  for program in $SEARCH_PROGRAMS; do invokes "$program" "$1" && return 0; done
  return 1
}

has_unquoted_include_glob() {
  case "${SHELL:-}" in */zsh|zsh) printf '%s' "$1" | grep -qE "$UNQUOTED_INCLUDE_GLOB" ;; *) return 1 ;; esac
}

missing_wrappers_named() {
  for wrapper in $REQUIRED_WRAPPERS; do
    case "$1" in *"$wrapper"*) command -v "$wrapper" >/dev/null 2>&1 || printf '%s ' "$wrapper" ;; esac
  done
}

allow_rewritten() {
  receipt_append "$GATE_NAME" "$working_dir" rewritten
  printf '%s' "$payload" | jq --arg command "$1" --arg reason "PRISMA shell traps quoted the --include pattern, because zsh aborts an unquoted one with 'no matches found'. The command that runs is: $1" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow", permissionDecisionReason: $reason, updatedInput: (.tool_input + {command: $command})}}'
  exit 0
}

check_include_glob() {
  has_unquoted_include_glob "$bare_command" && invokes_a_search "$command_text" || return 0
  if [ -z "$wrappers" ]; then
    rewritten=$(printf '%s' "$command_text" | "$QUOTE_INCLUDES" 2>/dev/null) && {
      [ -n "$rewritten" ] && allow_rewritten "$rewritten"
      return 0
    }
  fi
  block "a command on this line will not run." \
    "Under zsh an unquoted --include pattern is read as a file glob. It matches no file, zsh aborts that command with 'no matches found', and the rest of the line goes on as if the search had found nothing." \
    "quote the pattern, for example --include='*.md'."
}

check_wrappers() {
  for wrapper in $1; do
    invokes "$wrapper" "$command_text" && block "$wrapper is not installed on this machine." \
      "The command it wraps never runs, and the error hides in the output." \
      "drop $wrapper, or set the time limit inside the program itself."
  done
}

run_gate() {
  command -v jq >/dev/null 2>&1 || { echo "WARN: the shell traps gate did not run, jq is missing." >&2; exit 0; }
  payload=$(cat)
  [ "$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)" = "Bash" ] || exit 0
  command_text=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)
  working_dir=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)
  wrappers=$(missing_wrappers_named "$command_text")
  has_unquoted_include_glob "$command_text" || [ -n "$wrappers" ] || exit 0
  [ -x "$INVOKES" ] || not_measured "command-invokes.sh is missing"
  bare_command=$(printf '%s' "$command_text" | "$STRIP_QUOTES" 2>/dev/null) || not_measured "strip-quotes.sh could not read the command"
  if escape_declared "$ESCAPE" "$bare_command"; then receipt_append "$GATE_NAME" "$working_dir" escaped; exit 0; fi
  check_include_glob
  check_wrappers "$wrappers"
  exit 0
}

payload_for() {
  printf '{"tool_name":"Bash","cwd":"/tmp","tool_input":{"command":%s,"description":"probe","timeout":%s}}' "$(printf '%s' "$1" | jq -Rs .)" "$PROBE_TIMEOUT"
}

run_hook() {
  payload_for "$1" | SHELL="$2" PATH="${3:-$PATH}" PRISMA_REQUIRED_WRAPPERS="${4:-$DEFAULT_WRAPPERS}" sh "$SELF" 2>/dev/null
}

run_command() {
  out=$(run_hook "$@"); rc=$?
  printf '%s %s' "$rc" "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedInput.command // empty' 2>/dev/null)"
}

run_fields() {
  run_hook "$@" | jq -e --arg t "$PROBE_TIMEOUT" '.hookSpecificOutput.updatedInput | .description == "probe" and (.timeout | tostring) == $t' >/dev/null 2>&1 \
    && echo "keeps description and timeout" || echo "lost fields"
}

run_reason() {
  run_hook "$@" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null | grep -qF "'*.md'" && echo "names the pattern" || echo "no pattern in the reason"
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
  expect "1 an unquoted include glob under zsh is quoted and runs" "$(run_command 'grep -rn --include=*.md foo .' "$ZSH")" "0 grep -rn --include='*.md' foo ."
  expect "2 the same pattern in single quotes passes untouched" "$(run_command "grep -rn --include='*.md' foo ." "$ZSH")" "0 "
  expect "3 the whole flag in double quotes passes untouched" "$(run_command 'grep -rn "--include=*.md" foo .' "$ZSH")" "0 "
  expect "4 a search only mentioned inside quotes passes untouched" "$(run_command 'echo "grep -rn --include=*.md foo ."' "$ZSH")" "0 "
  expect "5 a real search next to a quoted mention of the glob passes untouched" "$(run_command 'grep -rn foo . && echo "next time use --include=*.md"' "$ZSH")" "0 "
  expect "6 an escaped quote inside double quotes stays and the glob is quoted" "$(run_command 'grep -rn "a\|href=\"#" src/ --include=*.tsx | grep -v "test"' "$ZSH")" "0 grep -rn \"a\|href=\\\"#\" src/ --include='*.tsx' | grep -v \"test\""
  expect "7 under bash the unquoted glob reaches grep and passes untouched" "$(run_command 'grep -rn --include=*.md foo .' /bin/bash)" "0 "
  expect "8 a brace glob becomes one quoted flag per item" "$(run_command 'cd notes && grep -rln --include=*.{md,txt} foo . | wc -l' /usr/bin/zsh)" "0 cd notes && grep -rln --include='*.md' --include='*.txt' foo . | wc -l"
  expect "9 a brace list with no glob character expands and passes untouched" "$(run_command 'grep -rn --include={a.md,b.md} foo .' "$ZSH")" "0 "
  expect "10 a search written only in a trailing comment passes untouched" "$(run_command 'ls -la # then grep -rn --include=*.md foo .' "$ZSH")" "0 "
  expect "11 the escape lets the unquoted glob through untouched" "$(run_command "$ESCAPE grep -rn --include=*.md foo ." "$ZSH")" "0 "
  expect "12 the pattern as a separate word is quoted too" "$(run_command 'grep -rn --include *.md foo .' "$ZSH")" "0 grep -rn --include '*.md' foo ."
  expect "13 a glob character escaped with a backslash passes untouched" "$(run_command 'grep -rn --include=\*.md foo .' "$ZSH")" "0 "
  expect "14 egrep counts as a search" "$(run_command 'egrep -rn --include=*.md foo .' "$ZSH")" "0 egrep -rn --include='*.md' foo ."
  expect "15 a SHELL named without its path still counts as zsh" "$(run_command 'grep -rn --include=*.md foo .' zsh)" "0 grep -rn --include='*.md' foo ."
  expect "23 nested braces cannot be rewritten safely and block" "$(run_payload 'grep -rn --include=*.{md,{txt,csv}} foo .' "$ZSH")" 2
  expect "24 every unquoted include on the line is quoted" "$(run_command 'grep -rn --include=*.md --include=*.txt foo .' "$ZSH")" "0 grep -rn --include='*.md' --include='*.txt' foo ."
  expect "25 the rewrite keeps the other fields of the call" "$(run_fields 'grep -rn --include=*.md foo .' "$ZSH")" "keeps description and timeout"
  expect "26 the reason names the quoted pattern" "$(run_reason 'grep -rn --include=*.md foo .' "$ZSH")" "names the pattern"
  expect "28 an include glob inside a heredoc body is data and passes untouched" "$(run_command "$HEREDOC_PROBE" "$ZSH")" "0 "
  expect "29 a real search after a heredoc is still quoted and the body is kept" "$(run_command "$HEREDOC_THEN_SEARCH" "$ZSH")" "0 $HEREDOC_THEN_SEARCH_FIXED"
  expect "30 a glob next to a quote cannot be quoted safely and blocks" "$(run_payload 'grep -rn --include=*"x".md foo .' "$ZSH")" 2
  expect "31 a glob next to a variable cannot be quoted safely and blocks" "$(run_payload 'grep -rn --include=*.$EXT foo .' "$ZSH")" 2
  expect "32 one unsafe pattern blocks the whole line, no half rewrite" "$(run_payload 'grep -rn --include=*.md --include=*"x".txt foo .' "$ZSH")" 2
  expect "33 a quoter that fails blocks as before, never opens" "$(PRISMA_QUOTE_INCLUDES=/usr/bin/false run_payload 'grep -rn --include=*.md foo .' "$ZSH")" 2
  expect "34 a herestring is not a heredoc, the search below it is quoted" "$(run_command "$HERESTRING_THEN_SEARCH" "$ZSH")" "0 $HERESTRING_THEN_SEARCH_FIXED"
  expect "35 an include next to a missing wrapper blocks" "$(run_payload "$MISSING_WRAPPER 5 grep -rn --include=*.md foo ." "$ZSH" "$PATH" "$MISSING_WRAPPER")" 2
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
  selftest_wrappers_and_input
  selftest_receipt
  rm -rf "$fake_bin"
  [ "$cases" = "$SELFTEST_CASES" ] || { printf 'FAIL %s cases ran and %s were expected\n' "$cases" "$SELFTEST_CASES"; ok=0; }
  [ "$ok" = "1" ] && printf 'SELFTEST OK: %s/%s\n' "$SELFTEST_CASES" "$SELFTEST_CASES" && exit 0
  printf 'SELFTEST FAILED\n'; exit 1
}

[ "${1:-}" = "--selftest" ] && selftest
run_gate
