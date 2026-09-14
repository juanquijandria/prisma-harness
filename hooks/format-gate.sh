#!/bin/sh
# Prisma Harness. Documented in README.md, section "format-gate", and in STYLE.md.

HOOKS_DIR="${PRISMA_HOOKS_DIR:-$(cd "$(dirname "$0")" 2>/dev/null && pwd)}"
DOCS_ROOT="${PRISMA_DOCS_ROOT:-${CLAUDE_PROJECT_DIR:-$PWD}}"
DOCS_DIR="${PRISMA_DOCS_DIR:-wiki}"
CONFIG_FILE="${PRISMA_FORMAT_CONFIG:-$DOCS_ROOT/.prisma-format.conf}"
DATA_DIR="${CLAUDE_PLUGIN_DATA:-$HOME/.prisma-harness}"
BASELINE_FILE="$DATA_DIR/format-debt-baseline.txt"

RULE_KEBAB_CASE=1
RULE_H1_FIRST_LINE=1
RULE_EM_DASH=1
RULE_COLON_IN_PROSE=1
RULE_HEADING_COUNTS=1
RULE_VOSEO=1
RULE_LINE_CEILING=150
RULE_SOURCES_FOOTER=0
RULE_WIKILINKS=0
RULE_VERIFY_TAG=0
EXEMPT_NAMES="index.md CLAUDE.md MEMORY.md README.md SKILL.md log.md"
EXEMPT_DIRS="raw archive inbox Clippings"

