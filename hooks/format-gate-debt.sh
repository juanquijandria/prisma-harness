# Prisma Harness. Documented in README.md, section "What is inside". Loaded by format-gate.sh, not run alone.

debt() {
  printf '=== format debt inventory of %s/%s (%s) ===\n\n' "$DOCS_ROOT" "$DOCS_DIR" "$(date +%Y-%m-%d)"
  TMP=$(mktemp)
  for f in $(find "$DOCS_ROOT/$DOCS_DIR" -name '*.md'); do review "$f"; done > "$TMP" 2>&1
  NF=$(grep -c '^FAIL' "$TMP")
  NW=$(grep -c '^WARN' "$TMP")
  printf 'BLOCKING  %s\n' "$NF"
  grep '^FAIL' "$TMP" | sed 's/^FAIL  /  /'
  printf '\nWARNINGS  %s, by type:\n' "$NW"
  grep '^WARN' "$TMP" \
    | sed -E 's/.*\| //; s/[0-9]+ lines.*/over the line ceiling/; s/the link .* has no page/broken link/; s/:[0-9]+ .*//' \
    | sort | uniq -c | sort -rn | sed 's/^/  /'

  printf '\nPAGES  %s reviewed, %s with at least one warning\n' \
    "$(find "$DOCS_ROOT/$DOCS_DIR" -name '*.md' | wc -l | tr -d ' ')" \
    "$(grep '^WARN' "$TMP" | sed 's/^WARN  //; s/[:| ].*//' | sort -u | wc -l | tr -d ' ')"

  if [ -f "$BASELINE_FILE" ]; then
    BW=$(sed -n '2p' "$BASELINE_FILE"); BF=$(sed -n '3p' "$BASELINE_FILE"); BD=$(sed -n '1p' "$BASELINE_FILE")
    DW=$((NW - ${BW:-0})); DF=$((NF - ${BF:-0}))
    printf '\nAGAINST THE BASELINE of %s\n' "$BD"
    if [ "$DW" -eq 0 ] && [ "$DF" -eq 0 ]; then
      printf '  no change, %s warnings and %s blocking\n' "$NW" "$NF"
    else
      [ "$DF" -ne 0 ] && printf '  BLOCKING  %+d  (%s -> %s)\n' "$DF" "$BF" "$NF"
      [ "$DW" -ne 0 ] && printf '  warnings  %+d  (%s -> %s)\n' "$DW" "$BW" "$NW"
      printf '  A POSITIVE delta is new debt, not old debt.\n'
      printf '  If the change is deliberate, refreeze with --debt-freeze.\n'
    fi
  else
    printf '\nNO BASELINE. Freeze one with: format-gate.sh --debt-freeze\n'
  fi
  rm -f "$TMP"
  [ "$NF" -eq 0 ]
}

debt_freeze() {
  TMP=$(mktemp)
  for f in $(find "$DOCS_ROOT/$DOCS_DIR" -name '*.md'); do review "$f"; done > "$TMP" 2>&1
  mkdir -p "$DATA_DIR"
  {
    date +%Y-%m-%d
    grep -c '^WARN' "$TMP"
    grep -c '^FAIL' "$TMP"
  } > "$BASELINE_FILE"
  printf 'baseline frozen: %s warnings, %s blocking, on %s\n' \
    "$(grep -c '^WARN' "$TMP")" "$(grep -c '^FAIL' "$TMP")" "$(date +%Y-%m-%d)"
  rm -f "$TMP"
}
