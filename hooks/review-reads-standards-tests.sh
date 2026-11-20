#!/bin/sh
# Prisma Harness. Documented in README.md, section "What is inside". Loaded by review-reads-standards.sh, not run alone.

expect() {
  cases=$((cases+1))
  if [ "$2" = "$3" ]; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s, expected [%s] and got [%s]\n' "$1" "$3" "$2"; ok=0; fi
}

new_repo() {
  repo=$(mktemp -d)
  git -C "$repo" init -q 2>/dev/null
  printf '# Project rules\nNo comments.\n' > "$repo/CLAUDE.md"
  mkdir -p "$repo/rules"
  printf '# Code rules\nSeven sections.\n' > "$repo/rules/code-rules.md"
  transcript="$repo/agent.jsonl"
}

prompt_line() {
  "$JQ" -nc --arg text "$1" '{type: "user", message: {role: "user", content: $text}}' > "$transcript"
}

review_prompt() {
  prompt_line "Invoke the skill \`prisma-harness:$REVIEW_SKILL\` and follow it.
- Fixed point: main.
- Plan record: $repo/plan.md
- $1"
}

read_call() {
  "$JQ" -nc --arg id "$1" --arg path "$2" '{type: "assistant", message: {content: [{type: "tool_use", id: $id, name: "Read", input: {file_path: $path}}]}}' >> "$transcript"
}

failed_result() {
  "$JQ" -nc --arg id "$1" '{type: "user", message: {content: [{type: "tool_result", tool_use_id: $id, is_error: true, content: "File does not exist."}]}}' >> "$transcript"
}

shell_call() {
  "$JQ" -nc --arg command "$1" '{type: "assistant", message: {content: [{type: "tool_use", id: "tu_shell", name: "Bash", input: {command: $command}}]}}' >> "$transcript"
}

subagent_stop() {
  "$JQ" -nc --arg transcript "${TRANSCRIPT_FOR_TEST-$transcript}" --arg cwd "${CWD_FOR_TEST-$repo}" --argjson active "${ACTIVE_FOR_TEST:-false}" --arg agent_type "${AGENT_TYPE_FOR_TEST:-general-purpose}" \
    '{hook_event_name: "SubagentStop", agent_type: $agent_type, agent_transcript_path: $transcript, transcript_path: "/there/is/no/parent.jsonl", cwd: $cwd, stop_hook_active: $active}' \
    | PRISMA_JQ="${JQ_FOR_TEST-$JQ}" sh "$GATE" 2>"$repo/stderr.txt"
}

handback_call() {
  "$JQ" -nc --arg id "$1" '{type: "assistant", message: {content: [{type: "tool_use", id: $id, name: "SubagentHandback", input: {message: "the report"}}]}}' >> "$transcript"
}

gate_feedback() {
  "$JQ" -nc --arg id "$1" --arg text "PreToolUse:SubagentHandback hook error: $GATE_SIGNATURE: this review has not opened every source" \
    '{type: "user", message: {content: [{type: "tool_result", tool_use_id: $id, is_error: true, content: $text}]}}' >> "$transcript"
}

handback_attempt() {
  "$JQ" -nc --arg parent "$repo/parent.jsonl" --arg cwd "$repo" --arg tool "${TOOL_FOR_TEST:-SubagentHandback}" \
    '{hook_event_name: "PreToolUse", tool_name: $tool, tool_input: {message: "the report"}, agent_type: "general-purpose", agent_id: "a1", transcript_path: $parent, cwd: $cwd}' \
    | PRISMA_JQ="$JQ" sh "$GATE" 2>"$repo/stderr.txt"
}

verdict() {
  : > "$PRISMA_RECEIPT_FILE"
  "${EVENT_FOR_TEST:-subagent_stop}" >/dev/null; rc=$?
  outcome=$(cut -f4 "$PRISMA_RECEIPT_FILE" | tr '\n' ' ' | sed 's/ $//')
  printf '%s %s' "$rc" "${outcome:-silent}"
}

names_in_stderr() { grep -c -- "$1" "$repo/stderr.txt"; }

