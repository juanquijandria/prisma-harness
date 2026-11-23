#!/bin/sh
# Prisma Harness. Documented in README.md, section "What is inside".
if [ "${1:-}" = "--selftest" ]; then . "$(cd "$(dirname "$0")" && pwd)/selftest-env.sh"; fi

HOOKS_DIR="${PRISMA_HOOKS_DIR:-$(cd "$(dirname "$0")" 2>/dev/null && pwd)}"
JQ="${PRISMA_JQ-$(command -v jq)}"
INVOKES="$HOOKS_DIR/command-invokes.sh"
GATE_NAME="destructive-git-gate"
ESCAPE="PRISMA_DESTRUCTIVE_OK=1"
GIT_LOOKING_COMMAND='(^|[^[:alnum:]_-])git([^[:alnum:]_-]|$)'
TIMEOUT_WRAPPER='(^|[;&|({[:space:]])timeout[[:space:]]+(-[^[:space:]]+[[:space:]]+([0-9.]+[smhd]?[[:space:]]+)?)*[0-9.]+[smhd]?[[:space:]]+'
PARSER_FAILED=3
PARSER_WARNING="the command parser could not read the command"
FORCE_FLAG="--force"
FLAGS_GIT_TAKES_CUT_SHORT="--force-with-lease:--force-w --force-if-includes:--force-i --mirror:--m"
HARD_CUT_SHORT="--hard:--h"
DELETE_CUT_SHORT="--delete:--d"
BRANCH_FORCE_CUT_SHORT="--force:--forc"
FORCE_CREATE_CUT_SHORT="--force-create:--force-c"
GIT_SUBCOMMANDS="push reset branch checkout switch"
NAMES_A_READ_SUBCOMMAND='(^|[^[:alnum:]_-])(push|reset|branch|checkout|switch)([^[:alnum:]_-]|$)'
FORCE_CREATE_OF_CHECKOUT="-B"
FORCE_CREATE_OF_SWITCH="-C"
SHORT_FORCE_CLUSTER='^-[A-Za-z]*f[A-Za-z]*$'
FORCED_REFSPEC='^[+]'
FOLDER_FLAG="-C"
FORCED_DELETE_CLUSTER='^-[A-Za-z]*D[A-Za-z]*$'
SHORT_CLUSTER='^-[A-Za-z]+$'
LEADING_FOLDER_CHANGE='^[[:space:]]*cd[[:space:]]'
HOOK_BLOCKS=2
PYTHON="${PRISMA_PYTHON-$(command -v python3 || command -v python)}"
SHELL_TEXT="$HOOKS_DIR/shell-text.sh"
WITHOUT_HEREDOC_BODIES='import sys
LINE_CONTINUATION = chr(92) + chr(10)
sys.stdout.write(without_comments(sys.stdin.read(), True).replace(LINE_CONTINUATION, " "))'
TREE_FLAGS="--git-dir --work-tree"
TREE_NAMED_ELSEWHERE='(^|[^[:alnum:]_])(pushd|popd)([^[:alnum:]_]|$)|GIT_DIR=|GIT_WORK_TREE='
COMMAND_INSIDE_A_COMMAND='(^|[;&|({[:space:]])((sh|bash|zsh|dash|ksh)[[:space:]]+(-[A-Za-z]+[[:space:]]+)*-[A-Za-z]*c([[:space:]]|$)|eval[[:space:]]|xargs[[:space:]]|env[[:space:]]+([^;&|]*[[:space:]])?-C[[:space:]])|`'
DESTRUCTIVE_TEXT='git([[:space:]]+[^;&|]*)?[[:space:]](push[[:space:]]([^;&|]*[[:space:]])?(--force|--mirror|-[A-Za-z]*f[A-Za-z]*|[+][^[:space:]])|reset[[:space:]]([^;&|]*[[:space:]])?--hard|branch[[:space:]]([^;&|]*[[:space:]])?(-[A-Za-z]*D|--delete[[:space:]]([^;&|]*[[:space:]])?--force|-d[[:space:]]+-f))'
INSIDE_FINDING="- a command handed to another command as text, which this gate cannot read word by word"
SELFTEST_CASES=82
PRISMA_RECEIPT_SOURCED=1
. "$HOOKS_DIR/receipt.sh"
PRISMA_ESCAPE_SOURCED=1
. "$HOOKS_DIR/escape-declared.sh"

