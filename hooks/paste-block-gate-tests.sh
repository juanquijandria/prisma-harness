#!/bin/sh
# Prisma Harness. Documented in README.md, section "What is inside". Loaded by paste-block-gate.sh, not run alone.

FENCE='════════════════════'

expect() {
  cases=$((cases+1))
  if [ "$2" = "$3" ]; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s, expected [%s] and got [%s]\n' "$1" "$3" "$2"; ok=0; fi
}

in_block() { printf 'Te dejo el mensaje.\n\n%s\n%s\n%s\n\nAvísame si algo.' "$FENCE" "$1" "$FENCE"; }

stop() {
  "$JQ" -nc --arg final "$1" --argjson active "${ACTIVE_FOR_TEST:-false}" --arg has_final "${NO_FINAL_FOR_TEST:-yes}" \
    '{session_id: "s", transcript_path: "/there/is/no/transcript.jsonl", cwd: "/repo/paste", hook_event_name: "Stop", stop_hook_active: $active}
      + (if $has_final == "yes" then {last_assistant_message: $final} else {} end)' \
    | PRISMA_JQ="${JQ_FOR_TEST-$JQ}" sh "$GATE" 2>/dev/null
}

decision() {
  out=$(stop "$1"); rc=$?
  said_decision=$(printf '%s' "$out" | "$JQ" -r '.decision // empty' 2>/dev/null)
  printf '%s %s' "$rc" "${said_decision:-pass}"
}