selftest_named_sources() {
  new_repo
  review_prompt "Standards: $repo/CLAUDE.md and $repo/rules/code-rules.md."
  read_call tu_1 "$repo/CLAUDE.md"
  expect "1 the real case, the prompt names the code rules and the reviewer never opens them, holds the reviewer" "$(verdict)" "2 blocked"
  expect "2 the message names the source that was not opened" "$(names_in_stderr "rules/code-rules.md")" "1"
  expect "3 the message does not name the source that was opened" "$(names_in_stderr "$repo/CLAUDE.md")" "0"
  read_call tu_2 "$repo/rules/code-rules.md"
  expect "4 the same review after opening the rules passes without a receipt line" "$(verdict)" "0 silent"
  rm -rf "$repo"
}

selftest_what_counts_as_opening() {
  new_repo
  review_prompt "Standards: $repo/rules/code-rules.md"
  read_call tu_1 "$repo/rules/code-rules.md"; failed_result tu_1
  expect "5 a Read of the rules that failed is not opening them" "$(verdict)" "2 blocked"
  review_prompt "Standards: $repo/rules/code-rules.md"
  shell_call "cat $repo/rules/code-rules.md"
  expect "6 printing the rules from the shell is opening them" "$(verdict)" "0 silent"
  review_prompt "Standards: $repo/rules/code-rules.md"
  shell_call "R=$repo; sed -n 1,80p \$R/rules/code-rules.md"
  expect "7 printing them through a variable still names the file and counts" "$(verdict)" "0 silent"
  review_prompt "Standards: $repo/rules/code-rules.md"
  shell_call "ls -la $repo/rules/code-rules.md; wc -l $repo/rules/code-rules.md"
  expect "8 listing and counting the rules is not opening them" "$(verdict)" "2 blocked"
  review_prompt "Standards: $repo/rules/code-rules.md"
  shell_call "cat $repo/CLAUDE.md"; shell_call "wc -l $repo/rules/code-rules.md"
  expect "9 a reader in one command and the file name in another do not add up" "$(verdict)" "2 blocked"
  review_prompt "Standards: $repo/rules/code-rules.md"
  shell_call "grep -n \"^#\\|^- \" $repo/rules/code-rules.md | head -60"
  expect "28 the real case, a search of the rules whose pattern carries a bar, is opening them" "$(verdict)" "0 silent"
  review_prompt "Standards: $repo/rules/code-rules.md"
  shell_call "wc -l $repo/rules/code-rules.md | head -1"
  expect "38 counting the rules and printing the count is not opening them" "$(verdict)" "2 blocked"
  rm -rf "$repo"
}

selftest_how_sources_are_named() {
  new_repo
  review_prompt "Estándares del repo: $repo/CLAUDE.md y $repo/rules/code-rules.md."
  read_call tu_1 "$repo/CLAUDE.md"
  expect "10 the Spanish label names sources too" "$(verdict)" "2 blocked"
  review_prompt "Standards: rules/code-rules.md, relative to the repository."
  expect "11 a relative source is read from the working directory of the session" "$(verdict)" "2 blocked"
  read_call tu_1 "$repo/rules/code-rules.md"
  expect "12 and opening it by its absolute path passes" "$(verdict)" "0 silent"
  mkdir -p "$HOME/notes"; printf '# Home rules\n' > "$HOME/notes/home-rules.md"
  review_prompt "Standards: ~/notes/home-rules.md"
  expect "13 a source under the home written with a tilde is required" "$(verdict)" "2 blocked"
  read_call tu_1 "$HOME/notes/home-rules.md"
  expect "14 and opening it passes" "$(verdict)" "0 silent"
  review_prompt "Standards: $repo/rules/gone.md and nothing else."
  expect "15 a named source that is not on disk is not required" "$(verdict)" "0 silent"
  review_prompt "Plan record $repo/rules/code-rules.md, ticket 3. Standards: $repo/CLAUDE.md"
  read_call tu_1 "$repo/CLAUDE.md"
  expect "29 a file named before the label on the same line is not a source" "$(verdict)" "0 silent"
  printf 'export default []\n' > "$repo/tool.mjs"
  review_prompt "Standards: $repo/CLAUDE.md. The script uses $repo/tool.mjs from the parent folder."
  read_call tu_1 "$repo/CLAUDE.md"
  expect "30 a file that is not a written page is not a source" "$(verdict)" "0 silent"
  prompt_line "Summarise the repository. Standards: $repo/rules/code-rules.md"
  printf '# Contributing\n' > "$repo/CONTRIBUTING.md"
  prompt_line "Read $repo/skills/prisma-fidelity-review/SKILL.md and summarise it."
  expect "39 a subagent that only names the file of the skill is not a reviewer" "$(verdict)" "0 silent"
  expect "40 without jq a subagent that is not a reviewer leaves no receipt line" "$(JQ_FOR_TEST= verdict)" "0 silent"
  rm -f "$repo/CONTRIBUTING.md"
  expect "16 a subagent that is not the fidelity reviewer passes without a receipt line" "$(verdict)" "0 silent"
  rm -rf "$repo"
}

