#!/bin/sh
# Prisma Harness. Documented in README.md, section "What is inside". Loaded by pr-ready.sh and claim-ready-gate.sh, not run alone.

GITHUB_REMOTE_PATTERN='s#^.*github\.com[:/]\([^/]*/[^/]*\)$#\1#p'

github_repos_of() {
  [ -d "$1" ] || return 0
  if [ -n "${2:-}" ]; then git -C "$1" remote get-url "$2" 2>/dev/null
  else git -C "$1" remote -v 2>/dev/null | awk '{ print $2 }'; fi \
    | sed -n "$GITHUB_REMOTE_PATTERN" | sed 's#\.git$##' | tr 'A-Z' 'a-z' | sort -u
}
