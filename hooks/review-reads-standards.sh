#!/bin/sh
# Prisma Harness. Documented in README.md, section "What is inside".
if [ "${1:-}" = "--selftest" ]; then . "$(cd "$(dirname "$0")" && pwd)/selftest-env.sh"; fi

HOOKS_DIR="${PRISMA_HOOKS_DIR:-$(cd "$(dirname "$0")" 2>/dev/null && pwd)}"
JQ="${PRISMA_JQ-$(command -v jq)}"
GATE_NAME="review-reads-gate"
REVIEW_SKILL="prisma-fidelity-review"
REVIEW_SKILL_INVOKED="$REVIEW_SKILL([^/]|\$)"
TRANSCRIPT_FIELD='s/.*"agent_transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
HOOK_BLOCKS=2
STANDARDS_LABEL='standards|est(a|á)ndares'
TOKEN_SEPARATORS=' ,;()`"'"'"
REPOSITORY_SOURCE_NAMES="CONTRIBUTING.md CODING_STANDARDS.md STYLE.md STYLEGUIDE.md CONVENTIONS.md"
PAGE_EXTENSIONS="md mdx txt rst adoc"
INSTRUCTIONS_NAMES="CLAUDE.md CLAUDE.local.md"
PERSON_INSTRUCTIONS_FOLDER=".claude"
AGENT_TYPES_WITHOUT_INSTRUCTIONS="Explore Plan"
CONTENT_PRINTERS='cat|sed|head|tail|nl|awk|less|more|bat|grep|rg'
SELFTEST_CASES=40
PRISMA_RECEIPT_SOURCED=1
. "$HOOKS_DIR/receipt.sh"

FIRST_PROMPT_JQ='first(inputs | select(.type == "user") | .message.content
  | if type == "string" then . else (map(select(.type == "text") | .text) | join("\n")) end)'
READ_PATHS_JQ='[inputs] as $lines
  | [$lines[] | select(.type == "user") | .message.content | arrays | .[] | select(.type == "tool_result" and .is_error == true) | .tool_use_id] as $errored
  | $lines[] | select(.type == "assistant") | .message.content | arrays | .[]
  | select(.type == "tool_use" and .name == "Read") | select(.id as $id | $errored | index($id) | not)
  | .input.file_path // empty'
SHELL_SEGMENTS_JQ='inputs | select(.type == "assistant") | .message.content | arrays | .[]
  | select(.type == "tool_use" and .name == "Bash") | .input.command // empty | splits("&&|[;\n]")'

not_measured() {
  echo "WARN: the review reads gate did not measure, $1." >&2
  receipt_append "$GATE_NAME" "$working_dir" not-measured
  exit 0
}

absolute_path() {
  case "$1" in
    "~/"*) printf '%s' "$HOME/${1#\~/}" ;;
    /*) printf '%s' "$1" ;;
    *) printf '%s' "$working_dir/$1" ;;
  esac
}

path_tokens() {
  tr "$TOKEN_SEPARATORS" '\n' | sed 's/[.:]*$//' | while IFS= read -r token; do
    case "$token" in */*|*.*) absolute_path "$token"; printf '\n' ;; esac
  done
}

is_a_page() {
  for extension in $PAGE_EXTENSIONS; do case "$1" in *."$extension") return 0 ;; esac; done
  return 1
}

named_sources() {
  printf '%s' "$prompt" | "$JQ" -Rrs --arg label "$STANDARDS_LABEL" 'split("\n")[] | select(test($label; "i")) | .[(match($label; "i").offset):]' 2>/dev/null \
    | path_tokens | while IFS= read -r candidate; do
      is_a_page "$candidate" && [ -f "$candidate" ] && printf '%s\n' "$candidate"
    done
}

named_folders() {
  printf '%s\n' "$working_dir"
  printf '%s\n' "$prompt" | path_tokens | while IFS= read -r candidate; do
    if [ -d "$candidate" ]; then printf '%s\n' "$candidate"; elif [ -f "$candidate" ]; then dirname "$candidate"; fi
  done
}

repository_sources() {
  named_folders | while IFS= read -r folder; do
    [ -d "$folder" ] && git -C "$folder" rev-parse --show-toplevel 2>/dev/null
  done | sort -u | while IFS= read -r top; do
    for name in $REPOSITORY_SOURCE_NAMES; do find "$top" -maxdepth 1 -type f -iname "$name" 2>/dev/null; done
  done
}