selftest_repository_sources() {
  new_repo
  printf '# Contributing\n## Code standards\n' > "$repo/CONTRIBUTING.md"
  review_prompt "Standards: $repo/CLAUDE.md"
  read_call tu_1 "$repo/CLAUDE.md"
  expect "17 the real case, a contributing guide the prompt never named and the reviewer never opened, holds the reviewer" "$(verdict)" "2 blocked"
  expect "18 the message names the contributing guide" "$(names_in_stderr "CONTRIBUTING.md")" "1"
  shell_call "cat $repo/CONTRIBUTING.md"
  expect "19 the same review after opening the guide passes" "$(verdict)" "0 silent"
  mv "$repo/CONTRIBUTING.md" "$repo/contributing.md"
  review_prompt "Standards: $repo/CLAUDE.md"
  read_call tu_1 "$repo/CLAUDE.md"
  expect "20 the guide is found whatever the case of its name" "$(verdict)" "2 blocked"
  elsewhere=$(mktemp -d)
  expect "21 the guide is found from a named source when the session works in another folder" "$(CWD_FOR_TEST="$elsewhere" verdict)" "2 blocked"
  review_prompt "Worktree: $repo, branch feat/x.
- Standards: the CLAUDE.md of the worktree."
  expect "31 the real case, a repository the prompt names only as a folder, has its guide looked for" "$(CWD_FOR_TEST="$elsewhere" verdict)" "2 blocked"
  review_prompt "Standards: $repo/CLAUDE.md"
  read_call tu_1 "$repo/CLAUDE.md"
  mkdir -p "$repo/docs/deep"; mv "$repo/contributing.md" "$repo/docs/deep/CONTRIBUTING.md"
  expect "22 a guide below the root of the repository is not looked for" "$(verdict)" "0 silent"
  rm -rf "$repo" "$elsewhere"
}

selftest_never_holds_twice_and_fails_open() {
  new_repo
  review_prompt "Standards: $repo/rules/code-rules.md"
  expect "23 a reviewer already held once is let go, and the receipt says warned" "$(ACTIVE_FOR_TEST=true verdict)" "0 warned"
  expect "24 without jq the gate lets the reviewer go and says it did not measure" "$(JQ_FOR_TEST= verdict)" "0 not-measured"
  expect "25 a transcript that is not there is not measured" "$(TRANSCRIPT_FOR_TEST="$repo/no-such.jsonl" verdict)" "0 not-measured"
  printf 'this is not json\n' > "$repo/broken.jsonl"
  expect "26 a transcript that cannot be parsed is not measured" "$(TRANSCRIPT_FOR_TEST="$repo/broken.jsonl" verdict)" "0 not-measured"
  : > "$PRISMA_RECEIPT_FILE"
  printf '' | PRISMA_JQ="$JQ" sh "$GATE" 2>/dev/null; rc=$?
  expect "27 an empty payload is not measured" "$rc $(cut -f4 "$PRISMA_RECEIPT_FILE")" "0 not-measured"
  rm -rf "$repo"
}

selftest_instructions_already_in_context() {
  new_repo
  mkdir -p "$repo/packages/app" "$HOME/.claude"; printf '# Global rules\n' > "$HOME/.claude/CLAUDE.md"
  elsewhere=$(mktemp -d)
  review_prompt "Standards: $repo/CLAUDE.md"
  expect "32 the real case, the instructions file of the folder the session works in, is already held by the reviewer" "$(verdict)" "0 silent"
  expect "33 the instructions file of a folder above the working one is held too" "$(CWD_FOR_TEST="$repo/packages/app" verdict)" "0 silent"
  expect "34 the instructions file of another folder is not held, and has to be opened" "$(CWD_FOR_TEST="$elsewhere" verdict)" "2 blocked"
  expect "35 an agent type that starts without the instructions files has to open them" "$(AGENT_TYPE_FOR_TEST=Explore verdict)" "2 blocked"
  review_prompt "Standards: ~/.claude/CLAUDE.md"
  expect "36 the instructions file of the person is held from any folder" "$(CWD_FOR_TEST="$elsewhere" verdict)" "0 silent"
  cp "$repo/CLAUDE.md" "$repo/NOTES.md"
  review_prompt "Standards: $repo/NOTES.md"
  expect "37 any other page of the working folder has to be opened" "$(verdict)" "2 blocked"
  rm -rf "$repo" "$elsewhere"
}

