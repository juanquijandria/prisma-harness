#!/bin/sh
# Prisma Harness. Documented in README.md, section "What is inside".
if [ "${1:-}" = "--selftest" ]; then
  . "$(cd "$(dirname "$0")" && pwd)/selftest-env.sh"
  unset CLAUDE_CODE_DISABLE_1M_CONTEXT CLAUDE_CODE_AUTO_COMPACT_WINDOW
fi

SELF=$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")
HOOKS_JSON="$(dirname "$SELF")/hooks.json"

DATA_DIR="${CLAUDE_PLUGIN_DATA:-$HOME/.prisma-harness}"
MARKER_DIR="$DATA_DIR/session-size"
JQ="${PRISMA_JQ-$(command -v jq)}"
WARN_PERCENT=80
DEFAULT_WINDOW=1000000
WITHOUT_1M_WINDOW=200000
PER_CENT=100
TOKENS_PER_THOUSAND=1000
TAIL_LINES=200

is_count() {
  case "$1" in ''|*[!0-9]*|0*) return 1 ;; esac
  return 0
}

is_truthy() {
  case "$(printf '%s' "$1" | tr 'A-Z' 'a-z')" in 1|true|yes|on) return 0 ;; esac
  return 1
}

context_window() {
  window=$DEFAULT_WINDOW
  if is_count "${PRISMA_CONTEXT_WINDOW:-}"; then window=$PRISMA_CONTEXT_WINDOW
  elif is_truthy "${CLAUDE_CODE_DISABLE_1M_CONTEXT:-}"; then window=$WITHOUT_1M_WINDOW
  fi
  compact="${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-}"
  if is_count "$compact" && [ "$compact" -lt "$window" ]; then window=$compact; fi
  printf '%s' "$window"
}

last_context_size() {
  tail -n "$TAIL_LINES" "$1" 2>/dev/null | "$JQ" -rR 'fromjson? // empty | select(type == "object" and .type == "assistant") | .message.usage // empty
    | ((.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0))' 2>/dev/null | tail -1
}

claim_marker() {
  marker="$MARKER_DIR/$(printf '%s' "$1" | tr -c 'A-Za-z0-9-' '-')-$WARN_PERCENT"
  [ -e "$marker" ] && return 1
  mkdir -p "$MARKER_DIR" 2>/dev/null || return 1
  { : > "$marker"; } 2>/dev/null || return 1
  return 0
}

warning_json() {
  "$JQ" -n --arg thousands "$(( $1 / TOKENS_PER_THOUSAND ))" --arg share "$(( $1 * PER_CENT / $2 ))" --arg window "$(( $2 / TOKENS_PER_THOUSAND ))" \
    '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: ("This session now rereads about " + $thousands + "k tokens on every call, " + $share + "% of its " + $window + "k context window, and every message pays that again. When you finish what you are doing, tell the person in one line that running /compact is worth it now, and go on with what they asked.")}}'
}

run_hook() {
  [ "${PRISMA_SESSION_SIZE:-1}" = "0" ] && exit 0
  [ -n "$JQ" ] && [ -x "$JQ" ] || exit 0
  input=$(cat)
  transcript=$(printf '%s' "$input" | "$JQ" -r '.transcript_path // empty' 2>/dev/null)
  session=$(printf '%s' "$input" | "$JQ" -r '.session_id // empty' 2>/dev/null)
  [ -n "$transcript" ] && [ -f "$transcript" ] && [ -n "$session" ] || exit 0
  size=$(last_context_size "$transcript")
  is_count "$size" || exit 0
  window=$(context_window)
  [ "$size" -ge $(( window * WARN_PERCENT / PER_CENT )) ] || exit 0
  claim_marker "$session" || exit 0
  warning_json "$size" "$window"
  exit 0
}

FIXTURE_INPUT_TOKENS=5
FIXTURE_CREATION_TOKENS=100
FIGURE_PATTERN='about [0-9]*k'
SHARE_PATTERN='[0-9]*% of'

