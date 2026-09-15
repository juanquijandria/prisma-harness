#!/usr/bin/env bash
# Prisma Harness. Documented in README.md, section "What is inside".
set -uo pipefail

PCT_MAX="${PRISMA_COMMENTS_MAX_PCT:-0}"
BLOQUE_MAX="${PRISMA_COMMENTS_MAX_BLOCK:-0}"
BASE=""
DIFF_FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --pct)    PCT_MAX="$2"; shift 2 ;;
    --bloque) BLOQUE_MAX="$2"; shift 2 ;;
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
  DIFF=$(git diff "$MB") || { echo "could not read the diff against '$MB'" >&2; exit 2; }
fi

[ -n "$DIFF" ] || { echo "comments gate: empty diff, nothing to measure"; exit 0; }

printf '%s\n' "$DIFF" | awk -v pctmax="$PCT_MAX" -v blomax="$BLOQUE_MAX" '
function hash_comment_language(f) { return (f ~ /\.(sh|bash|py|rb)$/) }
function es_comentario(s, f) {
  gsub(/^[ \t]*/, "", s)
  if (hash_comment_language(f)) return (s ~ /^#[^!]/ || s == "#")
  return (s ~ /^\/\// || s ~ /^\/\*/ || s ~ /^\*/ || s ~ /^\*\// || s ~ /^<!--/ || s ~ /^#[^!]/ || s == "#")
}
/^\+\+\+ b\// { archivo = substr($0, 7); next }
/^\+/ && !/^\+\+\+/ {
  linea = substr($0, 2)
  if (archivo !~ /\.(php|js|mjs|cjs|jsx|ts|tsx|vue|py|rb|go|java|kt|swift|sh|bash|css|scss|sql)$/) next
  if (archivo ~ /(^|\/)(vendor|node_modules|dist|build)\// || archivo ~ /\.(lock|min\.js|snap)$/) next
  total++
  if (es_comentario(linea, archivo)) {
    linea_sin_marca = linea
    sub(/^[ \t]*(\/\/|\/\*\*?|\*)[ \t]*/, "", linea_sin_marca)
    if (linea_sin_marca ~ /^@[a-zA-Z-]+/ || linea_sin_marca ~ /^(eslint|ts-|prettier|phpcs|phpstan|psalm|@ts-)/) {
      run = 0
      en_anotacion = 1
      next
    }
    marca = linea
    gsub(/^[ \t]*/, "", marca)
    gsub(/[ \t]*$/, "", marca)
    if (marca == "/**") { pendiente_apertura = 1; next }
    if (marca == "*/" || marca == "*") {
      if (en_anotacion) { en_anotacion = 0; run = 0; next }
    }
    if (pendiente_apertura) { com++; pendiente_apertura = 0 }
    com++
    run++; if (run == 1) { run_ini = archivo; run_ln = NR }
    if (run > blomax && run > peor_run_por_archivo[run_ini]) { peor_run_por_archivo[run_ini] = run }
    if (run > peor) { peor = run; peor_f = run_ini }
    if (linea ~ /[0-9][.,][0-9][0-9][0-9]/ || linea ~ /[0-9]+ ?%/ || linea ~ /[0-9][0-9]\/[0-9][0-9]/) {
      cifras[archivo] = cifras[archivo] " " NR
      n_cifras++
    }
    if (linea ~ /[A-Za-z0-9_\/.-]+\.(php|js|mjs|ts|tsx|vue|py|sh):[0-9]+/) {
      refs[archivo] = refs[archivo] " " NR
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
  printf "  longest block        %d  (ceiling %d)%s\n", peor+0, blomax, (peor > blomax ? "  <-- " peor_f : "")
  printf "  figures in comments  %d\n", n_cifras+0
  printf "  file:line refs       %d\n\n", n_refs+0

  fallos = 0
  if (pct > pctmax)   { printf "BLOCK  %.1f%% comment lines, the ceiling is %d%%\n", pct, pctmax; fallos++ }
  if (peor > blomax)  { printf "BLOCK  %d-line comment block in %s, the ceiling is %d\n", peor, peor_f, blomax; fallos++ }
  if (n_cifras > 0) {
    printf "BLOCK  %d figures inside comments. A MUTABLE figure without source or date belongs in the docs; a protocol constant or a value a test pins is legitimate and is declared with the escape\n", n_cifras
    for (f in cifras) printf "         %s ->%s\n", f, cifras[f]
    fallos++
  }
  if (n_refs > 0) {
    printf "BLOCK  %d file:line references inside comments. Name the symbol instead, unless it is a permalink pinned to a commit, and then declare it\n", n_refs
    for (f in refs) printf "         %s ->%s\n", f, refs[f]
    fallos++
  }
  for (f in peor_run_por_archivo) if (f != peor_f) printf "WARN   %d-line comment block in %s\n", peor_run_por_archivo[f], f

  if (fallos) { printf "\ncomments gate: %d blocking findings\n", fallos; exit 1 }
  print "comments gate: clean"
}'
