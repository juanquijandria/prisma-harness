#!/bin/sh
# Prisma Harness. Documented in README.md, section "What is inside".
if [ "${1:-}" = "--selftest" ]; then . "$(cd "$(dirname "$0")" && pwd)/selftest-env.sh"; fi

HOOKS_DIR="${PRISMA_HOOKS_DIR:-$(cd "$(dirname "$0")" 2>/dev/null && pwd)}"
INVOKES="$HOOKS_DIR/command-invokes.sh"
STRIP_QUOTES="$HOOKS_DIR/strip-quotes.sh"
QUOTE_WORDS="${PRISMA_QUOTE_WORDS:-$HOOKS_DIR/quote-zsh-words.sh}"
KILL_TARGETS="$HOOKS_DIR/kill-targets.sh"
KILLERS="pkill killall"
PARTLY_MEASURED=5
KILL_LINES_SHOWN=10
ESCAPE="PRISMA_SHELL_TRAPS_OK=1"
GATE_NAME="shell-traps-gate"
UNQUOTED_INCLUDE_GLOB='(^|[[:space:]])--include(=|[[:space:]]+)([^'"'"'"[:space:]\\]|\\.)*[*?[]'
UNQUOTED_EQUALS_WORD='(^|[[:space:];&|(])=='
SEARCH_PROGRAMS="grep egrep fgrep ugrep"
DEFAULT_WRAPPERS="timeout"
REQUIRED_WRAPPERS="${PRISMA_REQUIRED_WRAPPERS:-$DEFAULT_WRAPPERS}"
PARSER_FAILED=3
UNSAFE_INCLUDE=4
UNSAFE_EQUALS=6
SELFTEST_CASES=75
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

matches_under_zsh() {
  case "${SHELL:-}" in */zsh|zsh) printf '%s' "$2" | grep -qE "$1" ;; *) return 1 ;; esac
}

has_unquoted_include_glob() { matches_under_zsh "$UNQUOTED_INCLUDE_GLOB" "$1"; }

has_unquoted_equals_word() { matches_under_zsh "$UNQUOTED_EQUALS_WORD" "$1"; }

missing_wrappers_named() {
  for wrapper in $REQUIRED_WRAPPERS; do
    case "$1" in *"$wrapper"*) command -v "$wrapper" >/dev/null 2>&1 || printf '%s ' "$wrapper" ;; esac
  done
}

allow_rewritten() {
  receipt_append "$GATE_NAME" "$working_dir" rewritten
  printf '%s' "$payload" | jq --arg command "$1" --arg reason "PRISMA shell traps quoted what zsh would have expanded, an --include pattern that aborts with 'no matches found' or a word starting with = that zsh reads as the path of a command. The command that runs is: $1" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow", permissionDecisionReason: $reason, updatedInput: (.tool_input + {command: $command})}}'
  exit 0
}

block_equals_word() {
  block "a command on this line will not run." \
    "Under zsh an unquoted word that starts with = is replaced by the path of the command named after it. A word like ==== names no command, zsh stops with '= not found', and the rest of a line joined with && never runs." \
    "quote the word, for example echo '===='."
}

check_quoting() {
  include=""; has_unquoted_include_glob "$bare_command" && invokes_a_search "$command_text" && include=1
  [ -n "$include" ] || has_unquoted_equals_word "$bare_command" || return 0
  quoter_rc=""
  if [ -z "$wrappers" ]; then
    rewritten=$(printf '%s' "$command_text" | "$QUOTE_WORDS" 2>/dev/null); quoter_rc=$?
    [ "$quoter_rc" = "0" ] && { [ -n "$rewritten" ] && allow_rewritten "$rewritten"; return 0; }
  fi
  { [ "$quoter_rc" = "$UNSAFE_EQUALS" ] || { [ "$quoter_rc" != "$UNSAFE_INCLUDE" ] && [ -z "$include" ]; }; } && block_equals_word
  block "a command on this line will not run." \
    "Under zsh an unquoted --include pattern is read as a file glob. It matches no file, zsh aborts that command with 'no matches found', and the rest of the line goes on as if the search had found nothing." \
    "quote the pattern, for example --include='*.md'."
}

kill_words_in() {
  for killer in $KILLERS; do
    case "$1" in *"$killer"*) return 0 ;; esac
  done
  return 1
}

invokes_a_killer() {
  for killer in $KILLERS; do invokes "$killer" "$command_text" && return 0; done
  return 1
}

check_kills() {
  invokes_a_killer || return 0
  [ -n "$working_dir" ] || { receipt_append "$GATE_NAME" unknown not-measured; return 0; }
  targets=$(printf '%s' "$command_text" | "$KILL_TARGETS" "$working_dir" 2>/dev/null); rc=$?
  [ "$rc" = "0" ] || receipt_append "$GATE_NAME" "$working_dir" not-measured
  [ "$rc" = "0" ] || [ "$rc" = "$PARTLY_MEASURED" ] || return 0
  [ -n "$targets" ] || return 0
  shown=$(printf '%s\n' "$targets" | head -n "$KILL_LINES_SHOWN")
  block "this command would stop processes that run in another folder." \
    "Its pattern matches $(printf '%s\n' "$targets" | wc -l | tr -d ' ') processes whose working folder is outside $working_dir, the folder this session works in:
$shown" \
    "stop only what you started, by the PID you saved with \$!, or narrow the pattern to a path inside your own folder."
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
  kill_words=""; kill_words_in "$command_text" && kill_words=1
  has_unquoted_include_glob "$command_text" || has_unquoted_equals_word "$command_text" || [ -n "$wrappers" ] || [ -n "$kill_words" ] || exit 0
  [ -x "$INVOKES" ] || not_measured "command-invokes.sh is missing"
  bare_command=$(printf '%s' "$command_text" | "$STRIP_QUOTES" 2>/dev/null) || not_measured "strip-quotes.sh could not read the command"
  if escape_declared "$ESCAPE" "$bare_command"; then receipt_append "$GATE_NAME" "$working_dir" escaped; exit 0; fi
  [ -n "$kill_words" ] && check_kills
  check_quoting
  check_wrappers "$wrappers"
  exit 0
}

if [ "${1:-}" = "--selftest" ]; then
  . "$HOOKS_DIR/shell-traps-tests.sh"
  selftest
fi
run_gate
