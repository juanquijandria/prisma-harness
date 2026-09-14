# Prisma Harness. Documented in README.md, section "format-gate". Loaded by format-gate.sh, not run alone.

selftest() {
  STRICT=1
  RULE_KEBAB_CASE=1; RULE_H1_FIRST_LINE=1; RULE_EM_DASH=1; RULE_COLON_IN_PROSE=1; RULE_HEADING_COUNTS=1
  RULE_VOSEO=1; RULE_LINE_CEILING=150; RULE_SOURCES_FOOTER=1; RULE_WIKILINKS=1; RULE_VERIFY_TAG=1
  T=$(mktemp -d)
  DOCS_ROOT="$T"; DOCS_DIR="wiki"
  mkdir -p "$T/wiki/a/b/c/d"
  GOOD="$T/wiki/good-page.md"
  cat > "$GOOD" <<'EOT'
# Good page

A two-line summary that explains the concept.
Nothing else.

## One detail

**1.** The only item.

Sources: made up for the selftest.
EOT
  printf '=== the gate on a good page (must pass clean) ===\n'
  : > "$TALLY"
  OUT_GOOD=$( review "$GOOD" 2>&1 )
  if [ -n "$OUT_GOOD" ]; then
    printf 'SELFTEST BROKEN: the good page did not pass clean\n%s\n' "$OUT_GOOD"; rm -rf "$T"; return 1
  fi
  printf '  (clean)\n\n'

  R=0
  break_it() {
    : > "$TALLY"
    O=$( review "$2" 2>&1 | grep '^FAIL' )
    if [ -z "$O" ]; then printf '  BLIND on "%s"\n' "$1"; R=1
    else printf '  caught "%s"\n' "$1"; fi
  }
  break_warn() {
    : > "$TALLY"
    O=$( review "$2" 2>&1 | grep '^WARN' )
    if [ -z "$O" ]; then printf '  BLIND on "%s"\n' "$1"; R=1
    else printf '  caught "%s"\n' "$1"; fi
  }
  stay_quiet() {
    : > "$TALLY"
    O=$( review "$2" 2>&1 )
    if [ -n "$O" ]; then printf '  FALSE ALARM on "%s"\n%s\n' "$1" "$O"; R=1
    else printf '  quiet on "%s"\n' "$1"; fi
  }

  printf '=== broken pages, each must FAIL ===\n'
  sed 's/^# Good page/No H1/' "$GOOD" > "$T/wiki/no-h1.md";                       break_it "no H1" "$T/wiki/no-h1.md"
  grep -v '^Sources:' "$GOOD" > "$T/wiki/no-sources.md";                          break_it "no Sources footer" "$T/wiki/no-sources.md"
  sed 's/concept./concept — with an em-dash./' "$GOOD" > "$T/wiki/em-dash.md";    break_it "em-dash" "$T/wiki/em-dash.md"
  sed 's/## One detail/## Three details/' "$GOOD" > "$T/wiki/bad-count.md";        break_it "heading count mismatch (English numeral)" "$T/wiki/bad-count.md"
  sed 's/## One detail/## Tres detalles/' "$GOOD" > "$T/wiki/bad-count-es.md";     break_it "heading count mismatch (Spanish numeral)" "$T/wiki/bad-count-es.md"
  cp "$GOOD" "$T/wiki/Bad_Name.md";                                                break_it "file name not kebab-case" "$T/wiki/Bad_Name.md"
  sed 's/Nothing else./Mirá el panel y usá la ruta corta./' "$GOOD" > "$T/wiki/voseo.md"; break_it "voseo (mirá, usá)" "$T/wiki/voseo.md"
  sed 's/Nothing else./Mirá esto./' "$GOOD" > "$T/wiki/voseo-capital.md"; break_it "voseo with a capital letter (Mirá)" "$T/wiki/voseo-capital.md"
  sed 's/Nothing else./This is prose — with an em-dash in the middle./' "$GOOD" > "$T/wiki/em-dash-prose.md"; break_it "em-dash in prose (negative control)" "$T/wiki/em-dash-prose.md"

  printf '\n=== warning cases, each must WARN ===\n'
  sed 's/Nothing else./Pending datum [verify] without a date./' "$GOOD" > "$T/wiki/verify-no-date.md"; break_warn "[verify] without date" "$T/wiki/verify-no-date.md"
  sed 's/Nothing else./The rule is simple: never like this in prose./' "$GOOD" > "$T/wiki/colon.md";    break_warn "colon in prose" "$T/wiki/colon.md"
  sed 's/Nothing else./See [[page-that-never-exists]]./' "$GOOD" > "$T/wiki/broken-link.md";           break_warn "broken wikilink" "$T/wiki/broken-link.md"
  sed 's/Nothing else./See the drawing ![[no-such-drawing.svg]] next door./' "$GOOD" > "$T/wiki/broken-attachment.md"; break_warn "missing embedded attachment" "$T/wiki/broken-attachment.md"
  sed 's/Nothing else./Missing datum [verify] and nobody wrote when./' "$GOOD" > "$T/wiki/verify-real.md"; break_warn "[verify] real, without date (negative control)" "$T/wiki/verify-real.md"

  printf '\n=== cases that must stay QUIET (no false alarm) ===\n'
  sed 's/Nothing else./Run the workflow `PLAY — Monthly downloads` and done./' "$GOOD" > "$T/wiki/em-dash-in-code.md"
  stay_quiet "em-dash inside backticks (quoted proper name)" "$T/wiki/em-dash-in-code.md"
  awk '{ print } /^Nothing else\.$/ && !d { print "\n```\ntable — with an em-dash inside a code block\n```"; d=1 }' "$GOOD" > "$T/wiki/em-dash-in-block.md"
  stay_quiet "em-dash inside a code block" "$T/wiki/em-dash-in-block.md"
  sed 's/^## One detail$/## One detail — with a title separator/' "$GOOD" > "$T/wiki/em-dash-heading.md"
  stay_quiet "em-dash in a heading (title separator)" "$T/wiki/em-dash-heading.md"
  sed 's/Nothing else./On day 08 escribí que la prueba fallaba y corregí el predicado./' "$GOOD" > "$T/wiki/preterite.md"
  stay_quiet "first-person preterite (escribí, corregí) is NOT voseo" "$T/wiki/preterite.md"
  sed 's/Nothing else./El script vosea y los casos famosos son peligrosos./' "$GOOD" > "$T/wiki/substring.md"
  stay_quiet "vos/sos inside vosea, famosos, casos, peligrosos" "$T/wiki/substring.md"
  sed 's/Nothing else./The convention is to write `[verify]` with its date next to it./' "$GOOD" > "$T/wiki/verify-quoted.md"
  stay_quiet "[verify] inside backticks (page names the convention)" "$T/wiki/verify-quoted.md"
  sed 's/Nothing else./Links `[[like-this]]` join pages./' "$GOOD" > "$T/wiki/wikilink-quoted.md"
  stay_quiet "wikilink inside backticks (page names the convention)" "$T/wiki/wikilink-quoted.md"
  sed 's/Nothing else./The meeting was at 10:30 and ended at 11:15./' "$GOOD" > "$T/wiki/times.md"
  stay_quiet "clock times are not colons in prose" "$T/wiki/times.md"
  cp "$GOOD" "$T/wiki/a/b/c/d/deep-page.md"
  sed 's/Nothing else./See [[deep-page]]./' "$GOOD" > "$T/wiki/deep-link.md"
  stay_quiet "link to a page at depth 4" "$T/wiki/deep-link.md"
  : > "$T/wiki/diagram.svg"
  sed 's/Nothing else./See the drawing ![[diagram.svg]] next door./' "$GOOD" > "$T/wiki/attachment-exists.md"
  stay_quiet "embedded attachment that exists" "$T/wiki/attachment-exists.md"
  cat > "$T/wiki/sketch.excalidraw.md" <<'EOX'
---
excalidraw-plugin: parsed
---
{"type":"excalidraw","elements":[]}
EOX
  stay_quiet ".excalidraw.md file (machine format)" "$T/wiki/sketch.excalidraw.md"
  sed 's/Nothing else./See the diagram [[sketch.excalidraw]] next door./' "$GOOD" > "$T/wiki/dotted-name.md"
  stay_quiet "link to a page with a dot in its name" "$T/wiki/dotted-name.md"

  printf '\n=== rules switched off by config must stay QUIET ===\n'
  RULE_VOSEO=0
  stay_quiet "voseo with RULE_VOSEO=0" "$T/wiki/voseo.md"
  RULE_VOSEO=1
  RULE_EM_DASH=0
  stay_quiet "em-dash with RULE_EM_DASH=0" "$T/wiki/em-dash-prose.md"
  RULE_EM_DASH=1
  RULE_SOURCES_FOOTER=0
  stay_quiet "no Sources footer with RULE_SOURCES_FOOTER=0" "$T/wiki/no-sources.md"
  RULE_SOURCES_FOOTER=1

  rm -rf "$T"
  printf '\n'
  [ "$R" -eq 0 ] && printf 'SELFTEST OK: passes the good page, catches the 14 breaks, stays quiet on the 15 quiet cases\n' || printf 'SELFTEST FAILED: blind checks or false alarms\n'
  return $R
}

