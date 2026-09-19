# Prisma Harness. Documented in README.md, section "What is inside", and in STYLE.md. Loaded by format-gate.sh, not run alone.

rate_applies() {
  [ "$RULE_RATE_SECOND_READING" = "1" ] || return 1
  for d in $RATE_DIRS; do case "$1" in "$DOCS_ROOT/$d"/*) return 0 ;; esac; done
  return 1
}

rate_readings() {
  awk '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    /^\|/ {
      n = split($0, c, "|")
      if ($0 ~ /^\|[ \t]*:?-+/) { insep = 1; next }
      if (!inhdr) { for (i = 2; i < n; i++) hdr[i] = trim(c[i]); inhdr = 1; next }
      if (insep) {
        row = trim(c[2])
        for (i = 3; i < n; i++) {
          v = trim(c[i])
          if (v !~ /%/) continue
          cells++
          k = row "\t" hdr[i]
          if (!((k SUBSEP v) in seen)) { seen[k SUBSEP v] = 1; distinct[k]++ }
        }
      }
      next
    }
    { inhdr = 0; insep = 0 }
    END { for (k in distinct) if (distinct[k] > 1) two++; printf "%d %d\n", cells + 0, two + 0 }
  ' "$1"
}

rate_rule() {
  rate_applies "$1" || return
  COUNTS=$(rate_readings "$1")
  RATE_CELLS=${COUNTS%% *}
  RATE_CELLS_WITH_A_SECOND_READING=${COUNTS##* }
  [ "$RATE_CELLS" -ge "$RATE_CELLS_FLOOR" ] || return
  [ "$RATE_CELLS_WITH_A_SECOND_READING" = "0" ] || return
  warn "${1#$DOCS_ROOT/} | $RATE_CELLS rate cells and not one of them published under a second definition. Two routes that share the definition are one route, so publish the cell that carries the conclusion under both and reconcile the difference with counted records"
}
