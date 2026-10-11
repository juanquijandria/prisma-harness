#!/bin/sh
# Prisma Harness. Documented in README.md, section "What is inside".
if [ "${1:-}" = "--selftest" ]; then . "$(cd "$(dirname "$0")" && pwd)/selftest-env.sh"; fi

HOOKS_DIR="${PRISMA_HOOKS_DIR:-$(cd "$(dirname "$0")" 2>/dev/null && pwd)}"
JQ=$(command -v jq)
PR_READY_COMMAND="$HOOKS_DIR/pr-ready.sh"
GATE_NAME="claim-ready-gate"
TRANSCRIPT_TAIL_LINES=400
DENIAL_WINDOW_WORDS=3
CLAIM_SEPARATOR='|'
SELFTEST_CASES=33
PRISMA_RECEIPT_SOURCED=1
. "$HOOKS_DIR/receipt.sh"
. "$HOOKS_DIR/github-remote.sh"
. "$HOOKS_DIR/pr-ready-codes.sh"

LAST_MESSAGE_JQ='reduce (inputs | fromjson? // empty | select(.isSidechain != true)) as $entry ({id: null, text: []};
  ($entry.message.content // "") as $content
  | if $entry.type == "user" and (($content | type) == "string" or any($content[]?; .type == "text")) then {id: null, text: []}
    elif $entry.type == "assistant" and any($content[]?; .type == "text") then
      [$content[] | select(.type == "text") | .text] as $said
      | if .id != null and .id == $entry.message.id then .text += $said else {id: $entry.message.id, text: $said} end
    else . end)
| .text | join("\n")'

CLAIMS_JQ='def ready_claim: "ready (to|for) merge|list[oa]s? para merge(ar)?";
def green_claim: "(is|are) green|en verde";
def readiness: "\\b(ready|list[oa]s?)\\b";
def negators: ["no", "not", "never", "nunca", "tampoco", "ni", "isnt", "arent", "isn'"'"'t", "aren'"'"'t"];
def own_clause: [splits("[,:;()]")] | last // "";
def denied($before): [$before | own_clause | ascii_downcase | splits("[^\\p{L}'"'"']+") | select(length > 0)] | .[-$window:]
  | any(.[]; . as $word | negators | index($word));
def said_with_denial($sentence; $pattern; $denial): any($sentence | match($pattern; "gi"); denied($sentence[0:.offset]) == $denial);
def url_refs: [match("github[.]com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)/pull/([0-9]+)"; "g") | "\(.captures[0].string)|\(.captures[1].string)"];
def repo_refs: [match("(?:^|[^A-Za-z0-9_./-])([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)#([0-9]+)(?![A-Za-z0-9_])"; "g") | "\(.captures[0].string)|\(.captures[1].string)"];
def bare_refs: gsub("[A-Za-z0-9_.:/-]*(github[.]com/[^ ]*|[A-Za-z0-9_.-]/[A-Za-z0-9_.-]+#[0-9]+)"; " ")
  | [match("#([0-9]+)(?![A-Za-z0-9_])"; "g") | "|\(.captures[0].string)"];
gsub("```[^`]*```"; " ")
| [splits("(?<=[.!?;])\\s+|\\n+")][]
| select(test("^\\s*¿|[?]\\s*$") | not)
| . as $sentence
| select(said_with_denial($sentence; ready_claim; false)
    or (said_with_denial($sentence; green_claim; false) and (said_with_denial($sentence; readiness; true) | not)))
| (url_refs + repo_refs + bare_refs)[]'

not_measured() {
  echo "WARN: the claim gate did not measure, $1." >&2
  receipt_append "$GATE_NAME" "$working_dir" not-measured
}

claims_in() {
  "$JQ" -Rrs --argjson window "$DENIAL_WINDOW_WORDS" "$CLAIMS_JQ" 2>/dev/null | tr -d '\r' | sort -u
}

claimed_prs() {
  if [ -n "$final_message" ]; then printf '%s' "$final_message" | claims_in; return; fi
  tail -n "$TRANSCRIPT_TAIL_LINES" "$1" | "$JQ" -nrR "$LAST_MESSAGE_JQ" 2>/dev/null | claims_in
}

judge_claim() {
  repo=${1:-$here}
  [ -n "$repo" ] || { not_measured "#$2 was claimed ready and this directory has no GitHub remote to say which repository it is in"; return; }
  [ -d "${working_dir:-.}" ] || { not_measured "the session folder $working_dir does not exist, so $repo#$2 was not measured"; return; }
  verdict=$(cd "${working_dir:-.}" && sh "$PR_READY_COMMAND" "$repo" "$2" 2>&1); rc=$?
  case "$rc" in
    "$EXIT_READY") ;;
    "$EXIT_NOT_READY") missing="$missing
You said $repo#$2 is ready, and it is not.
$(printf '%s\n' "$verdict" | grep -E '^ +FAIL ' | sed 's/^ *FAIL */- /')" ;;
    *) not_measured "pr-ready.sh could not measure $repo#$2" ;;
  esac
}

run_gate() {
  [ -n "$JQ" ] || { echo "WARN: the claim gate did not run, jq is missing." >&2; exit 0; }
  payload=$(cat)
  [ "$(printf '%s' "$payload" | "$JQ" -r '.stop_hook_active // false' 2>/dev/null)" = "true" ] && exit 0
  transcript=$(printf '%s' "$payload" | "$JQ" -r '.transcript_path // empty' 2>/dev/null)
  working_dir=$(printf '%s' "$payload" | "$JQ" -r '.cwd // empty' 2>/dev/null)
  final_message=$(printf '%s' "$payload" | "$JQ" -r '.last_assistant_message // empty' 2>/dev/null)
  [ -n "$final_message" ] || { [ -n "$transcript" ] && [ -f "$transcript" ]; } || { not_measured "it could not read the transcript"; exit 0; }
  claims=$(claimed_prs "$transcript")
  [ -n "$claims" ] || exit 0
  here=$(github_repos_of "$working_dir" origin | head -1)
  missing=""
  while IFS="$CLAIM_SEPARATOR" read -r repo number; do judge_claim "$repo" "$number"; done <<CLAIMS
$claims
CLAIMS
  [ -n "$missing" ] || exit 0
  receipt_append "$GATE_NAME" "$working_dir" blocked
  "$JQ" -n --arg reason "PRISMA claim gate:$missing
Fix what is missing, or say plainly that it is not ready yet and why, before you stop." '{decision: "block", reason: $reason}'
  exit 0
}

if [ "${1:-}" = "--selftest" ]; then
  . "$HOOKS_DIR/claim-ready-gate-tests.sh"
  selftest; exit $?
fi
run_gate
