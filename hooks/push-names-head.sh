#!/bin/sh
# Prisma Harness. Decides whether a push command can be proven to send the branch HEAD is on, from the repository the gate is standing in. Documented in README.md, section "What is inside".

GIT_FLAGS_BEFORE_THE_SUBCOMMAND="--no-pager --paginate -p --no-replace-objects --literal-pathspecs --no-optional-locks --no-lazy-fetch"
GIT_FLAGS_THAT_TAKE_THE_NEXT_TOKEN="-c"
PUSH_FLAGS_THAT_TAKE_NO_VALUE="-u --set-upstream -f --force --force-with-lease -n --dry-run -q --quiet -v --verbose --progress --no-verify --verify --atomic --follow-tags --porcelain --thin --no-thin --prune --ipv4 --ipv6 -4 -6"
PUSH_FLAG_FOR_ALL_TAGS="--tags"
PUSH_FLAG_FOR_DELETE="--delete"
TAG_REFS="refs/tags/"
PUSHED_COMMIT="HEAD"

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

read_push_tokens() {
  set -f
  set -- $1
  set +f
  past_push=0
  skip_next=0
  remote_seen=0
  push_branch_refspecs=0
  push_tag_refspecs=0
  push_all_tags=0
  push_deletes=0
  refspec=""
  for token in "$@"; do
    if [ "$skip_next" = "1" ]; then skip_next=0; continue; fi
    if [ "$past_push" = "0" ]; then
      [ "$token" = "push" ] && { past_push=1; continue; }
      case "$token" in
        -*)
          is_one_of "$token" $GIT_FLAGS_THAT_TAKE_THE_NEXT_TOKEN && { skip_next=1; continue; }
          is_one_of "$token" $GIT_FLAGS_BEFORE_THE_SUBCOMMAND || return 1
          ;;
      esac
      continue
    fi
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
  [ "$past_push" = "1" ]
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
  raw_command="$3"
  case "$raw_command" in *GIT_DIR=*|*GIT_WORK_TREE=*|*GIT_COMMON_DIR=*) return 1 ;; esac
  read_push_tokens "$2" || return 1
  [ "$push_deletes" = "0" ] || return 1
  [ "$push_branch_refspecs" -le 1 ] || return 1
  if [ "$push_branch_refspecs" = "0" ]; then
    [ "$push_all_tags" = "0" ] && [ "$push_tag_refspecs" = "0" ]
    return
  fi
  source_ref=${refspec%%:*}
  source_ref=${source_ref#+}
  source_ref=${source_ref#refs/heads/}
  [ "$source_ref" = "HEAD" ] && return 0
  [ -n "$head_branch" ] && [ "$source_ref" = "$head_branch" ] && return 0
  return 1
}

content_the_push_sends() {
  invokes="$1"
  [ -x "$invokes" ] || { printf '%s' "$PUSHED_COMMIT"; return 0; }
  commits=$(printf '%s' "$2" | "$invokes" git commit 2>/dev/null)
  [ -n "$commits" ] || printf '%s' "$PUSHED_COMMIT"
}