match_test() {
  P="$1"
  [ -f "$P" ] || { printf 'match: %s does not exist\n' "$P"; return 2; }
  STRICT=1
  T=$(mktemp -d)
  Q="$T/$(basename "$P")"
  R=0; CAUGHT=0; TOTAL=0
  printf '=== match test on %s ===\n' "$(basename "$P")"

  probe() {
    TOTAL=$((TOTAL+1))
    : > "$TALLY"
    if review "$Q" 2>&1 | grep -q "$2"; then printf '  caught %s\n' "$1"; CAUGHT=$((CAUGHT+1))
    else printf '  BLIND on %s\n' "$1"; R=1; fi
  }

  awk 'NR==3 && !d { print $0 " — injected match"; d=1; next } { print }' "$P" > "$Q"
  probe "em-dash in prose" "em-dash"
  { cat "$P"; printf 'The rule is simple: never like this in prose.\n'; } > "$Q"
  probe "colon in prose" "colon in prose"
  { cat "$P"; printf 'Mirá el panel y usá la ruta corta.\n'; } > "$Q"
  probe "voseo" "voseo"
  tail -n +2 "$P" > "$Q"
  probe "missing H1" "missing the H1"
  cp "$P" "$T/Bad_Name.md"; QQ="$Q"; Q="$T/Bad_Name.md"
  probe "file name not kebab-case" "kebab-case"
  Q="$QQ"

  rm -rf "$T"
  printf '\nINJECTION RECALL: %s of %s classes caught\n' "$CAUGHT" "$TOTAL"
  printf 'This measures the classes the gate CLAIMS to cover. A class nobody thought of does not show up here.\n'
  [ "$R" -eq 0 ] && printf 'MATCH OK\n' || printf 'MATCH FAILED: blind checks on real pages\n'
  return $R
}
