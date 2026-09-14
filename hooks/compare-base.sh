#!/bin/sh
# Prisma Harness. Documented in README.md, section "compare-base".

git rev-parse --git-dir >/dev/null 2>&1 || exit 1

ARBOL_VACIO=$(git hash-object -t tree /dev/null 2>/dev/null)
[ -n "$ARBOL_VACIO" ] || exit 1

rama=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
cabeza_remota=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)

remota=""
for candidata in "@{upstream}" "origin/$rama" $cabeza_remota origin/main origin/master origin/develop origin/staging; do
  [ -n "$candidata" ] || continue
  git rev-parse --verify --quiet "$candidata" >/dev/null 2>&1 && { remota="$candidata"; break; }
done

base="$remota"
if [ -z "$base" ]; then
  for candidata in main master; do
    [ "$candidata" = "$rama" ] && continue
    git rev-parse --verify --quiet "$candidata" >/dev/null 2>&1 && { base="$candidata"; break; }
  done
fi

if [ -z "$base" ]; then
  printf '%s\n' "$ARBOL_VACIO"
  exit 0
fi

mb=$(git merge-base "$base" HEAD 2>/dev/null) || { printf '%s\n' "$ARBOL_VACIO"; exit 0; }

if [ "$mb" = "$(git rev-parse HEAD 2>/dev/null)" ]; then
  [ -n "$remota" ] && exit 2
  printf '%s\n' "$ARBOL_VACIO"
  exit 0
fi

printf '%s\n' "$mb"
