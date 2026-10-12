#!/bin/sh
# Prisma Harness. Documented in README.md, section "What is inside".
if [ "${1:-}" = "--selftest" ]; then . "$(cd "$(dirname "$0")" && pwd)/selftest-env.sh"; fi

HOOKS_DIR="${PRISMA_HOOKS_DIR:-$(cd "$(dirname "$0")" 2>/dev/null && pwd)}"
SELF="$HOOKS_DIR/secret-reads.sh"
INVOKES="$HOOKS_DIR/command-invokes.sh"
SECRET_ARGS="$HOOKS_DIR/secret-args.sh"
PROGRAM_WORDS='cat|head|tail|less|more|bat|sed|awk|xxd|diff|strings|nl|grep|egrep|fgrep|rg|git|xargs|find'
INPUT_REDIRECTION='<'
GIT_PRINTERS='grep|diff|show|log'
GIT_WORD="git"
WORD_CHARACTERS='A-Za-z0-9_.-'
GATE_NAME="secret-reads-gate"
ESCAPE="PRISMA_SECRET_READS_OK=1"
SHELL_TRAPS_ESCAPE="PRISMA_SHELL_TRAPS_OK=1"
STRIP_QUOTES="$HOOKS_DIR/strip-quotes.sh"
BLOCK_VERDICT="block"
REWRITE_VERDICT="rewrite"
QUOTE_WORDS="${PRISMA_QUOTE_WORDS:-$HOOKS_DIR/quote-zsh-words.sh}"
SELFTEST_CASES=82
SECRETS_MARK=".env"
BASH_TOOL_FIELD='"tool_name"[[:space:]]*:[[:space:]]*"Bash"'
JSON_STRING_VALUE='[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*'
PRISMA_RECEIPT_SOURCED=1
. "$HOOKS_DIR/receipt.sh"
PRISMA_ESCAPE_SOURCED=1
. "$HOOKS_DIR/escape-declared.sh"

not_measured() {
  echo "WARN: the secret reads gate did not run, $1." >&2
  receipt_append "$GATE_NAME" "$working_dir" not-measured
  exit 0
}

block() {
  {
    printf 'SECRET FILE: this command would print the lines of a secrets file.\n\n%s\n\n' "$1"
    printf 'What a command prints stays in the transcript and travels in the context of the model.\n\n'
    printf 'Fix: to see only names, use grep -l PATTERN FILE for the files that match, or cut -d= -f1 FILE for the variable names.\n'
  } >&2
  receipt_append "$GATE_NAME" "$working_dir" blocked
  exit 2
}

named_programs() {
  words=$(printf '%s' "$command_text" | tr -c "$WORD_CHARACTERS" '\n' | sort -u)
  printf '%s\n' "$words" | grep -qxE "$GIT_PRINTERS" || words=$(printf '%s\n' "$words" | grep -vx "$GIT_WORD")
  printf '%s\n' "$words" | grep -xE "$PROGRAM_WORDS" | tr '\n' ' '
}

reads_input_from_a_file() {
  case "$command_text" in *"$INPUT_REDIRECTION"*) return 0 ;; esac
  return 1
}

collect_invocations() {
  invocations=""
  for program in $1; do
    found=$(printf '%s' "$command_text" | "$INVOKES" "$program" 2>/dev/null) || not_measured "the command parser could not read the command"
    [ -n "$found" ] && invocations="$invocations$found
"
  done
}

json_field_guess() {
  printf '%s' "$payload" | sed -nE "s/.*\"$1\"$JSON_STRING_VALUE/\\1/p"
}

guess_without_jq() {
  printf '%s' "$payload" | grep -qE "$BASH_TOOL_FIELD" || exit 0
  guessed=$(json_field_guess command)
  case "${guessed:-$payload}" in *"$SECRETS_MARK"*) ;; *) exit 0 ;; esac
  working_dir=$(json_field_guess cwd)
  working_dir="${working_dir:-unknown}"
  not_measured "jq is missing"
}

run_gate_hook() {
  payload=$(cat)
  command -v jq >/dev/null 2>&1 || guess_without_jq
  [ "$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)" = "Bash" ] || exit 0
  command_text=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)
  working_dir=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)
  programs=$(named_programs)
  [ -n "$programs" ] || reads_input_from_a_file || exit 0
  bare_command=$(printf '%s' "$command_text" | "$STRIP_QUOTES" 2>/dev/null) || not_measured "strip-quotes.sh could not read the command"
  if escape_declared "$ESCAPE" "$bare_command"; then receipt_append "$GATE_NAME" "$working_dir" escaped; exit 0; fi
  collect_invocations "$programs"
  [ -n "$invocations" ] || reads_input_from_a_file || exit 0
  verdicts=$(printf '%s' "$invocations" | SECRET_COMMAND="$command_text" "$SECRET_ARGS" --classify 2>/dev/null) || not_measured "secret-args.sh could not classify the command"
  blocked=$(printf '%s\n' "$verdicts" | sed -n "s/^$BLOCK_VERDICT	//p")
  [ -n "$blocked" ] && block "$blocked"
  rewrites=$(printf '%s\n' "$verdicts" | grep -c "^$REWRITE_VERDICT	")
  [ "$rewrites" = "0" ] && exit 0
  rewrite_searches "$rewrites"
}

zsh_would_quote() {
  case "${SHELL:-}" in */zsh|zsh) ;; *) return 1 ;; esac
  ! escape_declared "$SHELL_TRAPS_ESCAPE" "$bare_command"
}

rewrite_searches() {
  result=$(printf '%s' "$command_text" | "$SECRET_ARGS" --rewrite 2>/dev/null) || not_measured "it could not place the exclusion inside this command"
  placed=$(printf '%s' "$result" | head -n 1)
  [ "$placed" = "$1" ] || not_measured "the two parsers found $1 and $placed searches to rewrite"
  rewritten=$(printf '%s' "$result" | sed '1d')
  zsh_would_quote && quoted=$(printf '%s' "$rewritten" | "$QUOTE_WORDS" 2>/dev/null) && [ -n "$quoted" ] && rewritten="$quoted"
  allow_rewritten "$rewritten"
}

allow_rewritten() {
  receipt_append "$GATE_NAME" "$working_dir" rewritten
  reason="PRISMA secret reads kept files named .env out of this search, so their lines never reach the console, and a match inside one of them will not show. To learn which secrets files match, use grep -l. The command that runs is: $1"
  printf '%s' "$payload" | jq --arg command "$1" --arg reason "$reason" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow", permissionDecisionReason: $reason, additionalContext: $reason, updatedInput: (.tool_input + {command: $command})}}'
  exit 0
}

if [ "${1:-}" = "--selftest" ]; then
  . "$HOOKS_DIR/secret-reads-tests.sh"
  selftest
fi
run_gate_hook
