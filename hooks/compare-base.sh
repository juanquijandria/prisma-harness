#!/bin/sh
# Prisma Harness. Documented in README.md, section "compare-base".

git rev-parse --git-dir >/dev/null 2>&1 || exit 1

EMPTY_TREE=$(git hash-object -t tree /dev/null 2>/dev/null)
[ -n "$EMPTY_TREE" ] || exit 1

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
cabeza_remota=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)

remote=""
for candidate in "@{upstream}" "origin/$branch" $cabeza_remota origin/main origin/master origin/develop origin/staging; do
  [ -n "$candidate" ] || continue
  git rev-parse --verify --quiet "$candidate" >/dev/null 2>&1 && { remote="$candidate"; break; }
done

base="$remote"
if [ -z "$base" ]; then
  for candidate in main master; do
    [ "$candidate" = "$branch" ] && continue
    git rev-parse --verify --quiet "$candidate" >/dev/null 2>&1 && { base="$candidate"; break; }
  done
fi

if [ -z "$base" ]; then
  echo "WARN: no base branch to compare against, falling back to the whole history." >&2
  printf '%s\n' "$EMPTY_TREE"
  exit 0
fi

merge_base=$(git merge-base "$base" HEAD 2>/dev/null) || {
  echo "WARN: no merge base with $base, falling back to the whole history." >&2
  printf '%s\n' "$EMPTY_TREE"
  exit 0
}

if [ "$merge_base" = "$(git rev-parse HEAD 2>/dev/null)" ]; then
  [ -n "$remote" ] && exit 2
  echo "WARN: HEAD is already contained in $base, falling back to the whole history." >&2
  printf '%s\n' "$EMPTY_TREE"
  exit 0
fi

printf '%s\n' "$merge_base"
