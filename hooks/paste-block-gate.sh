#!/bin/sh
# Prisma Harness. Documented in README.md, section "What is inside".
if [ "${1:-}" = "--selftest" ]; then . "$(cd "$(dirname "$0")" && pwd)/selftest-env.sh"; fi

HOOKS_DIR="${PRISMA_HOOKS_DIR:-$(cd "$(dirname "$0")" 2>/dev/null && pwd)}"
JQ="${PRISMA_JQ-$(command -v jq)}"
GATE_NAME="paste-block-gate"
ESCAPE="PRISMA_PASTE_OK=1"
FENCE_MIN_CHARS=3
MARKER_MAX_CHARS=40
SELFTEST_CASES=55
PRISMA_RECEIPT_SOURCED=1
. "$HOOKS_DIR/receipt.sh"

HOLES_JQ='def fence: test("^\\s*═{\($fence_min),}\\s*$");
def split_blocks: reduce split("\n")[] as $line ({inside: false, open: [], closed: [], outside: []};
  if ($line | fence) then (if .inside then .closed += .open else .outside += .open end) | .open = [] | .inside = (.inside | not)
  elif .inside then .open += [$line] else .outside += [$line] end) | .outside += .open;
def html_tags: ["a", "b", "i", "u", "p", "s", "br", "hr", "em", "strong", "div", "span", "li", "ul", "ol",
  "sub", "sup", "small", "tr", "td", "th", "table", "h1", "h2", "h3", "h4", "h5", "h6"];
def trailing_dots: match("(?:=[ \\t]*\\S*|:[ \\t]*\\S*\\p{L}\\S*)(?:…|\\.\\.\\.)(?=[\\s,.;:!?)]|$)"; "g") | .string;
def angle_marker: match("(?<![\\p{L}\\p{N}_])<([\\p{L}][\\p{L}\\p{N} _-]{0,\($marker_max - 2)})>"; "g")
  | select(.captures[0].string | ascii_downcase | IN(html_tags[]) | not) | .string;
def placeholder_word: match("\\b(?:(?<!\\p{Lu}\\p{Lu} )TODO|XXX|FIXME)\\b"; "g") | .string;
def bracket_marker: match("(?<![\\p{L}\\p{N}_\\]\\)])\\[[\\p{L}][^\\[\\]]{1,\($marker_max - 2)}(?<! )\\](?![(\\[])"; "g") | .string;
def unquoted: gsub("(?<value>[=:][ \\t]*(?:\"[^\"]*\"|“[^”]*”))|\"[^\"]*\"|“[^”]*”"; .value // " ");
def placeholder_parts: "aqui|aquí|here|placeholder|changeme|your|tu|reemplazar|replace|x{3,}";
def named_value: match("[=:][ \\t]*([\\p{L}\\p{N}]+(?:[_-][\\p{L}\\p{N}]+)+)"; "g")
  | select(.captures[0].string | test("(?:^|[_-])(?:" + placeholder_parts + ")(?:[_-]|$)"; "i")) | .captures[0].string;
def holes: unquoted | [trailing_dots, angle_marker, placeholder_word, bracket_marker, named_value];
split_blocks
| [.closed[] | . as $line | holes[] | "- \(.) in the line: \($line)"] as $found
| if $found == [] then empty
  elif any(.outside[]; test("^\\s*" + $escape + "\\s*$")) then "escaped"
  else $found[] end'

not_measured() {
  echo "WARN: the paste block gate did not measure, $1." >&2
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
    | "$JQ" -Rrs --arg escape "$ESCAPE" \
      --argjson fence_min "$FENCE_MIN_CHARS" --argjson marker_max "$MARKER_MAX_CHARS" "$HOLES_JQ" 2>/dev/null) \
    || { not_measured "jq could not read the final message"; exit 0; }
  [ -n "$found" ] || exit 0
  [ "$found" = "escaped" ] && { receipt_append "$GATE_NAME" "$working_dir" escaped; exit 0; }
  receipt_append "$GATE_NAME" "$working_dir" blocked
  "$JQ" -n --arg reason "PRISMA paste block gate: a block between two lines of ═ is pasted as it is, and this one has a hole to fill.
$found
Get the real value before you open the block, take that line out of the message, or ask the person for the value first.
Wanting the message ready before the value exists is not a reason to keep the hole, take the line out and say outside the block what is still missing.
$ESCAPE, on a line of its own outside the block, is only when the person asked for that hole in so many words." '{decision: "block", reason: $reason}'
  exit 0
}

if [ "${1:-}" = "--selftest" ]; then
  . "$HOOKS_DIR/paste-block-gate-tests.sh"
  selftest; exit $?
fi
run_gate
