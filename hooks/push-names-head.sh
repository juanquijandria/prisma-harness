#!/bin/sh
# Prisma Harness. Decides whether a push command can be proven to send the branch HEAD is on, from the repository the gate is standing in. Documented in README.md, section "What is inside".

GIT_FLAGS_BEFORE_THE_SUBCOMMAND="--no-pager --paginate -p --no-replace-objects --literal-pathspecs --no-optional-locks --no-lazy-fetch"
GIT_FLAGS_THAT_TAKE_THE_NEXT_TOKEN="-c"
PUSH_FLAGS_THAT_TAKE_NO_VALUE="-u --set-upstream -f --force --force-with-lease -n --dry-run -q --quiet -v --verbose --progress --no-verify --verify --atomic --follow-tags --porcelain --thin --no-thin --prune --ipv4 --ipv6 -4 -6"

push_names_head() {
  head_branch="$1"
  push_command="$2"
  raw_command="$3"
  case "$raw_command" in *GIT_DIR=*|*GIT_WORK_TREE=*|*GIT_COMMON_DIR=*) return 1 ;; esac
  set -f
  set -- $push_command
  set +f
  past_push=0
  skip_next=0
  remote_seen=0
  refspecs=0
  refspec=""
  for token in "$@"; do
    if [ "$skip_next" = "1" ]; then skip_next=0; continue; fi
    if [ "$past_push" = "0" ]; then
      [ "$token" = "push" ] && { past_push=1; continue; }
      case "$token" in
        -*)
          known=0
          for flag in $GIT_FLAGS_BEFORE_THE_SUBCOMMAND; do [ "$token" = "$flag" ] && known=1; done
          for flag in $GIT_FLAGS_THAT_TAKE_THE_NEXT_TOKEN; do [ "$token" = "$flag" ] && { known=1; skip_next=1; }; done
          [ "$known" = "1" ] || return 1
          ;;
      esac
      continue
    fi
    case "$token" in
      -*=*) continue ;;
      -*)
        known=0
        for flag in $PUSH_FLAGS_THAT_TAKE_NO_VALUE; do [ "$token" = "$flag" ] && known=1; done
        [ "$known" = "1" ] || return 1
        continue
        ;;
    esac
    if [ "$remote_seen" = "0" ]; then remote_seen=1; continue; fi
    refspecs=$((refspecs+1))
    refspec="$token"
  done
  [ "$past_push" = "1" ] || return 1
  [ "$refspecs" -le 1 ] || return 1
  [ "$refspecs" = "0" ] && return 0
  source_ref=${refspec%%:*}
  source_ref=${source_ref#+}
  source_ref=${source_ref#refs/heads/}
  [ "$source_ref" = "HEAD" ] && return 0
  [ -n "$head_branch" ] && [ "$source_ref" = "$head_branch" ] && return 0
  return 1
}