not_measured() {
  echo "WARN: the destructive git gate did not measure, $1." >&2
  printf '%s' "$command_text" | grep -qE "$GIT_LOOKING_COMMAND" && receipt_append "$GATE_NAME" "$working_dir" not-measured
  exit 0
}

is_one_of() {
  needle="$1"; shift
  for candidate in "$@"; do [ "$needle" = "$candidate" ] && return 0; done
  return 1
}

matching() {
  printf '%s' "$scanned_text" | grep -qE "(^|[^[:alnum:]_-])$1([^[:alnum:]_-]|\$)" || return 0
  found=$(printf '%s' "$scanned_text" | sed -E "s/$TIMEOUT_WRAPPER/\\1/g" | "$INVOKES" git "$1" 2>/dev/null); rc=$?
  [ "$rc" = "$PARSER_FAILED" ] && return 1
  printf '%s\n' "$found" | while IFS= read -r segment; do
    [ -n "$segment" ] && "$2" "$segment" && printf -- '- %s\n' "$segment"
  done
  return 0
}

cut_short() {
  written=${2%%=*}; whole=${1%%:*}; least=${1##*:}
  case "$written" in "$least"*) ;; *) return 1 ;; esac
  case "$whole" in "$written"*) return 0 ;; esac
  return 1
}

is_forced_push() {
  set -f; set -- $1; set +f
  for token in "$@"; do
    [ "${token%%=*}" = "$FORCE_FLAG" ] && return 0
    for flag in $FLAGS_GIT_TAKES_CUT_SHORT; do cut_short "$flag" "$token" && return 0; done
    printf '%s' "$token" | grep -qE "$SHORT_FORCE_CLUSTER|$FORCED_REFSPEC" && return 0
  done
  return 1
}

is_hard_reset() {
  set -f; set -- $1; set +f
  for token in "$@"; do cut_short "$HARD_CUT_SHORT" "$token" && return 0; done
  return 1
}

is_forced_deletion() {
  set -f; set -- $1; set +f
  deletes=0; forces=0
  for token in "$@"; do
    printf '%s' "$token" | grep -qE "$FORCED_DELETE_CLUSTER" && return 0
    cut_short "$DELETE_CUT_SHORT" "$token" && deletes=1
    cut_short "$BRANCH_FORCE_CUT_SHORT" "$token" && forces=1
    if printf '%s' "$token" | grep -qE "$SHORT_CLUSTER"; then
      case "$token" in *d*) deletes=1 ;; esac
      case "$token" in *f*) forces=1 ;; esac
    fi
  done
  [ "$deletes" = "1" ] && [ "$forces" = "1" ]
}

before_the_subcommand() {
  set -f; set -- $1; set +f
  for token in "$@"; do
    is_one_of "$token" $GIT_SUBCOMMANDS && return 0
    printf '%s ' "$token"
  done
}

after_the_subcommand() {
  set -f; set -- $1; set +f
  while [ "$#" -gt 0 ]; do
    token="$1"; shift
    is_one_of "$token" $GIT_SUBCOMMANDS && { printf '%s' "$*"; return 0; }
  done
}

