#!/usr/bin/env bash
# Prisma Harness. Documented in README.md, section "What is inside".
set -uo pipefail

PCT_MAX="${PRISMA_COMMENTS_MAX_PCT:-0}"
BLOCK_MAX="${PRISMA_COMMENTS_MAX_BLOCK:-0}"
BASE=""
DIFF_FILE=""
PLAIN_DIFF="--no-ext-diff --no-color --src-prefix=a/ --dst-prefix=b/"

while [ $# -gt 0 ]; do
  case "$1" in
    --pct)    PCT_MAX="$2"; shift 2 ;;
    --block)  BLOCK_MAX="$2"; shift 2 ;;
    --diff)   DIFF_FILE="$2"; shift 2 ;;
    *)        BASE="$1"; shift ;;
  esac
done

if [ -n "$DIFF_FILE" ]; then
  [ -r "$DIFF_FILE" ] || { echo "cannot read $DIFF_FILE" >&2; exit 2; }
  DIFF=$(cat "$DIFF_FILE") || { echo "could not read the diff in $DIFF_FILE" >&2; exit 2; }
else
  git rev-parse --git-dir >/dev/null 2>&1 || { echo "not a git repo" >&2; exit 2; }

  if [ -z "$BASE" ]; then
    BASE=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
  fi
  if [ -z "$BASE" ]; then
    for cand in origin/main origin/master origin/develop main master; do
      if git rev-parse --verify "$cand" >/dev/null 2>&1; then BASE="$cand"; break; fi
    done
  fi
  [ -n "$BASE" ] || { echo "could not infer the remote base branch" >&2; exit 2; }
  git rev-parse --verify "$BASE" >/dev/null 2>&1 || { echo "base '$BASE' does not exist" >&2; exit 2; }
  MB=$(git merge-base "$BASE" HEAD) || { echo "no merge-base with '$BASE'" >&2; exit 2; }
  DIFF=$(git diff $PLAIN_DIFF "$MB" HEAD) || { echo "could not read the diff against '$MB'" >&2; exit 2; }
fi

[ -n "$DIFF" ] || { echo "comments gate: empty diff, nothing to measure"; exit 0; }

printf '%s\n' "$DIFF" | awk -v pctmax="$PCT_MAX" -v blockmax="$BLOCK_MAX" '
function hash_comment_language(f) { return (f ~ /\.(sh|bash|py|rb)$/) }
function is_comment(s, f) {
  gsub(/^[ \t]*/, "", s)
  if (hash_comment_language(f)) return (s ~ /^#[^!]/ || s == "#")
  return (s ~ /^\/\// || s ~ /^\/\*/ || s ~ /^\*/ || s ~ /^\*\// || s ~ /^<!--/ || s ~ /^#[^!]/ || s == "#")
}
/^\+\+\+ b\// { file_name = substr($0, 7); next }
/^\+/ && !/^\+\+\+/ {
  line = substr($0, 2)
  if (file_name !~ /\.(php|js|mjs|cjs|jsx|ts|tsx|vue|py|rb|go|java|kt|swift|sh|bash|css|scss|sql)$/) next
  if (file_name ~ /(^|\/)(vendor|node_modules|dist|build)\// || file_name ~ /\.(lock|min\.js|snap)$/) next
  total++
  if (is_comment(line, file_name)) {
    line_without_marker = line
    sub(/^[ \t]*(\/\/|\/\*\*?|\*)[ \t]*/, "", line_without_marker)
    if (line_without_marker ~ /^@[a-zA-Z-]+/ || line_without_marker ~ /^(eslint|ts-|prettier|phpcs|phpstan|psalm|@ts-)/) {
      run = 0
      in_annotation = 1
      next
    }
    marker = line
    gsub(/^[ \t]*/, "", marker)
    gsub(/[ \t]*$/, "", marker)
    if (marker == "/**") { pending_opening = 1; next }
    if (marker == "*/" || marker == "*") {
      if (in_annotation) { in_annotation = 0; run = 0; next }
    }
    if (pending_opening) { com++; pending_opening = 0 }
    com++
    run++; if (run == 1) { run_file = file_name; run_ln = NR }
    if (run > blockmax && run > worst_run_by_file[run_file]) { worst_run_by_file[run_file] = run }
    if (run > worst) { worst = run; worst_file = run_file }
    if (line ~ /[0-9][.,][0-9][0-9][0-9]/ || line ~ /[0-9]+ ?%/ || line ~ /[0-9][0-9]\/[0-9][0-9]/) {
      figures[file_name] = figures[file_name] " " NR
      n_figures++
    }
    if (line ~ /[A-Za-z0-9_\/.-]+\.(php|js|mjs|ts|tsx|vue|py|sh):[0-9]+/) {
      refs[file_name] = refs[file_name] " " NR
      n_refs++
    }
  } else { run = 0 }
  next
}
{ run = 0 }
END {
  pct = total ? com * 100 / total : 0
  printf "\n  lines added          %d\n", total
  printf "  comment lines        %d  (%.1f%%, ceiling %d%%)\n", com+0, pct, pctmax
  printf "  longest block        %d  (ceiling %d)%s\n", worst+0, blockmax, (worst > blockmax ? "  <-- " worst_file : "")
  printf "  figures in comments  %d\n", n_figures+0
  printf "  file:line refs       %d\n\n", n_refs+0

  failures = 0
  if (pct > pctmax)   { printf "BLOCK  %.1f%% comment lines, the ceiling is %d%%\n", pct, pctmax; failures++ }
  if (worst > blockmax)  { printf "BLOCK  %d-line comment block in %s, the ceiling is %d\n", worst, worst_file, blockmax; failures++ }
  if (n_figures > 0) {
    printf "BLOCK  %d figures inside comments. A MUTABLE figure without source or date belongs in the docs; a protocol constant or a value a test pins is legitimate and is declared with the escape\n", n_figures
    for (f in figures) printf "         %s ->%s\n", f, figures[f]
    failures++
  }
  if (n_refs > 0) {
    printf "BLOCK  %d file:line references inside comments. Name the symbol instead, unless it is a permalink pinned to a commit, and then declare it\n", n_refs
    for (f in refs) printf "         %s ->%s\n", f, refs[f]
    failures++
  }
  for (f in worst_run_by_file) if (f != worst_file) printf "WARN   %d-line comment block in %s\n", worst_run_by_file[f], f

  if (failures) { printf "\ncomments gate: %d blocking findings\n", failures; exit 1 }
  print "comments gate: clean"
}'