selftest_reports_handed_back_through_a_tool() {
  new_repo
  mkdir -p "$repo/parent/subagents"; transcript="$repo/parent/subagents/agent-a1.jsonl"
  review_prompt "Standards: $repo/rules/code-rules.md"
  expect "41 the real case, a reviewer about to hand back a report without opening the rules, is held before the report leaves" "$(EVENT_FOR_TEST=handback_attempt verdict)" "2 blocked"
  expect "42 the message names the source" "$(names_in_stderr "rules/code-rules.md")" "1"
  handback_call tu_h1; gate_feedback tu_h1
  expect "43 a reviewer held once at the hand back is let go the second time, and the receipt says warned" "$(EVENT_FOR_TEST=handback_attempt verdict)" "0 warned"
  handback_call tu_h2
  expect "44 the stop that follows a hand back is not judged again" "$(verdict)" "0 silent"
  review_prompt "Standards: $repo/rules/code-rules.md"
  read_call tu_1 "$repo/rules/code-rules.md"
  expect "45 a reviewer that opened the rules hands back without a receipt line" "$(EVENT_FOR_TEST=handback_attempt verdict)" "0 silent"
  review_prompt "Standards: $repo/rules/code-rules.md"
  expect "46 another tool of the same reviewer is not a hand back" "$(TOOL_FOR_TEST=Read EVENT_FOR_TEST=handback_attempt verdict)" "0 silent"
  rm -rf "$repo"
}

child_of() {
  "$JQ" -nc --arg parent "$1" '{agentType: "general-purpose", parentAgentId: $parent}' > "$repo/parent/subagents/agent-$2.meta.json"
  "$JQ" -nc --arg path "$3" '{type: "assistant", message: {content: [{type: "tool_use", id: "tu_child", name: "Read", input: {file_path: $path}}]}}' > "$repo/parent/subagents/agent-$2.jsonl"
}

selftest_axes_run_by_subagents() {
  new_repo
  mkdir -p "$repo/parent/subagents"; transcript="$repo/parent/subagents/agent-a1.jsonl"
  review_prompt "Standards: $repo/rules/code-rules.md"
  child_of a1 b2 "$repo/rules/code-rules.md"
  expect "47 the real case, a reviewer whose standards axis ran in a subagent that opened the rules, passes" "$(verdict)" "0 silent"
  child_of zz b2 "$repo/rules/code-rules.md"
  expect "48 what the subagent of another agent opened does not count" "$(verdict)" "2 blocked"
  child_of a1 b2 "$repo/CLAUDE.md"; child_of b2 c3 "$repo/rules/code-rules.md"
  expect "49 what a subagent of the subagent opened counts" "$(verdict)" "0 silent"
  child_of a1 b2 "$repo/CLAUDE.md"; rm -f "$repo/parent/subagents/agent-c3."*
  expect "50 a subagent that opened another file does not count" "$(verdict)" "2 blocked"
  rm -rf "$repo"
}

selftest() {
  ok=1; cases=0
  [ -n "$JQ" ] || { printf 'SKIP the review reads gate needs jq to build its fixtures\n'; printf 'SELFTEST OK: 1/1\n'; return 0; }
  selftest_named_sources
  selftest_what_counts_as_opening
  selftest_how_sources_are_named
  selftest_repository_sources
  selftest_never_holds_twice_and_fails_open
  selftest_instructions_already_in_context
  selftest_reports_handed_back_through_a_tool
  selftest_axes_run_by_subagents
  [ "$ok" = "1" ] && [ "$cases" = "$SELFTEST_CASES" ] && { printf 'SELFTEST OK: %s/%s\n' "$cases" "$SELFTEST_CASES"; return 0; }
  printf 'SELFTEST FAILED, %s cases ran and %s were declared\n' "$cases" "$SELFTEST_CASES"; return 1
}
