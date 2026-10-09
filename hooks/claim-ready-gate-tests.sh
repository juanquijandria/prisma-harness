#!/bin/sh
# Prisma Harness. Documented in README.md, section "What is inside". Loaded by claim-ready-gate.sh, not run alone.

. "$HOOKS_DIR/pr-ready-fixtures.sh"

said() {
  transcript="$T/transcript-$cases.jsonl"
  "$JQ" -nc --arg text "$1" --arg earlier "${2:-}" --arg turn "${3:-same}" '
    def says($id; $words): {type: "assistant", message: {id: $id, role: "assistant", content: [{type: "text", text: $words}]}};
    {type: "user", message: {role: "user", content: "how is it going"}},
    (if $earlier == "" then empty else says("m0"; $earlier) end),
    (if $turn == "same" then empty else {type: "user", message: {role: "user", content: "and now"}} end),
    {type: "assistant", message: {id: "m1", role: "assistant", content: [{type: "tool_use", id: "t1", name: "Bash", input: {}}]}},
    {type: "user", message: {role: "user", content: [{type: "tool_result", tool_use_id: "t1", content: "done"}]}},
    (if $text == "" then empty else says("m2"; $text) end)' > "$transcript"
}

stop() {
  serve
  "$JQ" -nc --arg transcript "${TRANSCRIPT_FOR_TEST:-$transcript}" --arg cwd "${CWD_FOR_TEST:-$GITHUB_CLONE}" \
    --argjson active "${ACTIVE_FOR_TEST:-false}" --arg final "${FINAL_FOR_TEST-}" --arg has_final "${FINAL_FOR_TEST+yes}" \
    '{session_id: "s", transcript_path: $transcript, cwd: $cwd, hook_event_name: "Stop", stop_hook_active: $active}
      + (if $has_final == "yes" then {last_assistant_message: $final} else {} end)' \
    | PRISMA_GH="${GH_FOR_TEST:-$FAKE_GH_DIR/gh}" sh "$GATE" 2>/dev/null
}

decision() {
  out=$(stop); rc=$?
  said_decision=$(printf '%s' "$out" | "$JQ" -r '.decision // empty' 2>/dev/null)
  printf '%s %s' "$rc" "${said_decision:-pass}"
}

reason_names() { stop | "$JQ" -r '.reason // empty' 2>/dev/null | grep -F -- "$1" >/dev/null && echo names || echo silent; }
receipt_count() { grep -c "	claim-ready-gate	.*	$1\$" "$PRISMA_RECEIPT_FILE" 2>/dev/null | tr -d ' '; }

not_ready() { green_scenario; COMMENTS='[]'; unset TRANSCRIPT_FOR_TEST CWD_FOR_TEST ACTIVE_FOR_TEST FINAL_FOR_TEST; }
ready() { green_scenario; unset TRANSCRIPT_FOR_TEST CWD_FOR_TEST ACTIVE_FOR_TEST FINAL_FOR_TEST; }

selftest_claims() {
  not_ready; said "PR #7 listo para mergear."
  expect "1 a claim that a PR is ready when it is not blocks the stop" "$(decision)" "0 block"
  ready; said "PR #7 listo para mergear."
  expect "2 the same claim on a PR that is ready lets the stop through" "$(decision)" "0 pass"
  not_ready; said "PR #7 listo para mergear."
  expect "3 the reason names what is missing" "$(reason_names 'claude[bot]')" "names"
  not_ready; said "https://github.com/$FAKE_REPO/pull/7 is ready to merge"; CWD_FOR_TEST="$T"
  expect "4 a GitHub link names the PR from any directory" "$(decision)" "0 block"
  not_ready; said "Los PRs #7 y #8 quedaron listos para merge"
  expect "5 the plural and the short form are claims too" "$(decision)" "0 block"
  not_ready; said "El PR #7 está en verde"
  expect "6 en verde next to a PR is a claim" "$(decision)" "0 block"
  not_ready; said "No falla: #7 listo para mergear."
  expect "7 a no in an earlier clause does not deny the claim" "$(decision)" "0 block"
  not_ready; said "El #7 sin conflictos y listo para mergear."
  expect "8 sin before a claim does not deny it" "$(decision)" "0 block"
}

