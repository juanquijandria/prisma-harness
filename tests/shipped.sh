#!/bin/sh
# Prisma Harness. The paths this repo publishes, so that no test reaches into the files of whoever runs it.

SHIPPED_DIRS="hooks skills tests docs assets .claude-plugin .github"
SHIPPED_FILES="README.md README.es.md METHOD.md STYLE.md CLAUDE.md CONTRIBUTING.md SECURITY.md LICENSE .gitignore .prisma-format.conf.example"
FILES_THAT_MAY_NAME_THE_EXTERNAL_PLUGIN="README.md README.es.md tests/skills-controls.sh tests/runner-controls.sh"

shipped_paths() {
  for dir in $SHIPPED_DIRS; do
    [ -d "$1/$dir" ] && printf '%s\n' "$1/$dir"
  done
  for file in $SHIPPED_FILES; do
    [ -f "$1/$file" ] && printf '%s\n' "$1/$file"
  done
  return 0
}

shipped_pages() {
  for dir in $SHIPPED_DIRS; do
    [ -d "$1/$dir" ] && find "$1/$dir" -name '*.md'
  done
  for file in $SHIPPED_FILES; do
    case "$file" in *.md) [ -f "$1/$file" ] && printf '%s\n' "$1/$file" ;; esac
  done
  return 0
}
