#!/bin/sh
# Prisma Harness. Documented in README.md, section "What is inside", and in STYLE.md.
if [ "${1:-}" = "--selftest" ]; then . "$(cd "$(dirname "$0")" && pwd)/selftest-env.sh"; fi

SELF=$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")
DATA_DIR="${CLAUDE_PLUGIN_DATA:-$HOME/.prisma-harness}"
PROJECT="${CLAUDE_PROJECT_DIR:-$PWD}"

announcement_text() {
  cat <<'ANNOUNCE'
This is the first session of this project with these rules. Tell the person, in one line of your first reply, that the Prisma Harness plugin is setting the writing rules of this session and that PRISMA_VOICE=0 in their Claude Code settings turns them off.
ANNOUNCE
}

first_session_here() {
  marker_dir="$DATA_DIR/announced"
  marker="$marker_dir/$(printf '%s' "$PROJECT" | cksum | cut -d' ' -f1)"
  [ -f "$marker" ] && return 1
  mkdir -p "$marker_dir" 2>/dev/null || return 0
  : > "$marker" 2>/dev/null
  return 0
}

voice_text() {
  cat <<'VOICE'
PRISMA WRITING RULES, active in this session. They apply to every reply and every page you write.
1. The answer goes first. A closed question gets its answer in the first line, before any heading.
2. Any reply longer than a few lines is structured with short level-1 headings (#) that end in a colon, and the key point of each section goes in bold at its start. No horizontal rules between sections.
3. One idea per sentence, with a verb. No em-dashes, no parentheticals, no arrows, no colons inside prose. A comma, a period or "and" states how two ideas relate.
4. Numbers and code stay out of prose. A measurement goes on its own line or in a table with the date it was measured; a command goes in a code block.
5. Every proper name gets its role the first time or does not appear. Every "today" becomes an absolute date.
6. Every figure that leaves the machine is a hypothesis until measured by two routes. Say what you verified, what you did not, and what you tried when you could not.
7. A text the reader will paste elsewhere goes between two lines of the character ═, with nothing of yours inside, never in a code block or a quote.
8. When you write Spanish here it is Peruvian, tú and never vos. Code, identifiers and commits are in English.
VOICE
}

if [ "$1" = "--selftest" ]; then
  ok=1
  out=$(printf '{}' | /bin/sh "$SELF"); rc=$?
  if [ "$rc" -eq 0 ] && command -v jq >/dev/null 2>&1 && printf '%s' "$out" | jq -e '.hookSpecificOutput.hookEventName=="SessionStart" and (.hookSpecificOutput.additionalContext | contains("The answer goes first"))' >/dev/null 2>&1; then
    printf 'PASS emits valid SessionStart JSON with the rules\n'
  else printf 'FAIL output: %s (rc=%s)\n' "$out" "$rc"; ok=0; fi
  n=$(voice_text | grep -c '^[0-9]\.')
  if [ "$n" -eq 8 ]; then printf 'PASS carries 8 numbered rules\n'; else printf 'FAIL carries %s rules\n' "$n"; ok=0; fi
  if voice_text | grep -q '—'; then printf 'FAIL the rules contain an em-dash\n'; ok=0; else printf 'PASS the rules obey their own em-dash rule\n'; fi
  fresh_project=$(mktemp -d)
  first=$(printf '{}' | CLAUDE_PROJECT_DIR="$fresh_project" /bin/sh "$SELF")
  second=$(printf '{}' | CLAUDE_PROJECT_DIR="$fresh_project" /bin/sh "$SELF")
  if printf '%s' "$first" | grep -q 'PRISMA_VOICE'; then printf 'PASS the first session of a project is told what set the rules and how to switch them off\n'; else printf 'FAIL the first session was never told: %s\n' "$first"; ok=0; fi
  if printf '%s' "$second" | grep -q 'PRISMA_VOICE'; then printf 'FAIL every session repeats the announcement\n'; ok=0; else printf 'PASS the announcement is made once per project and not every session\n'; fi
  out=$(printf '{}' | PRISMA_VOICE=0 /bin/sh "$SELF")
  if [ -z "$out" ]; then printf 'PASS PRISMA_VOICE=0 switches it off\n'; else printf 'FAIL PRISMA_VOICE=0 still emitted output\n'; ok=0; fi
  [ "$ok" -eq 1 ] && printf 'SELFTEST OK: 6/6\n' && exit 0
  printf 'SELFTEST FAILED\n'; exit 1
fi

[ "${PRISMA_VOICE:-1}" = "1" ] || exit 0
cat >/dev/null
session_text() {
  voice_text
  first_session_here && announcement_text
}
command -v jq >/dev/null 2>&1 || { session_text; exit 0; }
session_text | jq -Rs '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:.}}'
exit 0
