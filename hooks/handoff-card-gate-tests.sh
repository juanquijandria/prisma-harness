#!/bin/sh
# Prisma Harness. Documented in README.md, section "What is inside". Loaded by handoff-card-gate.sh, not run alone.

FENCE='```'
FAILING_JQ_STATUS=3

expect() {
  cases=$((cases+1))
  if [ "$2" = "$3" ]; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s, expected [%s] and got [%s]\n' "$1" "$3" "$2"; ok=0; fi
}

CARD_HEAD='| Terminal | Por qué | Entrega | Orden | Reporta a | Se cierra |
|---|---|---|---|---|---|'
REAL_LAUNCH='cd ~/dev/bot/codigo && cc -n vigia-reclamos "Decision of 12/10, run PRISMA in the code lane"'
REAL_ROW='| `vigia-reclamos` | otro repo y termina en un despliegue | el cambio del bot con sus pruebas | en paralelo | esta sesión y el inbox | cuando avise que publicó |'

with_card() { printf '%s\n%s\n\n%s' "$CARD_HEAD" "$1" "$(in_fence "$2")"; }

in_fence() { printf 'Abre esta terminal.\n\n%s\n%s\n%s\n' "$FENCE" "$1" "$FENCE"; }

stop() {
  "$JQ" -nc --arg final "$1" --argjson active "${ACTIVE_FOR_TEST:-false}" --arg has_final "${NO_FINAL_FOR_TEST:-yes}" \
    '{session_id: "s", transcript_path: "/there/is/no/transcript.jsonl", cwd: "/repo/handoff", hook_event_name: "Stop", stop_hook_active: $active}
      + (if $has_final == "yes" then {last_assistant_message: $final} else {} end)' \
    | PRISMA_JQ="${JQ_FOR_TEST-$JQ}" PRISMA_LAUNCH_COMMANDS="${LAUNCH_FOR_TEST-}" sh "$GATE" 2>/dev/null
}

decision() {
  out=$(stop "$1"); rc=$?
  said_decision=$(printf '%s' "$out" | "$JQ" -r '.decision // empty' 2>/dev/null)
  printf '%s %s' "$rc" "${said_decision:-pass}"
}