printed_in_the_shell() {
  file_name=$(basename "$1")
  printf '%s\n' "$shell_segments" | grep -F -- "$file_name" | while IFS= read -r segment; do
    printf '%s' "${segment%%"$file_name"*}" | grep -qE "(^|[^[:alnum:]_-])($CONTENT_PRINTERS)([^[:alnum:]_-]|\$)" && { printf 'yes'; break; }
  done | grep -q yes
}

already_in_context() {
  for bare in $AGENT_TYPES_WITHOUT_INSTRUCTIONS; do [ "$agent_type" = "$bare" ] && return 1; done
  is_instructions_file=no
  for name in $INSTRUCTIONS_NAMES; do [ "$(basename "$1")" = "$name" ] && is_instructions_file=yes; done
  [ "$is_instructions_file" = "yes" ] || return 1
  folder=$(dirname "$1")
  [ "$folder" -ef "$HOME/$PERSON_INSTRUCTIONS_FOLDER" ] && return 0
  above="$working_dir"
  while [ -n "$above" ] && [ -d "$above" ]; do
    [ "$folder" -ef "$above" ] && return 0
    [ "$above" = "/" ] && break
    above=$(dirname "$above")
  done
  return 1
}

opened() {
  already_in_context "$1" && { printf 'yes'; return; }
  printed_in_the_shell "$1" && { printf 'yes'; return; }
  printf '%s\n' "$read_paths" | while IFS= read -r read_path; do
    [ -n "$read_path" ] && [ "$(absolute_path "$read_path")" -ef "$1" ] && { printf 'yes'; break; }
  done
}

without_jq() {
  guessed=$(printf '%s' "$payload" | sed -n "$TRANSCRIPT_FIELD")
  [ -f "$guessed" ] && head -1 "$guessed" | grep -qE "$REVIEW_SKILL_INVOKED" || exit 0
  not_measured "jq is missing"
}

run_gate() {
  payload=$(cat)
  [ -n "$JQ" ] || without_jq
  [ -n "$payload" ] || not_measured "the stop event came empty"
  working_dir=$(printf '%s' "$payload" | "$JQ" -r '.cwd // empty' 2>/dev/null)
  agent_type=$(printf '%s' "$payload" | "$JQ" -r '.agent_type // empty' 2>/dev/null)
  agent_transcript=$(printf '%s' "$payload" | "$JQ" -r '.agent_transcript_path // empty' 2>/dev/null)
  [ -f "$agent_transcript" ] || not_measured "the transcript of the subagent is not there"
  prompt=$("$JQ" -rn "$FIRST_PROMPT_JQ" "$agent_transcript" 2>/dev/null) || not_measured "jq could not read the transcript of the subagent"
  printf '%s' "$prompt" | grep -qE "$REVIEW_SKILL_INVOKED" || exit 0
  read_paths=$("$JQ" -rn "$READ_PATHS_JQ" "$agent_transcript" 2>/dev/null) || not_measured "jq could not list what the reviewer read"
  shell_segments=$("$JQ" -rn "$SHELL_SEGMENTS_JQ" "$agent_transcript" 2>/dev/null) || not_measured "jq could not list what the reviewer ran"
  missing=$({ named_sources; repository_sources; } | sort -u | while IFS= read -r source; do
    [ -n "$(opened "$source")" ] || printf -- '- %s\n' "$source"
  done)
  [ -n "$missing" ] || exit 0
  if [ "$(printf '%s' "$payload" | "$JQ" -r '.stop_hook_active // false' 2>/dev/null)" = "true" ]; then
    receipt_append "$GATE_NAME" "$working_dir" warned
    exit 0
  fi
  receipt_append "$GATE_NAME" "$working_dir" blocked
  printf 'PRISMA review reads gate: this review has not opened every source that documents how code is written.\n%s\nOpen each one, redo the standards axis against it, and list the sources you read at the top of the Standards section.\n' "$missing" >&2
  exit "$HOOK_BLOCKS"
}

if [ "${1:-}" = "--selftest" ]; then
  GATE="$HOOKS_DIR/review-reads-standards.sh"
  . "$HOOKS_DIR/review-reads-standards-tests.sh"
  selftest; exit $?
fi
run_gate
