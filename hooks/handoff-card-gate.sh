#!/bin/sh
# Prisma Harness. Documented in README.md, section "What is inside".
if [ "${1:-}" = "--selftest" ]; then . "$(cd "$(dirname "$0")" && pwd)/selftest-env.sh"; fi

HOOKS_DIR="${PRISMA_HOOKS_DIR:-$(cd "$(dirname "$0")" 2>/dev/null && pwd)}"
JQ="${PRISMA_JQ-$(command -v jq)}"
GATE_NAME="handoff-card-gate"
ESCAPE="PRISMA_HANDOFF_OK=1"
NOT_A_NEW_SESSION_FLAGS="-p|--print|-r|--resume|-c|--continue|-v|--version|-h|--help"
SUBCOMMAND_PATTERN="^[a-z][a-z-]*$"
NAME_FLAG_SHORT="-n"
NAME_FLAG_LONG="--name"
DEFAULT_LAUNCH_COMMANDS=claude
LAUNCH_COMMANDS="$DEFAULT_LAUNCH_COMMANDS ${PRISMA_LAUNCH_COMMANDS:-}"
ASSIGNMENT_PATTERN="^[A-Za-z_][A-Za-z0-9_]*="
NAME_SEPARATOR_PATTERN='[^\p{L}\p{N}_.-]+'
CARD_CELLS=6
SELFTEST_CASES=50
PRISMA_RECEIPT_SOURCED=1
. "$HOOKS_DIR/receipt.sh"

LAUNCHES_JQ='def fence: test("^\\s*(```|~~~)");
def split_fences: reduce split("\n")[] as $line ({inside: false, code: [], prose: [], block: []};
  if ($line | fence) then (if .inside then .code += [.block | join("\n")] | .block = [] else . end) | .inside = (.inside | not)
  elif .inside then .block += [$line] else .prose += [$line] end)
  | if .inside then .code += [.block | join("\n")] else . end;
def tokens: [match("(?<dq>\"(?:[^\"\\\\]|\\\\.)*\")|(?<sq>\u0027[^\u0027]*\u0027)|(?<cont>\\\\\n)|(?<sep>&&|\\|\\||[;\n|&])|(?<ws>[ \t]+)|(?<word>(?:[^\\s;&|\"\u0027]+|\"(?:[^\"\\\\]|\\\\.)*\"|\u0027[^\u0027]*\u0027)+)|(?<other>.)"; "g")
  | [.captures[] | select(.string != null)][0]
  | if .name == "dq" or .name == "sq" then {q: true, text: .string[1:-1]}
    elif .name == "word" then {q: false, text: .string}
    elif .name == "sep" or .name == "other" then {sep: true}
    else empty end];
def segments: reduce (tokens[], {sep: true}) as $t ({done: [], open: []};
  if $t.sep then (if .open == [] then . else .done += [.open] | .open = [] end) else .open += [$t] end) | .done;
def command_words: . as $t | ([range(length)] | map(select($t[.].q or ($t[.].text | test($assignment) | not))) | first) as $i
  | if $i == null then [] else $t[$i:] end;
def launch($words): command_words
  | select(length > 0 and (.[0].q | not) and (.[0].text | IN($words[])))
  | .[1:] as $args
  | select(any($args[]; (.q | not) and (.text | test("^(" + $headless + ")(=.*)?$"))) | not)
  | select(($args[0] // {q: true}) | .q or (.text | test($subcommand) | not))
  | ([range($args | length) | select(($args[.].q | not) and ($args[.].text | IN($short, $long)))] | first) as $flag
  | {name: (if $flag != null then $args[$flag + 1].text
            else ([$args[] | select(.q | not) | .text | select(startswith($long + "=")) | ltrimstr($long + "=") | gsub("[\"\u0027]"; "")] | first) end),
     shown: ([.[] | if .q then "\"…\"" else .text end] | join(" "))};
def table_rows: .[] | select(test("^\\s*\\|") and (test("^[\\s|:-]+$") | not))
  | sub("^\\s*\\|"; "") | sub("\\|\\s*$"; "") | [split("|")[] | gsub("^\\s+|\\s+$"; "")];
def first_cell_names($name): (.[0] | gsub("[`*]"; "") | gsub("^\\s+|\\s+$"; "")) as $cell
  | $cell == $name or ([$cell | splits($separator)] | index([$name]) != null);
def carded($rows): .name as $name | any($rows[]; first_cell_names($name) and length >= $cells and all(.[]; length > 0));
($launch | [splits("\\s+")] | map(select(length > 0))) as $words
| split_fences
| [.prose | table_rows] as $rows
| .prose as $prose
| [.code[] | segments[] | launch($words) | select(carded($rows) | not)]
| if . == [] then empty
  elif any($prose[]; test("^\\s*" + $escape + "\\s*$")) then "escaped"
  else .[] | if .name == null then "- a session launched without \($short), so no card can name it: \(.shown)"
        else "- no row of \($cells) filled cells whose first cell names \(.name)" end end'

not_measured() {
  echo "WARN: the handoff card gate did not measure, $1." >&2
  receipt_append "$GATE_NAME" "$working_dir" not-measured
}

run_gate() {
  [ -n "$JQ" ] || { not_measured "jq is missing"; exit 0; }
  payload=$(cat)
  [ "$(printf '%s' "$payload" | "$JQ" -r '.stop_hook_active // false' 2>/dev/null)" = "true" ] && exit 0
  working_dir=$(printf '%s' "$payload" | "$JQ" -r '.cwd // empty' 2>/dev/null)
  [ "$(printf '%s' "$payload" | "$JQ" -r 'has("last_assistant_message")' 2>/dev/null)" = "true" ] \
    || { not_measured "it could not read a final message in the stop event"; exit 0; }
  found=$(printf '%s' "$payload" | "$JQ" -r '.last_assistant_message // ""' 2>/dev/null \
    | "$JQ" -Rrs --arg launch "$LAUNCH_COMMANDS" --arg escape "$ESCAPE" --arg headless "$NOT_A_NEW_SESSION_FLAGS" --arg subcommand "$SUBCOMMAND_PATTERN" \
      --arg assignment "$ASSIGNMENT_PATTERN" --arg separator "$NAME_SEPARATOR_PATTERN" \
      --arg short "$NAME_FLAG_SHORT" --arg long "$NAME_FLAG_LONG" --argjson cells "$CARD_CELLS" "$LAUNCHES_JQ" 2>/dev/null) \
    || { not_measured "jq could not read the final message"; exit 0; }
  [ -n "$found" ] || exit 0
  [ "$found" = "escaped" ] && { receipt_append "$GATE_NAME" "$working_dir" escaped; exit 0; }
  receipt_append "$GATE_NAME" "$working_dir" blocked
  "$JQ" -n --arg reason "PRISMA handoff card gate: this message asks the person to open another session, and the request does not carry its card.
$found
Every session you ask for gets a name with $NAME_FLAG_SHORT, and a row in a table, outside the code block, whose first cell is that name and whose $CARD_CELLS cells are filled, in this order, the session, why it is another session, what it delivers, its order, who it reports to, and when it closes.
Another session is for another ticket of a plan that does not fit one session, another repository, another lane with its own plan, or a deploy. Anything else stays in this session or goes to a subagent.
$ESCAPE, on a line of its own outside the code block, is only when the person asked for a session without its card." '{decision: "block", reason: $reason}'
  exit 0
}

if [ "${1:-}" = "--selftest" ]; then
  . "$HOOKS_DIR/handoff-card-gate-tests.sh"
  selftest; exit $?
fi
run_gate