[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
for v in RULE_KEBAB_CASE RULE_H1_FIRST_LINE RULE_EM_DASH RULE_COLON_IN_PROSE RULE_HEADING_COUNTS RULE_VOSEO RULE_LINE_CEILING RULE_SOURCES_FOOTER RULE_WIKILINKS RULE_VERIFY_TAG EXEMPT_NAMES EXEMPT_DIRS; do
  eval "override=\${PRISMA_$v:-}"
  [ -n "$override" ] && eval "$v=\"\$override\""
done

TALLY=$(mktemp)
trap 'rm -f "$TALLY"' EXIT

exempt() {
  name=$(basename "$1")
  for n in $EXEMPT_NAMES; do [ "$name" = "$n" ] && return 0; done
  case "$name" in *.excalidraw.md) return 0 ;; esac
  for d in $EXEMPT_DIRS; do case "$1" in */"$d"/*) return 0 ;; esac; done
  return 1
}

ceiling_imposed() {
  head -10 "$1" 2>/dev/null | grep -q '<!-- *ceiling-imposed: *[^ ]' && return 0
  return 1
}

fail() { printf 'FAIL  %s\n' "$1"; printf 'F\n' >> "$TALLY"; }
warn() { printf 'WARN  %s\n' "$1"; printf 'W\n' >> "$TALLY"; }
strict_or_warn() { if [ "$STRICT" = "1" ]; then fail "$1"; else warn "$1"; fi; }

review() {
  F="$1"
  [ -f "$F" ] || { fail "$F | does not exist"; return; }
  REL="${F#$DOCS_ROOT/}"
  exempt "$F" && return

  if [ "$RULE_KEBAB_CASE" = "1" ]; then
    B=$(basename "$F" .md)
    printf '%s' "$B" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*$' || fail "$REL | file name is not kebab-case"
  fi

  if [ "$RULE_H1_FIRST_LINE" = "1" ]; then
    head -1 "$F" | grep -qE '^# .' || fail "$REL:1 | missing the H1 on the first line"
  fi

  if [ "${RULE_LINE_CEILING:-0}" -gt 0 ] && ! ceiling_imposed "$F"; then
    N=$(wc -l < "$F" | tr -d ' ')
    NEAR=$((RULE_LINE_CEILING * 9 / 10))
    if [ "$N" -gt "$RULE_LINE_CEILING" ]; then
      warn "$REL | $N lines, over the ceiling of $RULE_LINE_CEILING. Split it unless an outside structure imposes the length"
    elif [ "$N" -gt "$NEAR" ]; then
      warn "$REL | $N lines, close to the ceiling of $RULE_LINE_CEILING"
    fi
  fi

  if [ "$RULE_SOURCES_FOOTER" = "1" ]; then
    grep -qE '^\*?\*?(Fuentes|Sources):' "$F" || fail "$REL | missing the 'Sources:' footer line"
  fi

  if [ "$RULE_EM_DASH" = "1" ]; then
    for L in $(awk '
      /^[[:space:]]*```/ { infence = !infence; next }
      infence { next }
      /^[[:space:]]*#/ { next }
      { line=$0
        if (line ~ /^[[:space:]]*\|/) gsub(/\|[[:space:]]*—[[:space:]]*(\||$)/, "||", line)
        gsub(/`[^`]*`/, "", line)
        if (index(line, "—") > 0) print NR }
    ' "$F"); do
      strict_or_warn "$REL:$L | em-dash in prose"
    done
  fi

  if [ "$RULE_HEADING_COUNTS" = "1" ]; then
    for LINE in $(awk '
      function num(w) {
        w = tolower(w)
        if (w=="dos"||w=="two") return 2;      if (w=="tres"||w=="three") return 3
        if (w=="cuatro"||w=="four") return 4;  if (w=="cinco"||w=="five") return 5
        if (w=="seis"||w=="six") return 6;     if (w=="siete"||w=="seven") return 7
        if (w=="ocho"||w=="eight") return 8;   if (w=="nueve"||w=="nine") return 9
        if (w=="diez"||w=="ten") return 10;    if (w ~ /^[0-9]+$/) return w+0
        return -1
      }
      function close_section() { if (e>0 && v>0 && v!=e) printf "%d:%d:%d\n", hl, e, v }
      /^#{2,3} / { close_section(); e=0; v=0; split($0,p," ")
                   for (i=2;i<=NF && i<=4;i++) { x=num(p[i]); if (x>0) { e=x; hl=NR; break } }
                   next }
      /^\*\*[0-9]+\./ { if (e>0) v++ }
      END { close_section() }
    ' "$F"); do
      HL=$(printf '%s' "$LINE" | cut -d: -f1)
      EXP=$(printf '%s' "$LINE" | cut -d: -f2)
      GOT=$(printf '%s' "$LINE" | cut -d: -f3)
      fail "$REL:$HL | the heading says $EXP and there are $GOT items"
    done
  fi

  if [ "$RULE_VERIFY_TAG" = "1" ]; then
    for L in $(awk '{ line = $0; gsub(/`[^`]*`/, "", line); if (line ~ /\[(verificar|verify)\]/) print NR ": " line }' "$F" \
               | grep -vE '[0-9]{2}/[0-9]{2}/[0-9]{4}|[0-9]{4}-[0-9]{2}-[0-9]{2}' | cut -d: -f1); do
      warn "$REL:$L | [verify] tag without a date"
    done
  fi

  if [ "$RULE_WIKILINKS" = "1" ]; then
    for LK in $(awk '{ line=$0; gsub(/`[^`]*`/, "", line); print line }' "$F" \
                | grep -oE '\[\[[^]|]+' | sed 's/^\[\[//' | tr ' ' '\001' | sort -u); do
      LK=$(printf '%s' "$LK" | tr '\001' ' ')
      [ -z "$LK" ] && continue
      if ! { find "$DOCS_ROOT/$DOCS_DIR" -name "$LK" -print -quit 2>/dev/null
             find "$DOCS_ROOT/$DOCS_DIR" -name "${LK}.md" -print -quit 2>/dev/null
             find "$DOCS_ROOT" -maxdepth 1 -name "$LK" -print -quit 2>/dev/null
             find "$DOCS_ROOT" -maxdepth 1 -name "${LK}.md" -print -quit 2>/dev/null
           } | grep -q .; then
        warn "$REL | the link [[$LK]] has no page"
      fi
    done
  fi

  if [ "$RULE_COLON_IN_PROSE" = "1" ]; then
    for L in $(awk '
      /^```/ { infence = !infence; next }
      infence { next }
      /^[[:space:]]*\|/ { next }
      /^#/ { next }
      /^(\*\*)?(Fuentes|Sources):/ { next }
      {
        line = $0
        gsub(/https?:\/\/[^ )]+/, "", line)
        gsub(/[0-9][0-9]?:[0-9][0-9]/, "", line)
        gsub(/`[^`]*`/, "", line)
        if (line ~ /[a-záéíóúñ]: [a-záéíóúA-ZÁÉÍÓÚ]/) print NR
      }
    ' "$F"); do
      warn "$REL:$L | possible colon in prose"
    done
  fi

  if [ "$RULE_VOSEO" = "1" ]; then
    VOSEO='tenés|podés|querés|sabés|preferís|venís|decís|hacés|sentís|seguís|elegís|mirá|andá|usá|probá|armá|dejá|pasá|contá|mandá|buscá|agregá|revisá|ajustá|explicá|evitá|tomá|llamá|cambiá|guardá|fijate|acordate|quedate'
    for L in $(awk -v vos="$VOSEO" '
      /^```/ { infence = !infence; next }
      infence { next }
      /^[[:space:]]*\|/ { next }
      {
        line = tolower($0)
        gsub(/`[^`]*`/, "", line)
        if (line ~ /voseo|argentin/) next
        if (line ~ ("(^|[^[:alnum:]])(" vos ")([^[:alnum:]]|$)")) { print NR; next }
        if (line ~ /(^|[^[:alnum:]])(vos|sos)([^[:alnum:]]|$)/) print NR
      }
    ' "$F"); do
      strict_or_warn "$REL:$L | voseo. The rule is Peruvian Spanish, tú and never vos"
    done
  fi
}

. "$HOOKS_DIR/format-gate-tests.sh"
. "$HOOKS_DIR/format-gate-debt.sh"
STRICT=0
if [ "$1" = "--strict" ]; then STRICT=1; shift; fi

case "$1" in
  --selftest) selftest; exit $? ;;
  --match)    shift; match_test "${1:?a real page is required}"; exit $? ;;
  --debt)     debt; exit $? ;;
  --debt-freeze) debt_freeze; exit $? ;;
  --changed)
    STRICT=1
    F=$(find "$DOCS_ROOT/$DOCS_DIR" -name '*.md' -newermt "$(date +%Y-%m-%d)" 2>/dev/null)
    if [ $? -ne 0 ]; then
      echo "WARN: --changed could not list today's pages, so NOTHING was reviewed." >&2
      exit 0
    fi
    [ -z "$F" ] && { echo "no pages under $DOCS_DIR/ touched today"; exit 0; }
    HOOK_MODE=1
    for f in $F; do exempt "$f" || review "$f"; done
    ;;
  "") printf 'usage: format-gate.sh [--strict] <file.md ...> | --changed | --debt | --debt-freeze | --match <file> | --selftest\n'; exit 2 ;;
  *)  for f in "$@"; do exempt "$f" && { printf 'SKIP  %s (exempt from page format)\n' "${f#$DOCS_ROOT/}"; continue; }; review "$f"; done ;;
esac

printf '\n'
FAILS=$(grep -c '^F$' "$TALLY" 2>/dev/null); FAILS=${FAILS:-0}
WARNS=$(grep -c '^W$' "$TALLY" 2>/dev/null); WARNS=${WARNS:-0}
if [ "$FAILS" -gt 0 ]; then
  printf 'FAIL: %d blocking, %d warnings\n' "$FAILS" "$WARNS"
  if [ "${HOOK_MODE:-0}" = "1" ]; then
    printf 'FORMAT GATE: %d page(s) touched today break the writing rules. Fix them before stopping. Run hooks/format-gate.sh --strict <page> to see each finding.\n' "$FAILS" >&2
    exit 2
  fi
  exit 1
fi
printf 'PASS: 0 blocking, %d warnings\n' "$WARNS"; exit 0
