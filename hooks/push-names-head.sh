#!/bin/sh
# Prisma Harness. Reads a push command token by token, to tell whether it sends a branch, whether it can be proven to send the branch HEAD is on, and whether the command runs a git command that can change what is committed. Documented in README.md, section "What is inside".

GIT_FLAGS_BEFORE_THE_SUBCOMMAND="--no-pager --paginate -p --no-replace-objects --literal-pathspecs --no-optional-locks --no-lazy-fetch"
GIT_FLAGS_THAT_TAKE_THE_NEXT_TOKEN="-c"
PUSH_FLAGS_THAT_TAKE_NO_VALUE="-u --set-upstream -f --force --force-with-lease -n --dry-run -q --quiet -v --verbose --progress --no-verify --verify --atomic --follow-tags --porcelain --thin --no-thin --prune --ipv4 --ipv6 -4 -6"
PUSH_FLAG_FOR_ALL_TAGS="--tags"
PUSH_FLAG_FOR_DELETE="--delete"
TAG_REFS="refs/tags/"
BRANCH_REFS="refs/heads/"
HEAD_REF="HEAD"
PUSH_SUBCOMMAND="push"
GIT_SUBCOMMANDS_THAT_CHANGE_WHAT_IS_PUSHED="commit switch checkout reset rebase merge pull cherry-pick revert am update-ref symbolic-ref commit-tree"

is_one_of() {
  needle="$1"
  shift
  for candidate in "$@"; do [ "$needle" = "$candidate" ] && return 0; done
  return 1
}

is_tag_refspec() {
  destination=${1#+}
  destination=${destination#*:}
  case "$destination" in "$TAG_REFS"*) return 0 ;; esac
  return 1
}

split_git_segment() {
  set -f
  set -- $1
  set +f
  git_subcommand=""
  git_arguments=""
  [ "$#" -gt 0 ] || return 1
  shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -*)
        if is_one_of "$1" $GIT_FLAGS_THAT_TAKE_THE_NEXT_TOKEN; then
          [ "$#" -gt 1 ] || return 1
          shift 2
          continue
        fi
        is_one_of "$1" $GIT_FLAGS_BEFORE_THE_SUBCOMMAND || return 1
        shift
        ;;
      *)
        git_subcommand="$1"
        shift
        git_arguments="$*"
        return 0
        ;;
    esac
  done
  return 1
}

read_push_tokens() {
  split_git_segment "$1" || return 1
  [ "$git_subcommand" = "$PUSH_SUBCOMMAND" ] || return 1
  set -f
  set -- $git_arguments
  set +f
  remote_seen=0
  push_branch_refspecs=0
  push_tag_refspecs=0
  push_all_tags=0
  push_deletes=0
  refspec=""
  for token in "$@"; do
    [ "$token" = "$PUSH_FLAG_FOR_ALL_TAGS" ] && { push_all_tags=1; continue; }
    [ "$token" = "$PUSH_FLAG_FOR_DELETE" ] && { push_deletes=1; continue; }
    case "$token" in
      -*=*) continue ;;
      -*)
        is_one_of "$token" $PUSH_FLAGS_THAT_TAKE_NO_VALUE || return 1
        continue
        ;;
    esac
    if [ "$remote_seen" = "0" ]; then remote_seen=1; continue; fi
    if is_tag_refspec "$token"; then push_tag_refspecs=$((push_tag_refspecs+1)); continue; fi
    push_branch_refspecs=$((push_branch_refspecs+1))
    refspec="$token"
  done
  return 0
}

push_sends_no_branch() {
  read_push_tokens "$1" || return 1
  [ "$push_deletes" = "1" ] && return 0
  [ "$push_branch_refspecs" = "0" ] || return 1
  [ "$push_all_tags" = "1" ] || [ "$push_tag_refspecs" -gt 0 ]
}

pushes_that_send_a_branch() {
  printf '%s\n' "$1" | while IFS= read -r one_push; do
    [ -n "$one_push" ] || continue
    push_sends_no_branch "$one_push" || printf '%s\n' "$one_push"
  done
}

push_names_head() {
  head_branch="$1"
  push_command="$2"
  raw_command="$3"
  case "$raw_command" in *GIT_DIR=*|*GIT_WORK_TREE=*|*GIT_COMMON_DIR=*) return 1 ;; esac
  read_push_tokens "$push_command" || return 1
  [ "$push_deletes" = "0" ] || return 1
  [ "$push_branch_refspecs" -le 1 ] || return 1
  if [ "$push_branch_refspecs" = "0" ]; then
    [ "$push_all_tags" = "0" ] && [ "$push_tag_refspecs" = "0" ]
    return
  fi
  source_ref=${refspec%%:*}
  source_ref=${source_ref#+}
  source_ref=${source_ref#"$BRANCH_REFS"}
  [ "$source_ref" = "$HEAD_REF" ] && return 0
  [ -n "$head_branch" ] && [ "$source_ref" = "$head_branch" ] && return 0
  return 1
}

git_may_change_what_is_pushed() {
  invokes="$1"
  [ -x "$invokes" ] || return 0
  git_segments=$(printf '%s' "$2" | "$invokes" git 2>/dev/null) || return 0
  while IFS= read -r git_segment; do
    [ -n "$git_segment" ] || continue
    split_git_segment "$git_segment" || return 0
    is_one_of "$git_subcommand" $GIT_SUBCOMMANDS_THAT_CHANGE_WHAT_IS_PUSHED && return 0
  done <<SEGMENTS
$git_segments
SEGMENTS
  return 1
}

unmeasured_because_git_may_change() {
  echo "WARN: this command runs a git command that can change what is committed, so $1 cannot know what the push sends and measured nothing. Push in a command of its own to have it measured." >&2
  receipt_append "$2" "$3" not-measured
}