branch_moved_by_force() {
  kind="$1"
  set -f; set -- $(after_the_subcommand "$2"); set +f
  moved=""; forces=0; deletes=0
  while [ "$#" -gt 0 ]; do
    token="$1"; shift
    case "$kind" in
      checkout) [ "$token" = "$FORCE_CREATE_OF_CHECKOUT" ] && { printf '%s' "${1:-}"; return 0; } ;;
      switch) { [ "$token" = "$FORCE_CREATE_OF_SWITCH" ] || cut_short "$FORCE_CREATE_CUT_SHORT" "$token"; } && { printf '%s' "${1:-}"; return 0; } ;;
      branch)
        cut_short "$BRANCH_FORCE_CUT_SHORT" "$token" && forces=1
        cut_short "$DELETE_CUT_SHORT" "$token" && deletes=1
        if printf '%s' "$token" | grep -qE "$SHORT_CLUSTER"; then
          case "$token" in *f*) forces=1 ;; esac
          case "$token" in *[dD]*) deletes=1 ;; esac
        fi
        case "$token" in -*) ;; *) [ -n "$moved" ] || moved="$token" ;; esac ;;
    esac
  done
  [ "$forces" = "1" ] && [ "$deletes" = "0" ] && printf '%s' "$moved"
}

moves_a_branch_that_exists() {
  moved=$(branch_moved_by_force "$1" "$2")
  [ -n "$moved" ] || return 1
  folder=$(folder_of "$2") || return 0
  [ -n "$folder" ] || return 0
  git -C "$folder" rev-parse --git-dir >/dev/null 2>&1 || return 0
  git -C "$folder" show-ref --verify --quiet "refs/heads/$moved"
}

branch_is_moved() { moves_a_branch_that_exists branch "$1"; }
checkout_is_forced() { moves_a_branch_that_exists checkout "$1"; }
switch_is_forced() { moves_a_branch_that_exists switch "$1"; }

