#!/bin/sh
# Prisma Harness. Documented in README.md, section "measure-diff-size".

REPO="${1:?repo path required}"
BASE="${2:?base ref required}"
HEAD="${3:?head ref required}"

EXCLUIR='(^|/)(package-lock\.json|pnpm-lock\.yaml|yarn\.lock|composer\.lock|Gemfile\.lock|poetry\.lock|Cargo\.lock|go\.sum)$|\.(lock|svg|png|jpe?g|gif|webp|woff2?|ttf|eot|map|snap|min\.(js|css))$'

git -C "$REPO" diff --numstat "$BASE" "$HEAD" 2>/dev/null \
  | grep -vE "$EXCLUIR" \
  | awk '{ if ($1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/) total += $1 + $2 } END { print total + 0 }'