selftest_launches() {
  LAUNCH_FOR_TEST="cc claude"
  expect "1 the real case, a named session with its mission and no card, blocks the stop" \
    "$(decision "$(in_fence "$REAL_LAUNCH")")" "0 block"
  expect "2 the same request with its card in a Spanish table passes" "$(decision "$(with_card "$REAL_ROW" "$REAL_LAUNCH")")" "0 pass"
  expect "15 a mission quoted across several lines is one launch and its name is read" \
    "$(decision "$(with_card "$REAL_ROW" 'cc -n vigia-reclamos "Decision of 12/10.
Run PRISMA in the code lane;
report to the main session"')")" "0 pass"
  expect "16 the same launch across lines with no card blocks" "$(decision "$(in_fence 'cc -n vigia-reclamos "Decision of 12/10.
Run PRISMA; report back"')")" "0 block"
  expect "17 a launch with no name blocks even with a card for another session" "$(decision "$(with_card "$REAL_ROW" 'claude "Read your mission in the plan"')")" "0 block"
  expect "18 a launch after a semicolon is read" "$(decision "$(in_fence 'cd ~/dev/bot; cc -n vigia-reclamos "the mission"')")" "0 block"
  expect "19 the name written as --name=value is read" "$(decision "$(with_card "$REAL_ROW" 'cc --name=vigia-reclamos "the mission"')")" "0 pass"
  expect "20 a variable set before the command does not hide the launch" "$(decision "$(in_fence 'PRISMA_VOICE=0 cc -n vigia-reclamos "the mission"')")" "0 block"
  expect "21 a quoted name is read" "$(decision "$(with_card "$REAL_ROW" 'cc -n "vigia-reclamos" "the mission"')")" "0 pass"
  expect "22 a row with five filled cells is not a card" \
    "$(decision "$(with_card '| vigia-reclamos | otro repo | el cambio del bot | en paralelo | esta sesión |' "$REAL_LAUNCH")")" "0 block"
  expect "23 a row with an empty cell is not a card" \
    "$(decision "$(with_card '| vigia-reclamos | otro repo | el cambio del bot |  | esta sesión | cuando publique |' "$REAL_LAUNCH")")" "0 block"
  expect "24 the name in a later cell and not in the first is not a card" \
    "$(decision "$(with_card '| T1 | vigia-reclamos | el cambio del bot | en paralelo | esta sesión | cuando publique |' "$REAL_LAUNCH")")" "0 block"
  expect "25 two launches with a card for one of them block" \
    "$(decision "$(with_card "$REAL_ROW" "$REAL_LAUNCH
cc -n vigia-docs \"update the docs\"")")" "0 block"
  expect "26 a card in English passes too" \
    "$(decision "$(with_card '| vigia-reclamos | another repository | the bot change and its tests | in parallel | this session | when it says it shipped |' "$REAL_LAUNCH")")" "0 pass"
  expect "41 the real case of 26/09, a session opened with flags and its mission said apart, blocks" \
    "$(decision "$(in_fence 'cd ~/dev/backoffice && claude --dangerously-skip-permissions --add-dir ~')")" "0 block"
  expect "42 an alias with flags only blocks" "$(decision "$(in_fence 'cd ~/vault && cc --add-dir ~/dev')")" "0 block"
  expect "43 a bare claude after cd opens a session and blocks" "$(decision "$(in_fence 'cd ~/dev/web && claude')")" "0 block"
  expect "44 a version check is not a session to open" "$(decision "$(in_fence 'claude --version')")" "0 pass"
  expect "45 a name that is only part of a longer name in the first cell has no card" \
    "$(decision "$(with_card '| vigia-reclamos-plata | otro repo | el cambio | en paralelo | esta sesión | cuando publique |' 'cc -n vigia "the mission"')")" "0 block"
  expect "46 a variable with a quoted value before the command does not hide the launch" \
    "$(decision "$(in_fence 'MODE="a b" cc -n vigia-reclamos "the mission"')")" "0 block"
  expect "47 a code block left open runs to the end of the message and its launch is read" \
    "$(decision "$(printf 'Abre esta terminal.\n\n%s\n%s\n' "$FENCE" "$REAL_LAUNCH")")" "0 block"
  expect "48 a name with a space finds its row" \
    "$(decision "$(with_card '| fix login | otro repo | el arreglo | en paralelo | esta sesión | cuando publique |' 'cc -n "fix login" "the mission"')")" "0 pass"
  expect "27 a row inside the code block is not a card" "$(decision "$(in_fence "$REAL_ROW
$REAL_LAUNCH")")" "0 block"
  unset LAUNCH_FOR_TEST
}

selftest_alias_adds() {
  LAUNCH_FOR_TEST="cc"
  expect "49 declaring an alias keeps claude watched" "$(decision "$(in_fence 'claude -n vigia-reclamos "the mission"')")" "0 block"
  expect "50 the declared alias is watched" "$(decision "$(in_fence "$REAL_LAUNCH")")" "0 block"
  unset LAUNCH_FOR_TEST
}