usage_line() {
  printf '{"type":"assistant","message":{"usage":{"input_tokens":%s,"cache_read_input_tokens":%s,"cache_creation_input_tokens":%s}}}\n' \
    "$FIXTURE_INPUT_TOKENS" "$(( $1 - FIXTURE_INPUT_TOKENS - FIXTURE_CREATION_TOKENS ))" "$FIXTURE_CREATION_TOKENS"
}

fire() {
  printf '{"session_id":"%s","transcript_path":"%s","prompt":"go on"}' "$1" "$2" | /bin/sh "$SELF" 2>&1
}

fire_says() {
  out=$(fire "$1" "$2" | grep -o "$3")
  printf '%s' "${out:-silence}"
}

check() {
  cases=$((cases+1))
  if [ "$2" = "$3" ]; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s, expected [%s] and got [%s]\n' "$1" "$3" "$2"; ok=0; fi
}

selftest_threshold() {
  usage_line 50000 > "$t/small.jsonl"
  check "a small session says nothing" "$(fire_says s1 "$t/small.jsonl" "$FIGURE_PATTERN")" "silence"
  usage_line 650000 > "$t/below.jsonl"
  check "650k on a 1M window is under 80% and says nothing" "$(fire_says s2 "$t/below.jsonl" "$FIGURE_PATTERN")" "silence"
  usage_line 820000 > "$t/big.jsonl"
  check "820k on a 1M window warns with the figure" "$(fire_says s3 "$t/big.jsonl" "$FIGURE_PATTERN")" "about 820k"
  usage_line 950000 >> "$t/big.jsonl"
  check "it warns once per session even as the session keeps growing" "$(fire_says s3 "$t/big.jsonl" "$FIGURE_PATTERN")" "silence"
  check "the warning says which share of the window it is" "$(fire_says s5 "$t/big.jsonl" "$SHARE_PATTERN")" "95% of"
  check "the warning recommends /compact" "$(fire_says s6 "$t/big.jsonl" '/compact')" "/compact"
  said=$(fire s7 "$t/big.jsonl")
  if [ -n "$said" ] && ! printf '%s' "$said" | grep -qi 'new session'; then check "the warning never proposes a new session" "never" "never"
  else check "the warning never proposes a new session" "$said" "a warning without it"; fi
  if command -v jq >/dev/null 2>&1 && fire s8 "$t/big.jsonl" | jq -e '.hookSpecificOutput.hookEventName=="UserPromptSubmit" and (.hookSpecificOutput.additionalContext | length > 0)' >/dev/null 2>&1; then
    check "the warning is valid UserPromptSubmit JSON" "valid" "valid"
  else check "the warning is valid UserPromptSubmit JSON" "$(fire s8-shown-on-failure "$t/big.jsonl")" "valid"; fi
}

selftest_window() {
  usage_line 170000 > "$t/w170.jsonl"
  check "PRISMA_CONTEXT_WINDOW=200000 makes 170k warn" "$(PRISMA_CONTEXT_WINDOW=200000 fire_says w1 "$t/w170.jsonl" "$FIGURE_PATTERN")" "about 170k"
  usage_line 820000 > "$t/w820.jsonl"
  check "a misspelled PRISMA_CONTEXT_WINDOW falls back to the 1M window" "$(PRISMA_CONTEXT_WINDOW=200k fire_says w2 "$t/w820.jsonl" '[0-9]*% of its [0-9]*k')" "82% of its 1000k"
  check "CLAUDE_CODE_DISABLE_1M_CONTEXT brings the window down to 200k" "$(CLAUDE_CODE_DISABLE_1M_CONTEXT=1 fire_says w3 "$t/w170.jsonl" "$FIGURE_PATTERN")" "about 170k"
  check "CLAUDE_CODE_DISABLE_1M_CONTEXT=0 leaves the window at 1M" "$(CLAUDE_CODE_DISABLE_1M_CONTEXT=0 fire_says w3b "$t/w170.jsonl" "$FIGURE_PATTERN")" "silence"
  usage_line 420000 > "$t/w420.jsonl"
  check "a smaller CLAUDE_CODE_AUTO_COMPACT_WINDOW rules" "$(CLAUDE_CODE_AUTO_COMPACT_WINDOW=500000 fire_says w4 "$t/w420.jsonl" "$SHARE_PATTERN")" "84% of"
  check "a larger CLAUDE_CODE_AUTO_COMPACT_WINDOW never widens the window" "$(CLAUDE_CODE_DISABLE_1M_CONTEXT=1 CLAUDE_CODE_AUTO_COMPACT_WINDOW=1000000 fire_says w5 "$t/w170.jsonl" "$FIGURE_PATTERN")" "about 170k"
}