selftest_holes() {
  expect "1 the real case, a test code left as TEST… after =, blocks the stop" \
    "$(decision "$(in_block '- META_CONVERSIONS_ENABLED=true y META_CONVERSIONS_TEST_EVENT_CODE=TEST… y reiniciar')")" "0 block"
  expect "2 a value left as three dots after a colon blocks" "$(decision "$(in_block 'token: abc...')")" "0 block"
  expect "3 a marker in angles in Spanish blocks" "$(decision "$(in_block 'Pega aquí <tu código> y reinicia')")" "0 block"
  expect "4 a marker in angles in English blocks" "$(decision "$(in_block 'Authorization: Bearer <your token>')")" "0 block"
  expect "5 a one word marker in angles blocks" "$(decision "$(in_block 'el enlace es <link>')")" "0 block"
  expect "6 a marker in angles inside a quoted value blocks" "$(decision "$(in_block 'API_KEY="<valor>"')")" "0 block"
  expect "7 TODO as a word of its own blocks" "$(decision "$(in_block 'La fecha de entrega es TODO')")" "0 block"
  expect "8 XXX as a word of its own blocks" "$(decision "$(in_block 'Tu cuenta es la XXX')")" "0 block"
  expect "9 FIXME as a word of its own blocks" "$(decision "$(in_block 'FIXME poner el monto')")" "0 block"
  expect "10 a marker in brackets that asks to put something blocks" "$(decision "$(in_block 'Hola [pon aquí] cómo estás')")" "0 block"
  expect "11 a name in brackets blocks" "$(decision "$(in_block 'Hola [nombre], te escribo por lo del lunes')")" "0 block"
  expect "12 a value in brackets in English blocks" "$(decision "$(in_block 'limit = [value]')")" "0 block"
  expect "13 a real message that went out with the link still to put blocks" "$(decision "$(in_block 'acá está el kit de pauta

[link]

ojo que todavía se está subiendo')")" "0 block"
  expect "14 a real message that went out with the drive link still to put blocks" "$(decision "$(in_block 'acá está el kit de pauta

[link del drive]

lo que más te interesa está en la carpeta de fotos')")" "0 block"
}

selftest_named_values() {
  expect "39 a value that says here in Spanish, as the step 3 session wrote it, blocks" "$(decision "$(in_block 'META_CONVERSIONS_TEST_EVENT_CODE=TEST_CODIGO_AQUI')")" "0 block"
  expect "40 a value that says your and here in English blocks" "$(decision "$(in_block 'API_KEY=YOUR_API_KEY_HERE')")" "0 block"
  expect "41 a value of x after a prefix blocks" "$(decision "$(in_block 'STRIPE_SECRET: sk_test_xxxxxxxx')")" "0 block"
  expect "42 a real value in capitals with underscores is not a hole" "$(decision "$(in_block 'LOG_LEVEL=DEBUG_VERBOSE y REGION: US_EAST_1')")" "0 pass"
  expect "43 a sentence after a colon is not a value" "$(decision "$(in_block 'Nota: tu pedido llega el lunes aquí')")" "0 pass"
  expect "44 an hour followed by three dots is not a hole" "$(decision "$(in_block 'Nos vemos a las 10:30... o un poco antes')")" "0 pass"
  expect "45 a label followed by dots alone is style" "$(decision "$(in_block 'Ojo: … esto es importante')")" "0 pass"
  expect "46 an empty value cut with dots after = blocks" "$(decision "$(in_block 'SECRET=...')")" "0 block"
  expect "47 code in angles is a marker, not a tag this text would carry" "$(decision "$(in_block 'CODE=<code>')")" "0 block"
  expect "48 title in angles is a marker too" "$(decision "$(in_block 'Hola <title>, te escribo')")" "0 block"
  expect "49 a reference link in markdown is not a marker" "$(decision "$(in_block 'mira [la guía][1] cuando puedas')")" "0 pass"
  expect "50 the reason keeps the escape for a hole the person asked for in so many words" "$(reason_says "$(in_block "SENTRY_DSN=PEGAR_AQUI_EL_DSN")" 'only when the person asked for that hole in so many words')" "says"
  expect "51 a value that says here with an accent in capitals blocks" "$(decision "$(in_block 'CODE=TEST_CODIGO_AQUÍ')")" "0 block"
  expect "52 a value cut with dots and followed by a comma blocks" "$(decision "$(in_block 'CODE=TEST…, y reinicia')")" "0 block"
  expect "53 a quoted value two spaces after the colon is still a value" "$(decision "$(in_block 'KEY:  "<tu token>"')")" "0 block"
  expect "54 TODO after a word in capitals is the Spanish word, not a marker" "$(decision "$(in_block 'GRACIAS POR TODO')")" "0 pass"
  expect "55 a generic type in code is not a marker" "$(decision "$(in_block 'devuelve List<String> y Map<Key>')")" "0 pass"
}

selftest_not_holes() {
  expect "15 a template variable in double braces is not a hole" "$(decision "$(in_block 'Hola {{nombre}}, tu pedido sale mañana')")" "0 pass"
  expect "16 three dots inside a sentence are style, not a hole" "$(decision "$(in_block 'Quizás ahora sí… o quizás la próxima. Bueno... ya veremos')")" "0 pass"
  expect "17 a hole outside the block is not this gate's business" "$(decision "Reemplaza <tu código> por el tuyo.
$(in_block 'Hola, ya quedó')")" "0 pass"
  expect "18 a block with no hole lets the stop through" "$(decision "$(in_block 'Hola, ya quedó el reporte y está en la carpeta compartida')")" "0 pass"
  expect "19 an index in code is not a marker" "$(decision "$(in_block 'copia c[0].f y data[key]')")" "0 pass"
  expect "20 a button label with spaces inside the brackets is not a marker" "$(decision "$(in_block '[ Ver los planes ]')")" "0 pass"
  expect "21 a checked box is not a marker" "$(decision "$(in_block '- [x] enviado')")" "0 pass"
  expect "22 a markdown link is not a marker" "$(decision "$(in_block 'mira [la guía](https://example.com/guia)')")" "0 pass"
  expect "23 an HTML tag is not a marker" "$(decision "$(in_block 'primera línea<br>segunda <b>línea</b>')")" "0 pass"
  expect "24 a chat mention in angles is not a marker" "$(decision "$(in_block 'avísale a <@123456> y a <#987654>')")" "0 pass"
  expect "25 a marker quoted from another text is not a hole of this one" "$(decision "$(in_block 'el push dice "mañana hay [plato fuerte]" y el sábado no hay menú')")" "0 pass"
  expect "26 a fence with no partner opens no block" "$(decision "Te dejo esto.
$FENCE
Hola <tu código>")" "0 pass"
  expect "27 a quoted value before a quotation does not pair its closing quote with the quotation" "$(decision "$(in_block 'MODE="live" y el push dice "mañana hay [plato fuerte]"')")" "0 pass"
}

reason_says() { stop "$1" | "$JQ" -r '.reason // empty' 2>/dev/null | grep -F -- "$2" >/dev/null && echo says || echo silent; }
receipt_count() { grep -c "	$GATE_NAME	.*	$1\$" "$PRISMA_RECEIPT_FILE" 2>/dev/null | tr -d ' '; }

selftest_reason_and_receipt() {
  : > "$PRISMA_RECEIPT_FILE"
  real_case=$(in_block 'META_CONVERSIONS_TEST_EVENT_CODE=TEST…')
  expect "28 the reason names the hole" "$(reason_says "$real_case" '=TEST…')" "says"
  expect "29 the reason says to ask the person for the value first" "$(reason_says "$real_case" 'ask the person')" "says"
  blocked_before=$(receipt_count blocked)
  expect "30 a block leaves its line in the receipt" "$(decision "$real_case") $(($(receipt_count blocked) - blocked_before))" "0 block 1"
  ACTIVE_FOR_TEST=true
  expect "31 a stop that a stop hook already continued is let through" "$(decision "$real_case")" "0 pass"
  unset ACTIVE_FOR_TEST
  expect "32 the declared escape on its own line outside the block lets the stop through and leaves its line" \
    "$(decision "$real_case
PRISMA_PASTE_OK=1") $(receipt_count escaped)" "0 pass 1"
  expect "33 the escape inside the block does not count, it would be pasted" \
    "$(decision "$(in_block 'PRISMA_PASTE_OK=1
CODE=TEST…')")" "0 block"
  JQ_FOR_TEST=""
  expect "34 with no jq the stop goes through and the receipt says not measured" "$(decision "$real_case") $(receipt_count not-measured)" "0 pass 1"
  unset JQ_FOR_TEST
  NO_FINAL_FOR_TEST=no
  expect "35 an event with no final message goes through and the receipt says not measured" "$(decision "$real_case") $(receipt_count not-measured)" "0 pass 2"
  unset NO_FINAL_FOR_TEST
  lines_before=$(wc -l < "$PRISMA_RECEIPT_FILE" | tr -d ' ')
  expect "36 a message with no block writes nothing to the receipt" "$(decision "Listo, ya está.") $(wc -l < "$PRISMA_RECEIPT_FILE" | tr -d ' ')" "0 pass $lines_before"
  expect "37 an escape with no hole to excuse writes nothing to the receipt" "$(decision "$(in_block 'Hola, ya quedó')
PRISMA_PASTE_OK=1") $(wc -l < "$PRISMA_RECEIPT_FILE" | tr -d ' ')" "0 pass $lines_before"
  JQ_FOR_TEST="$T/jq-that-fails-on-the-message"
  expect "38 a jq that fails on the message is not a pass, the receipt says not measured" "$(decision "$real_case") $(receipt_count not-measured)" "0 pass 3"
  unset JQ_FOR_TEST
}

selftest() {
  GATE=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
  T=$(mktemp -d)
  printf '#!/bin/sh\ncase "$*" in *-Rrs*) exit 3 ;; esac\nexec "%s" "$@"\n' "$JQ" > "$T/jq-that-fails-on-the-message"
  chmod +x "$T/jq-that-fails-on-the-message"
  ok=1; cases=0
  selftest_holes
  selftest_not_holes
  selftest_reason_and_receipt
  selftest_named_values
  rm -rf "$T"
  [ "$cases" = "$SELFTEST_CASES" ] || { printf 'FAIL %s cases ran and %s were expected\n' "$cases" "$SELFTEST_CASES"; ok=0; }
  [ "$ok" = "1" ] && printf 'SELFTEST OK: %s/%s\n' "$SELFTEST_CASES" "$SELFTEST_CASES" && return 0
  printf 'SELFTEST FAILED\n'; return 1
}