selftest_not_launches() {
  LAUNCH_FOR_TEST=""
  expect "3 a headless run with -p is not a session to open" "$(decision "$(in_fence 'claude -p "summarize the diff"')")" "0 pass"
  expect "4 a headless run with --print is not a session to open" "$(decision "$(in_fence 'claude --print "summarize the diff"')")" "0 pass"
  expect "5 reopening a session with --resume is not a new one" "$(decision "$(in_fence 'claude --resume 4fd701 "go on"')")" "0 pass"
  expect "6 reopening a session with -r is not a new one" "$(decision "$(in_fence 'claude -r 4fd701 "go on"')")" "0 pass"
  expect "7 continuing with --continue is not a new session" "$(decision "$(in_fence 'claude --continue "go on"')")" "0 pass"
  expect "8 continuing with -c is not a new session" "$(decision "$(in_fence 'claude -c "go on"')")" "0 pass"
  expect "10 the plugin update command of the README is not a session to open" "$(decision "$(in_fence 'claude plugin marketplace update
claude plugin update prisma-harness@prisma-harness')")" "0 pass"
  expect "11 a subcommand such as setup-token is not a session to open" "$(decision "$(in_fence 'claude setup-token')")" "0 pass"
  expect "12 an alias that nobody declared is not a launch" "$(decision "$(in_fence "$REAL_LAUNCH")")" "0 pass"
  expect "13 a launch written in prose outside a code block is not read" "$(decision 'Abre una terminal con cc -n vigia-reclamos "la misión" cuando puedas.')" "0 pass"
  expect "14 a command whose first word only contains claude is not a launch" "$(decision "$(in_fence 'echo claude -n notes "hello" && myclaude -n x "y"')")" "0 pass"
  expect "9 the -p inside the quoted mission does not make it headless" "$(decision "$(in_fence 'claude -n tickets "run the build, never with -p"')")" "0 block"
  unset LAUNCH_FOR_TEST
}

reason_says() { stop "$1" | "$JQ" -r '.reason // empty' 2>/dev/null | grep -F -- "$2" >/dev/null && echo says || echo silent; }
receipt_count() { grep -c "	$GATE_NAME	.*	$1\$" "$PRISMA_RECEIPT_FILE" 2>/dev/null | tr -d ' '; }
receipt_lines() { wc -l < "$PRISMA_RECEIPT_FILE" | tr -d ' '; }

selftest_reason_and_receipt() {
  : > "$PRISMA_RECEIPT_FILE"
  LAUNCH_FOR_TEST="cc claude"
  real_case=$(in_fence "$REAL_LAUNCH")
  expect "28 the reason names the session that has no card" "$(reason_says "$real_case" 'vigia-reclamos')" "says"
  expect "29 the reason shows the launch that has no name" "$(reason_says "$(in_fence 'claude "Read your mission"')" 'claude "…"')" "says"
  expect "30 the reason lists the six cells of the card" "$(reason_says "$real_case" 'why it is another session, what it delivers, its order, who it reports to, and when it closes')" "says"
  expect "31 the reason sends a task that needs no other session back to this one or a subagent" "$(reason_says "$real_case" 'stays in this session or goes to a subagent')" "says"
  blocked_before=$(receipt_count blocked)
  expect "32 a block leaves one line in the receipt" "$(decision "$real_case") $(($(receipt_count blocked) - blocked_before))" "0 block 1"
  ACTIVE_FOR_TEST=true
  expect "33 a stop that a stop hook already continued is let through" "$(decision "$real_case")" "0 pass"
  unset ACTIVE_FOR_TEST
  expect "34 the declared escape on its own line outside the code lets the stop through and leaves its line" \
    "$(decision "$real_case
PRISMA_HANDOFF_OK=1") $(receipt_count escaped)" "0 pass 1"
  expect "35 the escape inside the code block does not count" "$(decision "$(in_fence "PRISMA_HANDOFF_OK=1
$REAL_LAUNCH")")" "0 block"
  JQ_FOR_TEST=""
  expect "36 with no jq the stop goes through and the receipt says not measured" "$(decision "$real_case") $(receipt_count not-measured)" "0 pass 1"
  unset JQ_FOR_TEST
  NO_FINAL_FOR_TEST=no
  expect "37 an event with no final message goes through and the receipt says not measured" "$(decision "$real_case") $(receipt_count not-measured)" "0 pass 2"
  unset NO_FINAL_FOR_TEST
  JQ_FOR_TEST="$T/jq-that-fails-on-the-message"
  expect "38 a jq that fails on the message is not a pass, the receipt says not measured" "$(decision "$real_case") $(receipt_count not-measured)" "0 pass 3"
  unset JQ_FOR_TEST
  lines_before=$(receipt_lines)
  expect "39 a message with no launch writes nothing to the receipt" "$(decision "Listo, ya está.") $(receipt_lines)" "0 pass $lines_before"
  expect "40 an escape with no launch to excuse writes nothing to the receipt" "$(decision "Listo.
PRISMA_HANDOFF_OK=1") $(receipt_lines)" "0 pass $lines_before"
  unset LAUNCH_FOR_TEST
}

selftest() {
  GATE=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
  T=$(mktemp -d)
  printf '#!/bin/sh\ncase "$*" in *-Rrs*) exit %s ;; esac\nexec "%s" "$@"\n' "$FAILING_JQ_STATUS" "$JQ" > "$T/jq-that-fails-on-the-message"
  chmod +x "$T/jq-that-fails-on-the-message"
  ok=1; cases=0
  selftest_launches
  selftest_not_launches
  selftest_alias_adds
  selftest_reason_and_receipt
  rm -rf "$T"
  [ "$cases" = "$SELFTEST_CASES" ] || { printf 'FAIL %s cases ran and %s were expected\n' "$cases" "$SELFTEST_CASES"; ok=0; }
  [ "$ok" = "1" ] && printf 'SELFTEST OK: %s/%s\n' "$SELFTEST_CASES" "$SELFTEST_CASES" && return 0
  printf 'SELFTEST FAILED\n'; return 1
}
