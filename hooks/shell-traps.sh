#!/bin/sh
# Prisma Harness. Documented in README.md, section "What is inside".
if [ "${1:-}" = "--selftest" ]; then . "$(cd "$(dirname "$0")" && pwd)/selftest-env.sh"; fi

HOOKS_DIR="${PRISMA_HOOKS_DIR:-$(cd "$(dirname "$0")" 2>/dev/null && pwd)}"
INVOKES="$HOOKS_DIR/command-invokes.sh"
STRIP_QUOTES="$HOOKS_DIR/strip-quotes.sh"
ESCAPE="PRISMA_SHELL_TRAPS_OK=1"
GATE_NAME="shell-traps"
UNQUOTED_INCLUDE_GLOB='(^|[[:space:]])--include=[^'"'"'"[:space:]]*[*?[]'
SEARCH_PROGRAMS="grep egrep fgrep ugrep"
REQUIRED_WRAPPERS="${PRISMA_REQUIRED_WRAPPERS:-timeout}"
PARSER_FAILED=3
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
  case "${SHELL:-}" in */zsh) printf '%s' "$1" | grep -qE "$UNQUOTED_INCLUDE_GLOB" ;; *) return 1 ;; esac
}

missing_wrappers_named() {
  for wrapper in $REQUIRED_WRAPPERS; do
    case "$1" in *"$wrapper"*) command -v "$wrapper" >/dev/null 2>&1 || printf '%s ' "$wrapper" ;; esac
  done
}

check_include_glob() {
  has_unquoted_include_glob "$bare_command" && invokes_a_search "$command_text" && block "this search will not run." \
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

selftest() {
  SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
  fake_bin=$(mktemp -d)
  printf '#!/bin/sh\nexit 0\n' > "$fake_bin/timeout"; chmod +x "$fake_bin/timeout"
  ok=1; cases=0
  run() {
    printf '{"tool_name":"Bash","cwd":"/tmp","tool_input":{"command":%s}}' "$(printf '%s' "$1" | jq -Rs .)" \
      | SHELL="$2" PATH="${3:-$PATH}" PRISMA_REQUIRED_WRAPPERS="${4:-timeout}" sh "$SELF" >/dev/null 2>&1
    echo "$?"
  }
  expect() {
    cases=$((cases+1))
    if [ "$2" = "$3" ]; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s, expected exit %s and got %s\n' "$1" "$3" "$2"; ok=0; fi
  }
  expect "1 an unquoted include glob under zsh blocks" "$(run 'grep -rn --include=*.md foo .' /bin/zsh)" 2
  expect "2 the same pattern in single quotes passes" "$(run "grep -rn --include='*.md' foo ." /bin/zsh)" 0
  expect "3 the whole flag in double quotes passes" "$(run 'grep -rn "--include=*.md" foo .' /bin/zsh)" 0
  expect "4 a search only mentioned inside quotes passes" "$(run 'echo "grep -rn --include=*.md foo ."' /bin/zsh)" 0
  expect "5 a real search next to a quoted mention of the glob passes" "$(run 'grep -rn foo . && echo "next time use --include=*.md"' /bin/zsh)" 0
  expect "6 an escaped quote inside double quotes does not hide the glob" "$(run 'grep -rn "a\|href=\"#" src/ --include=*.tsx | grep -v "test"' /bin/zsh)" 2
  expect "7 under bash the unquoted glob reaches grep and passes" "$(run 'grep -rn --include=*.md foo .' /bin/bash)" 0
  expect "8 a brace glob after a cd and before a pipe blocks" "$(run 'cd notes && grep -rln --include=*.{md,txt} foo . | wc -l' /usr/bin/zsh)" 2
  expect "9 a brace list with no glob character expands and passes" "$(run 'grep -rn --include={a.md,b.md} foo .' /bin/zsh)" 0
  expect "10 a search written only in a trailing comment passes" "$(run 'ls -la # then grep -rn --include=*.md foo .' /bin/zsh)" 0
  expect "11 the escape lets the unquoted glob through" "$(run "$ESCAPE grep -rn --include=*.md foo ." /bin/zsh)" 0
  expect "12 a wrapper that is not installed blocks" "$(run 'no-such-wrapper-alpha 10 curl -s https://example.com' /bin/zsh "$PATH" no-such-wrapper-alpha)" 2
  expect "13 an installed timeout passes" "$(run 'timeout 10 curl -s https://example.com' /bin/zsh "$fake_bin:$PATH")" 0
  expect "14 a missing wrapper only mentioned passes" "$(run 'echo no-such-wrapper-alpha is missing' /bin/zsh "$PATH" no-such-wrapper-alpha)" 0
  expect "15 input that is not JSON passes" "$(printf 'this is not json' | sh "$SELF" >/dev/null 2>&1; echo "$?")" 0
  expect "16 a tool other than Bash passes" "$(printf '{"tool_name":"Write","tool_input":{"command":"grep --include=*.md x"}}' | SHELL=/bin/zsh sh "$SELF" >/dev/null 2>&1; echo "$?")" 0
  rm -rf "$fake_bin"
  [ "$ok" = "1" ] && printf 'SELFTEST OK: %s/%s\n' "$cases" "$cases" && exit 0
  printf 'SELFTEST FAILED\n'; exit 1
}

[ "${1:-}" = "--selftest" ] && selftest
run_gate