selftest_not_claims() {
  not_ready; said "El #7 no está listo para mergear todavía."
  expect "9 a claim denied in Spanish is not a claim" "$(decision)" "0 pass"
  not_ready; said "#7 is not ready to merge yet"
  expect "10 a claim denied in English is not a claim" "$(decision)" "0 pass"
  not_ready; said "¿El #7 está listo para mergear?"
  expect "11 a question is not a claim" "$(decision)" "0 pass"
  not_ready; said "El CI está en verde."
  expect "12 en verde with no PR named is not a claim" "$(decision)" "0 pass"
  not_ready; said "Me equivoqué, todavía falta la revisión." "PR #7 listo para mergear."
  expect "13 a claim corrected later in the same turn does not count, only the last message does" "$(decision)" "0 pass"
  not_ready; said "" "PR #7 listo para mergear." next
  expect "14 a claim from an earlier turn is not judged again when the last turn said nothing" "$(decision)" "0 pass"
  not_ready; said 'Para avisar escribe esto.
```
PR #7 listo para mergear
```'
  expect "15 a claim inside a code block is not a claim" "$(decision)" "0 pass"
  not_ready; said "Revisando."; FINAL_FOR_TEST="PR #7 listo para mergear."
  expect "16 the final message the event carries is read when the transcript lags behind it" "$(decision)" "0 block"
  not_ready; said "PR #7 listo para mergear."; FINAL_FOR_TEST="Me equivoqué, todavía falta la revisión."
  expect "17 the final message the event carries wins over the transcript" "$(decision)" "0 pass"
  not_ready; said "PR #7 listo para mergear."; ACTIVE_FOR_TEST=true
  expect "18 a stop that a stop hook already continued is let through" "$(decision)" "0 pass"
  not_ready; said "La PR #7 está lista para mergear."
  expect "23 a feminine claim in Spanish is a claim" "$(decision)" "0 block"
  not_ready; said "PR #7 is ready for merge."
  expect "24 ready for merge is a claim" "$(decision)" "0 block"
  not_ready; said "PR #7 is green."
  expect "25 is green is a claim" "$(decision)" "0 block"
  not_ready; said "El #7 no quedaría listo para mergear."
  expect "26 a denial with an accented word is a denial" "$(decision)" "0 pass"
  not_ready; said "El #7 no está todavía listo para mergear."
  expect "27 a denial three words before the claim is a denial" "$(decision)" "0 pass"
}

selftest_denied_readiness() {
  not_ready; said "El #7 está en verde, pero no está listo."
  expect "29 green in a sentence that denies the PR is ready is not a claim" "$(decision)" "0 pass"
  not_ready; said "The CI of #7 is green, but it is not ready to merge."
  expect "30 the same in English is not a claim" "$(decision)" "0 pass"
  not_ready; said "#8 no está listo, pero #7 está listo para mergear."
  expect "31 a ready to merge that is not denied stays a claim beside a denied one" "$(decision)" "0 block"
  not_ready; said "#8 is not ready, but #7 is ready to merge."
  expect "32 the same in English stays a claim" "$(decision)" "0 block"
}

selftest_receipt() {
  : > "$PRISMA_RECEIPT_FILE"
  not_ready; said "PR #7 listo para mergear."
  expect "19 a block leaves its line in the receipt" "$(decision) $(receipt_count blocked)" "0 block 1"
  not_ready; said "PR #7 listo para mergear."; CWD_FOR_TEST="$T"
  expect "20 a bare number with no GitHub repo here is not measured and says so" "$(decision) $(receipt_count not-measured)" "0 pass 1"
  not_ready; said "PR #7 listo para mergear."; GH_FOR_TEST="$T/there-is-no-gh-here"
  expect "21 a gh that cannot run lets the stop through and says so" "$(decision) $(receipt_count not-measured)" "0 pass 2"
  unset GH_FOR_TEST
  not_ready; TRANSCRIPT_FOR_TEST="$T/there-is-no-transcript.jsonl"
  expect "22 a missing transcript lets the stop through and says so" "$(decision) $(receipt_count not-measured)" "0 pass 3"
  not_ready; said "https://github.com/$FAKE_REPO/pull/7 listo para mergear."; CWD_FOR_TEST="$T/there-is-no-folder-here"
  expect "28 a session folder that does not exist lets the stop through and says so" "$(decision) $(receipt_count not-measured)" "0 pass 4"
}

selftest() {
  GATE=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
  T=$(mktemp -d)
  install_fake_gh "$T"
  GITHUB_CLONE="$T/clone"; mkdir -p "$GITHUB_CLONE"
  git -C "$GITHUB_CLONE" init -q && git -C "$GITHUB_CLONE" remote add origin "git@github.com:$FAKE_REPO.git"
  ok=1; cases=0
  selftest_claims
  selftest_not_claims
  selftest_denied_readiness
  selftest_receipt
  rm -rf "$T"
  [ "$cases" = "$SELFTEST_CASES" ] || { printf 'FAIL %s cases ran and %s were expected\n' "$cases" "$SELFTEST_CASES"; ok=0; }
  [ "$ok" = "1" ] && printf 'SELFTEST OK: %s/%s\n' "$SELFTEST_CASES" "$SELFTEST_CASES" && return 0
  printf 'SELFTEST FAILED\n'; return 1
}