selftest_silence() {
  check "without a transcript it says nothing" "$(fire_says q1 "$t/missing.jsonl" '.')" "silence"
  { usage_line 820000; printf '{"type":"assistant","message":{"usage":{"input_tokens":0}}}\n'; } > "$t/zero.jsonl"
  check "a last usage of 0 says nothing" "$(fire_says q2 "$t/zero.jsonl" '.')" "silence"
  check "without jq it says nothing" "$(PRISMA_JQ="" fire_says q3 "$t/big.jsonl" '.')" "silence"
  check "PRISMA_SESSION_SIZE=0 switches it off" "$(PRISMA_SESSION_SIZE=0 fire_says q4 "$t/big.jsonl" '.')" "silence"
  { printf 'not json at all\n'; usage_line 820000; } > "$t/noisy.jsonl"
  check "a line that is not JSON does not stop the reading" "$(fire_says q5 "$t/noisy.jsonl" "$FIGURE_PATTERN")" "about 820k"
  check "an input that is not JSON says nothing" "$(printf 'not json' | /bin/sh "$SELF" 2>&1 | grep -o . | head -1)" ""
  check "an empty session id says nothing" "$(fire_says "" "$t/big.jsonl" '.')" "silence"
  fire '../../escaped' "$t/big.jsonl" >/dev/null
  if [ -e "$HOME/.prisma-harness/escaped-80" ] || [ -e "$HOME/escaped-80" ]; then check "a session id cannot place its marker outside the marker folder" "outside" "inside"
  else check "a session id cannot place its marker outside the marker folder" "inside" "inside"; fi
}

selftest_unwritable() {
  locked=$(mktemp -d); chmod 500 "$locked"
  if mkdir "$locked/probe" 2>/dev/null; then
    chmod 700 "$locked"
    cases=$((cases+1))
    printf 'SKIP this filesystem does not enforce directory permissions, so an unwritable marker folder cannot be tested here\n'
    return
  fi
  said=$(CLAUDE_PLUGIN_DATA="$locked/data" fire_says u1 "$t/big.jsonl" '.')
  chmod 700 "$locked"
  check "a marker folder it cannot write to says nothing and leaks no error" "$said" "silence"
}

selftest_registered() {
  if command -v jq >/dev/null 2>&1 && jq -e '[.hooks.UserPromptSubmit[]?.hooks[]?.command] | any(test("hooks/session-size.sh"))' "$HOOKS_JSON" >/dev/null 2>&1; then
    check "hooks.json registers it on UserPromptSubmit" "registered" "registered"
  else check "hooks.json registers it on UserPromptSubmit" "missing" "registered"; fi
}

selftest() {
  ok=1; cases=0; t=$(mktemp -d)
  selftest_threshold
  selftest_window
  selftest_silence
  selftest_unwritable
  selftest_registered
  [ "$ok" -eq 1 ] && printf 'SELFTEST OK: %s/%s\n' "$cases" "$cases" && exit 0
  printf 'SELFTEST FAILED\n'; exit 1
}

[ "${1:-}" = "--selftest" ] && selftest
run_hook