folder_of() {
  printf '%s' "$scanned_text" | grep -qE "$TREE_NAMED_ELSEWHERE" && return 1
  set -f; set -- $(before_the_subcommand "$1"); set +f
  named=""; folders_named=0
  for token in "$@"; do
    [ "$token" = "$FOLDER_FLAG" ] && folders_named=$((folders_named+1))
    for flag in $TREE_FLAGS; do case "$token" in "$flag"|"$flag"=*) return 1 ;; esac; done
  done
  [ "$folders_named" -gt 1 ] && return 1
  while [ "$#" -gt 1 ]; do
    [ "$1" = "$FOLDER_FLAG" ] && { named="$2"; break; }
    shift
  done
  if [ -z "$named" ]; then
    changes=$(printf '%s' "$scanned_text" | "$INVOKES" cd 2>/dev/null)
    [ "$(printf '%s\n' "$changes" | grep -c .)" -gt 1 ] && return 1
    [ -z "$changes" ] || printf '%s' "$command_text" | grep -qE "$LEADING_FOLDER_CHANGE" || return 1
    named=${changes#cd }
    [ -n "$changes" ] || named="$working_dir"
  fi
  case "$named" in
    "~") named="$HOME" ;;
    "~/"*) named="$HOME/${named#\~/}" ;;
    /*|[A-Za-z]:[/\\]*) ;;
    *) named="$working_dir/$named" ;;
  esac
  [ -d "$named" ] && printf '%s' "$named"
}

may_lose_uncommitted_work() {
  folder=$(folder_of "$1") || return 0
  [ -n "$folder" ] || return 0
  changed=$(git -C "$folder" status --porcelain --untracked-files=no 2>/dev/null) || return 0
  [ -n "$changed" ]
}

ask_the_person() {
  receipt_append "$GATE_NAME" "$working_dir" asked
  when_a_reset_asks=""
  [ -n "$2" ] && when_a_reset_asks=" A hard reset asks when its tree has uncommitted changes or cannot be measured, and naming the folder literally with git $FOLDER_FLAG lets it be measured."
  "$JQ" -n --arg reason "PRISMA destructive git gate: Enter accepts this command, so read it first.
It rewrites a remote, moves a branch that exists, or discards work that no commit holds, and that is confirmed by the person every time.
$1
$ESCAPE does not skip this question.$when_a_reset_asks" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $reason}}'
  exit 0
}

run_gate() {
  payload=$(cat)
  [ -n "$payload" ] || exit 0
  [ -n "$JQ" ] || { command_text="$payload"; not_measured "jq is missing"; }
  [ "$(printf '%s' "$payload" | "$JQ" -r '.tool_name // empty' 2>/dev/null)" = "Bash" ] || exit 0
  command_text=$(printf '%s' "$payload" | "$JQ" -r '.tool_input.command // empty' 2>/dev/null)
  working_dir=$(printf '%s' "$payload" | "$JQ" -r '.cwd // empty' 2>/dev/null)
  printf '%s' "$command_text" | grep -qE "$GIT_LOOKING_COMMAND" || exit 0
  printf '%s' "$command_text" | grep -qE "$NAMES_A_READ_SUBCOMMAND" || exit 0
  [ -x "$INVOKES" ] || [ -r "$INVOKES" ] || not_measured "command-invokes.sh is missing"
  [ -n "$PYTHON" ] && [ -r "$SHELL_TEXT" ] || not_measured "python or shell-text.sh is missing"
  . "$SHELL_TEXT"
  scanned_text=$(printf '%s' "$command_text" | "$PYTHON" -c "$SHELL_TEXT_CODE
$WITHOUT_HEREDOC_BODIES" 2>/dev/null) || not_measured "$PARSER_WARNING"
  forced_pushes=$(matching push is_forced_push) || not_measured "$PARSER_WARNING"
  hard_resets=$(matching reset is_hard_reset) || not_measured "$PARSER_WARNING"
  to_block=$(matching branch is_forced_deletion) || not_measured "$PARSER_WARNING"
  for reader in branch:branch_is_moved checkout:checkout_is_forced switch:switch_is_forced; do
    moved_branches=$(matching "${reader%%:*}" "${reader##*:}") || not_measured "$PARSER_WARNING"
    [ -n "$moved_branches" ] && forced_pushes=$(printf '%s\n%s' "$forced_pushes" "$moved_branches")
  done
  to_ask=$(printf '%s\n' "$forced_pushes" | grep .); resets_to_ask=""
  if printf '%s' "$scanned_text" | grep -qE "$COMMAND_INSIDE_A_COMMAND" && printf '%s' "$scanned_text" | grep -qE "$DESTRUCTIVE_TEXT"; then
    to_ask=$(printf '%s\n%s' "$to_ask" "$INSIDE_FINDING")
  fi
  while IFS= read -r finding; do
    [ -n "$finding" ] || continue
    if may_lose_uncommitted_work "${finding#- }"; then to_ask=$(printf '%s\n%s' "$to_ask" "$finding"); resets_to_ask=yes; else to_block=$(printf '%s\n%s' "$to_block" "$finding"); fi
  done <<RESETS
$hard_resets
RESETS
  [ -n "$to_ask" ] && ask_the_person "$(printf '%s\n%s' "$to_ask" "$to_block" | grep .)" "$resets_to_ask"
  [ -n "$to_block" ] || exit 0
  if escape_declared "$ESCAPE" "$command_text"; then
    receipt_append "$GATE_NAME" "$working_dir" escaped
    exit 0
  fi
  receipt_append "$GATE_NAME" "$working_dir" blocked
  printf 'PRISMA destructive git gate: this command deletes a branch whatever its state, or moves one with a hard reset.\n%s\nIf that is what the person asked for, declare %s at the start of the command.\n' "$(printf '%s\n' "$to_block" | grep .)" "$ESCAPE" >&2
  exit "$HOOK_BLOCKS"
}

if [ "${1:-}" = "--selftest" ]; then
  GATE="$HOOKS_DIR/destructive-git.sh"
  . "$HOOKS_DIR/destructive-git-tests.sh"
  selftest; exit $?
fi
run_gate
